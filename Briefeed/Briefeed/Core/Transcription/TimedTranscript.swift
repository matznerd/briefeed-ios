import Foundation

enum TimedTranscriptGranularity: String, Codable, Equatable, Sendable {
    case word
    case phrase
}

struct TimedTranscriptUnit: Codable, Equatable, Sendable {
    let text: String
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let confidence: Double?
    let granularity: TimedTranscriptGranularity
}

enum TimedTranscriptValidationError: Error, Equatable {
    case invalidDuration
    case invalidProcessingDuration
    case missingIdentity
    case emptyText(index: Int)
    case invalidRange(index: Int)
    case overlappingRange(index: Int)
}

struct TimedTranscript: Codable, Equatable, Sendable {
    let assetFingerprint: String
    let engineIdentifier: String
    let engineVersion: String
    let localeIdentifier: String
    let recognizedText: String
    let audioDurationSeconds: TimeInterval
    let processingDurationSeconds: TimeInterval
    let units: [TimedTranscriptUnit]

    init(
        assetFingerprint: String,
        engineIdentifier: String,
        engineVersion: String,
        localeIdentifier: String,
        recognizedText: String,
        audioDurationSeconds: TimeInterval,
        processingDurationSeconds: TimeInterval,
        units: [TimedTranscriptUnit]
    ) throws {
        guard audioDurationSeconds.isFinite, audioDurationSeconds > 0 else {
            throw TimedTranscriptValidationError.invalidDuration
        }
        guard processingDurationSeconds.isFinite, processingDurationSeconds >= 0 else {
            throw TimedTranscriptValidationError.invalidProcessingDuration
        }
        guard !assetFingerprint.isEmpty, !engineIdentifier.isEmpty, !engineVersion.isEmpty, !localeIdentifier.isEmpty else {
            throw TimedTranscriptValidationError.missingIdentity
        }

        var previousEnd: TimeInterval?
        for (index, unit) in units.enumerated() {
            guard !unit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TimedTranscriptValidationError.emptyText(index: index)
            }
            guard unit.startSeconds.isFinite,
                  unit.endSeconds.isFinite,
                  unit.startSeconds >= 0,
                  unit.endSeconds > unit.startSeconds,
                  unit.endSeconds <= audioDurationSeconds else {
                throw TimedTranscriptValidationError.invalidRange(index: index)
            }
            if let previousEnd, unit.startSeconds < previousEnd {
                throw TimedTranscriptValidationError.overlappingRange(index: index)
            }
            previousEnd = unit.endSeconds
        }

        self.assetFingerprint = assetFingerprint
        self.engineIdentifier = engineIdentifier
        self.engineVersion = engineVersion
        self.localeIdentifier = localeIdentifier
        self.recognizedText = recognizedText
        self.audioDurationSeconds = audioDurationSeconds
        self.processingDurationSeconds = processingDurationSeconds
        self.units = units
    }
}
