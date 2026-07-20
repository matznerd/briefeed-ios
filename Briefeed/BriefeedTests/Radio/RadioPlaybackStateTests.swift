import Combine
import Foundation
import Testing
@testable import Briefeed

@Suite("Radio playback state")
@MainActor
struct RadioPlaybackStateTests {
    let now = Date(timeIntervalSince1970: 20_000)

    @Test func progressPersistsAtRealFiveSecondBoundariesAndAlwaysUpdatesMemory() async {
        let episode = candidate("one")
        let store = FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key))
        let repository = CompletionRepository(candidates: [episode])
        let coordinator = make(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        store.resetCalls()

        coordinator.recordProgress(for: episode.key, positionSeconds: 1, duration: 100)
        coordinator.recordProgress(for: episode.key, positionSeconds: 4.9, duration: 100)
        #expect(repository.progressWrites.isEmpty)
        #expect(store.debouncedSaves.isEmpty)
        #expect(coordinator.entries[0].positionSeconds == 4.9)

        coordinator.recordProgress(for: episode.key, positionSeconds: 5, duration: 100)
        coordinator.recordProgress(for: episode.key, positionSeconds: 9.9, duration: 100)
        coordinator.recordProgress(for: episode.key, positionSeconds: 10, duration: 100)
        #expect(repository.progressWrites.map(\.seconds) == [5, 10])
        #expect(store.debouncedSaves.count == 2)
        #expect(coordinator.entries[0].positionSeconds == 10)
    }

    @Test func nonFiniteProgressIsSanitizedBeforeBucketConversion() async {
        let episode = candidate("one")
        let coordinator = make(candidates: [episode])
        _ = await coordinator.restore(autoplayEnabled: false)

        coordinator.recordProgress(for: episode.key, positionSeconds: .nan, duration: 100)
        coordinator.recordProgress(for: episode.key, positionSeconds: .infinity, duration: 100)

        #expect(coordinator.entries[0].positionSeconds == 0)
    }

    @Test func staleLowLevelCallbacksCannotMutateOrCompleteCurrent() async {
        let first = candidate("one"); let second = candidate("two")
        let repository = CompletionRepository(candidates: [first, second])
        let coordinator = make(
            store: FakeRadioSessionStore(snapshot: session([entry(first.key), entry(second.key)], current: first.key)),
            repository: repository
        )
        _ = await coordinator.restore(autoplayEnabled: false)
        _ = coordinator.selectEpisode(second.key)

        coordinator.recordProgress(for: first.key, positionSeconds: 88, duration: 100)
        #expect(coordinator.entries.first { $0.key == second.key }?.positionSeconds == 0)
        #expect(coordinator.playbackFailed(for: first.key, message: "stale", positionSeconds: 88, duration: 100, connectivity: .online) == nil)
        #expect(coordinator.playbackCompleted(for: first.key, at: now) == nil)
        #expect(repository.completed.isEmpty)
        #expect(coordinator.currentKey == second.key)
    }

    @Test func nextDefersCurrentAtDeferredTailBeforeFailedEntries() async {
        let first = candidate("one"); let next = candidate("two"); let deferred = candidate("three"); let failed = candidate("four")
        let snapshot = session([
            entry(failed.key), entry(first.key), entry(next.key), entry(deferred.key, disposition: .deferred)
        ], current: failed.key)
        let scheduler = TestRadioRetryScheduler()
        let coordinator = make(
            store: FakeRadioSessionStore(snapshot: snapshot),
            repository: CompletionRepository(candidates: [first, next, deferred, failed]),
            scheduler: scheduler
        )
        _ = await coordinator.restore(autoplayEnabled: false)
        _ = coordinator.playbackFailed(for: failed.key, message: "one", positionSeconds: 1, duration: 300, connectivity: .online)
        scheduler.fire()
        _ = coordinator.playbackFailed(for: failed.key, message: "two", positionSeconds: 2, duration: 300, connectivity: .online)
        #expect(coordinator.currentKey == first.key)
        #expect(coordinator.entries.first { $0.key == failed.key }?.disposition == .failedThisSession)

        #expect(coordinator.manualNext(positionSeconds: 42, duration: 300)?.key == next.key)
        #expect(coordinator.entries.map(\.key) == [next.key, deferred.key, first.key, failed.key])
        #expect(coordinator.entries[2].disposition == .deferred)
    }

    @Test func selectingAnotherEpisodeCompletesNearlyFinishedCurrentInsteadOfDeferringIt() async {
        let first = candidate("one"); let selected = candidate("two")
        let repository = CompletionRepository(candidates: [first, selected])
        let store = FakeRadioSessionStore(snapshot: session([entry(first.key), entry(selected.key)], current: first.key))
        let coordinator = make(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.recordProgress(for: first.key, positionSeconds: 286, duration: 300)

        #expect(coordinator.selectEpisode(selected.key)?.key == selected.key)
        #expect(repository.completed == [first.key])
        #expect(!coordinator.entries.contains { $0.key == first.key })
        #expect(coordinator.entries.allSatisfy { $0.disposition != .deferred })
        #expect(store.savedNow?.currentKey == selected.key)
    }

    @Test func failedCompletionWhileSelectingKeepsExactCurrentAndRetryFinishesSelection() async {
        let first = candidate("one"); let selected = candidate("two")
        let repository = CompletionRepository(candidates: [first, selected], completionError: TestError.denied)
        let store = FakeRadioSessionStore(snapshot: session([entry(first.key), entry(selected.key)], current: first.key))
        let coordinator = make(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.recordProgress(for: first.key, positionSeconds: 286.5, duration: 300)

        #expect(coordinator.selectEpisode(selected.key) == nil)
        #expect(coordinator.currentKey == first.key)
        #expect(coordinator.entries.first { $0.key == first.key }?.positionSeconds == 286.5)
        #expect(coordinator.entries.first { $0.key == first.key }?.disposition != .deferred)
        repository.completionError = nil

        #expect(coordinator.retry()?.key == selected.key)
        #expect(repository.completed == [first.key])
        #expect(coordinator.currentKey == selected.key)
    }

    @Test func nearlyCompleteNextRetainsExactPositionWhenCompletionFails() async {
        let first = candidate("one"); let next = candidate("two")
        let repository = CompletionRepository(candidates: [first, next], completionError: TestError.denied)
        let store = FakeRadioSessionStore(snapshot: session([entry(first.key), entry(next.key)], current: first.key))
        let coordinator = make(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        store.resetCalls()

        #expect(coordinator.manualNext(positionSeconds: 95.25, duration: 100) == nil)
        #expect(coordinator.currentKey == first.key)
        #expect(coordinator.entries.first?.positionSeconds == 95.25)
        #expect(repository.progressWrites.last?.seconds == 95.25)
        #expect(store.savedNow?.entries.first?.positionSeconds == 95.25)
        #expect(coordinator.state == .failed(.persistence("denied")))
    }

    @Test func completionBeforeCoreDataSaveLeavesSnapshotResumable() async {
        let episode = candidate("one")
        let repository = CompletionRepository(candidates: [episode], completionError: TestError.denied)
        let store = FakeRadioSessionStore(snapshot: session([entry(episode.key, position: 33)], current: episode.key))
        let coordinator = make(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)

        #expect(coordinator.playbackCompleted(for: episode.key, at: now) == nil)
        #expect(coordinator.currentKey == episode.key)
        #expect(coordinator.entries.contains { $0.key == episode.key })
        #expect(store.snapshot?.entries.contains { $0.key == episode.key } == true)
    }

    @Test func completionAfterCoreDataSaveTreatsCompletedRowAsAuthoritativeInProcess() async {
        let first = candidate("one"); let next = candidate("two")
        let repository = CompletionRepository(candidates: [first, next])
        let store = FakeRadioSessionStore(snapshot: session([entry(first.key), entry(next.key)], current: first.key))
        let coordinator = make(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        store.saveNowError = TestError.denied

        #expect(coordinator.playbackCompleted(for: first.key, at: now) == nil)
        #expect(repository.completed == [first.key])
        #expect(!coordinator.entries.contains { $0.key == first.key })
        #expect(coordinator.currentKey == next.key)
        #expect(coordinator.retry() == nil)
        #expect(coordinator.state == .failed(.persistence("denied")))
    }

    @Test func retryAfterCompletionMarkFailureRetriesCompletionInsteadOfPlayback() async {
        let first = candidate("one"); let next = candidate("two")
        let repository = CompletionRepository(candidates: [first, next], completionError: TestError.denied)
        let store = FakeRadioSessionStore(snapshot: session([entry(first.key, position: 37), entry(next.key)], current: first.key))
        let coordinator = make(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)

        #expect(coordinator.playbackCompleted(for: first.key, at: now) == nil)
        #expect(repository.completionAttempts == [first.key])
        #expect(coordinator.currentKey == first.key)
        #expect(coordinator.entries.first?.positionSeconds == 37)
        repository.completionError = nil

        #expect(coordinator.retry()?.key == next.key)
        #expect(repository.completionAttempts == [first.key, first.key])
        #expect(repository.completed == [first.key])
        #expect(!coordinator.entries.contains { $0.key == first.key })
    }

    @Test func retryAfterSnapshotFailureOnlyRepairsSnapshotAndContinues() async {
        let first = candidate("one"); let next = candidate("two")
        let repository = CompletionRepository(candidates: [first, next])
        let store = FakeRadioSessionStore(snapshot: session([entry(first.key), entry(next.key)], current: first.key))
        let coordinator = make(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        store.saveNowError = TestError.denied

        #expect(coordinator.playbackCompleted(for: first.key, at: now) == nil)
        #expect(repository.completionAttempts == [first.key])
        #expect(coordinator.currentKey == next.key)
        store.saveNowError = nil

        #expect(coordinator.retry()?.key == next.key)
        #expect(repository.completionAttempts == [first.key])
        #expect(store.savedNow?.currentKey == next.key)
        #expect(!store.savedNow!.entries.contains { $0.key == first.key })
    }

    @Test func naturalCompletionReturnsNextIntentAfterCoreDataThenSnapshotSave() async {
        let first = candidate("one"); let next = candidate("two")
        var order: [String] = []
        let repository = CompletionRepository(candidates: [first, next], onCompletion: { order.append("complete") })
        let store = FakeRadioSessionStore(snapshot: session([entry(first.key), entry(next.key)], current: first.key), onSaveNow: { order.append("snapshot") })
        let coordinator = make(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        order.removeAll(); store.resetCalls()

        #expect(coordinator.playbackCompleted(for: first.key, at: now)?.key == next.key)
        #expect(order == ["complete", "snapshot"])
        #expect(store.savedNow?.currentKey == next.key)
        #expect(coordinator.currentKey == next.key)
    }

    @Test func firstOnlineFailureSchedulesExactlyOneDelayedRetry() async {
        let episode = candidate("one")
        let scheduler = TestRadioRetryScheduler()
        let coordinator = make(candidates: [episode], scheduler: scheduler)
        var intents: [RadioPlaybackIntent] = []
        let cancellable = coordinator.pendingNetworkIntentPublisher.sink { intents.append($0) }
        _ = await coordinator.restore(autoplayEnabled: false)

        #expect(coordinator.playbackFailed(for: episode.key, message: "one", positionSeconds: 9, duration: 100, connectivity: .online) == nil)
        #expect(coordinator.entries[0].playbackFailureCount == 1)
        #expect(scheduler.scheduledDelays == [0.5])
        scheduler.fire()
        scheduler.fire()
        #expect(intents.map(\.key) == [episode.key])
        withExtendedLifetime(cancellable) {}
    }

    @Test func oneFailureThenOfflineReconnectUsesOnlyTheRemainingDelayedRetry() async {
        let episode = candidate("one")
        let monitor = TestConnectivityMonitor(.online)
        let scheduler = TestRadioRetryScheduler()
        let coordinator = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key)),
            repository: CompletionRepository(candidates: [episode]), now: { now },
            connectivity: monitor, retryScheduler: scheduler
        )
        var intents: [RadioPlaybackIntent] = []
        let cancellable = coordinator.pendingNetworkIntentPublisher.sink { intents.append($0) }
        _ = await coordinator.restore(autoplayEnabled: false)

        _ = coordinator.playbackFailed(for: episode.key, message: "one", positionSeconds: 10, duration: 100, connectivity: .online)
        #expect(coordinator.entries[0].playbackFailureCount == 1)
        monitor.send(.offline)
        scheduler.fireCanceledActionAnyway()
        #expect(intents.isEmpty)
        monitor.send(.online)
        #expect(scheduler.scheduledDelays.last == 0.5)
        scheduler.fire()
        #expect(intents.map(\.key) == [episode.key])
        #expect(coordinator.entries[0].playbackFailureCount == 1)

        #expect(coordinator.playbackFailed(for: episode.key, message: "two", positionSeconds: 12, duration: 100, connectivity: .online) == nil)
        #expect(coordinator.entries[0].playbackFailureCount == 2)
        #expect(coordinator.entries[0].disposition == .failedThisSession)
        #expect(intents.count == 1)
        withExtendedLifetime(cancellable) {}
    }

    @Test func offlineAndUnknownFailuresConsumeNoAttemptButForceSaveExactPosition() async {
        let episode = candidate("one")
        let store = FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key))
        let scheduler = TestRadioRetryScheduler()
        let coordinator = make(store: store, repository: CompletionRepository(candidates: [episode]), scheduler: scheduler)
        _ = await coordinator.restore(autoplayEnabled: false)
        store.resetCalls()

        for (status, position) in [(ConnectivityStatus.offline, 12.25), (.unknown, 14.5)] {
            #expect(coordinator.playbackFailed(for: episode.key, message: "offline", positionSeconds: position, duration: 100, connectivity: status) == nil)
            #expect(coordinator.entries[0].playbackFailureCount == 0)
            #expect(store.savedNow?.entries[0].positionSeconds == position)
        }
        #expect(scheduler.scheduledDelays.isEmpty)
    }

    @Test func secondFailureStagesFailedDispositionAndNextCursorInOneSave() async {
        let first = candidate("one"); let next = candidate("two")
        let store = FakeRadioSessionStore(snapshot: session([entry(first.key), entry(next.key)], current: first.key))
        let scheduler = TestRadioRetryScheduler()
        let coordinator = make(store: store, repository: CompletionRepository(candidates: [first, next]), scheduler: scheduler)
        _ = await coordinator.restore(autoplayEnabled: false)
        _ = coordinator.playbackFailed(for: first.key, message: "one", positionSeconds: 11, duration: 100, connectivity: .online)
        scheduler.fire()
        store.resetCalls()

        #expect(coordinator.playbackFailed(for: first.key, message: "two", positionSeconds: 17, duration: 100, connectivity: .online)?.key == next.key)
        #expect(store.forcedSaves.count == 1)
        #expect(store.forcedSaves[0].currentKey == next.key)
        #expect(store.forcedSaves[0].entries.first { $0.key == first.key }?.disposition == .failedThisSession)
        #expect(coordinator.currentKey == next.key)
    }

    @Test func onlyFailedQueueRemainsRetryableAndSuccessfulRefreshResetsBeforeReconcile() async {
        let episode = candidate("one")
        let failed = RadioQueueEntry(key: episode.key, positionSeconds: 8, disposition: .failedThisSession, playbackFailureCount: 2, lastPlaybackError: "bad")
        let repository = CompletionRepository(candidates: [episode])
        let scheduler = TestRadioRetryScheduler()
        let coordinator = make(store: FakeRadioSessionStore(snapshot: session([failed], current: episode.key)), repository: repository, scheduler: scheduler)
        _ = await coordinator.restore(autoplayEnabled: false)
        _ = coordinator.playbackFailed(for: episode.key, message: "again", positionSeconds: 8, duration: 100, connectivity: .online)
        scheduler.fire()
        _ = coordinator.playbackFailed(for: episode.key, message: "twice", positionSeconds: 8, duration: 100, connectivity: .online)
        #expect(coordinator.entries[0].disposition == .failedThisSession)

        coordinator.applyRefresh(.init(results: [.init(feedID: "feed", outcome: .success(insertedEpisodeIDs: []))]))
        #expect(coordinator.currentKey == episode.key)
        #expect(coordinator.entries[0].disposition == .pending)
        #expect(coordinator.entries[0].playbackFailureCount == 0)
        #expect(coordinator.beginCurrent()?.key == episode.key)
    }

    @Test func failedRefreshDoesNotResetPlaybackFailureBudget() async {
        let episode = candidate("one")
        let failed = RadioQueueEntry(key: episode.key, positionSeconds: 8, disposition: .failedThisSession, playbackFailureCount: 2, lastPlaybackError: "bad")
        let scheduler = TestRadioRetryScheduler()
        let coordinator = make(store: FakeRadioSessionStore(snapshot: session([failed], current: nil)), repository: CompletionRepository(candidates: [episode]), scheduler: scheduler)
        _ = await coordinator.restore(autoplayEnabled: false)
        _ = coordinator.playbackFailed(for: episode.key, message: "one", positionSeconds: 8, duration: 100, connectivity: .online)
        scheduler.fire()
        _ = coordinator.playbackFailed(for: episode.key, message: "two", positionSeconds: 8, duration: 100, connectivity: .online)

        coordinator.applyRefresh(.init(results: [.init(feedID: "feed", outcome: .failed(message: "refresh failed"))]))
        #expect(coordinator.entries[0].disposition == .failedThisSession)
        #expect(coordinator.entries[0].playbackFailureCount == 2)
        #expect(coordinator.currentKey == nil)
    }

    @Test func explicitRetryRevivesAnAllFailedQueue() async {
        let episode = candidate("one")
        let scheduler = TestRadioRetryScheduler()
        let coordinator = make(candidates: [episode], scheduler: scheduler)
        _ = await coordinator.restore(autoplayEnabled: false)
        _ = coordinator.playbackFailed(for: episode.key, message: "one", positionSeconds: 8, duration: 100, connectivity: .online)
        scheduler.fire()
        _ = coordinator.playbackFailed(for: episode.key, message: "two", positionSeconds: 8, duration: 100, connectivity: .online)
        #expect(coordinator.entries[0].disposition == .failedThisSession)

        #expect(coordinator.retry()?.key == episode.key)
        #expect(coordinator.entries[0].disposition == .pending)
        #expect(coordinator.entries[0].playbackFailureCount == 0)
    }

    @Test func successfulRefreshResetsOnlyItsOwnSource() async {
        let first = candidate("one")
        let other = RadioEpisodeCandidate(
            key: .init(feedID: "other", episodeID: "two"), originalPlaybackURL: URL(string: "https://example.com/two.mp3")!,
            canonicalEnclosureURL: "https://example.com/two.mp3", title: "two", sourceName: "other",
            publicationDate: now, durationSeconds: 300, normalizedCoreDataProgress: 0, isCompleted: false,
            sourcePriority: 1, sourceFrequency: .hourly
        )
        let scheduler = TestRadioRetryScheduler()
        let coordinator = make(
            store: FakeRadioSessionStore(snapshot: session([entry(first.key), entry(other.key)], current: first.key)),
            repository: CompletionRepository(candidates: [first, other]),
            scheduler: scheduler
        )
        _ = await coordinator.restore(autoplayEnabled: false)
        _ = coordinator.playbackFailed(for: first.key, message: "one", positionSeconds: 0, duration: 100, connectivity: .online)
        scheduler.fire()
        _ = coordinator.playbackFailed(for: first.key, message: "two", positionSeconds: 0, duration: 100, connectivity: .online)
        _ = coordinator.playbackFailed(for: other.key, message: "one", positionSeconds: 0, duration: 100, connectivity: .online)
        scheduler.fire()
        _ = coordinator.playbackFailed(for: other.key, message: "two", positionSeconds: 0, duration: 100, connectivity: .online)

        coordinator.applyRefresh(.init(results: [
            .init(feedID: "feed", outcome: .success(insertedEpisodeIDs: [])),
            .init(feedID: "other", outcome: .failed(message: "still down"))
        ]))
        #expect(coordinator.entries.first { $0.key == first.key }?.disposition == .pending)
        #expect(coordinator.entries.first { $0.key == other.key }?.disposition == .failedThisSession)
    }

    @Test func successfulRefreshReselectsFailedEntriesAndRecomputesNextEligibility() async {
        let first = candidate("one")
        let other = RadioEpisodeCandidate(
            key: .init(feedID: "other", episodeID: "two"), originalPlaybackURL: URL(string: "https://example.com/two.mp3")!,
            canonicalEnclosureURL: "https://example.com/two.mp3", title: "two", sourceName: "other",
            publicationDate: now, durationSeconds: 300, normalizedCoreDataProgress: 0, isCompleted: false,
            sourcePriority: 1, sourceFrequency: .hourly
        )
        let scheduler = TestRadioRetryScheduler()
        let coordinator = make(
            store: FakeRadioSessionStore(snapshot: session([entry(first.key), entry(other.key)], current: first.key)),
            repository: CompletionRepository(candidates: [first, other]),
            scheduler: scheduler
        )
        _ = await coordinator.restore(autoplayEnabled: false)
        _ = coordinator.playbackFailed(for: first.key, message: "one", positionSeconds: 0, duration: 100, connectivity: .online)
        scheduler.fire()
        _ = coordinator.playbackFailed(for: first.key, message: "two", positionSeconds: 0, duration: 100, connectivity: .online)
        _ = coordinator.playbackFailed(for: other.key, message: "one", positionSeconds: 0, duration: 100, connectivity: .online)
        scheduler.fire()
        _ = coordinator.playbackFailed(for: other.key, message: "two", positionSeconds: 0, duration: 100, connectivity: .online)
        #expect(!coordinator.canPlayNext)

        coordinator.applyRefresh(.init(results: [
            .init(feedID: "feed", outcome: .success(insertedEpisodeIDs: [])),
            .init(feedID: "other", outcome: .success(insertedEpisodeIDs: []))
        ]))

        #expect(coordinator.currentKey != nil)
        #expect(coordinator.entries.allSatisfy { $0.disposition == .pending })
        #expect(coordinator.canPlayNext)
    }

    @Test func coldLaunchRestoreResetsPersistedFailureBudget() async {
        let episode = candidate("one")
        let failed = RadioQueueEntry(key: episode.key, positionSeconds: 12, disposition: .failedThisSession, playbackFailureCount: 2, lastPlaybackError: "old")
        let coordinator = make(
            store: FakeRadioSessionStore(snapshot: session([failed], current: episode.key)),
            repository: CompletionRepository(candidates: [episode])
        )

        _ = await coordinator.restore(autoplayEnabled: false)

        #expect(coordinator.entries[0].disposition == .pending)
        #expect(coordinator.entries[0].playbackFailureCount == 0)
        #expect(coordinator.entries[0].lastPlaybackError == nil)
    }

    @Test func pendingRetryIsCanceledByPauseBackgroundTerminationAndCurrentSwitch() async {
        let first = candidate("one"); let second = candidate("two")
        let scheduler = TestRadioRetryScheduler()
        let coordinator = make(
            store: FakeRadioSessionStore(snapshot: session([entry(first.key), entry(second.key)], current: first.key)),
            repository: CompletionRepository(candidates: [first, second]),
            scheduler: scheduler
        )
        var intents: [RadioPlaybackIntent] = []
        let cancellable = coordinator.pendingNetworkIntentPublisher.sink { intents.append($0) }
        _ = await coordinator.restore(autoplayEnabled: false)

        for cancel in [
            { _ = coordinator.pauseByUser(positionSeconds: 1, duration: 100) },
            { _ = coordinator.handleBackground(positionSeconds: 2, duration: 100) },
            { _ = coordinator.handleTermination(positionSeconds: 3, duration: 100) }
        ] {
            _ = coordinator.playbackFailed(for: coordinator.currentKey!, message: "retry", positionSeconds: 1, duration: 100, connectivity: .online)
            cancel()
            scheduler.fireCanceledActionAnyway()
            _ = coordinator.retry()
        }
        _ = coordinator.playbackFailed(for: first.key, message: "retry", positionSeconds: 1, duration: 100, connectivity: .online)
        _ = coordinator.selectEpisode(second.key)
        scheduler.fireCanceledActionAnyway()

        #expect(intents.isEmpty)
        withExtendedLifetime(cancellable) {}
    }

    @Test func everyUserTransitionCancelsDeferredColdLaunchAutoplay() async {
        let first = candidate("one"); let second = candidate("two")

        func coordinatorForAction() async -> RadioSessionCoordinator {
            let coordinator = RadioSessionCoordinator(
                store: FakeRadioSessionStore(snapshot: session([entry(first.key), entry(second.key)], current: first.key)),
                repository: CompletionRepository(candidates: [first, second]), now: { now },
                connectivityStatus: { .unknown }, retryScheduler: TestRadioRetryScheduler()
            )
            _ = await coordinator.restore(autoplayEnabled: true)
            #expect(coordinator.hasPendingColdLaunchAutoplay)
            return coordinator
        }

        let pause = await coordinatorForAction()
        _ = pause.pauseByUser(positionSeconds: 1, duration: 300)
        #expect(!pause.hasPendingColdLaunchAutoplay)
        let seek = await coordinatorForAction()
        _ = seek.seekEnded(positionSeconds: 1, duration: 300)
        #expect(!seek.hasPendingColdLaunchAutoplay)
        let next = await coordinatorForAction()
        _ = next.manualNext(positionSeconds: 1, duration: 300)
        #expect(!next.hasPendingColdLaunchAutoplay)
        let retry = await coordinatorForAction()
        _ = retry.retry()
        #expect(!retry.hasPendingColdLaunchAutoplay)
        let sleep = await coordinatorForAction()
        sleep.setSleepTimer(.deadline(now.addingTimeInterval(60)))
        #expect(!sleep.hasPendingColdLaunchAutoplay)
        let select = await coordinatorForAction()
        _ = select.selectEpisode(second.key)
        #expect(!select.hasPendingColdLaunchAutoplay)
    }

    @Test func forceSaveEventsCapturePositionAndOrdering() async {
        let episode = candidate("one")
        var order: [String] = []
        let store = FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key), onSaveNow: { order.append("snapshot") })
        let repository = CompletionRepository(candidates: [episode], onProgress: { order.append("coredata") })
        let coordinator = make(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)
        store.resetCalls(); order.removeAll()

        _ = coordinator.seekEnded(positionSeconds: 5, duration: 100)
        _ = coordinator.handleBackground(positionSeconds: 6, duration: 100)
        _ = coordinator.handleTermination(positionSeconds: 7, duration: 100)
        #expect(store.forcedSaves.map { $0.entries[0].positionSeconds } == [5, 6, 7])
        #expect(order == ["coredata", "snapshot", "coredata", "snapshot", "coredata", "snapshot"])
    }

    @Test func directPauseNextCompletionInterruptionAndRouteSaveBeforeReturningIntent() async {
        let first = candidate("one"); let next = candidate("two")
        var order: [String] = []
        let repository = CompletionRepository(
            candidates: [first, next],
            onProgress: { order.append("progress") },
            onCompletion: { order.append("complete") }
        )
        let store = FakeRadioSessionStore(snapshot: session([entry(first.key), entry(next.key)], current: first.key), onSaveNow: { order.append("snapshot") })
        let coordinator = make(store: store, repository: repository)
        _ = await coordinator.restore(autoplayEnabled: false)

        order.removeAll()
        #expect(coordinator.pauseByUser(positionSeconds: 1, duration: 100) == .pause)
        #expect(order == ["progress", "snapshot"])
        order.removeAll()
        _ = coordinator.handleInterruptionBegan(positionSeconds: 2, duration: 100)
        #expect(order == ["progress", "snapshot"])
        order.removeAll()
        _ = coordinator.handleRouteRemoval(positionSeconds: 3, duration: 100)
        #expect(order == ["progress", "snapshot"])
        order.removeAll()
        #expect(coordinator.manualNext(positionSeconds: 4, duration: 100)?.key == next.key)
        #expect(order == ["progress", "snapshot"])
        order.removeAll()
        #expect(coordinator.playbackCompleted(for: next.key, at: now)?.key == first.key)
        #expect(order == ["complete", "snapshot"])
    }

    @Test func pauseSaveFailureStillPausesAndInterruptionSaveFailureCannotResume() async {
        let episode = candidate("one")
        let store = FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key))
        let coordinator = make(store: store, repository: CompletionRepository(candidates: [episode]))
        _ = await coordinator.restore(autoplayEnabled: false)
        _ = coordinator.beginCurrent()
        store.saveNowError = TestError.denied

        #expect(coordinator.pauseByUser(positionSeconds: 10, duration: 100) == .pause)
        #expect(coordinator.state == .failed(.persistence("denied")))

        let interruptionStore = FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key))
        let interrupted = make(store: interruptionStore, repository: CompletionRepository(candidates: [episode]))
        _ = await interrupted.restore(autoplayEnabled: false)
        _ = interrupted.beginCurrent()
        interruptionStore.saveNowError = TestError.denied
        #expect(interrupted.handleInterruptionBegan(positionSeconds: 11, duration: 100) == .pause)
        #expect(interrupted.handleInterruptionEnded(shouldResume: true) == nil)
        #expect(interrupted.state == .failed(.persistence("denied")))
    }

    @Test func retryForceSavesBeforeReturningPlaybackIntent() async {
        let episode = candidate("one")
        var order: [String] = []
        let repository = CompletionRepository(candidates: [episode], onProgress: { order.append("progress") })
        let store = FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key), onSaveNow: { order.append("snapshot") })
        let scheduler = TestRadioRetryScheduler()
        let coordinator = make(store: store, repository: repository, scheduler: scheduler)
        _ = await coordinator.restore(autoplayEnabled: false)
        _ = coordinator.playbackFailed(for: episode.key, message: "one", positionSeconds: 12, duration: 100, connectivity: .online)
        scheduler.fire()
        _ = coordinator.playbackFailed(for: episode.key, message: "two", positionSeconds: 13, duration: 100, connectivity: .online)
        order.removeAll()

        #expect(coordinator.retry()?.key == episode.key)
        #expect(order == ["progress", "snapshot"])
    }

    @Test func interruptionSemanticallyPausesAndResumesOnlyPriorPlayingOnlineSession() async {
        let episode = candidate("one")
        var status = ConnectivityStatus.online
        let coordinator = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key)),
            repository: CompletionRepository(candidates: [episode]), now: { now }, connectivityStatus: { status }
        )
        _ = await coordinator.restore(autoplayEnabled: false)
        _ = coordinator.beginCurrent()
        #expect(coordinator.handleInterruptionBegan(positionSeconds: 12, duration: 100) == .pause)
        #expect(coordinator.state == .pausedByUser)
        status = .offline
        #expect(coordinator.handleInterruptionEnded(shouldResume: true) == nil)
        #expect(coordinator.state == .waitingForNetwork)
        status = .online
        #expect(coordinator.handleInterruptionEnded(shouldResume: true) == nil)

        let paused = make(store: FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key)), repository: CompletionRepository(candidates: [episode]))
        _ = await paused.restore(autoplayEnabled: false)
        _ = paused.pauseByUser(positionSeconds: 3, duration: 100)
        _ = paused.handleInterruptionBegan(positionSeconds: 3, duration: 100)
        #expect(paused.handleInterruptionEnded(shouldResume: true) == nil)
    }

    @Test func routeRemovalPreservesPersistenceErrorWhileStillPausingTransport() async {
        let episode = candidate("one")
        let store = FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key))
        let coordinator = make(store: store, repository: CompletionRepository(candidates: [episode]))
        _ = await coordinator.restore(autoplayEnabled: false)
        store.saveNowError = TestError.denied

        #expect(coordinator.handleRouteRemoval(positionSeconds: 31, duration: 100) == .pause)
        #expect(coordinator.state == .failed(.persistence("denied")))
    }

    private func make(
        store: FakeRadioSessionStore,
        repository: CompletionRepository,
        scheduler: TestRadioRetryScheduler? = nil
    ) -> RadioSessionCoordinator {
        RadioSessionCoordinator(
            store: store, repository: repository, now: { now },
            connectivityStatus: { .online }, retryScheduler: scheduler ?? TestRadioRetryScheduler()
        )
    }

    private func make(candidates: [RadioEpisodeCandidate], scheduler: TestRadioRetryScheduler? = nil) -> RadioSessionCoordinator {
        make(store: FakeRadioSessionStore(), repository: CompletionRepository(candidates: candidates), scheduler: scheduler)
    }

    private func candidate(_ id: String) -> RadioEpisodeCandidate {
        .init(key: .init(feedID: "feed", episodeID: id), originalPlaybackURL: URL(string: "https://example.com/\(id).mp3")!, canonicalEnclosureURL: "https://example.com/\(id).mp3", title: id, sourceName: "feed", publicationDate: now, durationSeconds: 300, normalizedCoreDataProgress: 0, isCompleted: false, sourcePriority: 0, sourceFrequency: .hourly)
    }

    private func entry(_ key: RadioEpisodeKey, position: TimeInterval = 0, disposition: RadioEntryDisposition = .pending) -> RadioQueueEntry {
        .init(key: key, positionSeconds: position, disposition: disposition, playbackFailureCount: disposition == .failedThisSession ? 2 : 0, lastPlaybackError: disposition == .failedThisSession ? "failed" : nil)
    }

    private func session(_ entries: [RadioQueueEntry], current: RadioEpisodeKey?) -> PersistedRadioSession {
        .init(schemaVersion: 1, entries: entries, currentKey: current, savedAt: now)
    }
}

@MainActor
final class CompletionRepository: RadioEpisodeRepository {
    struct ProgressWrite: Equatable { let key: RadioEpisodeKey; let seconds: TimeInterval; let duration: TimeInterval? }
    var values: [RadioEpisodeCandidate]
    var completed = Set<RadioEpisodeKey>()
    var completionError: Error?
    var progressError: Error?
    var progressWrites: [ProgressWrite] = []
    private let onProgress: () -> Void

    var completionAttempts: [RadioEpisodeKey] = []
    private let onCompletion: () -> Void

    init(
        candidates: [RadioEpisodeCandidate], completionError: Error? = nil,
        onProgress: @escaping () -> Void = {}, onCompletion: @escaping () -> Void = {}
    ) {
        values = candidates
        self.completionError = completionError
        self.onProgress = onProgress
        self.onCompletion = onCompletion
    }

    func candidates() throws -> [RadioEpisodeCandidate] { values }
    func candidate(for key: RadioEpisodeKey) throws -> RadioEpisodeCandidate? { values.first { $0.key == key } }
    func saveProgress(key: RadioEpisodeKey, seconds: TimeInterval, duration: TimeInterval?) throws {
        if let progressError { throw progressError }
        progressWrites.append(.init(key: key, seconds: seconds, duration: duration))
        onProgress()
    }
    func markCompleted(key: RadioEpisodeKey, at date: Date) throws {
        completionAttempts.append(key)
        if let completionError { throw completionError }
        onCompletion()
        completed.insert(key)
        values = values.map { value in
            guard value.key == key else { return value }
            return RadioEpisodeCandidate(
                key: value.key, originalPlaybackURL: value.originalPlaybackURL,
                canonicalEnclosureURL: value.canonicalEnclosureURL, title: value.title,
                sourceName: value.sourceName, publicationDate: value.publicationDate,
                durationSeconds: value.durationSeconds, normalizedCoreDataProgress: 1,
                isCompleted: true, sourcePriority: value.sourcePriority, sourceFrequency: value.sourceFrequency
            )
        }
    }
}

@MainActor
final class TestRadioRetryScheduler: RadioRetryScheduling {
    private var action: (@MainActor () -> Void)?
    private var canceledAction: (@MainActor () -> Void)?
    var scheduledDelays: [TimeInterval] = []

    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () -> Void) {
        cancel()
        scheduledDelays.append(seconds)
        self.action = action
    }

    func cancel() {
        if let action { canceledAction = action }
        action = nil
    }

    func fire() {
        let pending = action
        action = nil
        pending?()
    }

    func fireCanceledActionAnyway() {
        let pending = canceledAction
        canceledAction = nil
        pending?()
    }
}

private enum TestError: LocalizedError {
    case denied
    var errorDescription: String? { "denied" }
}
