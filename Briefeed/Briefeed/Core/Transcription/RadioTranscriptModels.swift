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
    var state: RadioTranscriptBatchEntryState
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
    case ready(TimedTranscript)
    case deferred
    case failed(message: String, canRetry: Bool)
}
