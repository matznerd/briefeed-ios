import Foundation
import XCTest
@testable import Briefeed

private actor CancellationProbeCompletion {
    private var result: Result<Void, Error>?

    func record(_ result: Result<Void, Error>) {
        self.result = result
    }

    func value() -> Result<Void, Error>? {
        result
    }
}

final class AppleSpeechAnalyzerIntegrationTests: XCTestCase {
    func testRightsClearedFixtureProducesTimedReceipt() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("SpeechAnalyzer requires iOS 26")
        }
        guard ProcessInfo.processInfo.environment["BRIEFEED_TRANSCRIPT_ALLOW_ASSET_DOWNLOAD"] == "1" else {
            throw XCTSkip("Run through run-transcript-probe.sh to permit the system asset request")
        }

        let bundle = Bundle(for: Self.self)
        let fixture = try fixtureURL(named: "apple-news-fixture", extension: "aiff", bundle: bundle)
        let script = try fixtureURL(named: "apple-news-script", extension: "txt", bundle: bundle)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BriefeedTranscriptProbe",
            isDirectory: true
        )
        try? FileManager.default.removeItem(at: output)

        let probe = PodcastTranscriptionProbe(engine: AppleSpeechAnalyzerEngine())
        do {
            _ = try await probe.run(
                fileURL: fixture,
                referenceText: try String(contentsOf: script, encoding: .utf8),
                locale: Locale(identifier: "en-US"),
                assetPolicy: .allowDownload,
                outputDirectory: output
            )
        } catch TimedTranscriptEngineError.engineUnavailable {
            throw XCTSkip("SpeechAnalyzer is unavailable on this simulator")
        } catch TimedTranscriptEngineError.unsupportedLocale(let locale) {
            throw XCTSkip("SpeechAnalyzer does not support \(locale) on this simulator")
        } catch TimedTranscriptEngineError.assetRequired(let locale) {
            throw XCTSkip("SpeechAnalyzer model asset is unavailable for \(locale)")
        }
        let receiptURL = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "json" }),
            "Transcript probe did not write a diagnostic receipt"
        )
        let receipt = try JSONDecoder().decode(
            PodcastTranscriptionReceipt.self,
            from: Data(contentsOf: receiptURL)
        )

        XCTAssertFalse(receipt.transcript.units.isEmpty)
        XCTAssertGreaterThanOrEqual(receipt.timingCoverage, 0.95)
        XCTAssertLessThanOrEqual(receipt.medianWordsPerUnit, 4)
        XCTAssertLessThanOrEqual(try XCTUnwrap(receipt.referenceWordErrorRate), 0.20)
        XCTAssertTrue(receipt.transcript.units.allSatisfy {
            $0.startSeconds >= 0
                && $0.startSeconds <= $0.endSeconds
                && $0.endSeconds <= receipt.transcript.audioDurationSeconds
        })
        print("BRIEFEED_TRANSCRIPT_RECEIPT=\(receiptURL.path)")
    }

    func testCancellationFinishesWithoutHanging() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("SpeechAnalyzer requires iOS 26")
        }
        guard ProcessInfo.processInfo.environment["BRIEFEED_TRANSCRIPT_ALLOW_ASSET_DOWNLOAD"] == "1" else {
            throw XCTSkip("Run through run-transcript-probe.sh")
        }

        let fixture = try fixtureURL(
            named: "apple-news-fixture",
            extension: "aiff",
            bundle: Bundle(for: Self.self)
        )
        let completion = CancellationProbeCompletion()
        let cancelledTranscription = expectation(description: "Cancelled transcription finishes")
        let task = Task {
            do {
                _ = try await AppleSpeechAnalyzerEngine().transcribe(
                    fileURL: fixture,
                    assetFingerprint: "cancellation-probe",
                    locale: Locale(identifier: "en-US"),
                    assetPolicy: .allowDownload
                )
                await completion.record(.success(()))
            } catch {
                await completion.record(.failure(error))
            }
            cancelledTranscription.fulfill()
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        // Do not await `task.value`: an uncooperative engine must not keep this
        // test alive after the XCTest timeout has reported the failure.
        await fulfillment(of: [cancelledTranscription], timeout: 2.0)

        guard let result = await completion.value() else {
            return
        }

        switch result {
        case .success:
            XCTFail("Cancelled transcription unexpectedly completed")
        case .failure(let error):
            if error is CancellationError {
                return
            }
            if let error = error as? TimedTranscriptEngineError {
                switch error {
                case .engineUnavailable:
                    throw XCTSkip("SpeechAnalyzer is unavailable on this simulator")
                case .unsupportedLocale(let locale):
                    throw XCTSkip("SpeechAnalyzer does not support \(locale) on this simulator")
                case .assetRequired(let locale):
                    throw XCTSkip("SpeechAnalyzer model asset is unavailable for \(locale)")
                default:
                    break
                }
            }
            XCTFail("Cancelled transcription failed with \(error) instead of CancellationError")
        }
    }

    private func fixtureURL(named name: String, extension fileExtension: String, bundle: Bundle) throws -> URL {
        try XCTUnwrap(
            bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Fixtures/Transcription")
                ?? bundle.url(forResource: name, withExtension: fileExtension),
            "\(name).\(fileExtension) is missing from BriefeedTests.xctest"
        )
    }
}
