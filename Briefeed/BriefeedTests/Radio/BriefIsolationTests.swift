import CoreData
import Foundation
import Testing
@testable import Briefeed

@Suite("Brief isolation from Radio")
@MainActor
struct BriefIsolationTests {
    @Test func radioActivationAndProgressLeaveBriefPositionAndIndexUntouched() async throws {
        let key = RadioEpisodeKey(feedID: "radio", episodeID: "episode")
        let candidate = RadioEpisodeCandidate(
            key: key,
            originalPlaybackURL: URL(string: "https://example.com/radio.mp3")!,
            canonicalEnclosureURL: "https://example.com/radio.mp3",
            title: "Radio", sourceName: "Source", publicationDate: .now,
            durationSeconds: 200, normalizedCoreDataProgress: 0, isCompleted: false,
            sourcePriority: 0, sourceFrequency: .hourly
        )
        let session = PersistedRadioSession(
            schemaVersion: 1,
            entries: [.init(key: key, positionSeconds: 23, disposition: .pending, playbackFailureCount: 0, lastPlaybackError: nil)],
            currentKey: key,
            savedAt: .now
        )
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: session),
            repository: RecordingRadioRepository(candidates: [candidate]),
            connectivityStatus: { .online }
        )
        _ = await radio.restore(autoplayEnabled: false)
        let brief = FakeBriefQueueCoordinator(currentPosition: 91)
        brief.currentIndex = -1
        let transport = SpyAudioTransport()
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true).container.viewContext
        )

        await player.playRadio()
        let id = try #require(transport.lastPlaybackID)
        player.audioProgressUpdated(id: id, progress: 0.5, currentTime: 100, duration: 200)

        #expect(brief.currentPosition == 91)
        #expect(brief.currentIndex == -1)
        #expect(brief.saveCount == 0)
    }

    @Test func interruptionShouldResumeDoesNotOverrideBriefUserPause() async {
        let brief = FakeBriefQueueCoordinator()
        brief.queue = [QueueItem(
            id: UUID(), type: .liveNews, title: "Brief", source: "Source",
            addedAt: .now, expiresAt: nil, articleID: nil, summaryState: .ready,
            cachedAudioURL: nil, episodeID: "brief", streamURL: URL(string: "https://example.com/brief.mp3"),
            lastPosition: 0, isListened: false
        )]
        brief.currentIndex = 0
        let events = BriefEventRecorder()
        let transport = SpyAudioTransport { events.values.append($0) }
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(),
            repository: RecordingRadioRepository(candidates: []),
            connectivityStatus: { .online }
        )
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true).container.viewContext
        )
        await player.play(at: 0)
        player.pause()
        events.values.removeAll()

        player.audioInterruptionBegan(id: transport.lastPlaybackID)
        player.audioInterruptionEnded(id: transport.lastPlaybackID, shouldResume: true)

        #expect(!events.values.contains("resume"))
    }

    @Test func viewModelAndAppDefaultSkipsAreTenSeconds() async {
        let brief = FakeBriefQueueCoordinator()
        brief.queue = [QueueItem(
            id: UUID(), type: .liveNews, title: "Brief", source: "Source",
            addedAt: .now, expiresAt: nil, articleID: nil, summaryState: .ready,
            cachedAudioURL: nil, episodeID: "brief", streamURL: URL(string: "https://example.com/brief.mp3"),
            lastPosition: 0, isListened: false
        )]
        brief.currentIndex = 0
        let transport = SpyAudioTransport()
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(),
            repository: RecordingRadioRepository(candidates: []),
            connectivityStatus: { .online }
        )
        let context = PersistenceController(inMemory: true).container.viewContext
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: context
        )
        let rss = RSSAudioService(viewContext: context, dataLoader: { _ in Data() })
        let viewModel = AudioPlayerViewModelV2(unifiedPlayer: player, radioCoordinator: radio, rssService: rss)
        let appViewModel = AppViewModel(audioPlayerViewModel: viewModel)

        await player.play(at: 0)
        appViewModel.skipForward()
        appViewModel.skipBackward()

        #expect(transport.seeks == [10, 0])
    }
}

@MainActor
private final class BriefEventRecorder { var values: [String] = [] }
