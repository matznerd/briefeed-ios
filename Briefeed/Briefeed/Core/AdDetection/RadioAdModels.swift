import Foundation

extension Notification.Name {
    static let radioAdPreferencesChanged = Notification.Name("RadioAdPreferencesChanged")
}

struct RadioAdPreferences: Equatable, Sendable {
    static let prepareKey = "radioPrepareAdsAhead"
    static let skipKey = "radioSkipAds"
    var prepareAhead = false
    var skipAds = false
    var preparationEnabled: Bool { prepareAhead || skipAds }

    static func load(defaults: UserDefaults) -> Self {
        .init(prepareAhead: defaults.bool(forKey: prepareKey),
              skipAds: RadioAdSkipPolicy.isReleaseQualified && defaults.bool(forKey: skipKey))
    }
}

enum RadioAdResourcePolicy {
    static let maximumDurationSeconds: TimeInterval = 90 * 60
    static let maximumDownloadBytes: Int64 = 100 * 1024 * 1024
    static let maximumWindows = 256

    static func permitsLookahead(duration: TimeInterval?, enabled: Bool) -> Bool {
        guard enabled, let duration, duration.isFinite, duration > 0 else { return false }
        return duration <= maximumDurationSeconds
    }
}

enum RadioAdKind: String, Codable, CaseIterable, Sendable {
    case paidAd, sponsorship, promotion, fundraising, stationID, editorial, uncertain

    var title: String {
        switch self {
        case .paidAd: "Ad"
        case .sponsorship: "Sponsor"
        case .promotion: "Promotion"
        case .fundraising: "Fundraising"
        case .stationID: "Station ID"
        case .editorial: "Not an ad"
        case .uncertain: "Uncertain"
        }
    }

    var isSponsor: Bool { self == .paidAd || self == .sponsorship }
}

struct RadioAdSpan: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var kind: RadioAdKind
    var startSeconds: TimeInterval
    var endSeconds: TimeInterval
    var categoryReviewed = false
    var boundariesReviewed = false
    var unresolvedGap = false
}

struct RadioAdCacheKey: Codable, Equatable, Sendable {
    let episodeKey: RadioEpisodeKey
    let assetFingerprint: String
    let transcriptEngine: String
    let transcriptVersion: String
    let locale: String
    let detectorVersion: String
    let modelVersion: String
}

struct RadioAdTiming: Codable, Equatable, Sendable {
    let audioSeconds: TimeInterval
    let speechSeconds: TimeInterval
    let classifierSeconds: TimeInterval
    let completedWindows: Int
    let failedWindows: Int

    func estimatedProcessingSeconds(for duration: TimeInterval) -> TimeInterval? {
        guard audioSeconds.isFinite, audioSeconds >= 60, speechSeconds.isFinite, speechSeconds >= 0,
              classifierSeconds.isFinite, classifierSeconds >= 0, completedWindows > 0,
              failedWindows == 0, duration.isFinite, duration > 0 else { return nil }
        let estimate = (speechSeconds + classifierSeconds) * duration / audioSeconds
        return estimate.isFinite && estimate >= 0 ? estimate : nil
    }
}

enum RadioAdValidationError: Error, Equatable {
    case invalidIdentity, invalidDuration, invalidSpan, unsupportedSchema, invalidTiming
}

struct RadioAdRecord: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let key: RadioAdCacheKey
    let audioDurationSeconds: TimeInterval
    var spans: [RadioAdSpan]
    let timing: RadioAdTiming
    var revision: Int
    let preparedAt: Date

    init(key: RadioAdCacheKey, audioDurationSeconds: TimeInterval, spans: [RadioAdSpan],
         timing: RadioAdTiming, revision: Int = 0, preparedAt: Date = Date()) throws {
        schemaVersion = 1
        self.key = key
        self.audioDurationSeconds = audioDurationSeconds
        self.spans = spans
        self.timing = timing
        self.revision = revision
        self.preparedAt = preparedAt
        try validate()
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw RadioAdValidationError.unsupportedSchema }
        guard key.assetFingerprint.count == 64,
              key.assetFingerprint.allSatisfy({ "0123456789abcdef".contains($0) }),
              !key.episodeKey.feedID.isEmpty, !key.episodeKey.episodeID.isEmpty,
              !key.transcriptEngine.isEmpty, !key.transcriptVersion.isEmpty,
              !key.detectorVersion.isEmpty, !key.modelVersion.isEmpty, !key.locale.isEmpty,
              revision >= 0 else { throw RadioAdValidationError.invalidIdentity }
        guard audioDurationSeconds.isFinite, audioDurationSeconds > 0 else {
            throw RadioAdValidationError.invalidDuration
        }
        guard timing.audioSeconds == audioDurationSeconds, timing.speechSeconds.isFinite,
              timing.speechSeconds >= 0, timing.classifierSeconds.isFinite, timing.classifierSeconds >= 0,
              timing.completedWindows >= 0, timing.failedWindows >= 0 else {
            throw RadioAdValidationError.invalidTiming
        }
        guard spans.count <= 1000, Set(spans.map(\.id)).count == spans.count else {
            throw RadioAdValidationError.invalidSpan
        }
        for span in spans {
            guard span.startSeconds.isFinite, span.endSeconds.isFinite, span.startSeconds >= 0,
                  span.endSeconds > span.startSeconds, span.endSeconds <= audioDurationSeconds else {
                throw RadioAdValidationError.invalidSpan
            }
        }
    }
}

enum RadioAdPreparationState: Equatable, Sendable {
    case queued
    case analyzing(completed: Int, total: Int)
    case ready(RadioAdRecord)
    case unavailable(String)
    case deferred

    var record: RadioAdRecord? {
        if case .ready(let record) = self { return record }
        return nil
    }
}

enum RadioAdSkipPolicy {
    // Do not change until the frozen editorial, boundary and physical-device gates pass.
    static let isReleaseQualified = false

    static func manualTarget(record: RadioAdRecord, spanID: UUID,
                             playingFingerprint: String?, isOwnedAudio: Bool) -> TimeInterval? {
        guard (try? record.validate()) != nil, isOwnedAudio,
              playingFingerprint == record.key.assetFingerprint,
              let span = record.spans.first(where: { $0.id == spanID }), span.kind.isSponsor,
              span.categoryReviewed, span.boundariesReviewed, !span.unresolvedGap else { return nil }
        let conflict = record.spans.contains {
            $0.kind == .editorial && $0.categoryReviewed &&
                $0.startSeconds < span.endSeconds && span.startSeconds < $0.endSeconds
        }
        guard !conflict else { return nil }
        return max(span.startSeconds, span.endSeconds - 0.25)
    }
}
