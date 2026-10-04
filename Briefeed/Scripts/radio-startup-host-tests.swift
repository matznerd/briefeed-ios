import Combine
import Foundation
import SwiftUI

@main
struct RadioStartupHostTests {
    @MainActor static func main() async {
        let now = Date()
        let episode = candidate("bbc", "restored", at: now)
        let radio = RadioSessionCoordinator(
            store: HostSessionStore(),
            repository: HostEpisodeRepository([episode]),
            now: { now },
            connectivityStatus: { .online }
        )
        _ = await radio.restore(autoplayEnabled: true)
        radio.refreshStarted(enabledSourceCount: 1)
        let intent = radio.applyInitialRefresh(.init(results: [
            .init(feedID: "bbc", outcome: .failed(message: "Synthetic timeout"))
        ]))
        guard intent?.key == episode.key else {
            print("FAIL: feed failure leaves a playable restored episode silent")
            exit(1)
        }
        print("PASS: failed opening refresh falls back to restored audio")
    }

    static func candidate(_ feed: String, _ id: String, at now: Date) -> RadioEpisodeCandidate {
        let url = URL(string: "https://example.com/\(feed)-\(id).mp3")!
        return .init(
            key: .init(feedID: feed, episodeID: id), originalPlaybackURL: url,
            canonicalEnclosureURL: url.absoluteString, title: id, sourceName: feed,
            publicationDate: now, durationSeconds: 300, normalizedCoreDataProgress: 0,
            isCompleted: false, sourcePriority: feed == "npr" ? 1 : 2,
            sourceFrequency: .hourly
        )
    }
}

@MainActor final class HostSessionStore: RadioSessionStoreProtocol {
    func load(durations: [RadioEpisodeKey: TimeInterval]) throws -> PersistedRadioSession? { nil }
    func saveDebounced(_ session: PersistedRadioSession) {}
    func saveNow(_ session: PersistedRadioSession) throws {}
    func clear() {}
}

@MainActor final class HostEpisodeRepository: RadioEpisodeRepository {
    var values: [RadioEpisodeCandidate]
    init(_ values: [RadioEpisodeCandidate]) { self.values = values }
    func candidates() throws -> [RadioEpisodeCandidate] { values }
    func candidate(for key: RadioEpisodeKey) throws -> RadioEpisodeCandidate? {
        values.first { $0.key == key }
    }
    func saveProgress(key: RadioEpisodeKey, seconds: TimeInterval, duration: TimeInterval?) throws {}
    func markCompleted(key: RadioEpisodeKey, at date: Date) throws {}
    func restartForReplay(key: RadioEpisodeKey) throws -> RadioEpisodeCandidate? {
        try candidate(for: key)
    }
}
