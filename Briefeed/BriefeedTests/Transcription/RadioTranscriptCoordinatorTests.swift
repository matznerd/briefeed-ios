import Combine
import CryptoKit
import Foundation
import Testing
@testable import Briefeed

@MainActor
@Suite("Radio transcript coordinator")
struct RadioTranscriptCoordinatorTests {
    @Test func currentAndExactlyTwoUpcomingCandidatesBecomeImmutableJobs() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        try await harness.metadata.setLanguageTag(
            "en-GB",
            source: .publisher,
            for: "next-feed"
        )
        let current = harness.candidate("current", feedID: "current-feed")
        let nextOne = harness.candidate("next-1", feedID: "next-feed")
        let nextTwo = harness.candidate("next-2", feedID: "next-feed")
        let ignored = harness.candidate("ignored", feedID: "next-feed")

        harness.coordinator.updateCurrent(
            current,
            next: [nextOne, nextTwo, ignored]
        )
        let reconciliation = try await harness.pipeline.waitForReconciliation()

        #expect(reconciliation.interactive.map(\.episodeKey) == [
            current.key, nextOne.key, nextTwo.key
        ])
        #expect(reconciliation.interactive.map(\.priority) == [
            .current, .nextOne, .nextTwo
        ])
        #expect(reconciliation.interactive.map(\.languageTag) == [
            "en-US", "en-GB", "en-GB"
        ])
    }

    @Test func playbackProgressUpdatesDoNotRestartTheSameWorkingSet() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        let current = harness.candidate("current", progress: 0)
        let next = harness.candidate("next")

        harness.coordinator.updateCurrent(current, next: [next])
        _ = try await harness.pipeline.waitForReconciliation()

        harness.coordinator.updateCurrent(
            harness.candidate("current", progress: 0.25),
            next: [next]
        )
        await Task.yield()

        #expect(await harness.pipeline.queuedReconciliationCount() == 0)
    }

    @Test func prepareAllUsesOnlyTheVisibleFreshUncompletedDeduplicatedSnapshot() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        let first = harness.candidate("first")
        let second = harness.candidate("second")
        let completed = harness.candidate("done", isCompleted: true)
        let stale = harness.candidate(
            "stale",
            publicationDate: .distantPast
        )
        harness.coordinator.updateVisibleSnapshot([
            first, first, completed, stale, second
        ])

        harness.coordinator.prepareAll()
        let reconciliation = try await harness.pipeline.waitForReconciliation()
        let loadedManifest = try await harness.store.loadBatch()
        let manifest = try #require(loadedManifest)

        #expect(reconciliation.batch.map(\.episodeKey) == [
            first.key, second.key
        ])
        #expect(manifest.entries.map(\.episodeKey) == [
            first.key, second.key
        ])
        #expect(harness.background.submittedTotals == [2])
    }

    @Test func acceptedBatchContinuesWithoutAutomaticJobsOnBackground() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        let current = harness.candidate("current")
        let batch = harness.candidate("batch", feedID: "batch-feed")
        harness.coordinator.updateCurrent(current, next: [])
        _ = try await harness.pipeline.waitForReconciliation()
        harness.coordinator.updateVisibleSnapshot([batch])
        harness.coordinator.prepareAll()
        _ = try await harness.pipeline.waitForReconciliation()

        harness.coordinator.handleBackground()
        let background = try await harness.pipeline.waitForReconciliation()

        #expect(background.interactive.isEmpty)
        #expect(background.batch.map(\.episodeKey) == [batch.key])
    }

    @Test func stalePipelineEventsCannotReplaceTheNewCurrentTranscript() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        let old = harness.candidate("old")
        let replacement = harness.candidate("replacement")
        harness.coordinator.updateCurrent(old, next: [])
        let oldReconciliation = try await harness.pipeline.waitForReconciliation()
        harness.coordinator.updateCurrent(replacement, next: [])
        let replacementReconciliation = try await harness.pipeline.waitForReconciliation()

        await harness.pipeline.emit(.preparation(
            episodeKey: old.key,
            generation: oldReconciliation.generation,
            state: .ready(try harness.transcript("old"))
        ))
        await Task.yield()
        #expect(harness.coordinator.presentation.episodeKey == replacement.key)
        #expect(!harness.coordinator.presentation.isReady)

        await harness.pipeline.emit(.preparation(
            episodeKey: replacement.key,
            generation: replacementReconciliation.generation,
            state: .ready(try harness.transcript("replacement"))
        ))
        try await harness.waitUntilPresentationReady()
        #expect(harness.coordinator.presentation.episodeKey == replacement.key)
        #expect(harness.coordinator.presentation.isReady)
    }

    @Test func persistedBatchReturnsAsStoppedAfterVisibleSnapshotRestores() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        let first = harness.candidate("first")
        let second = harness.candidate("second")
        let transcript = try harness.transcript("first")
        let cacheKey = RadioTranscriptCacheKey(
            episodeKey: first.key,
            assetFingerprint: transcript.assetFingerprint,
            engineIdentifier: transcript.engineIdentifier,
            engineVersion: transcript.engineVersion,
            localeIdentifier: transcript.localeIdentifier
        )
        try await harness.store.save(
            transcript: transcript,
            record: RadioTranscriptRecord(
                schemaVersion: RadioTranscriptRecord.currentSchemaVersion,
                key: cacheKey,
                sourceURLHash: "source",
                audioDurationSeconds: transcript.audioDurationSeconds,
                transcriptRelativePath: "artifacts/first.json",
                preparedAt: .now,
                lastAccessedAt: .now
            )
        )
        try await harness.store.saveBatch(
            harness.manifest(
                entries: [
                    .init(
                        episodeKey: first.key,
                        order: 0,
                        state: .transcriptReady(cacheKey: cacheKey)
                    ),
                    .init(
                        episodeKey: second.key,
                        order: 1,
                        state: .pending
                    )
                ]
            )
        )

        harness.coordinator.updateVisibleSnapshot([first, second])
        try await harness.waitUntilBatchState(.stopped)

        #expect(harness.coordinator.batchPresentation.completedCount == 1)
        #expect(harness.coordinator.batchPresentation.totalCount == 2)
    }

    @Test func missingTranscriptArtifactDoesNotRestoreAsCompleted() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        let candidate = harness.candidate("missing")
        let missingKey = RadioTranscriptCacheKey(
            episodeKey: candidate.key,
            assetFingerprint: "missing-fingerprint",
            engineIdentifier: "test",
            engineVersion: "1",
            localeIdentifier: "en-US"
        )
        try await harness.store.saveBatch(
            harness.manifest(
                entries: [
                    .init(
                        episodeKey: candidate.key,
                        order: 0,
                        state: .transcriptReady(cacheKey: missingKey)
                    )
                ]
            )
        )

        harness.coordinator.updateVisibleSnapshot([candidate])
        try await harness.waitUntilBatchState(.stopped)

        #expect(harness.coordinator.batchPresentation.completedCount == 0)
        #expect(harness.coordinator.batchPresentation.totalCount == 1)
    }

    @Test func resumeBatchCarriesCompletedCheckpointAndSchedulesOnlyPending() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        let first = harness.candidate("first")
        let second = harness.candidate("second")
        let transcript = try harness.transcript("first")
        let cacheKey = RadioTranscriptCacheKey(
            episodeKey: first.key,
            assetFingerprint: transcript.assetFingerprint,
            engineIdentifier: transcript.engineIdentifier,
            engineVersion: transcript.engineVersion,
            localeIdentifier: transcript.localeIdentifier
        )
        try await harness.store.save(
            transcript: transcript,
            record: RadioTranscriptRecord(
                schemaVersion: RadioTranscriptRecord.currentSchemaVersion,
                key: cacheKey,
                sourceURLHash: "source",
                audioDurationSeconds: transcript.audioDurationSeconds,
                transcriptRelativePath: "artifacts/first.json",
                preparedAt: .now,
                lastAccessedAt: .now
            )
        )
        let oldManifest = harness.manifest(
            entries: [
                .init(
                    episodeKey: first.key,
                    order: 0,
                    state: .transcriptReady(cacheKey: cacheKey)
                ),
                .init(
                    episodeKey: second.key,
                    order: 1,
                    state: .audioReady(assetFingerprint: "second-audio")
                )
            ]
        )
        try await harness.store.saveBatch(oldManifest)
        harness.coordinator.updateVisibleSnapshot([first, second])
        try await harness.waitUntilBatchState(.stopped)

        harness.coordinator.prepareAll()
        let reconciliation =
            try await harness.pipeline.waitForReconciliation()
        let resumed = try #require(try await harness.store.loadBatch())

        #expect(resumed.id != oldManifest.id)
        #expect(resumed.entries[0].state ==
                .transcriptReady(cacheKey: cacheKey))
        #expect(resumed.entries[1].state ==
                .audioReady(assetFingerprint: "second-audio"))
        #expect(reconciliation.batch.map(\.episodeKey) == [second.key])
        #expect(harness.background.submittedTotals == [2])
        #expect(harness.coordinator.batchPresentation.completedCount == 1)
    }

    @Test func completedSnapshotWithNewVisibleWorkRestoresAsOneOfTwo() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        let first = harness.candidate("first")
        let second = harness.candidate("second")
        let cacheKey = try await harness.saveTranscript(for: first)
        try await harness.store.saveBatch(
            harness.manifest(entries: [
                .init(
                    episodeKey: first.key,
                    order: 0,
                    remoteURL: first.originalPlaybackURL,
                    expectedDurationSeconds: first.durationSeconds,
                    languageTag: "en-US",
                    state: .transcriptReady(cacheKey: cacheKey)
                )
            ])
        )

        harness.coordinator.updateVisibleSnapshot([first, second])
        try await harness.waitUntilBatchState(.stopped)

        #expect(harness.coordinator.batchPresentation.completedCount == 1)
        #expect(harness.coordinator.batchPresentation.totalCount == 2)
        #expect(harness.coordinator.batchPresentation.episodeKeys == [
            first.key, second.key
        ])
    }

    @Test func stoppingBeforeBatchRestoreFinishesCannotRestartPreparation() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        harness.coordinator.updateVisibleSnapshot([
            harness.candidate("first")
        ])

        harness.coordinator.prepareAll()
        harness.coordinator.stopPrepareAll()
        try await Task.sleep(for: .milliseconds(100))

        #expect(harness.coordinator.batchPresentation.state == .stopped)
        #expect(harness.background.submittedTotals.isEmpty)
    }

    @Test func aTerminalFailedManifestStopsAndCompletesBackgroundAsFailure() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        let candidate = harness.candidate("failed")
        harness.coordinator.updateVisibleSnapshot([candidate])
        harness.coordinator.prepareAll()
        _ = try await harness.pipeline.waitForReconciliation()
        var manifest = try #require(try await harness.store.loadBatch())
        manifest.entries[0].state = .failed(message: "No speech")
        try await harness.store.saveBatch(manifest)

        await harness.pipeline.emit(.batchUpdated(manifest))
        try await harness.waitUntilBatchState(.stopped)

        #expect(harness.background.completions == [false])
        #expect(harness.coordinator.batchPresentation.completedCount == 0)
        #expect(harness.coordinator.batchPresentation.totalCount == 1)
    }

    @Test func resumePreservesUnfinishedManifestEntriesNoLongerVisible() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        let first = harness.candidate("first")
        let second = harness.candidate("second")
        let manifest = harness.manifest(entries: [
            .init(
                episodeKey: first.key,
                order: 0,
                remoteURL: first.originalPlaybackURL,
                expectedDurationSeconds: first.durationSeconds,
                languageTag: "en-US",
                state: .pending
            ),
            .init(
                episodeKey: second.key,
                order: 1,
                remoteURL: second.originalPlaybackURL,
                expectedDurationSeconds: second.durationSeconds,
                languageTag: "en-US",
                state: .pending
            )
        ])
        try await harness.store.saveBatch(manifest)
        harness.coordinator.updateVisibleSnapshot([first])
        try await harness.waitUntilBatchState(.stopped)

        harness.coordinator.prepareAll()
        let reconciliation =
            try await harness.pipeline.waitForReconciliation()
        let resumed = try #require(try await harness.store.loadBatch())

        #expect(resumed.entries.map(\.episodeKey) == [
            first.key, second.key
        ])
        #expect(reconciliation.batch.map(\.episodeKey) == [
            first.key, second.key
        ])
    }

    @Test func resumePreservesAnUnfinishedSnapshotAfterItsVisibleEpisodeBecomesStale() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        let stale = harness.candidate(
            "stale",
            publicationDate: .distantPast
        )
        try await harness.store.saveBatch(
            harness.manifest(entries: [
                .init(
                    episodeKey: stale.key,
                    order: 0,
                    remoteURL: stale.originalPlaybackURL,
                    expectedDurationSeconds: stale.durationSeconds,
                    languageTag: "en-US",
                    state: .pending
                )
            ])
        )
        harness.coordinator.updateVisibleSnapshot([stale])
        try await harness.waitUntilBatchState(.stopped)

        harness.coordinator.prepareAll()
        let reconciliation =
            try await harness.pipeline.waitForReconciliation()

        #expect(reconciliation.batch.map(\.episodeKey) == [stale.key])
    }

    @Test func readyCheckpointForAnotherEpisodeIsRescheduled() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        let expected = harness.candidate("expected")
        let other = harness.candidate("other")
        let wrongKey = try await harness.saveTranscript(for: other)
        try await harness.store.saveBatch(
            harness.manifest(entries: [
                .init(
                    episodeKey: expected.key,
                    order: 0,
                    remoteURL: expected.originalPlaybackURL,
                    expectedDurationSeconds: expected.durationSeconds,
                    languageTag: "en-US",
                    state: .transcriptReady(cacheKey: wrongKey)
                )
            ])
        )
        harness.coordinator.updateVisibleSnapshot([expected])
        try await harness.waitUntilBatchState(.stopped)

        harness.coordinator.prepareAll()
        let reconciliation =
            try await harness.pipeline.waitForReconciliation()

        #expect(reconciliation.batch.map(\.episodeKey) == [expected.key])
    }

    @Test func readyCheckpointForAChangedSourceURLIsRescheduled() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        let old = harness.candidate(
            "same",
            playbackURL: URL(string: "https://example.com/old.mp3")!
        )
        let changed = harness.candidate(
            "same",
            playbackURL: URL(string: "https://example.com/new.mp3")!
        )
        let cacheKey = try await harness.saveTranscript(for: old)
        try await harness.store.saveBatch(
            harness.manifest(entries: [
                .init(
                    episodeKey: old.key,
                    order: 0,
                    remoteURL: old.originalPlaybackURL,
                    expectedDurationSeconds: old.durationSeconds,
                    languageTag: "en-US",
                    state: .transcriptReady(cacheKey: cacheKey)
                )
            ])
        )
        harness.coordinator.updateVisibleSnapshot([changed])
        try await harness.waitUntilBatchState(.stopped)

        harness.coordinator.prepareAll()
        let reconciliation =
            try await harness.pipeline.waitForReconciliation()

        #expect(reconciliation.batch.map(\.remoteURL) == [
            changed.originalPlaybackURL
        ])
    }
}

private final class CoordinatorHarness: @unchecked Sendable {
    let root: URL
    let store: RadioTranscriptStore
    let pipeline = RecordingTranscriptPipeline()
    let assets = CoordinatorAssetProvider()
    let metadata = InMemoryRadioFeedSpeechMetadataStore()
    let background: CoordinatorBackgroundDriver
    let coordinator: RadioTranscriptCoordinator

    @MainActor
    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RadioTranscriptCoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        store = try RadioTranscriptStore(
            rootDirectory: root.appendingPathComponent("transcripts")
        )
        background = CoordinatorBackgroundDriver()
        coordinator = RadioTranscriptCoordinator(
            pipeline: pipeline,
            store: store,
            assetProvider: assets,
            metadataStore: metadata,
            backgroundDriver: background
        )
    }

    func candidate(
        _ id: String,
        feedID: String = "feed",
        isCompleted: Bool = false,
        progress: Double = 0,
        playbackURL: URL? = nil,
        publicationDate: Date = .now
    ) -> RadioEpisodeCandidate {
        let resolvedURL = playbackURL ??
            URL(string: "https://example.com/\(id).mp3")!
        return RadioEpisodeCandidate(
            key: .init(feedID: feedID, episodeID: id),
            originalPlaybackURL: resolvedURL,
            canonicalEnclosureURL: resolvedURL.absoluteString,
            title: id,
            sourceName: feedID,
            publicationDate: publicationDate,
            durationSeconds: 60,
            normalizedCoreDataProgress: isCompleted ? 1 : progress,
            isCompleted: isCompleted,
            sourcePriority: 0,
            sourceFrequency: .daily
        )
    }

    func saveTranscript(
        for candidate: RadioEpisodeCandidate
    ) async throws -> RadioTranscriptCacheKey {
        let transcript = try transcript(candidate.key.episodeID)
        let cacheKey = RadioTranscriptCacheKey(
            episodeKey: candidate.key,
            assetFingerprint: transcript.assetFingerprint,
            engineIdentifier: transcript.engineIdentifier,
            engineVersion: transcript.engineVersion,
            localeIdentifier: transcript.localeIdentifier
        )
        try await store.save(
            transcript: transcript,
            record: RadioTranscriptRecord(
                schemaVersion: RadioTranscriptRecord.currentSchemaVersion,
                key: cacheKey,
                sourceURLHash: Self.hash(candidate.originalPlaybackURL),
                audioDurationSeconds: transcript.audioDurationSeconds,
                transcriptRelativePath:
                    "artifacts/\(UUID().uuidString).json",
                preparedAt: .now,
                lastAccessedAt: .now
            )
        )
        return cacheKey
    }

    func transcript(_ id: String) throws -> TimedTranscript {
        try TimedTranscript(
            assetFingerprint: "fingerprint-\(id)",
            engineIdentifier: "test",
            engineVersion: "1",
            localeIdentifier: "en-US",
            recognizedText: "Latest news",
            audioDurationSeconds: 60,
            processingDurationSeconds: 1,
            units: [
                .init(
                    text: "Latest news",
                    startSeconds: 0,
                    endSeconds: 1,
                    confidence: 1,
                    granularity: .phrase
                )
            ]
        )
    }

    func manifest(
        entries: [RadioTranscriptBatchEntry]
    ) -> RadioTranscriptBatchManifest {
        RadioTranscriptBatchManifest(
            schemaVersion: RadioTranscriptBatchManifest.currentSchemaVersion,
            id: UUID(),
            createdAt: .now,
            updatedAt: .now,
            entries: entries
        )
    }

    @MainActor
    func waitUntilPresentationReady() async throws {
        for _ in 0..<100 {
            if coordinator.presentation.isReady { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for ready presentation")
    }

    @MainActor
    func waitUntilBatchState(
        _ state: RadioTranscriptBatchState
    ) async throws {
        for _ in 0..<100 {
            if coordinator.batchPresentation.state == state { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for batch state \(state)")
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func hash(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private actor RecordingTranscriptPipeline:
    RadioTranscriptPipelineScheduling
{
    struct Reconciliation: Sendable {
        let interactive: [RadioTranscriptJob]
        let batch: [RadioTranscriptJob]
        let generation: Int
    }

    private let stream: AsyncStream<RadioTranscriptPipelineEvent>
    private let continuation: AsyncStream<RadioTranscriptPipelineEvent>
        .Continuation
    private var reconciliations: [Reconciliation] = []

    init() {
        let pair = AsyncStream<RadioTranscriptPipelineEvent>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func events() -> AsyncStream<RadioTranscriptPipelineEvent> {
        stream
    }

    func reconcile(
        interactive: [RadioTranscriptJob],
        batch: [RadioTranscriptJob],
        generation: Int
    ) {
        reconciliations.append(.init(
            interactive: interactive,
            batch: batch,
            generation: generation
        ))
    }

    func cancelAll() {}

    func emit(_ event: RadioTranscriptPipelineEvent) {
        continuation.yield(event)
    }

    func waitForReconciliation() async throws -> Reconciliation {
        for _ in 0..<200 {
            if !reconciliations.isEmpty {
                return reconciliations.removeFirst()
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CoordinatorTestError.timeout
    }

    func queuedReconciliationCount() -> Int {
        reconciliations.count
    }
}

private enum CoordinatorTestError: Error {
    case timeout
}

private actor CoordinatorAssetProvider: RadioTranscriptAssetProviding {
    func acquire(
        _ request: RadioTranscriptAudioRequest
    ) async throws -> RadioTranscriptAudioAsset {
        throw CoordinatorTestError.timeout
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

@MainActor
private final class CoordinatorBackgroundDriver:
    RadioTranscriptBackgroundDriving
{
    private(set) var submittedTotals: [Int] = []
    private(set) var updates: [(Int, Int)] = []
    private(set) var completions: [Bool] = []
    private var expiration: (@MainActor @Sendable () -> Void)?

    func submit(
        batchID: UUID,
        total: Int,
        onExpiration: @escaping @MainActor @Sendable () -> Void
    ) -> RadioTranscriptBackgroundSubmission {
        submittedTotals.append(total)
        expiration = onExpiration
        return .accepted(identifier: "accepted.\(batchID)")
    }

    func update(completed: Int, total: Int) {
        updates.append((completed, total))
    }

    func complete(success: Bool) {
        completions.append(success)
    }
    func cancel() {}
}
