import Foundation

struct TimedTranscriptIndex: Sendable {
    private let units: [TimedTranscriptUnit]

    init(transcript: TimedTranscript) {
        units = transcript.units
    }

    func activeUnit(at mediaTime: TimeInterval) -> TimedTranscriptUnit? {
        guard let index = activeUnitIndex(at: mediaTime) else { return nil }
        return units[index]
    }

    func activeUnitIndex(at mediaTime: TimeInterval) -> Int? {
        guard mediaTime.isFinite, mediaTime >= 0, !units.isEmpty else { return nil }

        var lower = 0
        var upper = units.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if units[middle].startSeconds <= mediaTime {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        guard lower > 0 else { return nil }
        let candidateIndex = lower - 1
        let candidate = units[candidateIndex]
        if candidateIndex == units.count - 1, mediaTime >= candidate.endSeconds {
            return nil
        }
        return candidateIndex
    }

    func unitIndexes(
        intersecting mediaRange: ClosedRange<TimeInterval>
    ) -> [Int] {
        guard mediaRange.lowerBound.isFinite,
              mediaRange.upperBound.isFinite,
              mediaRange.upperBound >= 0,
              mediaRange.lowerBound <= mediaRange.upperBound,
              !units.isEmpty else {
            return []
        }
        let lowerBound = max(mediaRange.lowerBound, 0)
        var lower = 0
        var upper = units.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if units[middle].endSeconds < lowerBound {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let first = lower

        lower = first
        upper = units.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if units[middle].startSeconds <= mediaRange.upperBound {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard first < lower else { return [] }
        return Array(first..<lower)
    }
}
