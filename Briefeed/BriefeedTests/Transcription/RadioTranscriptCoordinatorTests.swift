import Combine
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

    @Test func prepareAllUsesOnlyTheVisibleUncompletedDeduplicatedSnapshot() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.cleanup() }
        let first = harness.candidate("first")
        let second = harness.candidate("second")
        let completed = harness.candidate("done", isCompleted: true)
        harness.coordinator.updateVisibleSnapshot([
            first, first, completed, second
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
        isCompleted: Bool = false
    ) -> RadioEpisodeCandidate {
        RadioEpisodeCandidate(
            key: .init(feedID: feedID, episodeID: id),
            originalPlaybackURL: URL(string: "https://example.com/\(id).mp3")!,
            canonicalEnclosureURL: "https://example.com/\(id).mp3",
            title: id,
            sourceName: feedID,
            publicationDate: .now,
            durationSeconds: 60,
            normalizedCoreDataProgress: isCompleted ? 1 : 0,
            isCompleted: isCompleted,
            sourcePriority: 0,
            sourceFrequency: .daily
        )
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

    @MainActor
    func waitUntilPresentationReady() async throws {
        for _ in 0..<100 {
            if coordinator.presentation.isReady { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for ready presentation")
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
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

    func complete(success: Bool) {}
    func cancel() {}
}
