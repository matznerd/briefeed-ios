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

protocol TimedTranscriptEngine: Sendable {
    func transcribe(
        fileURL: URL,
        assetFingerprint: String,
        locale: Locale,
        assetPolicy: SpeechAssetPolicy
    ) async throws -> TimedTranscript
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
