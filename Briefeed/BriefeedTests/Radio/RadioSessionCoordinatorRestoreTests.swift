import Foundation
import Combine
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

    @Test func remoteRestoreWaitsForOpeningRefreshAndAutoplaysLatestOnce() async {
        let previous = candidate("npr", "previous", date: now.addingTimeInterval(-3_600))
        let latest = candidate("npr", "latest")
        let repository = FakeRadioEpisodeRepository(candidates: [previous])
        let coordinator = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: session([entry(previous.key, position: 17)], current: previous.key)),
            repository: repository,
            now: { now },
            connectivityStatus: { .online }
        )

        #expect(await coordinator.restore(autoplayEnabled: true) == nil)
        #expect(coordinator.hasPendingColdLaunchAutoplay)
        #expect(coordinator.currentKey == previous.key)
        #expect(coordinator.state == .readyPaused)

        repository.values = [previous, latest]
        coordinator.refreshStarted(enabledSourceCount: 1)
        #expect(coordinator.applyInitialRefresh(success()) == .play(request(for: latest, position: 0)))
        #expect(coordinator.currentKey == latest.key)
        #expect(coordinator.state == .loading)
        coordinator.transportDidStart(for: latest.key)
        #expect(coordinator.state == .playing)
        #expect(await coordinator.restore(autoplayEnabled: true) == nil)
        #expect(coordinator.state == .playing)
    }

    @Test func connectivityAloneCannotBypassOpeningRefreshGate() async {
        let episode = candidate("npr", "one")
        let monitor = TestConnectivityMonitor(.unknown)
        let scheduler = TestRadioRetryScheduler()
        let coordinator = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: session([entry(episode.key, position: 17)], current: episode.key)),
            repository: FakeRadioEpisodeRepository(candidates: [episode]), now: { now },
            connectivity: monitor, retryScheduler: scheduler
        )
        var intents: [RadioPlaybackIntent] = []
        let cancellable = coordinator.pendingNetworkIntentPublisher.sink { intents.append($0) }

        #expect(await coordinator.restore(autoplayEnabled: true) == nil)
        #expect(coordinator.hasPendingColdLaunchAutoplay)
        #expect(scheduler.scheduledDelays.isEmpty)
        monitor.send(.offline)
        #expect(scheduler.scheduledDelays.isEmpty)
        monitor.send(.online)
        #expect(scheduler.scheduledDelays.isEmpty)
        scheduler.fire()
        scheduler.fire()
        #expect(intents.isEmpty)
        #expect(coordinator.hasPendingColdLaunchAutoplay)

        coordinator.refreshStarted(enabledSourceCount: 1)
        #expect(coordinator.applyInitialRefresh(success()) == .play(request(for: episode, position: 17)))
        #expect(!coordinator.hasPendingColdLaunchAutoplay)
        withExtendedLifetime(cancellable) {}
    }

    @Test func readableLocalRestoreAutoplaysWhileConnectivityUnknown() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let base = candidate("npr", "one")
        let local = RadioEpisodeCandidate(
            key: base.key, originalPlaybackURL: url, canonicalEnclosureURL: url.absoluteString,
            title: base.title, sourceName: base.sourceName, publicationDate: base.publicationDate,
            durationSeconds: base.durationSeconds, normalizedCoreDataProgress: 0,
            isCompleted: false, sourcePriority: 0, sourceFrequency: .hourly
        )
        let coordinator = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: session([entry(local.key)], current: local.key)),
            repository: FakeRadioEpisodeRepository(candidates: [local]), now: { now },
            connectivity: TestConnectivityMonitor(.unknown)
        )

        #expect(await coordinator.restore(autoplayEnabled: true) == .play(request(for: local, position: 0)))
        #expect(coordinator.state == .loading)
    }

    @Test func initialRefreshRemoteAutoplayWaitsForConnectivity() async {
        let repository = FakeRadioEpisodeRepository(candidates: [])
        let monitor = TestConnectivityMonitor(.offline)
        let scheduler = TestRadioRetryScheduler()
        let coordinator = RadioSessionCoordinator(
            store: FakeRadioSessionStore(), repository: repository, now: { now },
            connectivity: monitor, retryScheduler: scheduler
        )
        var intents: [RadioPlaybackIntent] = []
        let cancellable = coordinator.pendingNetworkIntentPublisher.sink { intents.append($0) }
        _ = await coordinator.restore(autoplayEnabled: true)
        let episode = candidate("npr", "one")
        repository.values = [episode]

        #expect(coordinator.applyInitialRefresh(success()) == nil)
        #expect(intents.isEmpty)
        #expect(scheduler.scheduledDelays.isEmpty)
        monitor.send(.online)
        scheduler.fire()
        #expect(intents == [.play(request(for: episode, position: 0))])
        withExtendedLifetime(cancellable) {}
    }

    @Test func cancelAutoplayPreventsDelayedReconnectAndExpiredAutoplayNeverEmits() async {
        var clock = now
        let episode = candidate("npr", "one")
        let monitor = TestConnectivityMonitor(.unknown)
        let scheduler = TestRadioRetryScheduler()
        let coordinator = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key)),
            repository: FakeRadioEpisodeRepository(candidates: [episode]), now: { clock },
            connectivity: monitor, retryScheduler: scheduler
        )
        var intents: [RadioPlaybackIntent] = []
        let cancellable = coordinator.pendingNetworkIntentPublisher.sink { intents.append($0) }
        _ = await coordinator.restore(autoplayEnabled: true)
        monitor.send(.online)
        coordinator.cancelPendingColdLaunchAutoplay()
        scheduler.fireCanceledActionAnyway()
        #expect(intents.isEmpty)

        let expiredScheduler = TestRadioRetryScheduler()
        let expiredMonitor = TestConnectivityMonitor(.unknown)
        let expired = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key)),
            repository: FakeRadioEpisodeRepository(candidates: [episode]), now: { clock },
            connectivity: expiredMonitor, retryScheduler: expiredScheduler
        )
        var expiredIntents: [RadioPlaybackIntent] = []
        let expiredCancellable = expired.pendingNetworkIntentPublisher.sink { expiredIntents.append($0) }
        _ = await expired.restore(autoplayEnabled: true)
        clock = now.addingTimeInterval(60)
        expiredMonitor.send(.online)
        expiredScheduler.fire()
        #expect(expired.applyInitialRefresh(success()) == nil)
        #expect(expiredIntents.isEmpty)
        #expect(!expired.hasPendingColdLaunchAutoplay)
        withExtendedLifetime((cancellable, expiredCancellable)) {}
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
        #expect(coordinator.state == .loading)
        coordinator.transportDidStart(for: episode.key)
        #expect(coordinator.state == .playing)

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

    @Test func selectingMissingOrExpiredEpisodeIsNoOp() async {
        let current = candidate("npr", "one")
        let expired = candidate("bbc", "old", date: now.addingTimeInterval(-86_401))
        let coordinator = makeCoordinator(
            store: FakeRadioSessionStore(snapshot: session([entry(current.key)], current: current.key)),
            candidates: [current, expired]
        )
        _ = await coordinator.restore(autoplayEnabled: false)

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
        #expect(coordinator.state == .loading)

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

    @Test func selectionDoesNotPublishOrMutateUntilForcedSaveSucceeds() async {
        let first = candidate("npr", "one")
        let selected = candidate("bbc", "two")
        let store = FakeRadioSessionStore(snapshot: session([entry(first.key, position: 12), entry(selected.key, position: 7)], current: first.key))
        let coordinator = makeCoordinator(store: store, candidates: [first, selected])
        _ = await coordinator.restore(autoplayEnabled: false)
        let before = coordinator.entries
        store.saveNowError = FakeError.failed
        #expect(coordinator.selectEpisode(selected.key) == nil)
        #expect(coordinator.entries == before)
    }

    @Test func selectionRejectsEntryThatFailedInTheCurrentSession() async {
        let failed = candidate("npr", "failed")
        let next = candidate("bbc", "next")
        let scheduler = TestRadioRetryScheduler()
        let coordinator = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: session([entry(failed.key), entry(next.key)], current: failed.key)),
            repository: FakeRadioEpisodeRepository(candidates: [failed, next]), now: { now },
            connectivityStatus: { .online }, retryScheduler: scheduler
        )
        _ = await coordinator.restore(autoplayEnabled: false)
        _ = coordinator.playbackFailed(for: failed.key, message: "one", positionSeconds: 1, duration: 60, connectivity: .online)
        scheduler.fire()
        _ = coordinator.playbackFailed(for: failed.key, message: "two", positionSeconds: 2, duration: 60, connectivity: .online)

        #expect(coordinator.selectEpisode(failed.key) == nil)
        #expect(coordinator.currentKey == next.key)
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
        #expect(coordinator.state == .loading)
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
        #expect(coordinator.applyInitialRefresh(success()) == .play(request(for: repository.values[0], position: 0)))
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
    private func request(for candidate: RadioEpisodeCandidate, position: TimeInterval) -> RadioPlaybackRequest { .init(key: candidate.key, url: candidate.originalPlaybackURL, title: candidate.displayTitle(), source: candidate.sourceName, positionSeconds: position) }
    private func candidate(_ feed: String, _ episode: String, date: Date? = nil, completed: Bool = false) -> RadioEpisodeCandidate { .init(key: key(feed, episode), originalPlaybackURL: URL(string: "https://example.com/\(feed)-\(episode).mp3")!, canonicalEnclosureURL: "https://example.com/\(feed)-\(episode).mp3", title: episode, sourceName: feed, publicationDate: date ?? now, durationSeconds: 60, normalizedCoreDataProgress: 0, isCompleted: completed, sourcePriority: 0, sourceFrequency: .hourly) }
}

@MainActor
final class FakeRadioSessionStore: RadioSessionStoreProtocol {
    var snapshot: PersistedRadioSession?
    var savedNow: PersistedRadioSession?
    var debouncedSaves: [PersistedRadioSession] = []
    var forcedSaves: [PersistedRadioSession] = []
    var loadError: Error?
    var saveNowError: Error?
    private let onSaveNow: () -> Void
    init(snapshot: PersistedRadioSession? = nil, onSaveNow: @escaping () -> Void = {}) {
        self.snapshot = snapshot
        self.onSaveNow = onSaveNow
    }
    func load(durations: [RadioEpisodeKey: TimeInterval]) throws -> PersistedRadioSession? { if let loadError { throw loadError }; return snapshot }
    func saveDebounced(_ session: PersistedRadioSession) { debouncedSaves.append(session); snapshot = session }
    func saveNow(_ session: PersistedRadioSession) throws {
        if let saveNowError { throw saveNowError }
        onSaveNow()
        savedNow = session
        forcedSaves.append(session)
        snapshot = session
    }
    func clear() { snapshot = nil }
    func resetCalls() { savedNow = nil; debouncedSaves = []; forcedSaves = [] }
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
    func restartForReplay(key: RadioEpisodeKey) throws -> RadioEpisodeCandidate? {
        values.first { $0.key == key }
    }
}

private enum FakeError: LocalizedError { case failed; var errorDescription: String? { "test failure" } }

@MainActor
final class TestConnectivityMonitor: ConnectivityMonitoring {
    private let subject: CurrentValueSubject<ConnectivityStatus, Never>
    var status: ConnectivityStatus { subject.value }
    var statusPublisher: AnyPublisher<ConnectivityStatus, Never> { subject.eraseToAnyPublisher() }

    init(_ status: ConnectivityStatus) { subject = .init(status) }
    func send(_ status: ConnectivityStatus) { subject.send(status) }
}
