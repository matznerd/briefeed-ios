import Foundation
import Testing
@testable import Briefeed

@Suite("Radio home presentation")
struct RadioHomePresentationTests {
    @Test func currentControlLabelMatchesRadioActivePlaybackPredicate() {
        #expect(RadioHomePresentation.currentControlLabel(activeMode: .radio, isPlaying: true) == "Pause Radio")
        #expect(RadioHomePresentation.currentControlLabel(activeMode: .brief, isPlaying: true) == "Play Radio")
        #expect(RadioHomePresentation.currentControlLabel(activeMode: .radio, isPlaying: false) == "Play Radio")
    }

    @Test func rowPrimaryActionsMakePlaybackAndArchiveRolesUnambiguous() {
        let episode = candidate(
            feedID: "source",
            episodeID: "latest",
            title: "Latest",
            publishedAt: Date(),
            priority: 0
        )
        func item(_ status: RadioPlaylistStatus, current: Bool = false) -> RadioPlaylistItem {
            RadioPlaylistItem(
                candidate: episode,
                entry: nil,
                isCurrent: current,
                status: status,
                earlierEpisodeCount: 3
            )
        }

        #expect(RadioHomePresentation.primaryAction(
            for: item(.upNext, current: true),
            activeMode: .radio,
            isPlaying: true
        ) == .pause)
        #expect(RadioHomePresentation.primaryAction(
            for: item(.inProgress(fraction: 0.4)),
            activeMode: .none,
            isPlaying: false
        ) == .resume)
        #expect(RadioHomePresentation.primaryAction(
            for: item(.listened),
            activeMode: .none,
            isPlaying: false
        ) == .replay)
        #expect(RadioHomePresentation.primaryAction(
            for: item(.latest),
            activeMode: .none,
            isPlaying: false
        ) == .play)
        #expect(RadioHomePresentation.primaryAction(
            for: item(.failed),
            activeMode: .none,
            isPlaying: false
        ) == .retry)
        #expect(RadioRowPrimaryAction.play.systemImage == "play.circle.fill")
        #expect(RadioRowPrimaryAction.replay.accessibilityVerb == "Replay")
    }

    @Test func allSourceFailureRefreshesSourcesWhileTransportFailuresRetryPlayback() {
        #expect(RadioHomePresentation.failureRecovery(for: .allSourcesUnavailable) == .refreshSources)
        #expect(RadioHomePresentation.failureRecovery(for: .playback("failed")) == .retryPlayback)
        #expect(RadioHomePresentation.failureRecovery(for: .persistence("failed")) == .retryPlayback)
    }

    @Test func playlistUsesOneNewestEpisodePerSourceInSourcePriorityOrder() {
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

        #expect(items.map(\.candidate.title) == ["Morning Update", "World Service Brief"])
        #expect(items.map(\.isCurrent) == [true, false])
        #expect(items[0].status == .inProgress(fraction: 0.25))
        #expect(items[1].status == .upNext)
    }

    @Test func playlistShowsOnlyNewestEpisodeWhenCurrentSourceHasAReplacement() {
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

        #expect(items.map(\.candidate.title) == ["New Hour"])
        #expect(items.map(\.status) == [.latest])
        #expect(items.map(\.isCurrent) == [false])
        #expect(items[0].earlierEpisodeCount == 1)
    }

    @Test func hourlyTitlesUseSourceIdentityAndTheUsersTimeZone() {
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let locale = Locale(identifier: "en_US_POSIX")
        let episode = candidate(
            feedID: "npr-news-now",
            episodeID: "hour",
            title: "NPR News: 07-20-2026 5PM EDT",
            publishedAt: Date(timeIntervalSince1970: 1_784_581_200),
            priority: 0,
            sourceName: "NPR News Now"
        )

        #expect(RadioHomePresentation.displayTitle(
            for: episode,
            timeZone: losAngeles,
            locale: locale
        ) == "NPR: 2 PM PDT · 7/20/26")
    }

    @Test(arguments: [
        ("npr-news-now", "NPR News Now", "NPR"),
        ("abc-news-update", "ABC News Update", "ABC"),
        ("cbs-on-the-hour", "CBS News: On The Hour", "CBS"),
        ("cbc-world-this-hour", "CBC World This Hour", "CBC")
    ])
    func hourlySourceIdentitiesUseCompactKnownNetworkNames(
        feedID: String,
        sourceName: String,
        expected: String
    ) {
        let episode = candidate(
            feedID: feedID,
            episodeID: "hour",
            title: "Raw title",
            publishedAt: Date(),
            priority: 0,
            sourceName: sourceName
        )

        #expect(RadioHomePresentation.sourceIdentity(for: episode) == expected)
    }

    @Test func dailyTitlesRemainEditorial() {
        let episode = candidate(
            feedID: "bbc",
            episodeID: "story",
            title: "A new government forms",
            publishedAt: Date(),
            priority: 1,
            frequency: .daily
        )

        #expect(RadioHomePresentation.displayTitle(for: episode) == "A new government forms")
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
        completed: Bool = false,
        sourceName: String? = nil,
        frequency: RSSUpdateFrequencyValue = .hourly
    ) -> RadioEpisodeCandidate {
        RadioEpisodeCandidate(
            key: RadioEpisodeKey(feedID: feedID, episodeID: episodeID),
            originalPlaybackURL: URL(string: "https://example.com/\(feedID)/\(episodeID).mp3")!,
            canonicalEnclosureURL: "https://example.com/\(feedID)/\(episodeID).mp3",
            title: title,
            sourceName: sourceName ?? feedID.uppercased(),
            publicationDate: publishedAt,
            durationSeconds: 300,
            normalizedCoreDataProgress: progress,
            isCompleted: completed,
            sourcePriority: priority,
            sourceFrequency: frequency
        )
    }
}
