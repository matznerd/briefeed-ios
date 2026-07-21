import Foundation
import Combine
import Testing
@testable import Briefeed

@Suite("Radio player presentation") @MainActor
struct RadioPlayerPresentationTests {
    @Test func radioTransportIsRightHandedAndHasNoPreviousControl() {
        #expect(PlayerPresentationPolicy.transportControls(for: .radio) == [
            .backTen,
            .playPause,
            .forwardTen,
            .next
        ])
        #expect(!PlayerPresentationPolicy.showsPrevious(for: .radio))
        #expect(PlayerPresentationPolicy.showsPrevious(for: .brief))
    }

    @Test func playbackTimePublishesAtMostOncePerDisplayedSecond() async throws {
        let setup = await makeRestoredPlayer()
        await setup.viewModel.play()
        let playbackID = try #require(setup.transport.lastPlaybackID)
        var publishedTimes: [TimeInterval] = []
        let cancellable = setup.viewModel.$currentTime
            .dropFirst()
            .sink { publishedTimes.append($0) }

        for time in [0.1, 0.2, 0.9, 1.0] {
            setup.player.audioProgressUpdated(
                id: playbackID,
                progress: Float(time / 300),
                currentTime: time,
                duration: 300
            )
        }

        #expect(publishedTimes == [1])
        withExtendedLifetime(cancellable) {}
    }

    @Test func speedMenuUsesCanonicalOptionsAndPersistsSelection() {
        #expect(PlayerPresentationPolicy.speedOptions == PlaybackSpeedPolicy.supported)
        #expect(PlayerPresentationPolicy.speedOptions == [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3])

        let suite = "RadioPlayerPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        PlaybackSpeedPolicy.persist(1.75, defaults: defaults)
        #expect(PlaybackSpeedPolicy.loadAndMigrate(defaults: defaults) == 1.75)
    }

    @Test func sleepMenuContainsExactPresetsAndCustomBounds() {
        #expect(RadioSleepMenuOption.all == [
            .off,
            .endOfEpisode,
            .minutes(10),
            .minutes(20),
            .minutes(30),
            .minutes(45),
            .minutes(60),
            .custom
        ])
        #expect(RadioSleepMenuOption.customBounds == 1...180)
        #expect(RadioSleepMenuOption.defaultCustomMinutes == 20)
        #expect(RadioSleepMenuOption.clampedCustomMinutes(0) == 1)
        #expect(RadioSleepMenuOption.clampedCustomMinutes(181) == 180)
    }

    @Test func sleepSelectionMapsToReplaceableCoordinatorState() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(RadioSleepMenuOption.off.timer(now: now) == .off)
        #expect(RadioSleepMenuOption.endOfEpisode.timer(now: now) == .endOfEpisode)
        #expect(RadioSleepMenuOption.minutes(20).timer(now: now) == .deadline(now.addingTimeInterval(1_200)))
        #expect(RadioSleepMenuOption.custom.timer(now: now, customMinutes: 37) == .deadline(now.addingTimeInterval(2_220)))
    }

    @Test func displayFormattingExposesElapsedRemainingAndTimerValues() {
        #expect(PlayerPresentationFormat.elapsed(134) == "2:14")
        #expect(PlayerPresentationFormat.remaining(position: 134, duration: 360) == "-3:46")
        #expect(PlayerPresentationFormat.scrubberAccessibilityValue(position: 134, duration: 360) == "2 minutes, 14 seconds elapsed, 3 minutes, 46 seconds remaining")

        let now = Date(timeIntervalSince1970: 1_000)
        #expect(PlayerPresentationFormat.sleepTimer(.off, now: now) == "Off")
        #expect(PlayerPresentationFormat.sleepTimer(.endOfEpisode, now: now) == "End of Episode")
        #expect(PlayerPresentationFormat.sleepTimer(.deadline(now.addingTimeInterval(1_201)), now: now) == "21 min")
    }

    @Test func displayFormattingSanitizesEveryNonFiniteClockInput() {
        for invalid in [TimeInterval.nan, .infinity, -.infinity] {
            #expect(PlayerPresentationFormat.elapsed(invalid) == "0:00")
            #expect(PlayerPresentationFormat.remaining(position: invalid, duration: 360) == "-6:00")
            #expect(PlayerPresentationFormat.remaining(position: 30, duration: invalid) == "-0:00")
            #expect(PlayerPresentationFormat.scrubberAccessibilityValue(position: invalid, duration: invalid) == "0 minutes, 0 seconds elapsed, 0 minutes, 0 seconds remaining")
        }
    }

    @Test func restoredRadioIsTheEffectiveSurfaceAndPlayRoutesToItsEpisode() async throws {
        let setup = await makeRestoredPlayer(position: 37)

        #expect(setup.player.activeMode == .none)
        #expect(setup.viewModel.effectivePlaybackMode == .radio)
        #expect(setup.viewModel.playerPresentation.kind == .playable)
        #expect(setup.viewModel.playerPresentation.title == "Episode one")
        #expect(setup.viewModel.playerPresentation.source == "NPR")
        #expect(setup.viewModel.playerPresentation.position == 37)
        #expect(setup.viewModel.playerPresentation.duration == 300)
        #expect(!setup.viewModel.playerPresentation.showsPrevious)
        #expect(setup.viewModel.playerPresentation.showsSleep)

        await setup.viewModel.play()

        #expect(setup.player.activeMode == .radio)
        #expect(try #require(setup.transport.loads.last?.1).absoluteString == "https://example.com/one.mp3")
        #expect(setup.brief.saveCount == 0)
    }

    @Test func restoredRadioSecondsAndNextNeverMutateBrief() async throws {
        let setup = await makeRestoredPlayer(position: 37, includesNext: true)

        setup.viewModel.seekForward()
        #expect(setup.repository.progress.last?.0 == RadioEpisodeKey(feedID: "one", episodeID: "one"))
        #expect(setup.repository.progress.last?.1 == 47)
        #expect(setup.transport.seeks.isEmpty)
        #expect(setup.brief.saveCount == 0)
        #expect(setup.viewModel.canPlayNext)

        await setup.viewModel.playNext()

        #expect(try #require(setup.transport.loads.last?.1).absoluteString == "https://example.com/two.mp3")
        #expect(setup.brief.saveCount == 0)
    }

    @Test func speedSelectionPersistsAndLoadsInANewViewModel() async {
        var savedSpeed: Float = 1.75
        let first = await makeRestoredPlayer(
            playbackSpeedLoad: { savedSpeed },
            playbackSpeedSave: { savedSpeed = $0 }
        )
        #expect(first.viewModel.playbackSpeed == 1.75)

        first.viewModel.setSpeed(2.5)
        #expect(savedSpeed == 2.5)

        let relaunched = await makeRestoredPlayer(
            playbackSpeedLoad: { savedSpeed },
            playbackSpeedSave: { savedSpeed = $0 }
        )
        #expect(relaunched.viewModel.playbackSpeed == 2.5)
    }

    @Test func customSleepTimerClampsAndReplacesTheActualCoordinatorDeadline() async {
        let now = Date(timeIntervalSince1970: 5_000)
        let setup = await makeRestoredPlayer()

        setup.viewModel.setCustomSleepTimer(minutes: 0, now: now)
        #expect(setup.radio.sleepTimer == .deadline(now.addingTimeInterval(60)))

        setup.viewModel.setCustomSleepTimer(minutes: 181, now: now)
        #expect(setup.radio.sleepTimer == .deadline(now.addingTimeInterval(10_800)))
        setup.viewModel.cancelSleepTimer()
        #expect(setup.radio.sleepTimer == .off)
    }

    @Test func expandedRadioGatingComesFromTheEffectiveRestoredSurface() async {
        let setup = await makeRestoredPlayer()
        let presentation = setup.viewModel.playerPresentation

        #expect(presentation.mode == .radio)
        #expect(presentation.allowsExpand)
        #expect(presentation.allowsSeek)
        #expect(presentation.primaryAction == .playPause)
        #expect(!presentation.showsQueue)
        #expect(!presentation.showsPrevious)
        #expect(presentation.showsSleep)
    }

    @Test func exhaustedRadioBecomesCaughtUpRefreshInsteadOfFakePlayback() async {
        let setup = await makeRestoredPlayer()
        _ = setup.radio.playbackCompleted(
            for: RadioEpisodeKey(feedID: "one", episodeID: "one"),
            at: .now
        )
        await Task.yield()

        let presentation = setup.viewModel.playerPresentation
        #expect(presentation.kind == .caughtUp)
        #expect(presentation.title == "You're caught up")
        #expect(presentation.primaryAction == .refresh)
        #expect(!presentation.allowsPlay)
        #expect(!presentation.allowsSeek)
        #expect(!presentation.allowsExpand)
        #expect(!presentation.showsQueue)
        #expect(!presentation.showsPrevious)
    }

    @Test func restoredBriefQueueIsPlayableAndPrimaryPlayLoadsInsteadOfFakeResume() async throws {
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(),
            repository: RecordingRadioRepository(candidates: []),
            connectivityStatus: { .online }
        )
        let brief = FakeBriefQueueCoordinator()
        var transportEvents: [String] = []
        let transport = SpyAudioTransport { transportEvents.append($0) }
        let context = PersistenceController(inMemory: true).container.viewContext
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: context,
            persistPlaybackRate: { _ in }
        )
        let viewModel = AudioPlayerViewModelV2(
            unifiedPlayer: player,
            radioCoordinator: radio,
            rssService: RSSAudioService(viewContext: context, dataLoader: { _ in Data() }),
            playbackSpeedLoad: { 1 }
        )
        brief.queue = [briefItem]
        brief.currentIndex = 0
        await Task.yield()

        #expect(player.activeMode == .none)
        #expect(viewModel.effectivePlaybackMode == .brief)
        #expect(viewModel.playerPresentation.kind == .playable)
        #expect(viewModel.playerPresentation.allowsPlay)

        await viewModel.play()

        #expect(player.activeMode == .brief)
        #expect(try #require(transport.loads.last?.1).absoluteString == "https://example.com/brief.mp3")
        #expect(!transportEvents.contains("resume"))
    }

    @Test func restoredBriefPositionDrivesPresentationAndPreplayTenSecondSeeks() async {
        let setup = await makeBriefOnlyPlayer(position: 52)

        #expect(setup.player.activeMode == .none)
        #expect(setup.player.presentationPosition == 52)
        #expect(setup.viewModel.playerPresentation.position == 52)

        setup.player.skipForward()
        #expect(setup.brief.currentPosition == 62)
        #expect(setup.player.presentationPosition == 62)
        #expect(setup.transport.seeks.isEmpty)

        setup.player.skipBackward()
        #expect(setup.brief.currentPosition == 52)
        #expect(setup.player.presentationPosition == 52)
    }

    @Test func directAndRemoteBeginLoadAnEffectiveBriefInsteadOfResumingEmptyTransport() async throws {
        let direct = await makeBriefOnlyPlayer(position: 18)
        await direct.player.beginEffectiveCurrent()
        #expect(try #require(direct.transport.loads.last?.1).absoluteString == "https://example.com/brief.mp3")
        direct.player.audioItemReady(id: try #require(direct.transport.lastPlaybackID), duration: 300)
        #expect(direct.transport.seeks.last == 18)

        let remote = await makeBriefOnlyPlayer(position: 24)
        remote.player.audioRequestPlay()
        for _ in 0..<10 { await Task.yield() }
        #expect(try #require(remote.transport.loads.last?.1).absoluteString == "https://example.com/brief.mp3")
    }

    @Test func finalBriefCompletionReleasesTransportSoRestoredRadioBecomesEffective() async throws {
        let episode = candidate("radio", title: "Radio episode")
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: PersistedRadioSession(
                schemaVersion: PersistedRadioSession.schemaVersion,
                entries: [RadioQueueEntry(
                    key: episode.key,
                    positionSeconds: 31,
                    disposition: .pending,
                    playbackFailureCount: 0,
                    lastPlaybackError: nil
                )],
                currentKey: episode.key,
                savedAt: .now
            )),
            repository: RecordingRadioRepository(candidates: [episode]),
            connectivityStatus: { .online }
        )
        _ = await radio.restore(autoplayEnabled: false)
        let brief = RemovingBriefQueueCoordinator(item: briefItem)
        let transport = SpyAudioTransport()
        let context = PersistenceController(inMemory: true).container.viewContext
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: context,
            persistPlaybackRate: { _ in },
            briefCompletionDelay: {}
        )
        await Task.yield()
        await player.play(at: 0)
        let playbackID = try #require(transport.lastPlaybackID)

        player.audioDidFinishPlaying(id: playbackID, successfully: true)
        for _ in 0..<10 { await Task.yield() }

        #expect(brief.queue.isEmpty)
        #expect(player.activeMode == .none)
        #expect(player.effectivePlaybackMode == .radio)
        #expect(player.presentationPosition == 31)
    }

    @Test func unavailableSurfaceExposesNoPlaybackOrSeekActions() async {
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(),
            repository: RecordingRadioRepository(candidates: []),
            connectivityStatus: { .online }
        )
        let brief = FakeBriefQueueCoordinator()
        let transport = SpyAudioTransport()
        let context = PersistenceController(inMemory: true).container.viewContext
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: context,
            persistPlaybackRate: { _ in }
        )
        let viewModel = AudioPlayerViewModelV2(
            unifiedPlayer: player,
            radioCoordinator: radio,
            rssService: RSSAudioService(viewContext: context, dataLoader: { _ in Data() }),
            playbackSpeedLoad: { 1 }
        )

        #expect(viewModel.playerPresentation.kind == .unavailable)
        #expect(!viewModel.playerPresentation.allowsPlay)
        #expect(!viewModel.playerPresentation.allowsSeek)
        #expect(!viewModel.playerPresentation.allowsExpand)
    }

    @Test func playerControlsKeepStableAccessibilityIdentifiers() {
        #expect(AccessibilityID.MiniPlayer.rewind == "miniPlayer.rewind")
        #expect(AccessibilityID.MiniPlayer.playPause == "miniPlayer.playPause")
        #expect(AccessibilityID.MiniPlayer.forward == "miniPlayer.forward")
        #expect(AccessibilityID.MiniPlayer.next == "miniPlayer.next")
        #expect(AccessibilityID.MiniPlayer.scrubber == "miniPlayer.scrubber")
        #expect(AccessibilityID.MiniPlayer.speed == "miniPlayer.speed")
        #expect(AccessibilityID.MiniPlayer.sleep == "miniPlayer.sleep")
        #expect(AccessibilityID.MiniPlayer.refresh == "miniPlayer.refresh")
    }

    private func makeRestoredPlayer(
        position: TimeInterval = 0,
        includesNext: Bool = false,
        playbackSpeedLoad: @escaping @MainActor () -> Float = { 1 },
        playbackSpeedSave: @escaping @MainActor (Float) -> Void = { _ in }
    ) async -> (
        viewModel: AudioPlayerViewModelV2,
        player: UnifiedAudioPlayer,
        radio: RadioSessionCoordinator,
        repository: RecordingRadioRepository,
        brief: FakeBriefQueueCoordinator,
        transport: SpyAudioTransport
    ) {
        let candidates = [candidate("one", title: "Episode one")]
            + (includesNext ? [candidate("two", title: "Episode two")] : [])
        let repository = RecordingRadioRepository(candidates: candidates)
        let session = PersistedRadioSession(
            schemaVersion: PersistedRadioSession.schemaVersion,
            entries: candidates.enumerated().map { index, candidate in
                RadioQueueEntry(
                    key: candidate.key,
                    positionSeconds: index == 0 ? position : 0,
                    disposition: .pending,
                    playbackFailureCount: 0,
                    lastPlaybackError: nil
                )
            },
            currentKey: candidates[0].key,
            savedAt: .now
        )
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: session),
            repository: repository,
            connectivityStatus: { .online }
        )
        _ = await radio.restore(autoplayEnabled: false)
        let brief = FakeBriefQueueCoordinator(currentPosition: 91)
        let transport = SpyAudioTransport()
        let context = PersistenceController(inMemory: true).container.viewContext
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: context,
            persistPlaybackRate: playbackSpeedSave
        )
        let rss = RSSAudioService(viewContext: context, dataLoader: { _ in Data() })
        let viewModel = AudioPlayerViewModelV2(
            unifiedPlayer: player,
            radioCoordinator: radio,
            rssService: rss,
            playbackSpeedLoad: playbackSpeedLoad
        )
        return (viewModel, player, radio, repository, brief, transport)
    }

    private func makeBriefOnlyPlayer(position: TimeInterval) async -> (
        viewModel: AudioPlayerViewModelV2,
        player: UnifiedAudioPlayer,
        brief: FakeBriefQueueCoordinator,
        transport: SpyAudioTransport
    ) {
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(),
            repository: RecordingRadioRepository(candidates: []),
            connectivityStatus: { .online }
        )
        let brief = FakeBriefQueueCoordinator(currentPosition: position)
        let transport = SpyAudioTransport()
        let context = PersistenceController(inMemory: true).container.viewContext
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: context,
            persistPlaybackRate: { _ in }
        )
        let viewModel = AudioPlayerViewModelV2(
            unifiedPlayer: player,
            radioCoordinator: radio,
            rssService: RSSAudioService(viewContext: context, dataLoader: { _ in Data() }),
            playbackSpeedLoad: { 1 }
        )
        brief.queue = [briefItem]
        brief.currentIndex = 0
        await Task.yield()
        return (viewModel, player, brief, transport)
    }

    private func candidate(_ id: String, title: String) -> RadioEpisodeCandidate {
        RadioEpisodeCandidate(
            key: .init(feedID: id, episodeID: id),
            originalPlaybackURL: URL(string: "https://example.com/\(id).mp3")!,
            canonicalEnclosureURL: "https://example.com/\(id).mp3",
            title: title,
            sourceName: "NPR",
            publicationDate: .now,
            durationSeconds: 300,
            normalizedCoreDataProgress: 0,
            isCompleted: false,
            sourcePriority: 0,
            sourceFrequency: .daily
        )
    }

    private var briefItem: QueueItem {
        QueueItem(
            id: UUID(),
            type: .liveNews,
            title: "Brief episode",
            source: "Brief source",
            addedAt: .now,
            expiresAt: nil,
            articleID: nil,
            summaryState: .ready,
            cachedAudioURL: nil,
            episodeID: "brief",
            streamURL: URL(string: "https://example.com/brief.mp3"),
            lastPosition: 0,
            isListened: false
        )
    }
}

@MainActor
private final class RemovingBriefQueueCoordinator: BriefQueueCoordinating {
    var queue: [QueueItem] { didSet { queueSubject.send(queue) } }
    var currentIndex: Int { didSet { indexSubject.send(currentIndex) } }
    var currentPosition: TimeInterval = 0
    var currentItem: QueueItem? {
        guard currentIndex >= 0, currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }
    var itemCount: Int { queue.count }
    private let queueSubject: CurrentValueSubject<[QueueItem], Never>
    private let indexSubject: CurrentValueSubject<Int, Never>
    var queuePublisher: AnyPublisher<[QueueItem], Never> { queueSubject.eraseToAnyPublisher() }
    var currentIndexPublisher: AnyPublisher<Int, Never> { indexSubject.eraseToAnyPublisher() }

    init(item: QueueItem) {
        queue = [item]
        currentIndex = 0
        queueSubject = CurrentValueSubject([item])
        indexSubject = CurrentValueSubject(0)
    }

    func addArticle(_ article: Article, playNow: Bool, playNext: Bool) {}
    func addEpisode(_ episode: RSSEpisode, playNow: Bool, playNext: Bool) {}
    func removeItem(at index: Int) {}
    func clearQueue() { queue = []; currentIndex = -1 }
    func setCurrentIndex(_ index: Int) { currentIndex = index }
    func updateCurrentPosition(_ position: TimeInterval) { currentPosition = position }
    func markCurrentAsListened() {}
    func updateCachedAudioURL(for itemID: UUID, url: URL?) {}
    func markItemFailed(for itemID: UUID, error: String) {}
    func autoRemoveIfListened(at index: Int) -> UUID? {
        guard queue.indices.contains(index) else { return nil }
        let id = queue.remove(at: index).id
        currentIndex = queue.isEmpty ? -1 : min(index, queue.count - 1)
        return id
    }
    func saveStateNow() {}
}
