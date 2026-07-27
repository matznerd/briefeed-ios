import Foundation

enum SpeechAssetPolicy: Equatable, Sendable {
    case installedOnly
    case allowDownload
}

enum TimedTranscriptEngineError: Error, Equatable {
    case unsupportedOS
    case engineUnavailable
    case unsupportedLocale(String)
    case assetRequired(String)
    case emptyTranscript
    case invalidAudio
}

struct TranscriptAttributedRun: Equatable, Sendable {
    let text: String
    let startSeconds: TimeInterval?
    let endSeconds: TimeInterval?
    let confidence: Double?
}

struct TimedTranscriptProgress: Codable, Equatable, Sendable {
    let transcript: TimedTranscript
    let finalizedThroughSeconds: TimeInterval

    init(
        transcript: TimedTranscript,
        finalizedThroughSeconds: TimeInterval
    ) {
        let finiteCoverage = finalizedThroughSeconds.isFinite
            ? finalizedThroughSeconds
            : 0
        let lastUnitEnd = transcript.units.last?.endSeconds ?? 0
        self.transcript = transcript
        self.finalizedThroughSeconds = min(
            max(finiteCoverage, lastUnitEnd),
            transcript.audioDurationSeconds
        )
    }
}

typealias TimedTranscriptProgressHandler =
    @Sendable (TimedTranscriptProgress) async -> Void

protocol TimedTranscriptEngine: Sendable {
    func transcribe(
        fileURL: URL,
        assetFingerprint: String,
        locale: Locale,
        assetPolicy: SpeechAssetPolicy
    ) async throws -> TimedTranscript

    func transcribe(
        fileURL: URL,
        assetFingerprint: String,
        locale: Locale,
        assetPolicy: SpeechAssetPolicy,
        onProgress: @escaping TimedTranscriptProgressHandler
    ) async throws -> TimedTranscript
}

extension TimedTranscriptEngine {
    func transcribe(
        fileURL: URL,
        assetFingerprint: String,
        locale: Locale,
        assetPolicy: SpeechAssetPolicy,
        onProgress: @escaping TimedTranscriptProgressHandler
    ) async throws -> TimedTranscript {
        try await transcribe(
            fileURL: fileURL,
            assetFingerprint: assetFingerprint,
            locale: locale,
            assetPolicy: assetPolicy
        )
    }
}

enum TimedTranscriptNormalizer {
    static func normalize(runs: [TranscriptAttributedRun]) throws -> [TimedTranscriptUnit] {
        runs.compactMap { run in
            let text = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let start = run.startSeconds, let end = run.endSeconds else {
                return nil
            }

            let count = text.split(whereSeparator: \.isWhitespace).count
            return TimedTranscriptUnit(
                text: text,
                startSeconds: start,
                endSeconds: end,
                confidence: run.confidence,
                granularity: count == 1 ? .word : .phrase
            )
        }
    }
}
