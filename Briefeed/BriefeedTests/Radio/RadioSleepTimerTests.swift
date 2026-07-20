import Foundation
import Testing
@testable import Briefeed

@Suite("Radio sleep timer") @MainActor
struct RadioSleepTimerTests {
    @Test func deadlineReplacementCancellationAndSaveFailureAreOneShot() async {
        let now = Date(timeIntervalSince1970: 100)
        let episode = RadioEpisodeCandidate(key: .init(feedID: "f", episodeID: "e"), originalPlaybackURL: URL(string: "https://example.com/e.mp3")!, canonicalEnclosureURL: "https://example.com/e.mp3", title: "e", sourceName: "f", publicationDate: now, durationSeconds: 100, normalizedCoreDataProgress: 0, isCompleted: false, sourcePriority: 0, sourceFrequency: .hourly)
        let store = FakeRadioSessionStore(snapshot: .init(schemaVersion: 1, entries: [.init(key: episode.key, positionSeconds: 0, disposition: .pending, playbackFailureCount: 0, lastPlaybackError: nil)], currentKey: episode.key, savedAt: now))
        let coordinator = RadioSessionCoordinator(store: store, repository: FakeRadioEpisodeRepository(candidates: [episode]), now: { now }, connectivityStatus: { .online })
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.setSleepTimer(.deadline(now.addingTimeInterval(10)))
        coordinator.setSleepTimer(.deadline(now.addingTimeInterval(20)))
        #expect(coordinator.evaluateSleepTimer(at: now.addingTimeInterval(10)) == nil)
        store.saveNowError = SleepError.denied
        #expect(coordinator.evaluateSleepTimer(at: now.addingTimeInterval(20), positionSeconds: 5, duration: 100) == .pause)
        #expect(coordinator.sleepTimer == .off)
        #expect(coordinator.state == .failed(.persistence("sleep save denied")))
        #expect((coordinator.currentKey == episode.key))
        #expect(coordinator.evaluateSleepTimer(at: now.addingTimeInterval(21)) == nil)
        coordinator.setSleepTimer(.deadline(now.addingTimeInterval(30)))
        coordinator.setSleepTimer(.off)
        #expect(coordinator.evaluateSleepTimer(at: now.addingTimeInterval(31)) == nil)
    }

    @Test func endOfEpisodePersistsPausedNextCursorWithoutEmittingPlay() async {
        let now = Date(timeIntervalSince1970: 100)
        let first = candidate("one", now: now); let next = candidate("two", now: now)
        let store = FakeRadioSessionStore(snapshot: .init(schemaVersion: 1, entries: [entry(first.key), entry(next.key)], currentKey: first.key, savedAt: now))
        let repository = CompletionRepository(candidates: [first, next])
        let coordinator = RadioSessionCoordinator(store: store, repository: repository, now: { now }, connectivityStatus: { .online })
        _ = await coordinator.restore(autoplayEnabled: false)
        #expect(coordinator.evaluateSleepTimer(at: now.addingTimeInterval(11)) == nil)
        coordinator.setSleepTimer(.endOfEpisode)
        #expect(coordinator.playbackCompleted(for: first.key, at: now) == nil)
        #expect(coordinator.sleepTimer == .off)
        #expect(coordinator.currentKey == next.key)
        #expect(coordinator.state == .readyPaused)
        #expect(store.savedNow?.currentKey == next.key)
    }

    @Test func deadlineSurvivesOrdinaryNextAndNeverCompletesEpisode() async {
        let now = Date(timeIntervalSince1970: 100)
        let first = candidate("one", now: now); let next = candidate("two", now: now)
        let store = FakeRadioSessionStore(snapshot: .init(schemaVersion: 1, entries: [entry(first.key), entry(next.key)], currentKey: first.key, savedAt: now))
        let repository = CompletionRepository(candidates: [first, next])
        let coordinator = RadioSessionCoordinator(store: store, repository: repository, now: { now }, connectivityStatus: { .online })
        _ = await coordinator.restore(autoplayEnabled: false)
        let deadline = now.addingTimeInterval(30)
        coordinator.setSleepTimer(.deadline(deadline))

        #expect(coordinator.manualNext(positionSeconds: 10, duration: 100)?.key == next.key)
        #expect(coordinator.sleepTimer == .deadline(deadline))
        #expect(repository.completed.isEmpty)
        #expect(coordinator.evaluateSleepTimer(at: deadline, positionSeconds: 11, duration: 100) == .pause)
        #expect(repository.completed.isEmpty)
    }

    private func candidate(_ id: String, now: Date) -> RadioEpisodeCandidate {
        .init(key: .init(feedID: "f", episodeID: id), originalPlaybackURL: URL(string: "https://example.com/\(id).mp3")!, canonicalEnclosureURL: "https://example.com/\(id).mp3", title: id, sourceName: "f", publicationDate: now, durationSeconds: 100, normalizedCoreDataProgress: 0, isCompleted: false, sourcePriority: 0, sourceFrequency: .hourly)
    }

    private func entry(_ key: RadioEpisodeKey) -> RadioQueueEntry {
        .init(key: key, positionSeconds: 0, disposition: .pending, playbackFailureCount: 0, lastPlaybackError: nil)
    }
}

private enum SleepError: LocalizedError {
    case denied
    var errorDescription: String? { "sleep save denied" }
}
