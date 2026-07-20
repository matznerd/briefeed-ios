import Foundation
import Testing
@testable import Briefeed

@Suite("Radio home presentation")
struct RadioHomePresentationTests {
    @Test(arguments: [
        RadioSessionState.readyPaused,
        .loading,
        .playing,
        .pausedByUser
    ])
    func degradedBannerAppearsOnlyForPlayableCurrentStates(state: RadioSessionState) {
        #expect(RadioHomePresentation.showsDegradedBanner(
            state: state,
            activeMode: .radio,
            hasCurrentEpisode: true,
            sourceFailureCount: 1
        ))
    }

    @Test(arguments: [
        RadioSessionState.noSources,
        .exhausted,
        .failed(.allSourcesUnavailable),
        .waitingForNetwork,
        .refreshing
    ])
    func degradedBannerIsHiddenForTerminalAndUnplayableStates(state: RadioSessionState) {
        #expect(!RadioHomePresentation.showsDegradedBanner(
            state: state,
            activeMode: .radio,
            hasCurrentEpisode: true,
            sourceFailureCount: 1
        ))
    }

    @Test func degradedBannerNeedsBothCurrentEpisodeAndFailures() {
        #expect(!RadioHomePresentation.showsDegradedBanner(
            state: .playing,
            activeMode: .radio,
            hasCurrentEpisode: false,
            sourceFailureCount: 1
        ))
        #expect(!RadioHomePresentation.showsDegradedBanner(
            state: .playing,
            activeMode: .radio,
            hasCurrentEpisode: true,
            sourceFailureCount: 0
        ))
        #expect(!RadioHomePresentation.showsDegradedBanner(
            state: .playing,
            activeMode: .brief,
            hasCurrentEpisode: true,
            sourceFailureCount: 1
        ))
    }

    @Test func currentControlLabelMatchesRadioActivePlaybackPredicate() {
        #expect(RadioHomePresentation.currentControlLabel(activeMode: .radio, isPlaying: true) == "Pause Radio")
        #expect(RadioHomePresentation.currentControlLabel(activeMode: .brief, isPlaying: true) == "Play Radio")
        #expect(RadioHomePresentation.currentControlLabel(activeMode: .radio, isPlaying: false) == "Play Radio")
    }

    @Test func allSourceFailureRefreshesSourcesWhileTransportFailuresRetryPlayback() {
        #expect(RadioHomePresentation.failureRecovery(for: .allSourcesUnavailable) == .refreshSources)
        #expect(RadioHomePresentation.failureRecovery(for: .playback("failed")) == .retryPlayback)
        #expect(RadioHomePresentation.failureRecovery(for: .persistence("failed")) == .retryPlayback)
    }

    @Test func playlistPreservesPersistedQueueOrderBeforeSupplementalLatestRows() {
        let now = Date(timeIntervalSince1970: 10_000)
        let nprLatest = candidate(
            feedID: "npr",
            episodeID: "latest",
            title: "Morning Update",
            publishedAt: now,
            priority: 0,
            progress: 0.25
        )
        let nprOlder = candidate(
            feedID: "npr",
            episodeID: "older",
            title: "Older Update",
            publishedAt: now.addingTimeInterval(-3_600),
            priority: 0
        )
        let bbc = candidate(
            feedID: "bbc",
            episodeID: "latest",
            title: "World Service Brief",
            publishedAt: now.addingTimeInterval(-60),
            priority: 1
        )
        let entries = [
            RadioQueueEntry(
                key: bbc.key,
                positionSeconds: 0,
                disposition: .pending,
                playbackFailureCount: 0,
                lastPlaybackError: nil
            ),
            RadioQueueEntry(
                key: nprLatest.key,
                positionSeconds: 75,
                disposition: .playing,
                playbackFailureCount: 0,
                lastPlaybackError: nil
            )
        ]

        let items = RadioHomePresentation.playlistItems(
            candidates: [bbc, nprOlder, nprLatest],
            entries: entries,
            currentKey: nprLatest.key
        )

        #expect(items.map(\.candidate.title) == ["World Service Brief", "Morning Update"])
        #expect(items.map(\.isCurrent) == [false, true])
        #expect(items[0].status == .upNext)
        #expect(items[1].status == .inProgress(fraction: 0.25))
    }

    @Test func playlistKeepsOlderCurrentEpisodeAndSupplementsNewerEpisodeFromSameSource() {
        let now = Date(timeIntervalSince1970: 20_000)
        let current = candidate(
            feedID: "npr",
            episodeID: "current",
            title: "Current Hour",
            publishedAt: now.addingTimeInterval(-3_600),
            priority: 0,
            progress: 0.5
        )
        let newer = candidate(
            feedID: "npr",
            episodeID: "newer",
            title: "New Hour",
            publishedAt: now,
            priority: 0
        )
        let entry = RadioQueueEntry(
            key: current.key,
            positionSeconds: 150,
            disposition: .playing,
            playbackFailureCount: 0,
            lastPlaybackError: nil
        )

        let items = RadioHomePresentation.playlistItems(
            candidates: [newer, current],
            entries: [entry],
            currentKey: current.key
        )

        #expect(items.map(\.candidate.title) == ["Current Hour", "New Hour"])
        #expect(items.map(\.status) == [.inProgress(fraction: 0.5), .latest])
        #expect(items.map(\.isCurrent) == [true, false])
    }

    @Test func playlistUsesMoreDurableProgressWhenSessionSnapshotLagsCoreData() {
        let episode = candidate(
            feedID: "npr",
            episodeID: "partial",
            title: "Partial",
            publishedAt: Date(),
            priority: 0,
            progress: 0.4
        )
        let entry = RadioQueueEntry(
            key: episode.key,
            positionSeconds: 0,
            disposition: .pending,
            playbackFailureCount: 0,
            lastPlaybackError: nil
        )

        let item = RadioHomePresentation.playlistItems(
            candidates: [episode],
            entries: [entry],
            currentKey: episode.key
        ).first

        #expect(item?.status == .inProgress(fraction: 0.4))
    }

    @Test func playlistKeepsCompletedLatestEpisodeVisibleAsListened() {
        let completed = candidate(
            feedID: "npr",
            episodeID: "completed",
            title: "Completed Update",
            publishedAt: Date(),
            priority: 0,
            progress: 1,
            completed: true
        )

        let items = RadioHomePresentation.playlistItems(
            candidates: [completed],
            entries: [],
            currentKey: nil
        )

        #expect(items.count == 1)
        #expect(items[0].status == .listened)
    }

    @Test func latestEpisodeOutsideEligibleQueueRemainsVisibleButNotQueued() {
        let latest = candidate(
            feedID: "npr",
            episodeID: "stale",
            title: "Older Update",
            publishedAt: Date(),
            priority: 0
        )

        let items = RadioHomePresentation.playlistItems(
            candidates: [latest],
            entries: [],
            currentKey: nil
        )

        #expect(items.count == 1)
        #expect(items[0].status == .latest)
    }

    private func candidate(
        feedID: String,
        episodeID: String,
        title: String,
        publishedAt: Date,
        priority: Int,
        progress: Double = 0,
        completed: Bool = false
    ) -> RadioEpisodeCandidate {
        RadioEpisodeCandidate(
            key: RadioEpisodeKey(feedID: feedID, episodeID: episodeID),
            originalPlaybackURL: URL(string: "https://example.com/\(feedID)/\(episodeID).mp3")!,
            canonicalEnclosureURL: "https://example.com/\(feedID)/\(episodeID).mp3",
            title: title,
            sourceName: feedID.uppercased(),
            publicationDate: publishedAt,
            durationSeconds: 300,
            normalizedCoreDataProgress: progress,
            isCompleted: completed,
            sourcePriority: priority,
            sourceFrequency: .hourly
        )
    }
}
