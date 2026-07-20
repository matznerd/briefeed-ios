import Foundation
import Testing
@testable import Briefeed

@Suite("Radio sleep timer") @MainActor
struct RadioSleepTimerTests {
    @Test func deadlinePausesOnceAndEndOfEpisodeSuppressesAdvance() async {
        let now = Date(timeIntervalSince1970: 100)
        let episode = RadioEpisodeCandidate(key: .init(feedID: "f", episodeID: "e"), originalPlaybackURL: URL(string: "https://example.com/e.mp3")!, canonicalEnclosureURL: "https://example.com/e.mp3", title: "e", sourceName: "f", publicationDate: now, durationSeconds: 100, normalizedCoreDataProgress: 0, isCompleted: false, sourcePriority: 0, sourceFrequency: .hourly)
        let store = FakeRadioSessionStore(snapshot: .init(schemaVersion: 1, entries: [.init(key: episode.key, positionSeconds: 0, disposition: .pending, playbackFailureCount: 0, lastPlaybackError: nil)], currentKey: episode.key, savedAt: now))
        let coordinator = RadioSessionCoordinator(store: store, repository: FakeRadioEpisodeRepository(candidates: [episode]), now: { now }, connectivityStatus: { .online })
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.setSleepTimer(.deadline(now.addingTimeInterval(10)))
        #expect(coordinator.evaluateSleepTimer(at: now.addingTimeInterval(10), positionSeconds: 5, duration: 100) == .pause)
        #expect(coordinator.evaluateSleepTimer(at: now.addingTimeInterval(11)) == nil)
        coordinator.setSleepTimer(.endOfEpisode)
        _ = coordinator.manualNext(positionSeconds: 5, duration: 100)
        #expect(coordinator.sleepTimer == .off)
    }
}
