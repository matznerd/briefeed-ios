import Foundation
import Testing
@testable import Briefeed

@Suite("Radio source configuration")
@MainActor
struct RadioSourceConfigurationTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func disablingPlayingCurrentRemovesItAndPausesOnNextEligibleEpisode() async {
        let current = candidate("npr", priority: 0)
        let next = candidate("bbc", priority: 1)
        let store = FakeRadioSessionStore(snapshot: session([entry(current.key), entry(next.key)], current: current.key))
        let repository = FakeRadioEpisodeRepository(candidates: [current, next])
        let coordinator = makeCoordinator(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.setPlaybackStateForTesting(.playing)
        repository.values = [next]

        let intent = coordinator.sourceConfigurationDidChange(enabledSourceCount: 1)

        #expect(intent == .pause)
        #expect(coordinator.currentKey == next.key)
        #expect(coordinator.entries.map(\.key) == [next.key])
        #expect(coordinator.state == .readyPaused)
        #expect(!coordinator.canPlayNext)
        #expect(store.savedNow?.currentKey == next.key)
    }

    @Test func priorityChangeReordersPendingAndKeepsPlayingCurrent() async {
        let current = candidate("current", priority: 0)
        let first = candidate("first", priority: 1)
        let second = candidate("second", priority: 2)
        let store = FakeRadioSessionStore(snapshot: session([entry(current.key), entry(first.key), entry(second.key)], current: current.key))
        let repository = FakeRadioEpisodeRepository(candidates: [current, first, second])
        let coordinator = makeCoordinator(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.setPlaybackStateForTesting(.playing)
        repository.values = [current, candidate("first", priority: 2), candidate("second", priority: 1)]

        let intent = coordinator.sourceConfigurationDidChange(enabledSourceCount: 3)

        #expect(intent == nil)
        #expect(coordinator.currentKey == current.key)
        #expect(coordinator.entries.map(\.key) == [current.key, second.key, first.key])
        #expect(coordinator.state == .playing)
        #expect(coordinator.canPlayNext)
        #expect(store.savedNow?.entries.map(\.key) == [current.key, second.key, first.key])
    }

    @Test func disablingPendingSourceRemovesItWithoutInterruptingCurrent() async {
        let current = candidate("current", priority: 0)
        let disabledPending = candidate("disabled", priority: 1)
        let store = FakeRadioSessionStore(snapshot: session([entry(current.key), entry(disabledPending.key)], current: current.key))
        let repository = FakeRadioEpisodeRepository(candidates: [current, disabledPending])
        let coordinator = makeCoordinator(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.setPlaybackStateForTesting(.playing)
        repository.values = [current]

        #expect(coordinator.sourceConfigurationDidChange(enabledSourceCount: 1) == nil)
        #expect(coordinator.currentKey == current.key)
        #expect(coordinator.entries.map(\.key) == [current.key])
        #expect(coordinator.state == .playing)
        #expect(!coordinator.canPlayNext)
    }

    @Test func disablingLastPlayingSourcePausesAndTransitionsToNoSources() async {
        let current = candidate("current", priority: 0)
        let store = FakeRadioSessionStore(snapshot: session([entry(current.key)], current: current.key))
        let repository = FakeRadioEpisodeRepository(candidates: [current])
        let coordinator = makeCoordinator(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.setPlaybackStateForTesting(.playing)
        repository.values = []

        #expect(coordinator.sourceConfigurationDidChange(enabledSourceCount: 0) == .pause)
        #expect(coordinator.currentKey == nil)
        #expect(coordinator.entries.isEmpty)
        #expect(coordinator.state == .noSources)
        #expect(!coordinator.canPlayNext)
    }

    @Test func repositoryReadFailurePreservesActiveSession() async {
        let current = candidate("current", priority: 0)
        let store = FakeRadioSessionStore(snapshot: session([entry(current.key)], current: current.key))
        let repository = FakeRadioEpisodeRepository(candidates: [current])
        let coordinator = makeCoordinator(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.setPlaybackStateForTesting(.playing)
        repository.readError = SourceConfigurationTestError.failed

        #expect(coordinator.sourceConfigurationDidChange(enabledSourceCount: 1) == nil)
        #expect(coordinator.currentKey == current.key)
        #expect(coordinator.entries.map(\.key) == [current.key])
        #expect(coordinator.state == .playing)
    }

    @Test func snapshotSaveFailureKeepsReconciledPlayingSessionInMemory() async {
        let current = candidate("current", priority: 0)
        let first = candidate("first", priority: 1)
        let second = candidate("second", priority: 2)
        let store = FakeRadioSessionStore(snapshot: session([entry(current.key), entry(first.key), entry(second.key)], current: current.key))
        let repository = FakeRadioEpisodeRepository(candidates: [current, first, second])
        let coordinator = makeCoordinator(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.setPlaybackStateForTesting(.playing)
        store.saveNowError = SourceConfigurationTestError.failed
        repository.values = [current, candidate("first", priority: 2), candidate("second", priority: 1)]

        #expect(coordinator.sourceConfigurationDidChange(enabledSourceCount: 3) == nil)
        #expect(coordinator.entries.map(\.key) == [current.key, second.key, first.key])
        #expect(coordinator.state == .playing)
        #expect(store.savedNow == nil)
    }

    @Test func deletingPlayingCurrentRemovesItAndPausesOnNextEligibleEpisode() async {
        let deleted = candidate("deleted", priority: 0)
        let next = candidate("next", priority: 1)
        let store = FakeRadioSessionStore(snapshot: session([entry(deleted.key), entry(next.key)], current: deleted.key))
        let repository = FakeRadioEpisodeRepository(candidates: [deleted, next])
        let coordinator = makeCoordinator(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.setPlaybackStateForTesting(.playing)

        repository.values = [next]
        let intent = coordinator.sourceConfigurationDidChange(enabledSourceCount: 1)

        #expect(intent == .pause)
        #expect(coordinator.currentKey == next.key)
        #expect(coordinator.entries.map(\.key) == [next.key])
        #expect(coordinator.state == .readyPaused)
        #expect(store.savedNow?.currentKey == next.key)
    }

    @Test func deletingPendingSourceRemovesItWithoutInterruptingCurrent() async {
        let current = candidate("current", priority: 0)
        let deleted = candidate("deleted", priority: 1)
        let remaining = candidate("remaining", priority: 2)
        let store = FakeRadioSessionStore(snapshot: session(
            [entry(current.key), entry(deleted.key), entry(remaining.key)],
            current: current.key
        ))
        let repository = FakeRadioEpisodeRepository(candidates: [current, deleted, remaining])
        let coordinator = makeCoordinator(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.setPlaybackStateForTesting(.playing)

        repository.values = [current, remaining]
        let intent = coordinator.sourceConfigurationDidChange(enabledSourceCount: 2)

        #expect(intent == nil)
        #expect(coordinator.currentKey == current.key)
        #expect(coordinator.entries.map(\.key) == [current.key, remaining.key])
        #expect(coordinator.state == .playing)
        #expect(store.savedNow?.entries.map(\.key) == [current.key, remaining.key])
    }

    @Test func successfulAddWorkflowReconcilesFirstSourceWithoutAnotherRefresh() async throws {
        let added = candidate("added", priority: 0)
        let store = FakeRadioSessionStore(snapshot: session([], current: nil))
        let repository = FakeRadioEpisodeRepository(candidates: [])
        let coordinator = makeCoordinator(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        #expect(coordinator.state == .noSources)

        let workflow = AddRSSFeedWorkflow { urlString in
            #expect(urlString == "https://example.com/feed.xml")
            repository.values = [added]
        }
        var callbackCount = 0

        try await workflow.perform(
            urlString: "https://example.com/feed.xml",
            onAdded: {
                callbackCount += 1
                _ = coordinator.sourceConfigurationDidChange(enabledSourceCount: 1)
            }
        )

        #expect(callbackCount == 1)
        #expect(coordinator.currentKey == added.key)
        #expect(coordinator.entries.map(\.key) == [added.key])
        #expect(coordinator.state == .readyPaused)
        #expect(store.savedNow?.currentKey == added.key)
    }

    @Test func failedAddWorkflowDoesNotInvokeCallback() async {
        let workflow = AddRSSFeedWorkflow { _ in
            throw SourceConfigurationTestError.failed
        }
        var callbackInvoked = false

        do {
            try await workflow.perform(
                urlString: "https://example.com/feed.xml",
                onAdded: { callbackInvoked = true }
            )
            Issue.record("Expected add workflow to throw")
        } catch {
            #expect(error is SourceConfigurationTestError)
        }

        #expect(!callbackInvoked)
    }

    private func makeCoordinator(
        store: FakeRadioSessionStore,
        repository: FakeRadioEpisodeRepository
    ) -> RadioSessionCoordinator {
        RadioSessionCoordinator(
            store: store,
            repository: repository,
            now: { now },
            connectivityStatus: { .online }
        )
    }

    private func candidate(_ feedID: String, priority: Int) -> RadioEpisodeCandidate {
        RadioEpisodeCandidate(
            key: RadioEpisodeKey(feedID: feedID, episodeID: "latest"),
            originalPlaybackURL: URL(string: "https://example.com/\(feedID).mp3")!,
            canonicalEnclosureURL: "https://example.com/\(feedID).mp3",
            title: feedID,
            sourceName: feedID,
            publicationDate: now,
            durationSeconds: 60,
            normalizedCoreDataProgress: 0,
            isCompleted: false,
            sourcePriority: priority,
            sourceFrequency: .hourly
        )
    }

    private func entry(_ key: RadioEpisodeKey) -> RadioQueueEntry {
        RadioQueueEntry(
            key: key,
            positionSeconds: 0,
            disposition: .pending,
            playbackFailureCount: 0,
            lastPlaybackError: nil
        )
    }

    private func session(
        _ entries: [RadioQueueEntry],
        current: RadioEpisodeKey?
    ) -> PersistedRadioSession {
        PersistedRadioSession(
            schemaVersion: PersistedRadioSession.schemaVersion,
            entries: entries,
            currentKey: current,
            savedAt: now
        )
    }
}

private enum SourceConfigurationTestError: Error {
    case failed
}
