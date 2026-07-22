import CryptoKit
import Foundation

struct PodcastTranscriptionReceipt: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let createdAt: Date
    let operatingSystemVersion: String
    let transcript: TimedTranscript
    let recognizedCharacterCount: Int
    let timedCharacterCount: Int
    let timingCoverage: Double
    let medianWordsPerUnit: Double
    let wordUnitCount: Int
    let phraseUnitCount: Int
    let referenceWordErrorRate: Double?
}

struct PodcastTranscriptionProbe: Sendable {
    private let engine: any TimedTranscriptEngine
    private let now: @Sendable () -> Date
    private let operatingSystemVersion: @Sendable () -> String

    init(
        engine: any TimedTranscriptEngine,
        now: @escaping @Sendable () -> Date = { Date() },
        operatingSystemVersion: @escaping @Sendable () -> String = {
            ProcessInfo.processInfo.operatingSystemVersionString
        }
    ) {
        self.engine = engine
        self.now = now
        self.operatingSystemVersion = operatingSystemVersion
    }

    #if DEBUG
    func run(
        fileURL: URL,
        referenceText: String?,
        locale: Locale,
        assetPolicy: SpeechAssetPolicy,
        outputDirectory: URL
    ) async throws -> PodcastTranscriptionReceipt {
        let assetFingerprint = try Self.fingerprint(for: fileURL)
        let transcript = try await engine.transcribe(
            fileURL: fileURL,
            assetFingerprint: assetFingerprint,
            locale: locale,
            assetPolicy: assetPolicy
        )
        let receipt = Self.makeReceipt(
            transcript: transcript,
            referenceText: referenceText,
            createdAt: now(),
            operatingSystemVersion: operatingSystemVersion()
        )

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let receiptURL = outputDirectory.appending(path: "transcript-\(assetFingerprint.prefix(12)).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(receipt).write(to: receiptURL, options: .atomic)
        return receipt
    }
    #endif

    private static func fingerprint(for fileURL: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: fileURL))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func makeReceipt(
        transcript: TimedTranscript,
        referenceText: String?,
        createdAt: Date,
        operatingSystemVersion: String
    ) -> PodcastTranscriptionReceipt {
        let recognizedText = normalizedText(transcript.recognizedText)
        let timedText = normalizedText(transcript.units.map(\.text).joined(separator: " "))
        let wordCounts = transcript.units.map { normalizedWords($0.text).count }.sorted()
        let middle = wordCounts.count / 2
        let medianWordsPerUnit: Double
        if wordCounts.isEmpty {
            medianWordsPerUnit = 0
        } else if wordCounts.count.isMultiple(of: 2) {
            medianWordsPerUnit = Double(wordCounts[middle - 1] + wordCounts[middle]) / 2
        } else {
            medianWordsPerUnit = Double(wordCounts[middle])
        }

        return PodcastTranscriptionReceipt(
            schemaVersion: 1,
            createdAt: createdAt,
            operatingSystemVersion: operatingSystemVersion,
            transcript: transcript,
            recognizedCharacterCount: recognizedText.count,
            timedCharacterCount: timedText.count,
            timingCoverage: recognizedText.isEmpty ? 0 : Double(timedText.count) / Double(recognizedText.count),
            medianWordsPerUnit: medianWordsPerUnit,
            wordUnitCount: transcript.units.count(where: { $0.granularity == .word }),
            phraseUnitCount: transcript.units.count(where: { $0.granularity == .phrase }),
            referenceWordErrorRate: referenceText.map {
                normalizedWordErrorRate(reference: normalizedWords($0), hypothesis: normalizedWords(transcript.recognizedText))
            }
        )
    }

    private static func normalizedText(_ text: String) -> String {
        normalizedWords(text).joined(separator: " ")
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func normalizedWordErrorRate(reference: [String], hypothesis: [String]) -> Double {
        guard !reference.isEmpty else {
            return hypothesis.isEmpty ? 0 : 1
        }

        var previousRow = Array(0...hypothesis.count)
        for (referenceIndex, referenceWord) in reference.enumerated() {
            var currentRow = [referenceIndex + 1]
            for (hypothesisIndex, hypothesisWord) in hypothesis.enumerated() {
                let substitutionCost = referenceWord == hypothesisWord ? 0 : 1
                currentRow.append(min(
                    previousRow[hypothesisIndex + 1] + 1,
                    currentRow[hypothesisIndex] + 1,
                    previousRow[hypothesisIndex] + substitutionCost
                ))
            }
            previousRow = currentRow
        }
        return Double(previousRow[hypothesis.count]) / Double(reference.count)
    }
}
