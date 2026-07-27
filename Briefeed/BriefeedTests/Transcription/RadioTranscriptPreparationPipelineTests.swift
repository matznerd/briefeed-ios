import Foundation
import Testing
@testable import Briefeed

@Suite("Radio transcript preparation pipeline")
struct RadioTranscriptPreparationPipelineTests {
    @Test func transportSecurityFailureUsesProductLanguage() {
        let message = RadioTranscriptPreparationPipeline.errorMessage(
            URLError(.appTransportSecurityRequiresSecureConnection)
        )

        #expect(message ==
                "This source's audio could not be downloaded securely.")
        #expect(!message.localizedCaseInsensitiveContains("App Transport"))
    }

    @Test func currentAndNextTwoRunBeforeRemainingExplicitBatch() async throws {
        let harness = try PipelineHarness()
        defer { harness.cleanup() }
        let current = harness.job("current", priority: .current)
        let nextOne = harness.job("next-one", priority: .nextOne)
        let nextTwo = harness.job("next-two", priority: .nextTwo)
        let batch = harness.job("batch", priority: .batch)

        await harness.pipeline.reconcile(
            interactive: [nextTwo, current, nextOne],
            batch: [batch],
            generation: 1
        )
        try await harness.waitForCallCount(4)

        #expect(await harness.recorder.calls == [
            "current.audio", "next-one.audio", "next-two.audio", "batch.audio"
        ])
        #expect(await harness.recorder.maximumActiveCount == 1)
    }

    @Test func automaticWorkingSetIsDeduplicatedAndCappedAtThree() async throws {
        let harness = try PipelineHarness()
        defer { harness.cleanup() }
        let current = harness.job("current", priority: .current)
        let duplicate = harness.job("current", priority: .nextOne)

        await harness.pipeline.reconcile(
            interactive: [
                current,
                duplicate,
                harness.job("one", priority: .nextOne),
                harness.job("two", priority: .nextTwo),
                harness.job("three", priority: .nextTwo)
            ],
            batch: [],
            generation: 1
        )
        try await harness.waitForCallCount(3)

        #expect(await harness.recorder.calls == [
            "current.audio", "one.audio", "two.audio"
        ])
    }

    @Test func explicitBatchPreservesTheVisibleRadioOrder() async throws {
        let harness = try PipelineHarness()
        defer { harness.cleanup() }
        let visibleFirst = harness.job(
            "visible-first",
            feedID: "z-source",
            priority: .batch
        )
        let visibleSecond = harness.job(
            "visible-second",
            feedID: "a-source",
            priority: .batch
        )

        await harness.pipeline.reconcile(
            interactive: [],
            batch: [visibleFirst, visibleSecond],
            generation: 1
        )
        try await harness.waitForCallCount(2)

        #expect(await harness.recorder.calls == [
            "visible-first.audio", "visible-second.audio"
        ])
    }

    @Test func aNewGenerationPreventsCanceledResultsFromCommitting() async throws {
        let harness = try PipelineHarness(delay: .milliseconds(200))
        defer { harness.cleanup() }
        let old = harness.job("old", priority: .current)
        let replacement = harness.job("replacement", priority: .current)

        await harness.pipeline.reconcile(
            interactive: [old],
            batch: [],
            generation: 1
        )
        try await Task.sleep(for: .milliseconds(20))
        await harness.pipeline.reconcile(
            interactive: [replacement],
            batch: [],
            generation: 2
        )
        try await harness.waitForSuccessfulEpisode("replacement")

        #expect(try await harness.store.records(for: old.episodeKey).isEmpty)
        #expect(try await harness.store.records(for: replacement.episodeKey).count == 1)
    }

    @Test func batchProgressAdvancesOnlyAfterTranscriptIsDurable() async throws {
        let harness = try PipelineHarness()
        defer { harness.cleanup() }
        let job = harness.job("batch", priority: .batch)
        let manifest = RadioTranscriptBatchManifest(
            schemaVersion: RadioTranscriptBatchManifest.currentSchemaVersion,
            id: UUID(),
            createdAt: .now,
            updatedAt: .now,
            entries: [
                .init(episodeKey: job.episodeKey, order: 0, state: .pending)
            ]
        )
        try await harness.store.saveBatch(manifest)

        await harness.pipeline.reconcile(
            interactive: [],
            batch: [job],
            generation: 1
        )
        try await harness.waitForSuccessfulEpisode("batch")

        let loaded = try await harness.store.loadBatch()
        let saved = try #require(loaded)
        guard case .transcriptReady(let key) = saved.entries[0].state else {
            Issue.record("Expected a durable transcript-ready batch entry")
            return
        }
        #expect(try await harness.store.loadTranscript(for: key) != nil)
        #expect(saved.completedCount == 1)
    }

    @Test func anInteractiveJobAlsoAdvancesItsOverlappingBatchEntry() async throws {
        let harness = try PipelineHarness()
        defer { harness.cleanup() }
        let current = harness.job("shared", priority: .current)
        let batch = harness.job("shared", priority: .batch)
        try await harness.store.saveBatch(
            RadioTranscriptBatchManifest(
                schemaVersion:
                    RadioTranscriptBatchManifest.currentSchemaVersion,
                id: UUID(),
                createdAt: .now,
                updatedAt: .now,
                entries: [
                    .init(
                        episodeKey: current.episodeKey,
                        order: 0,
                        remoteURL: current.remoteURL,
                        expectedDurationSeconds:
                            current.expectedDurationSeconds,
                        languageTag: current.languageTag,
                        state: .pending
                    )
                ]
            )
        )

        await harness.pipeline.reconcile(
            interactive: [current],
            batch: [batch],
            generation: 1
        )
        try await harness.waitForSuccessfulEpisode("shared")

        let saved = try #require(try await harness.store.loadBatch())
        #expect(await harness.recorder.calls == ["shared.audio"])
        #expect(saved.completedCount == 1)
        guard case .transcriptReady(let key) = saved.entries[0].state else {
            Issue.record("Expected the overlapping batch entry to finish")
            return
        }
        #expect(try await harness.store.loadTranscript(for: key) != nil)
    }
}

private final class PipelineHarness: @unchecked Sendable {
    let root: URL
    let store: RadioTranscriptStore
    let recorder: PipelineEngineRecorder
    let pipeline: RadioTranscriptPreparationPipeline

    init(delay: Duration = .zero) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RadioTranscriptPipelineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = try RadioTranscriptStore(
            rootDirectory: root.appendingPathComponent("transcripts")
        )
        recorder = PipelineEngineRecorder(delay: delay)
        pipeline = RadioTranscriptPreparationPipeline(
            assetProvider: PipelineAssetProvider(root: root.appendingPathComponent("assets")),
            store: store,
            engineResolver: PipelineEngineResolver(recorder: recorder)
        )
    }

    func job(
        _ episodeID: String,
        feedID: String = "feed",
        priority: RadioTranscriptJobPriority
    ) -> RadioTranscriptJob {
        RadioTranscriptJob(
            episodeKey: .init(feedID: feedID, episodeID: episodeID),
            remoteURL: URL(string: "https://example.com/\(episodeID).mp3")!,
            expectedDurationSeconds: 30,
            languageTag: "en-US",
            priority: priority
        )
    }

    func waitForCallCount(_ expected: Int) async throws {
        for _ in 0..<200 {
            if await recorder.calls.count >= expected { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for \(expected) engine calls")
    }

    func waitForSuccessfulEpisode(_ episodeID: String) async throws {
        let key = RadioEpisodeKey(feedID: "feed", episodeID: episodeID)
        for _ in 0..<300 {
            if try await !store.records(for: key).isEmpty { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for \(episodeID) to persist")
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor PipelineAssetProvider: RadioTranscriptAssetProviding {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    func acquire(
        _ request: RadioTranscriptAudioRequest
    ) async throws -> RadioTranscriptAudioAsset {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("\(request.episodeKey.episodeID).audio")
        let fingerprint = "fingerprint-\(request.episodeKey.episodeID)"
        try Data(request.episodeKey.episodeID.utf8).write(to: url, options: .atomic)
        return RadioTranscriptAudioAsset(
            schemaVersion: RadioTranscriptAudioAsset.currentSchemaVersion,
            episodeKey: request.episodeKey,
            originalURL: request.remoteURL,
            finalURL: request.remoteURL,
            etag: nil,
            lastModified: nil,
            responseContentLength: nil,
            audioDurationSeconds: 30,
            assetFingerprint: fingerprint,
            localFileURL: url,
            completedAt: .now,
            lastAccessedAt: .now,
            isTranscriptReady: false
        )
    }

    func cachedAsset(
        for episodeKey: RadioEpisodeKey
    ) async throws -> RadioTranscriptAudioAsset? {
        nil
    }

    func preparedPlaybackURL(for episodeKey: RadioEpisodeKey) async -> URL? {
        nil
    }

    func markTranscriptReady(_ asset: RadioTranscriptAudioAsset) async throws {}

    func pin(
        _ episodeKey: RadioEpisodeKey,
        reason: RadioTranscriptAssetPinReason
    ) {}

    func unpin(
        _ episodeKey: RadioEpisodeKey,
        reason: RadioTranscriptAssetPinReason
    ) {}
}

private struct PipelineEngineResolver: RadioTranscriptEngineResolving {
    let recorder: PipelineEngineRecorder

    func resolve(languageTag: String) async throws -> RadioResolvedTranscriptEngine {
        RadioResolvedTranscriptEngine(
            engine: PipelineTimedTranscriptEngine(recorder: recorder),
            locale: Locale(identifier: "en-US"),
            engineIdentifier: "test-engine",
            engineVersion: "1"
        )
    }
}

private struct PipelineTimedTranscriptEngine: TimedTranscriptEngine {
    let recorder: PipelineEngineRecorder

    func transcribe(
        fileURL: URL,
        assetFingerprint: String,
        locale: Locale,
        assetPolicy: SpeechAssetPolicy
    ) async throws -> TimedTranscript {
        try await recorder.transcribe(
            fileURL: fileURL,
            assetFingerprint: assetFingerprint,
            locale: locale
        )
    }
}

private actor PipelineEngineRecorder {
    let delay: Duration
    private(set) var calls: [String] = []
    private(set) var maximumActiveCount = 0
    private var activeCount = 0

    init(delay: Duration) {
        self.delay = delay
    }

    func transcribe(
        fileURL: URL,
        assetFingerprint: String,
        locale: Locale
    ) async throws -> TimedTranscript {
        calls.append(fileURL.lastPathComponent)
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        defer { activeCount -= 1 }
        if delay != .zero {
            try await Task.sleep(for: delay)
        }
        try Task.checkCancellation()
        return try TimedTranscript(
            assetFingerprint: assetFingerprint,
            engineIdentifier: "test-engine",
            engineVersion: "1",
            localeIdentifier: locale.identifier,
            recognizedText: "Latest news",
            audioDurationSeconds: 30,
            processingDurationSeconds: 0.1,
            units: [
                .init(
                    text: "Latest",
                    startSeconds: 0,
                    endSeconds: 0.5,
                    confidence: 1,
                    granularity: .word
                ),
                .init(
                    text: "news",
                    startSeconds: 0.5,
                    endSeconds: 1,
                    confidence: 1,
                    granularity: .word
                )
            ]
        )
    }
}
