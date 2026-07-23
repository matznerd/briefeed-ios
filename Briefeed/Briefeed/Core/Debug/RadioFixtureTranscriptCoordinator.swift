#if DEBUG
import Combine
import Foundation

@MainActor
final class RadioFixtureTranscriptCoordinator:
    RadioTranscriptCoordinating
{
    @Published private(set) var presentation =
        RadioTranscriptPresentation.idle
    @Published private(set) var batchPresentation =
        RadioTranscriptBatchPresentation.idle

    var presentationPublisher:
        AnyPublisher<RadioTranscriptPresentation, Never> {
        $presentation.eraseToAnyPublisher()
    }

    var batchPresentationPublisher:
        AnyPublisher<RadioTranscriptBatchPresentation, Never> {
        $batchPresentation.eraseToAnyPublisher()
    }

    let isPreparationAvailable = true

    private var visibleCandidates: [RadioEpisodeCandidate] = []

    func updateCurrent(
        _ current: RadioEpisodeCandidate?,
        next: [RadioEpisodeCandidate]
    ) {
        guard let current,
              let transcript = try? Self.transcript(for: current) else {
            presentation = .idle
            return
        }
        presentation = RadioTranscriptPresentation(
            episodeKey: current.key,
            state: .ready(transcript)
        )
    }

    func updateVisibleSnapshot(_ candidates: [RadioEpisodeCandidate]) {
        visibleCandidates = candidates
    }

    func prepareAll() {
        batchPresentation = RadioTranscriptBatchPresentation(
            state: .completed,
            completedCount: visibleCandidates.count,
            totalCount: visibleCandidates.count,
            backgroundContinuation: .none,
            episodeKeys: visibleCandidates.map(\.key)
        )
    }

    func retryCurrent() {}

    func stopPrepareAll() {
        batchPresentation = RadioTranscriptBatchPresentation(
            state: .stopped,
            completedCount: 0,
            totalCount: visibleCandidates.count,
            backgroundContinuation: .none,
            episodeKeys: visibleCandidates.map(\.key)
        )
    }

    func handleActive() {}
    func handleBackground() {}
    func handleMemoryWarning() {}

    func preparedPlaybackURL(
        for episodeKey: RadioEpisodeKey
    ) async -> URL? {
        nil
    }

    private static func transcript(
        for candidate: RadioEpisodeCandidate
    ) throws -> TimedTranscript {
        let words = [
            "Good", "morning.", "This", "is", "your", "Briefeed",
            "radio", "update.", "Markets", "moved", "higher", "overnight",
            "while", "leaders", "met", "to", "discuss", "the", "latest",
            "economic", "news.", "Weather", "remains", "mild", "across",
            "the", "region.", "Transit", "agencies", "reported", "normal",
            "service", "for", "the", "morning", "commute.", "Officials",
            "will", "provide", "another", "update", "later", "today.",
            "You", "are", "listening", "to", "Briefeed", "Radio."
        ]
        let duration = max(candidate.durationSeconds ?? 90, 1)
        let unitDuration = duration / Double(words.count)
        let units = words.enumerated().map { index, word in
            TimedTranscriptUnit(
                text: word,
                startSeconds: Double(index) * unitDuration,
                endSeconds: Double(index + 1) * unitDuration,
                confidence: 0.98,
                granularity: .word
            )
        }
        return try TimedTranscript(
            assetFingerprint: "fixture-\(candidate.key.episodeID)",
            engineIdentifier: "fixture-speech-analyzer",
            engineVersion: "1",
            localeIdentifier: "en-US",
            recognizedText: words.joined(separator: " "),
            audioDurationSeconds: duration,
            processingDurationSeconds: 0,
            units: units
        )
    }
}
#endif
