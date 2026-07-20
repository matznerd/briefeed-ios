import Foundation

struct RadioEpisodeKey: Codable, Hashable, Sendable {
    let feedID: String
    let episodeID: String
}

enum RadioEntryDisposition: String, Codable, Sendable {
    case pending, playing, deferred, failedThisSession
}

struct RadioQueueEntry: Codable, Identifiable, Equatable, Sendable {
    var id: RadioEpisodeKey { key }
    let key: RadioEpisodeKey
    var positionSeconds: TimeInterval
    var disposition: RadioEntryDisposition
    var playbackFailureCount: Int
    var lastPlaybackError: String?
}

struct PersistedRadioSession: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    var entries: [RadioQueueEntry]
    var currentKey: RadioEpisodeKey?
    var savedAt: Date
}

enum RadioSessionState: Equatable, Sendable {
    case idle, restoring, refreshing, readyPaused, loading, playing
    case pausedByUser, waitingForNetwork, noSources, exhausted
    case failed(RadioFailure)
}

enum RadioSleepTimer: Equatable, Sendable {
    case off, deadline(Date), endOfEpisode
}

enum ConnectivityStatus: Equatable, Sendable {
    case unknown, online, offline
}

enum RSSUpdateFrequencyValue: String, Codable, Sendable {
    case hourly, daily
}

enum RadioFailure: Equatable, Sendable {
    case allSourcesUnavailable
    case playback(String)
    case persistence(String)
}

struct RadioPlaybackRequest: Equatable, Sendable {
    let key: RadioEpisodeKey
    let url: URL
    let title: String
    let source: String
    let positionSeconds: TimeInterval
}

enum RadioPlaybackIntent: Equatable, Sendable {
    case play(RadioPlaybackRequest)
    case pause

    var key: RadioEpisodeKey? {
        guard case .play(let request) = self else { return nil }
        return request.key
    }
}

@MainActor
protocol RadioSessionStoreProtocol: AnyObject {
    func load(durations: [RadioEpisodeKey: TimeInterval]) throws -> PersistedRadioSession?
    func saveDebounced(_ session: PersistedRadioSession)
    func saveNow(_ session: PersistedRadioSession) throws
    func clear()
}
