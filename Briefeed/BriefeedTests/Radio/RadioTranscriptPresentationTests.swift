import Foundation
import Testing
@testable import Briefeed

@Suite("Radio transcript presentation")
struct RadioTranscriptPresentationTests {
    @Test func preparationStatesKeepOneCompactHeightAndUseActionableCopy() {
        let episodeKey = RadioEpisodeKey(feedID: "npr", episodeID: "hour")
        let states: [(RadioTranscriptPreparationState, String)] = [
            (.unavailableOS, "Live transcript requires iOS 26"),
            (.unsupportedDevice, "Live transcript is not available on this iPhone"),
            (.unsupportedLocale("fr-CA"), "French (Canada) is not supported for this episode"),
            (.assetRequired, "Preparing on-device speech model"),
            (.queued, "Transcript queued"),
            (.downloading(progress: 0.5), "Preparing transcript"),
            (.transcribing, "Transcribing on this iPhone"),
            (.deferred, "Transcript will continue when Briefeed is active"),
            (
                .failed(message: "The episode could not be analyzed.", canRetry: true),
                "The episode could not be analyzed."
            )
        ]

        for (state, title) in states {
            let content = RadioTranscriptUIPresentation.compactContent(
                presentation: RadioTranscriptPresentation(
                    episodeKey: episodeKey,
                    state: state
                ),
                mediaTime: 0,
                accessibilityTextSize: false
            )

            #expect(content.title == title)
            #expect(content.fixedHeight == RadioTranscriptUIPresentation.compactHeight)
        }
    }

    @Test func compactReadyContentTracksTheActiveWordWithoutRegroupingLines() throws {
        let transcript = try makeTranscript()
        let presentation = RadioTranscriptPresentation(
            episodeKey: .init(feedID: "npr", episodeID: "hour"),
            state: .ready(transcript)
        )

        let early = RadioTranscriptUIPresentation.compactContent(
            presentation: presentation,
            mediaTime: 1.1,
            accessibilityTextSize: false
        )
        let later = RadioTranscriptUIPresentation.compactContent(
            presentation: presentation,
            mediaTime: 1.8,
            accessibilityTextSize: false
        )

        #expect(early.visibleLines.map(\.id) == later.visibleLines.map(\.id))
        #expect(early.activeLineID == later.activeLineID)
        #expect(early.activeUnitIndex == 2)
        #expect(later.activeUnitIndex == 3)
        #expect(early.visibleLines.count == 3)
    }

    @Test func accessibilityTextUsesFewerContextLinesInsteadOfShrinkingType() throws {
        let presentation = RadioTranscriptPresentation(
            episodeKey: .init(feedID: "npr", episodeID: "hour"),
            state: .ready(try makeTranscript())
        )

        let standard = RadioTranscriptUIPresentation.compactContent(
            presentation: presentation,
            mediaTime: 1.1,
            accessibilityTextSize: false
        )
        let accessibility = RadioTranscriptUIPresentation.compactContent(
            presentation: presentation,
            mediaTime: 1.1,
            accessibilityTextSize: true
        )

        #expect(standard.visibleLines.count == 3)
        #expect(accessibility.visibleLines.count == 2)
        #expect(accessibility.fixedHeight > standard.fixedHeight)
    }

    @Test func readyTextStaysHiddenUntilPlaybackIdentityIsValidated() throws {
        let presentation = RadioTranscriptPresentation(
            episodeKey: .init(feedID: "npr", episodeID: "hour"),
            state: .ready(try makeTranscript())
        )

        let content = RadioTranscriptUIPresentation.compactContent(
            presentation: presentation,
            mediaTime: 1,
            accessibilityTextSize: false,
            playbackIsValidated: false
        )

        #expect(!content.isReady)
        #expect(content.title == "Transcript prepared")
        #expect(content.visibleLines.isEmpty)
    }

    @Test func prepareAllPresentsEligibleProgressCompletionAndResume() {
        let idle = RadioTranscriptUIPresentation.prepareAll(
            batch: .idle,
            eligibleCount: 6,
            isAvailable: true
        )
        #expect(idle.title == "Prepare all")
        #expect(idle.detail == "6 episodes · On-device")
        #expect(idle.action == .prepare)
        #expect(idle.isEnabled)

        let preparing = RadioTranscriptUIPresentation.prepareAll(
            batch: RadioTranscriptBatchPresentation(
                state: .preparing,
                completedCount: 3,
                totalCount: 6,
                backgroundContinuation: .accepted
            ),
            eligibleCount: 6,
            isAvailable: true
        )
        #expect(preparing.title == "Preparing 3 of 6")
        #expect(preparing.action == .stop)
        #expect(preparing.progress == 0.5)

        let complete = RadioTranscriptUIPresentation.prepareAll(
            batch: RadioTranscriptBatchPresentation(
                state: .completed,
                completedCount: 6,
                totalCount: 6,
                backgroundContinuation: .none
            ),
            eligibleCount: 0,
            isAvailable: true
        )
        #expect(complete.title == "All transcripts ready")
        #expect(complete.action == .none)

        let stopped = RadioTranscriptUIPresentation.prepareAll(
            batch: RadioTranscriptBatchPresentation(
                state: .stopped,
                completedCount: 2,
                totalCount: 6,
                backgroundContinuation: .none
            ),
            eligibleCount: 4,
            isAvailable: true
        )
        #expect(stopped.title == "Resume preparation")
        #expect(stopped.detail == "4 remaining · On-device")
        #expect(stopped.action == .prepare)
    }

    @Test func prepareAllMakesUnavailableAndRejectedContinuationExplicit() {
        let unavailable = RadioTranscriptUIPresentation.prepareAll(
            batch: .idle,
            eligibleCount: 4,
            isAvailable: false
        )
        #expect(unavailable.title == "Prepare all unavailable")
        #expect(!unavailable.isEnabled)

        let rejected = RadioTranscriptUIPresentation.prepareAll(
            batch: RadioTranscriptBatchPresentation(
                state: .preparing,
                completedCount: 1,
                totalCount: 4,
                backgroundContinuation: .rejected(message: "Not permitted")
            ),
            eligibleCount: 4,
            isAvailable: true
        )
        #expect(rejected.detail == "Continues while Briefeed stays open")
        #expect(rejected.action == .stop)
    }

    @Test func prepareAllEligibilityUsesVisibleUncompletedRowsWithoutDuplicates() {
        let now = Date(timeIntervalSince1970: 1_000)
        let npr = candidate(feedID: "npr", episodeID: "one", date: now)
        let duplicate = candidate(feedID: "npr", episodeID: "one", date: now)
        let listened = candidate(
            feedID: "bbc",
            episodeID: "done",
            date: now,
            completed: true
        )
        let abc = candidate(feedID: "abc", episodeID: "two", date: now)
        let rows = [
            RadioPlaylistItem(
                candidate: npr,
                entry: nil,
                isCurrent: true,
                status: .upNext,
                earlierEpisodeCount: 0
            ),
            RadioPlaylistItem(
                candidate: duplicate,
                entry: nil,
                isCurrent: false,
                status: .latest,
                earlierEpisodeCount: 0
            ),
            RadioPlaylistItem(
                candidate: listened,
                entry: nil,
                isCurrent: false,
                status: .listened,
                earlierEpisodeCount: 0
            ),
            RadioPlaylistItem(
                candidate: abc,
                entry: nil,
                isCurrent: false,
                status: .latest,
                earlierEpisodeCount: 0
            )
        ]

        #expect(
            RadioTranscriptUIPresentation.eligibleCandidates(from: rows)
                .map(\.key) == [npr.key, abc.key]
        )
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
                confidence: 0.95,
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

    private func candidate(
        feedID: String,
        episodeID: String,
        date: Date,
        completed: Bool = false
    ) -> RadioEpisodeCandidate {
        RadioEpisodeCandidate(
            key: .init(feedID: feedID, episodeID: episodeID),
            originalPlaybackURL:
                URL(string: "https://example.com/\(episodeID).mp3")!,
            canonicalEnclosureURL:
                "https://example.com/\(episodeID).mp3",
            title: episodeID,
            sourceName: feedID,
            publicationDate: date,
            durationSeconds: 60,
            normalizedCoreDataProgress: completed ? 1 : 0,
            isCompleted: completed,
            sourcePriority: 0,
            sourceFrequency: .daily
        )
    }
}
