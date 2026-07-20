import Foundation
import Testing
@testable import Briefeed

@Suite("Radio session coordinator restore")
@MainActor
struct RadioSessionCoordinatorRestoreTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    @Test func pausedRestoreUsesLocalSessionWithoutAutoplay() async {
        let episode = candidate("npr", "one")
        let store = FakeRadioSessionStore(snapshot: session([entry(episode.key, position: 17)], current: episode.key))
        let coordinator = makeCoordinator(store: store, candidates: [episode])

        #expect(await coordinator.restore(autoplayEnabled: false) == nil)
        #expect(coordinator.currentKey == episode.key)
        #expect(coordinator.currentEpisode == episode)
        #expect(coordinator.state == .readyPaused)
    }

    @Test func eligibleRestoreAutoplaysOnceOnly() async {
        let episode = candidate("npr", "one")
        let coordinator = makeCoordinator(store: FakeRadioSessionStore(snapshot: session([entry(episode.key, position: 17)], current: episode.key)), candidates: [episode])

        #expect(await coordinator.restore(autoplayEnabled: true) == .play(request(for: episode, position: 17)))
        #expect(await coordinator.restore(autoplayEnabled: true) == nil)
    }

    @Test func deferredAutoplayIsEligibleAt59SecondsButExpiresAt60() async {
        var clock = now
        let repository = FakeRadioEpisodeRepository(candidates: [])
        let coordinator = RadioSessionCoordinator(store: FakeRadioSessionStore(), repository: repository, now: { clock }, connectivityStatus: { .online })

        #expect(await coordinator.restore(autoplayEnabled: true) == nil)
        clock = now.addingTimeInterval(59)
        let episode = candidate("npr", "one", date: clock)
        repository.values = [episode]
        #expect(coordinator.applyInitialRefresh(success()) == .play(request(for: episode, position: 0)))

        clock = now
        repository.values = []
        let expired = RadioSessionCoordinator(store: FakeRadioSessionStore(), repository: repository, now: { clock }, connectivityStatus: { .online })
        #expect(await expired.restore(autoplayEnabled: true) == nil)
        clock = now.addingTimeInterval(60)
        repository.values = [episode]
        #expect(expired.applyInitialRefresh(success()) == nil)
        #expect(!expired.hasPendingColdLaunchAutoplay)
    }

    @Test func manualPlaybackCancelsDeferredColdLaunchOpportunity() async {
        let repository = FakeRadioEpisodeRepository(candidates: [])
        let coordinator = RadioSessionCoordinator(store: FakeRadioSessionStore(), repository: repository, now: { now }, connectivityStatus: { .online })
        #expect(await coordinator.restore(autoplayEnabled: true) == nil)
        coordinator.cancelPendingColdLaunchAutoplay()
        repository.values = [candidate("npr", "one")]
        #expect(coordinator.applyRefresh(success()) == nil)
    }

    @Test func invalidCurrentIsRepairedAndLocalEntriesWinBeforeRefresh() async {
        let episode = candidate("npr", "one")
        let coordinator = makeCoordinator(store: FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: key("missing", "x"))), candidates: [episode])

        #expect(await coordinator.restore(autoplayEnabled: false) == nil)
        #expect(coordinator.currentKey == episode.key)
        #expect(coordinator.currentEpisode == episode)
    }

    @Test func selectingEligibleEpisodeDefersPartialCurrentPersistsAndUsesSavedPosition() async {
        let first = candidate("npr", "one")
        let selected = candidate("bbc", "two")
        let store = FakeRadioSessionStore(snapshot: session([entry(first.key, position: 19), entry(selected.key, position: 8)], current: first.key))
        let coordinator = makeCoordinator(store: store, candidates: [first, selected])
        _ = await coordinator.restore(autoplayEnabled: false)

        #expect(coordinator.selectEpisode(selected.key) == .play(request(for: selected, position: 8)))
        #expect(coordinator.currentKey == selected.key)
        #expect(coordinator.entries.filter { $0.key == selected.key }.count == 1)
        #expect(coordinator.entries.first { $0.key == first.key }?.disposition == .deferred)
        #expect(store.savedNow?.currentKey == selected.key)
    }

    @Test func selectingCompletedMissingOrExpiredEpisodeIsNoOp() async {
        let current = candidate("npr", "one")
        let completed = candidate("bbc", "done", completed: true)
        let expired = candidate("bbc", "old", date: now.addingTimeInterval(-7_201))
        let coordinator = makeCoordinator(store: FakeRadioSessionStore(snapshot: session([entry(current.key)], current: current.key)), candidates: [current, completed, expired])
        _ = await coordinator.restore(autoplayEnabled: false)

        #expect(coordinator.selectEpisode(completed.key) == nil)
        #expect(coordinator.selectEpisode(expired.key) == nil)
        #expect(coordinator.selectEpisode(key("missing", "x")) == nil)
        #expect(coordinator.currentKey == current.key)
    }

    @Test func restoreAndRefreshReadFailuresKeepExistingSessionAndActiveIdentity() async {
        let episode = candidate("npr", "one")
        let store = FakeRadioSessionStore(snapshot: session([entry(episode.key, position: 11)], current: episode.key))
        let repository = FakeRadioEpisodeRepository(candidates: [episode])
        let coordinator = RadioSessionCoordinator(store: store, repository: repository, now: { now }, connectivityStatus: { .online })
        _ = await coordinator.restore(autoplayEnabled: false)
        _ = coordinator.beginCurrent()
        repository.readError = FakeError.failed
        coordinator.refreshStarted(enabledSourceCount: 1)
        #expect(coordinator.applyRefresh(success()) == nil)
        #expect(coordinator.currentKey == episode.key)
        #expect(coordinator.state == .playing)

        let coldStore = FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key))
        coldStore.loadError = FakeError.failed
        let cold = RadioSessionCoordinator(store: coldStore, repository: FakeRadioEpisodeRepository(candidates: [episode]), now: { now }, connectivityStatus: { .online })
        #expect(await cold.restore(autoplayEnabled: false) == nil)
        #expect(cold.entries.isEmpty)
        #expect(cold.state == .failed(.persistence(FakeError.failed.localizedDescription)))

        let activeStore = FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key))
        let activeRepository = FakeRadioEpisodeRepository(candidates: [episode])
        let active = RadioSessionCoordinator(store: activeStore, repository: activeRepository, now: { now }, connectivityStatus: { .online })
        _ = await active.restore(autoplayEnabled: false)
        _ = active.beginCurrent()
        activeRepository.values = [candidate("bbc", "other")]
        activeStore.loadError = FakeError.failed
        #expect(await active.restore(autoplayEnabled: false) == nil)
        #expect(active.currentKey == episode.key)
        #expect(active.beginCurrent() == .play(request(for: episode, position: 0)))
    }

    @Test func selectionDoesNotPublishOrMutateUntilForcedSaveSucceedsAndRejectsFailedEntries() async {
        let first = candidate("npr", "one")
        let failed = candidate("bbc", "failed")
        let selected = candidate("bbc", "two")
        let store = FakeRadioSessionStore(snapshot: session([entry(first.key, position: 12), entry(failed.key, disposition: .failedThisSession), entry(selected.key, position: 7)], current: first.key))
        let coordinator = makeCoordinator(store: store, candidates: [first, failed, selected])
        _ = await coordinator.restore(autoplayEnabled: false)
        let before = coordinator.entries
        store.saveNowError = FakeError.failed
        #expect(coordinator.selectEpisode(selected.key) == nil)
        #expect(coordinator.entries == before)
        #expect(coordinator.selectEpisode(failed.key) == nil)
    }

    @Test func refreshPreservesPlayingLoadingAndPausedStatesForSameCurrent() async {
        let episode = candidate("npr", "one")
        let coordinator = makeCoordinator(store: FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key)), candidates: [episode])
        _ = await coordinator.restore(autoplayEnabled: false)
        for state in [RadioSessionState.playing, .loading, .pausedByUser] {
            coordinator.setPlaybackStateForTesting(state)
            coordinator.refreshStarted(enabledSourceCount: 1)
            coordinator.applyRefresh(success())
            #expect(coordinator.state == state)
        }
    }

    @Test func repeatedRestoreDoesNotResetAnActiveCurrentState() async {
        let episode = candidate("npr", "one")
        let coordinator = makeCoordinator(store: FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key)), candidates: [episode])
        _ = await coordinator.restore(autoplayEnabled: false)
        _ = coordinator.beginCurrent()
        _ = await coordinator.restore(autoplayEnabled: false)
        #expect(coordinator.currentKey == episode.key)
        #expect(coordinator.state == .playing)
    }

    @Test func onlyExplicitInitialRefreshCanConsumeDeferredAutoplay() async {
        var clock = now
        let repository = FakeRadioEpisodeRepository(candidates: [])
        let coordinator = RadioSessionCoordinator(store: FakeRadioSessionStore(), repository: repository, now: { clock }, connectivityStatus: { .online })
        _ = await coordinator.restore(autoplayEnabled: true)
        repository.values = [candidate("npr", "one")]
        clock = now.addingTimeInterval(59)
        #expect(coordinator.applyRefresh(success()) == nil)
        #expect(coordinator.hasPendingColdLaunchAutoplay)
        #expect(coordinator.applyInitialRefresh(success()) == nil)
        #expect(!coordinator.hasPendingColdLaunchAutoplay)

        let offlineRepository = FakeRadioEpisodeRepository(candidates: [])
        let offline = RadioSessionCoordinator(store: FakeRadioSessionStore(), repository: offlineRepository, now: { now }, connectivityStatus: { .online })
        _ = await offline.restore(autoplayEnabled: true)
        offlineRepository.values = [candidate("bbc", "ordinary")]
        #expect(offline.applyRefresh(success()) == nil)
        #expect(offline.currentKey == key("bbc", "ordinary"))
        #expect(offline.applyInitialRefresh(.init(results: [.init(feedID: "npr", outcome: .skippedOffline)])) == nil)
        #expect(offline.hasPendingColdLaunchAutoplay)
    }

    private func makeCoordinator(store: FakeRadioSessionStore, candidates: [RadioEpisodeCandidate]) -> RadioSessionCoordinator {
        RadioSessionCoordinator(store: store, repository: FakeRadioEpisodeRepository(candidates: candidates), now: { now }, connectivityStatus: { .online })
    }

    private func success() -> RSSRefreshBatchResult { .init(results: [.init(feedID: "npr", outcome: .success(insertedEpisodeIDs: ["one"]))]) }
    private func key(_ feed: String, _ episode: String) -> RadioEpisodeKey { .init(feedID: feed, episodeID: episode) }
    private func entry(_ key: RadioEpisodeKey, position: TimeInterval = 0, disposition: RadioEntryDisposition = .pending) -> RadioQueueEntry { .init(key: key, positionSeconds: position, disposition: disposition, playbackFailureCount: 0, lastPlaybackError: nil) }
    private func session(_ entries: [RadioQueueEntry], current: RadioEpisodeKey?) -> PersistedRadioSession { .init(schemaVersion: 1, entries: entries, currentKey: current, savedAt: now) }
    private func request(for candidate: RadioEpisodeCandidate, position: TimeInterval) -> RadioPlaybackRequest { .init(key: candidate.key, url: candidate.originalPlaybackURL, title: candidate.title, source: candidate.sourceName, positionSeconds: position) }
    private func candidate(_ feed: String, _ episode: String, date: Date? = nil, completed: Bool = false) -> RadioEpisodeCandidate { .init(key: key(feed, episode), originalPlaybackURL: URL(string: "https://example.com/\(feed)-\(episode).mp3")!, canonicalEnclosureURL: "https://example.com/\(feed)-\(episode).mp3", title: episode, sourceName: feed, publicationDate: date ?? now, durationSeconds: 60, normalizedCoreDataProgress: 0, isCompleted: completed, sourcePriority: 0, sourceFrequency: .hourly) }
}

@MainActor
final class FakeRadioSessionStore: RadioSessionStoreProtocol {
    var snapshot: PersistedRadioSession?
    var savedNow: PersistedRadioSession?
    var loadError: Error?
    var saveNowError: Error?
    init(snapshot: PersistedRadioSession? = nil) { self.snapshot = snapshot }
    func load(durations: [RadioEpisodeKey: TimeInterval]) throws -> PersistedRadioSession? { if let loadError { throw loadError }; return snapshot }
    func saveDebounced(_ session: PersistedRadioSession) { snapshot = session }
    func saveNow(_ session: PersistedRadioSession) throws { if let saveNowError { throw saveNowError }; savedNow = session; snapshot = session }
    func clear() { snapshot = nil }
}

@MainActor
final class FakeRadioEpisodeRepository: RadioEpisodeRepository {
    var values: [RadioEpisodeCandidate]
    var readError: Error?
    init(candidates: [RadioEpisodeCandidate]) { values = candidates }
    func candidates() throws -> [RadioEpisodeCandidate] { if let readError { throw readError }; return values }
    func candidate(for key: RadioEpisodeKey) throws -> RadioEpisodeCandidate? { if let readError { throw readError }; return values.first { $0.key == key } }
    func saveProgress(key: RadioEpisodeKey, seconds: TimeInterval, duration: TimeInterval?) throws {}
    func markCompleted(key: RadioEpisodeKey, at date: Date) throws {}
}

private enum FakeError: LocalizedError { case failed; var errorDescription: String? { "test failure" } }
