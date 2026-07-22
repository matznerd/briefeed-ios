import Foundation

struct TimedTranscriptIndex: Sendable {
    private let units: [TimedTranscriptUnit]

    init(transcript: TimedTranscript) {
        units = transcript.units
    }

    func activeUnit(at mediaTime: TimeInterval) -> TimedTranscriptUnit? {
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
        return candidate
    }
}
