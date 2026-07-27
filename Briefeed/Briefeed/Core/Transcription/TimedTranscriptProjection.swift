import Foundation

struct TimedTranscriptLine: Identifiable, Equatable, Sendable {
    let id: Int
    let unitIndexes: [Int]
    let text: String
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
}

struct TimedTranscriptProjection: Sendable {
    let lines: [TimedTranscriptLine]

    private let transcript: TimedTranscript
    private let index: TimedTranscriptIndex

    init(
        transcript: TimedTranscript,
        maxCharactersPerLine: Int,
        maxWordsPerLine: Int
    ) {
        self.transcript = transcript
        index = TimedTranscriptIndex(transcript: transcript)
        lines = Self.makeLines(
            units: transcript.units,
            maxCharactersPerLine: max(maxCharactersPerLine, 1),
            maxWordsPerLine: max(maxWordsPerLine, 1)
        )
    }

    func activeUnitIndex(at mediaTime: TimeInterval) -> Int? {
        index.activeUnitIndex(at: mediaTime)
    }

    func activeLineIndex(at mediaTime: TimeInterval) -> Int? {
        guard let unitIndex = activeUnitIndex(at: mediaTime) else { return nil }
        return lines.firstIndex { $0.unitIndexes.contains(unitIndex) }
    }

    func activeLine(at mediaTime: TimeInterval) -> TimedTranscriptLine? {
        guard let lineIndex = activeLineIndex(at: mediaTime) else { return nil }
        return lines[lineIndex]
    }

    func window(
        at mediaTime: TimeInterval,
        contextLineCount: Int
    ) -> [TimedTranscriptLine] {
        guard let activeLineIndex = activeLineIndex(at: mediaTime) else {
            return []
        }
        let context = max(contextLineCount, 0)
        let lower = max(activeLineIndex - context, lines.startIndex)
        let upper = min(activeLineIndex + context, lines.index(before: lines.endIndex))
        return Array(lines[lower...upper])
    }

    func seekTime(forLineAt lineIndex: Int) -> TimeInterval? {
        guard lines.indices.contains(lineIndex) else { return nil }
        return lines[lineIndex].startSeconds
    }

    private static func makeLines(
        units: [TimedTranscriptUnit],
        maxCharactersPerLine: Int,
        maxWordsPerLine: Int
    ) -> [TimedTranscriptLine] {
        guard !units.isEmpty else { return [] }

        var result: [TimedTranscriptLine] = []
        var indexes: [Int] = []
        var texts: [String] = []
        var characterCount = 0
        var wordCount = 0

        func appendCurrentLine() {
            guard let firstIndex = indexes.first,
                  let lastIndex = indexes.last else {
                return
            }
            result.append(
                TimedTranscriptLine(
                    id: firstIndex,
                    unitIndexes: indexes,
                    text: texts.joined(separator: " "),
                    startSeconds: units[firstIndex].startSeconds,
                    endSeconds: units[lastIndex].endSeconds
                )
            )
            indexes.removeAll(keepingCapacity: true)
            texts.removeAll(keepingCapacity: true)
            characterCount = 0
            wordCount = 0
        }

        for (unitIndex, unit) in units.enumerated() {
            let text = unit.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let unitWordCount = max(
                text.split(whereSeparator: \.isWhitespace).count,
                1
            )
            let separatorCount = texts.isEmpty ? 0 : 1
            let wouldExceedCharacters =
                characterCount + separatorCount + text.count > maxCharactersPerLine
            let wouldExceedWords = wordCount + unitWordCount > maxWordsPerLine

            if !indexes.isEmpty, wouldExceedCharacters || wouldExceedWords {
                appendCurrentLine()
            }

            indexes.append(unitIndex)
            texts.append(text)
            characterCount += (texts.count == 1 ? 0 : 1) + text.count
            wordCount += unitWordCount

            if endsPreferredLine(text) {
                appendCurrentLine()
            }
        }
        appendCurrentLine()
        return result
    }

    private static func endsPreferredLine(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return ".!?;:".contains(last)
    }
}

#if DEBUG
enum TimedTranscriptPace {
    static let defaultWindowDuration: TimeInterval = 20

    static func estimatedEffectiveWordsPerMinute(
        transcript: TimedTranscript,
        mediaTime: TimeInterval,
        playbackRate: Double,
        windowDuration: TimeInterval = defaultWindowDuration
    ) -> Int? {
        guard mediaTime.isFinite,
              playbackRate.isFinite,
              playbackRate > 0,
              windowDuration.isFinite,
              windowDuration > 0 else {
            return nil
        }

        let duration = transcript.audioDurationSeconds
        let observedDuration = min(windowDuration, duration)
        let clampedTime = min(max(mediaTime, 0), duration)
        let maximumStart = max(duration - observedDuration, 0)
        let windowStart = min(
            max(clampedTime - observedDuration / 2, 0),
            maximumStart
        )
        let windowEnd = windowStart + observedDuration
        let wordCount = transcript.units.reduce(into: 0) { count, unit in
            let midpoint = unit.startSeconds
                + (unit.endSeconds - unit.startSeconds) / 2
            guard midpoint >= windowStart, midpoint < windowEnd else {
                return
            }
            count += max(
                unit.text.split(whereSeparator: \.isWhitespace).count,
                1
            )
        }
        guard wordCount > 0 else { return nil }

        let sourceWordsPerMinute =
            Double(wordCount) / observedDuration * 60
        return Int((sourceWordsPerMinute * playbackRate).rounded())
    }
}
#endif
