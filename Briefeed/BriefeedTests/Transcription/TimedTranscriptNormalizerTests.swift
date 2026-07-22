import Testing
@testable import Briefeed

@Suite("Timed transcript normalizer")
struct TimedTranscriptNormalizerTests {
    @Test func preservesOneWordAndMultiwordRunGranularity() throws {
        let units = try TimedTranscriptNormalizer.normalize(runs: [
            TranscriptAttributedRun(text: " Today ", startSeconds: 0.1, endSeconds: 0.4, confidence: 0.9),
            TranscriptAttributedRun(text: "in California", startSeconds: 0.5, endSeconds: 1.2, confidence: 0.8)
        ])

        #expect(units[0] == TimedTranscriptUnit(text: "Today", startSeconds: 0.1, endSeconds: 0.4, confidence: 0.9, granularity: .word))
        #expect(units[1] == TimedTranscriptUnit(text: "in California", startSeconds: 0.5, endSeconds: 1.2, confidence: 0.8, granularity: .phrase))
    }

    @Test func dropsUntimedAndWhitespaceOnlyRunsWithoutInventingRanges() throws {
        let units = try TimedTranscriptNormalizer.normalize(runs: [
            TranscriptAttributedRun(text: " ", startSeconds: 0, endSeconds: 0.2, confidence: nil),
            TranscriptAttributedRun(text: "untimed", startSeconds: nil, endSeconds: nil, confidence: nil),
            TranscriptAttributedRun(text: "news", startSeconds: 0.3, endSeconds: 0.7, confidence: nil)
        ])

        #expect(units.map(\.text) == ["news"])
    }
}
