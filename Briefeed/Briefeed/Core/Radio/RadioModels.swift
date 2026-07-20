import Foundation

struct RadioEpisodeKey: Codable, Hashable, Sendable {
    let feedID: String
    let episodeID: String
}

enum RadioEntryDisposition: String, Codable, Sendable {
    case pending, playing, deferred, retired, failedThisSession
}

struct RadioQueueEntry: Codable, Identifiable, Equatable, Sendable {
    var id: RadioEpisodeKey { key }
    let key: RadioEpisodeKey
    var positionSeconds: TimeInterval
    var disposition: RadioEntryDisposition
    var playbackFailureCount: Int
    var lastPlaybackError: String?
    var isManuallyQueued: Bool

    init(
        key: RadioEpisodeKey,
        positionSeconds: TimeInterval,
        disposition: RadioEntryDisposition,
        playbackFailureCount: Int,
        lastPlaybackError: String?,
        isManuallyQueued: Bool = false
    ) {
        self.key = key
        self.positionSeconds = positionSeconds
        self.disposition = disposition
        self.playbackFailureCount = playbackFailureCount
        self.lastPlaybackError = lastPlaybackError
        self.isManuallyQueued = isManuallyQueued
    }

    private enum CodingKeys: String, CodingKey {
        case key, positionSeconds, disposition, playbackFailureCount, lastPlaybackError, isManuallyQueued
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(RadioEpisodeKey.self, forKey: .key)
        positionSeconds = try container.decode(TimeInterval.self, forKey: .positionSeconds)
        disposition = try container.decode(RadioEntryDisposition.self, forKey: .disposition)
        playbackFailureCount = try container.decode(Int.self, forKey: .playbackFailureCount)
        lastPlaybackError = try container.decodeIfPresent(String.self, forKey: .lastPlaybackError)
        isManuallyQueued = try container.decodeIfPresent(Bool.self, forKey: .isManuallyQueued) ?? false
    }
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
