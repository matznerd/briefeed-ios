import Foundation
import Testing
@testable import Briefeed

@Suite("Podcast transcription probe")
struct PodcastTranscriptionProbeTests {
    @Test func writesFingerprintAndDeterministicReceiptForExactReference() async throws {
        let fixtureData = Data([0x00, 0xFF, 0x10, 0x42, 0x7A])
        let fixtureURL = try writeFixture(fixtureData)
        let outputDirectory = try makeTemporaryDirectory()
        let expectedFingerprint = "73b2bb6839e0235f2178366e77b7ec585bbaeab947db4ab7f03f10e8d3e1f7c2"
        let engine = RecordingEngine(result: .success(try makeTranscript(assetFingerprint: expectedFingerprint)))
        let createdAt = Date(timeIntervalSince1970: 1_735_689_600)
        let probe = PodcastTranscriptionProbe(
            engine: engine,
            now: { createdAt },
            operatingSystemVersion: { "TestOS 1.0" }
        )

        let receipt = try await probe.run(
            fileURL: fixtureURL,
            referenceText: "Hello, world. News",
            locale: Locale(identifier: "en_US"),
            assetPolicy: .installedOnly,
            outputDirectory: outputDirectory
        )

        #expect(receipt.schemaVersion == 1)
        #expect(receipt.transcript.assetFingerprint == expectedFingerprint)
        #expect(receipt.createdAt == createdAt)
        #expect(receipt.operatingSystemVersion == "TestOS 1.0")
        #expect(receipt.recognizedCharacterCount == 16)
        #expect(receipt.timedCharacterCount == 16)
        #expect(receipt.timingCoverage == 1)
        #expect(receipt.medianWordsPerUnit == 1.5)
        #expect(receipt.wordUnitCount == 1)
        #expect(receipt.phraseUnitCount == 1)
        #expect(receipt.referenceWordErrorRate == 0)

        let invocation = await engine.invocation
        #expect(invocation?.fileURL == fixtureURL)
        #expect(invocation?.assetFingerprint == expectedFingerprint)
        #expect(invocation?.localeIdentifier == "en_US")
        #expect(invocation?.assetPolicy == .installedOnly)

        let receiptURL = outputDirectory.appending(path: "transcript-\(expectedFingerprint.prefix(12)).json")
        let receiptData = try Data(contentsOf: receiptURL)
        let receiptJSON = String(decoding: receiptData, as: UTF8.self)
        #expect(receiptJSON.contains("\"createdAt\" : \"2025-01-01T00:00:00Z\""))
        #expect(receiptJSON.range(of: "\"createdAt\"")!.lowerBound < receiptJSON.range(of: "\"schemaVersion\"")!.lowerBound)
        #expect(receiptJSON.range(of: "\"assetFingerprint\"")!.lowerBound < receiptJSON.range(of: "\"audioDurationSeconds\"")!.lowerBound)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(PodcastTranscriptionReceipt.self, from: receiptData) == receipt)
    }

    @Test func reportsLevenshteinWordErrorRateIncludingInsertionsDeletionsAndSubstitutions() async throws {
        let fixtureURL = try writeFixture(Data([0x01]))
        let engine = RecordingEngine(result: .success(try makeTranscript()))
        let probe = PodcastTranscriptionProbe(engine: engine)

        let insertionReceipt = try await probe.run(
            fileURL: fixtureURL,
            referenceText: "hello world",
            locale: Locale(identifier: "en-US"),
            assetPolicy: .allowDownload,
            outputDirectory: try makeTemporaryDirectory()
        )
        let deletionReceipt = try await probe.run(
            fileURL: fixtureURL,
            referenceText: "hello world news tomorrow",
            locale: Locale(identifier: "en-US"),
            assetPolicy: .allowDownload,
            outputDirectory: try makeTemporaryDirectory()
        )
        let substitutionReceipt = try await probe.run(
            fileURL: fixtureURL,
            referenceText: "hello planet news",
            locale: Locale(identifier: "en-US"),
            assetPolicy: .allowDownload,
            outputDirectory: try makeTemporaryDirectory()
        )

        #expect(insertionReceipt.referenceWordErrorRate == 0.5)
        #expect(deletionReceipt.referenceWordErrorRate == 0.25)
        #expect(substitutionReceipt.referenceWordErrorRate == 1.0 / 3.0)
    }

    @Test func omitsWordErrorRateWithoutReferenceText() async throws {
        let probe = PodcastTranscriptionProbe(engine: RecordingEngine(result: .success(try makeTranscript())))

        let receipt = try await probe.run(
            fileURL: try writeFixture(Data([0x02])),
            referenceText: nil,
            locale: Locale(identifier: "en-US"),
            assetPolicy: .installedOnly,
            outputDirectory: try makeTemporaryDirectory()
        )

        #expect(receipt.referenceWordErrorRate == nil)
    }

    @Test func propagatesEngineFailuresWithoutWritingAReceipt() async throws {
        let outputDirectory = try makeTemporaryDirectory().appending(path: "receipt")
        let probe = PodcastTranscriptionProbe(engine: RecordingEngine(result: .failure(.engineUnavailable)))

        await #expect(throws: TimedTranscriptEngineError.engineUnavailable) {
            try await probe.run(
                fileURL: try writeFixture(Data([0x03])),
                referenceText: nil,
                locale: Locale(identifier: "en-US"),
                assetPolicy: .installedOnly,
                outputDirectory: outputDirectory
            )
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    private func makeTranscript(assetFingerprint: String = "test-fingerprint") throws -> TimedTranscript {
        try TimedTranscript(
            assetFingerprint: assetFingerprint,
            engineIdentifier: "test-engine",
            engineVersion: "1",
            localeIdentifier: "en-US",
            recognizedText: "Hello world news",
            audioDurationSeconds: 2,
            processingDurationSeconds: 0.1,
            units: [
                TimedTranscriptUnit(text: "Hello", startSeconds: 0, endSeconds: 0.5, confidence: 1, granularity: .word),
                TimedTranscriptUnit(text: "world news", startSeconds: 0.5, endSeconds: 1, confidence: 1, granularity: .phrase)
            ]
        )
    }

    private func writeFixture(_ data: Data) throws -> URL {
        let url = try makeTemporaryDirectory().appending(path: "fixture.audio")
        try data.write(to: url)
        return url
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor RecordingEngine: TimedTranscriptEngine {
    struct Invocation: Equatable, Sendable {
        let fileURL: URL
        let assetFingerprint: String
        let localeIdentifier: String
        let assetPolicy: SpeechAssetPolicy
    }

    enum Result: Sendable {
        case success(TimedTranscript)
        case failure(TimedTranscriptEngineError)
    }

    let result: Result
    private(set) var invocation: Invocation?

    init(result: Result) {
        self.result = result
    }

    func transcribe(
        fileURL: URL,
        assetFingerprint: String,
        locale: Locale,
        assetPolicy: SpeechAssetPolicy
    ) throws -> TimedTranscript {
        invocation = Invocation(
            fileURL: fileURL,
            assetFingerprint: assetFingerprint,
            localeIdentifier: locale.identifier,
            assetPolicy: assetPolicy
        )
        switch result {
        case .success(let transcript):
            return transcript
        case .failure(let error):
            throw error
        }
    }
}
