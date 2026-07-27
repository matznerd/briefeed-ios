import Foundation

struct RadioTranscriptCacheKey: Codable, Hashable, Sendable {
    let episodeKey: RadioEpisodeKey
    let assetFingerprint: String
    let engineIdentifier: String
    let engineVersion: String
    let localeIdentifier: String
}

struct RadioTranscriptRecord: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let key: RadioTranscriptCacheKey
    let sourceURLHash: String
    let audioDurationSeconds: TimeInterval
    let transcriptRelativePath: String
    let preparedAt: Date
    var lastAccessedAt: Date
}

enum RadioTranscriptBatchEntryState: Codable, Equatable, Sendable {
    case pending
    case audioReady(assetFingerprint: String)
    case transcriptReady(cacheKey: RadioTranscriptCacheKey)
    case failed(message: String)
}

struct RadioTranscriptBatchEntry: Codable, Equatable, Sendable {
    let episodeKey: RadioEpisodeKey
    let order: Int
    let remoteURL: URL?
    let expectedDurationSeconds: TimeInterval?
    let languageTag: String?
    var state: RadioTranscriptBatchEntryState

    init(
        episodeKey: RadioEpisodeKey,
        order: Int,
        remoteURL: URL? = nil,
        expectedDurationSeconds: TimeInterval? = nil,
        languageTag: String? = nil,
        state: RadioTranscriptBatchEntryState
    ) {
        self.episodeKey = episodeKey
        self.order = order
        self.remoteURL = remoteURL
        self.expectedDurationSeconds = expectedDurationSeconds
        self.languageTag = languageTag
        self.state = state
    }
}

struct RadioTranscriptBatchManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var entries: [RadioTranscriptBatchEntry]

    var completedCount: Int {
        entries.lazy.filter {
            if case .transcriptReady = $0.state { return true }
            return false
        }.count
    }

    var remainingCount: Int {
        totalCount - completedCount
    }

    var failedCount: Int {
        entries.lazy.filter {
            if case .failed = $0.state { return true }
            return false
        }.count
    }

    var terminalCount: Int {
        completedCount + failedCount
    }

    var totalCount: Int {
        entries.count
    }
}

enum RadioTranscriptPreparationState: Equatable, Sendable {
    case unavailableOS
    case unsupportedDevice
    case unsupportedLocale(String)
    case assetRequired
    case queued
    case downloading(progress: Double?)
    case transcribing
    case partial(TimedTranscriptProgress)
    case ready(TimedTranscript)
    case deferred
    case failed(message: String, canRetry: Bool)
}

enum TimedTranscriptCoveragePolicy {
    static let enterLeadSeconds: TimeInterval = 5
    static let exitLeadSeconds: TimeInterval = 1

    static func shouldDisplay(
        finalizedThroughSeconds: TimeInterval,
        mediaTime: TimeInterval,
        wasDisplaying: Bool
    ) -> Bool {
        guard finalizedThroughSeconds.isFinite, mediaTime.isFinite else {
            return false
        }
        let requiredLead = wasDisplaying
            ? exitLeadSeconds
            : enterLeadSeconds
        return finalizedThroughSeconds - mediaTime >= requiredLead
    }
}

enum TimedTranscriptSamplingPolicy {
    static let maximumFramesPerSecond = 30.0
    static let rangeHighlightMinimumRate = 1.5

    static func timerInterval(playbackRate: Double) -> TimeInterval {
        let rate = playbackRate.isFinite ? max(playbackRate, 0.5) : 1
        return max(1.0 / maximumFramesPerSecond, 0.1 / rate)
    }

    static func highlightedSourceWindow(
        playbackRate: Double
    ) -> TimeInterval {
        let rate = playbackRate.isFinite ? max(playbackRate, 0.5) : 1
        return min(max(0.1 * rate, 0.1), 0.5)
    }

    static func usesRangeHighlight(playbackRate: Double) -> Bool {
        playbackRate.isFinite &&
            playbackRate > rangeHighlightMinimumRate
    }

    static func isSamePresentationFrame(
        _ previous: TimeInterval,
        _ next: TimeInterval
    ) -> Bool {
        guard previous.isFinite, next.isFinite else {
            return previous == next
        }
        return Int(
            (previous * maximumFramesPerSecond).rounded(.down)
        ) == Int(
            (next * maximumFramesPerSecond).rounded(.down)
        )
    }
}

enum RadioTranscriptPlaybackSyncState: Equatable, Sendable {
    case waiting
    case synchronized
    case audioVersionMismatch
}
