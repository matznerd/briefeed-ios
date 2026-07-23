import Foundation
import Testing
@testable import Briefeed

@Suite("Timed transcript projection")
struct TimedTranscriptProjectionTests {
    @Test func groupsStableLinesAtPunctuationAndExplicitLimits() throws {
        let transcript = try makeTranscript()
        let projection = TimedTranscriptProjection(
            transcript: transcript,
            maxCharactersPerLine: 24,
            maxWordsPerLine: 4
        )

        #expect(projection.lines.map(\.text) == [
            "Good morning.",
            "This is the latest",
            "news from California."
        ])
        #expect(projection.activeLineIndex(at: 1.3) == 1)
        #expect(projection.window(at: 1.3, contextLineCount: 1).map(\.id) ==
                projection.lines[0...2].map(\.id))
        #expect(projection.seekTime(forLineAt: 2) == transcript.units[6].startSeconds)
    }

    @Test func mediaTimeInsideOneLineNeverChangesLineIdentity() throws {
        let projection = TimedTranscriptProjection(
            transcript: try makeTranscript(),
            maxCharactersPerLine: 24,
            maxWordsPerLine: 4
        )

        let lineAtStart = projection.activeLine(at: 1.0)
        let lineAtMiddle = projection.activeLine(at: 1.6)
        let lineAtEnd = projection.activeLine(at: 2.1)

        #expect(lineAtStart?.id == lineAtMiddle?.id)
        #expect(lineAtMiddle?.id == lineAtEnd?.id)
        #expect(projection.activeUnitIndex(at: 1.0) == 2)
        #expect(projection.activeUnitIndex(at: 2.1) == 4)
    }

    @Test func contextWindowClampsAtTranscriptEdges() throws {
        let projection = TimedTranscriptProjection(
            transcript: try makeTranscript(),
            maxCharactersPerLine: 24,
            maxWordsPerLine: 4
        )

        #expect(projection.window(at: 0.1, contextLineCount: 1).map(\.id) == [0, 2])
        #expect(projection.window(at: 3.8, contextLineCount: 1).map(\.id) == [2, 6])
        #expect(projection.window(at: 4.6, contextLineCount: 1).isEmpty)
    }

    @Test func invalidConfigurationIsNormalizedWithoutLosingWords() throws {
        let transcript = try makeTranscript()
        let projection = TimedTranscriptProjection(
            transcript: transcript,
            maxCharactersPerLine: 0,
            maxWordsPerLine: 0
        )

        #expect(projection.lines.flatMap(\.unitIndexes).count == transcript.units.count)
        #expect(projection.lines.allSatisfy { !$0.text.isEmpty })
    }

    private func makeTranscript() throws -> TimedTranscript {
        let words = [
            "Good", "morning.", "This", "is", "the", "latest",
            "news", "from", "California."
        ]
        let units = words.enumerated().map { index, word in
            TimedTranscriptUnit(
                text: word,
                startSeconds: Double(index) * 0.5,
                endSeconds: Double(index + 1) * 0.5,
                confidence: 0.9,
                granularity: .word
            )
        }
        return try TimedTranscript(
            assetFingerprint: "sha256",
            engineIdentifier: "apple-speech-analyzer",
            engineVersion: "iOS-26",
            localeIdentifier: "en-US",
            recognizedText: words.joined(separator: " "),
            audioDurationSeconds: 4.5,
            processingDurationSeconds: 0.1,
            units: units
        )
    }
}
