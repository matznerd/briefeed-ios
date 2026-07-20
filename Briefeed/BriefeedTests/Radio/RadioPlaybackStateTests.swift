import Foundation
import Testing
@testable import Briefeed

@Suite("Radio playback state")
@MainActor
struct RadioPlaybackStateTests {
    let now = Date(timeIntervalSince1970: 20_000)

    @Test func progressUsesFiveSecondBucketsAndPauseForcesSave() async {
        let episode = candidate("one")
        let store = FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key))
        let coordinator = make(store: store, candidates: [episode])
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.recordProgress(positionSeconds: 1, duration: 100)
        coordinator.recordProgress(positionSeconds: 4, duration: 100)
        #expect(store.snapshot?.entries.first?.positionSeconds == 4)
        _ = coordinator.pauseByUser(positionSeconds: 7, duration: 100)
        #expect(store.savedNow?.entries.first?.positionSeconds == 7)
        #expect(coordinator.state == .pausedByUser)
    }

    @Test func nextDefersCurrentAndNaturalCompletionRemovesOnlyAfterCoreDataSave() async {
        let first = candidate("one"); let next = candidate("two")
        let store = FakeRadioSessionStore(snapshot: session([entry(first.key), entry(next.key)], current: first.key))
        let repository = CompletionRepository(candidates: [first, next])
        let coordinator = RadioSessionCoordinator(store: store, repository: repository, now: { now }, connectivityStatus: { .online })
        _ = await coordinator.restore(autoplayEnabled: false)
        #expect(coordinator.manualNext(positionSeconds: 42, duration: 300)?.key == next.key)
        #expect(coordinator.entries.last?.disposition == .deferred)
        _ = coordinator.playbackCompleted(at: now)
        #expect(repository.completed.contains(next.key))
        #expect(!coordinator.entries.contains { $0.key == next.key })
    }

    @Test func completionSaveFailureRetainsCurrentEntry() async {
        let episode = candidate("one")
        let repository = CompletionRepository(candidates: [episode], completionError: NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "test failure"]))
        let coordinator = RadioSessionCoordinator(store: FakeRadioSessionStore(snapshot: session([entry(episode.key)], current: episode.key)), repository: repository, now: { now }, connectivityStatus: { .online })
        _ = await coordinator.restore(autoplayEnabled: false)
        #expect(coordinator.playbackCompleted(at: now) == nil)
        #expect(coordinator.currentKey == episode.key)
        #expect(coordinator.state == .failed(.persistence("test failure")))
    }

    @Test func onlineGetsTwoAttemptsOfflineGetsNoneAndRetryResets() async {
        let episode = candidate("one")
        let coordinator = make(candidates: [episode])
        _ = await coordinator.restore(autoplayEnabled: false)
        #expect(coordinator.playbackFailed(message: "one")?.key == episode.key)
        #expect(coordinator.entries[0].playbackFailureCount == 1)
        _ = coordinator.playbackFailed(message: "two")
        #expect(coordinator.entries[0].disposition == .failedThisSession)
        _ = coordinator.retry()
        #expect(coordinator.entries[0].playbackFailureCount == 0)
    }

    private func make(store: FakeRadioSessionStore, candidates: [RadioEpisodeCandidate]) -> RadioSessionCoordinator { RadioSessionCoordinator(store: store, repository: FakeRadioEpisodeRepository(candidates: candidates), now: { now }, connectivityStatus: { .online }) }
    private func make(candidates: [RadioEpisodeCandidate]) -> RadioSessionCoordinator { make(store: FakeRadioSessionStore(), candidates: candidates) }
    private func candidate(_ id: String) -> RadioEpisodeCandidate { .init(key: .init(feedID: "feed", episodeID: id), originalPlaybackURL: URL(string: "https://example.com/\(id).mp3")!, canonicalEnclosureURL: "https://example.com/\(id).mp3", title: id, sourceName: "feed", publicationDate: now, durationSeconds: 300, normalizedCoreDataProgress: 0, isCompleted: false, sourcePriority: 0, sourceFrequency: .hourly) }
    private func entry(_ key: RadioEpisodeKey) -> RadioQueueEntry { .init(key: key, positionSeconds: 0, disposition: .pending, playbackFailureCount: 0, lastPlaybackError: nil) }
    private func session(_ entries: [RadioQueueEntry], current: RadioEpisodeKey) -> PersistedRadioSession { .init(schemaVersion: 1, entries: entries, currentKey: current, savedAt: now) }
}

@MainActor private final class CompletionRepository: RadioEpisodeRepository {
    var values: [RadioEpisodeCandidate]; var completed = Set<RadioEpisodeKey>(); var completionError: Error?
    init(candidates: [RadioEpisodeCandidate], completionError: Error? = nil) { values = candidates; self.completionError = completionError }
    func candidates() throws -> [RadioEpisodeCandidate] { values }
    func candidate(for key: RadioEpisodeKey) throws -> RadioEpisodeCandidate? { values.first { $0.key == key } }
    func saveProgress(key: RadioEpisodeKey, seconds: TimeInterval, duration: TimeInterval?) throws {}
    func markCompleted(key: RadioEpisodeKey, at date: Date) throws { if let completionError { throw completionError }; completed.insert(key) }
}
