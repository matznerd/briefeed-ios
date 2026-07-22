import Foundation
import Testing
@testable import Briefeed

@Suite("Timed transcript")
struct TimedTranscriptTests {
    private let units = [
        TimedTranscriptUnit(text: "Good morning", startSeconds: 0.2, endSeconds: 0.8, confidence: 0.98, granularity: .phrase),
        TimedTranscriptUnit(text: "California", startSeconds: 1.0, endSeconds: 1.5, confidence: 0.95, granularity: .word),
        TimedTranscriptUnit(text: "news", startSeconds: 1.5, endSeconds: 1.9, confidence: nil, granularity: .word)
    ]

    @Test func validatesAndRoundTripsWithoutLosingPrecision() throws {
        let transcript = try TimedTranscript(
            assetFingerprint: "abc123",
            engineIdentifier: "apple-speech-analyzer",
            engineVersion: "iOS-26",
            localeIdentifier: "en-US",
            recognizedText: "Good morning California news",
            audioDurationSeconds: 3,
            processingDurationSeconds: 0.75,
            units: units
        )
        let decoded = try JSONDecoder().decode(TimedTranscript.self, from: JSONEncoder().encode(transcript))
        #expect(decoded == transcript)
    }

    @Test func rejectsOverlappingAndOutOfBoundsRanges() {
        #expect(throws: TimedTranscriptValidationError.self) {
            try TimedTranscript(assetFingerprint: "a", engineIdentifier: "e", engineVersion: "1", localeIdentifier: "en-US", recognizedText: "one two", audioDurationSeconds: 2, processingDurationSeconds: 1, units: [
                TimedTranscriptUnit(text: "one", startSeconds: 0, endSeconds: 1.2, confidence: nil, granularity: .word),
                TimedTranscriptUnit(text: "two", startSeconds: 1, endSeconds: 1.5, confidence: nil, granularity: .word)
            ])
        }
        #expect(throws: TimedTranscriptValidationError.self) {
            try TimedTranscript(assetFingerprint: "a", engineIdentifier: "e", engineVersion: "1", localeIdentifier: "en-US", recognizedText: "late", audioDurationSeconds: 2, processingDurationSeconds: 1, units: [
                TimedTranscriptUnit(text: "late", startSeconds: 1.5, endSeconds: 2.1, confidence: nil, granularity: .word)
            ])
        }
    }

    @Test func mediaTimeSelectsUnitsAndRetainsPriorUnitOnlyInsideInternalGaps() throws {
        let transcript = try TimedTranscript(assetFingerprint: "a", engineIdentifier: "e", engineVersion: "1", localeIdentifier: "en-US", recognizedText: "Good morning California news", audioDurationSeconds: 3, processingDurationSeconds: 1, units: units)
        let index = TimedTranscriptIndex(transcript: transcript)

        #expect(index.activeUnit(at: 0.1) == nil)
        #expect(index.activeUnit(at: 0.2)?.text == "Good morning")
        #expect(index.activeUnit(at: 0.9)?.text == "Good morning")
        #expect(index.activeUnit(at: 1.0)?.text == "California")
        #expect(index.activeUnit(at: 1.5)?.text == "news")
        #expect(index.activeUnit(at: 2.0) == nil)
    }

    @Test func playbackRateNeverEntersMediaTimeLookup() throws {
        let transcript = try TimedTranscript(assetFingerprint: "a", engineIdentifier: "e", engineVersion: "1", localeIdentifier: "en-US", recognizedText: "Good morning California news", audioDurationSeconds: 3, processingDurationSeconds: 1, units: units)
        let index = TimedTranscriptIndex(transcript: transcript)
        let simulatedPlaybackRates = [0.5, 1.0, 2.0, 3.0]
        let selections = simulatedPlaybackRates.map { _ in index.activeUnit(at: 1.25)?.text }
        #expect(selections == Array(repeating: "California", count: simulatedPlaybackRates.count))
    }
}
