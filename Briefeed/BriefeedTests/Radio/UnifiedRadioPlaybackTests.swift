import Combine
import CoreData
import Foundation
import Testing
@testable import Briefeed

@Suite("Unified Radio playback")
@MainActor
struct UnifiedRadioPlaybackTests {
    @Test func transportStartPromotesPlayerAndCoordinatorToPlaying() async throws {
        let candidate = makeCandidate("start")
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: makeSession(candidate.key)),
            repository: RecordingRadioRepository(candidates: [candidate]),
            connectivityStatus: { .online }
        )
        _ = await radio.restore(autoplayEnabled: false)
        let transport = SpyAudioTransport()
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: FakeBriefQueueCoordinator(),
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true).container.viewContext
        )

        await player.playRadio()
        let id = try #require(transport.lastPlaybackID)
        #expect(player.isPlaying == false)
        #expect(radio.state == .loading)

        player.audioStateChanged(id: id, to: .playing, from: .loading)

        #expect(player.isPlaying)
        #expect(radio.state == .playing)
        #expect(radio.entries.first?.disposition == .playing)
    }

    @Test func restoresSecondsAndRoutesProgressOnlyToRadio() async throws {
        let candidate = makeCandidate("one")
        let store = FakeRadioSessionStore(snapshot: makeSession(candidate.key, position: 42))
        let repository = RecordingRadioRepository(candidates: [candidate])
        let radio = RadioSessionCoordinator(store: store, repository: repository, connectivityStatus: { .online })
        _ = await radio.restore(autoplayEnabled: false)
        let brief = FakeBriefQueueCoordinator(currentPosition: 17)
        let transport = SpyAudioTransport()
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true).container.viewContext
        )

        await player.playRadio()
        let id = try #require(transport.lastPlaybackID)
        player.audioItemReady(id: TransportPlaybackID(), duration: 999)
        #expect(transport.seeks.isEmpty)
        #expect(player.duration == 300)
        player.audioItemReady(id: id, duration: 300)
        #expect(transport.seeks == [42])

        player.audioProgressUpdated(id: id, progress: 0.2, currentTime: 60, duration: 300)
        #expect(radio.entries.first?.positionSeconds == 60)
        #expect(brief.currentPosition == 17)
        #expect(player.activeMode == .radio)
    }

    @Test func radioPausePersistsBeforeTransportMutation() async throws {
        var events: [String] = []
        let candidate = makeCandidate("one")
        let store = FakeRadioSessionStore(snapshot: makeSession(candidate.key), onSaveNow: { events.append("save") })
        let radio = RadioSessionCoordinator(store: store, repository: RecordingRadioRepository(candidates: [candidate]), connectivityStatus: { .online })
        _ = await radio.restore(autoplayEnabled: false)
        let transport = SpyAudioTransport { events.append($0) }
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: FakeBriefQueueCoordinator(),
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true).container.viewContext
        )
        await player.playRadio()
        events.removeAll()

        player.pause()

        #expect(events.prefix(2).elementsEqual(["save", "pause"]))
    }

    @Test func staleAndDuplicateTerminalCallbacksCannotCompleteReplacement() async throws {
        let first = makeCandidate("one")
        let second = makeCandidate("two")
        let repository = RecordingRadioRepository(candidates: [first, second])
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: makeSession([first.key, second.key], current: first.key)),
            repository: repository,
            connectivityStatus: { .online }
        )
        _ = await radio.restore(autoplayEnabled: false)
        let transport = SpyAudioTransport()
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: FakeBriefQueueCoordinator(),
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true).container.viewContext
        )
        await player.playRadio()
        let oldID = try #require(transport.lastPlaybackID)
        await player.playNext()
        let newID = try #require(transport.lastPlaybackID)
        #expect(oldID != newID)

        player.audioDidFinishPlaying(id: oldID, successfully: true)
        player.audioDidFinishPlaying(id: newID, successfully: true)
        player.audioDidFinishPlaying(id: newID, successfully: true)

        #expect(repository.completed == [second.key])
    }

    @Test func duplicateStreamFailureConsumesOnlyOneCoordinatorAttempt() async throws {
        let candidate = makeCandidate("one")
        let scheduler = TestRadioRetryScheduler()
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: makeSession(candidate.key)),
            repository: RecordingRadioRepository(candidates: [candidate]),
            connectivityStatus: { .online },
            retryScheduler: scheduler
        )
        _ = await radio.restore(autoplayEnabled: false)
        let transport = SpyAudioTransport()
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: FakeBriefQueueCoordinator(),
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true).container.viewContext
        )
        await player.playRadio()
        let id = try #require(transport.lastPlaybackID)

        player.audioDidFinishPlaying(id: id, successfully: false)
        player.audioDidFinishPlaying(id: id, successfully: false)

        #expect(radio.entries.first?.playbackFailureCount == 1)
        #expect(scheduler.scheduledDelays.count == 1)
    }

    @Test func thrownInitialLoadRetriesWithFreshIdentityThenExhaustsBudget() async throws {
        let candidate = makeCandidate("throwing")
        let scheduler = TestRadioRetryScheduler()
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: makeSession(candidate.key)),
            repository: RecordingRadioRepository(candidates: [candidate]),
            connectivityStatus: { .online },
            retryScheduler: scheduler
        )
        _ = await radio.restore(autoplayEnabled: false)
        let transport = SpyAudioTransport(playFailuresRemaining: 2)
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: FakeBriefQueueCoordinator(),
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true).container.viewContext
        )

        await player.playRadio()
        #expect(transport.loads.count == 1)
        #expect(scheduler.scheduledDelays.count == 1)

        scheduler.fire()
        for _ in 0..<20 where transport.loads.count < 2 {
            await Task.yield()
        }

        let firstLoad = try #require(transport.loads.first)
        let secondLoad = try #require(transport.loads.dropFirst().first)
        #expect(firstLoad.0 != secondLoad.0)
        #expect(radio.entries.first?.playbackFailureCount == 2)
        guard case .failed(.playback(let message)) = radio.state else {
            Issue.record("Expected an exhausted playback failure, got \(radio.state)")
            return
        }
        #expect(message == SpyTransportError.loadFailed.localizedDescription)
    }

    @Test func completionCommitsOnceButCannotReplaceNewBriefPlayback() async throws {
        let first = makeCandidate("one")
        let second = makeCandidate("two")
        let repository = RecordingRadioRepository(candidates: [first, second])
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: makeSession([first.key, second.key], current: first.key)),
            repository: repository,
            connectivityStatus: { .online }
        )
        _ = await radio.restore(autoplayEnabled: false)
        let brief = FakeBriefQueueCoordinator()
        brief.queue = [makeBriefItem()]
        brief.currentIndex = 0
        let transport = SpyAudioTransport()
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true).container.viewContext
        )
        await player.playRadio()
        let radioID = try #require(transport.lastPlaybackID)

        player.audioProgressUpdated(id: radioID, progress: 0.25, currentTime: 75, duration: 300)
        player.audioDidFinishPlaying(id: radioID, successfully: true)
        player.audioDidFinishPlaying(id: radioID, successfully: true)
        await player.play(at: 0)
        await Task.yield()

        #expect(repository.completed == [first.key])
        #expect(radio.currentKey == second.key)
        #expect(radio.entries.map(\.key) == [second.key])
        #expect(radio.entries.first?.positionSeconds == 0)
        #expect(player.activeMode == .brief)
        #expect(transport.loads.count == 2)
        #expect(transport.loads.last?.1.absoluteString == "https://example.com/brief.mp3")
    }

    @Test func failureCommitsOnceButCannotMutateNewBriefPlayback() async throws {
        let candidate = makeCandidate("one")
        let scheduler = TestRadioRetryScheduler()
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: makeSession(candidate.key)),
            repository: RecordingRadioRepository(candidates: [candidate]),
            connectivityStatus: { .online },
            retryScheduler: scheduler
        )
        _ = await radio.restore(autoplayEnabled: false)
        let brief = FakeBriefQueueCoordinator()
        brief.queue = [makeBriefItem()]
        brief.currentIndex = 0
        let events = EventRecorder()
        let transport = SpyAudioTransport { events.values.append($0) }
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true).container.viewContext
        )
        await player.playRadio()
        let radioID = try #require(transport.lastPlaybackID)

        player.audioDidFinishPlaying(id: radioID, successfully: false)
        player.audioDidFinishPlaying(id: radioID, successfully: false)
        await player.play(at: 0)
        events.values.removeAll()
        scheduler.fire()
        await Task.yield()

        #expect(radio.entries.first?.playbackFailureCount == 1)
        #expect(scheduler.scheduledDelays == [0.5])
        #expect(player.activeMode == .brief)
        #expect(transport.loads.count == 2)
        #expect(transport.loads.last?.1.absoluteString == "https://example.com/brief.mp3")
        #expect(events.values.isEmpty)
    }

    @Test func staleScheduledInterruptionAndRouteCannotPauseNewBriefPlayback() async throws {
        let candidate = makeCandidate("one")
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: makeSession(candidate.key)),
            repository: RecordingRadioRepository(candidates: [candidate]),
            connectivityStatus: { .online }
        )
        _ = await radio.restore(autoplayEnabled: false)
        let brief = FakeBriefQueueCoordinator()
        brief.queue = [makeBriefItem()]
        brief.currentIndex = 0
        let events = EventRecorder()
        let transport = SpyAudioTransport { events.values.append($0) }
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true).container.viewContext
        )
        await player.playRadio()
        let radioID = try #require(transport.lastPlaybackID)

        events.values.removeAll()
        player.audioInterruptionBegan(id: radioID)
        player.audioRouteWasRemoved(id: radioID)
        await player.play(at: 0)
        await Task.yield()

        #expect(player.activeMode == .brief)
        #expect(!events.values.contains("pause"))
    }

    @Test func seekNextInterruptionAndRoutePersistBeforeTransport() async throws {
        let first = makeCandidate("one")
        let second = makeCandidate("two")
        let events = EventRecorder()
        let store = FakeRadioSessionStore(
            snapshot: makeSession([first.key, second.key], current: first.key),
            onSaveNow: { events.values.append("save") }
        )
        let radio = RadioSessionCoordinator(
            store: store,
            repository: RecordingRadioRepository(candidates: [first, second]),
            connectivityStatus: { .online }
        )
        _ = await radio.restore(autoplayEnabled: false)
        let transport = SpyAudioTransport { events.values.append($0) }
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: FakeBriefQueueCoordinator(),
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true).container.viewContext
        )
        await player.playRadio()

        events.values.removeAll()
        player.seek(to: 12)
        #expect(events.values.prefix(2).elementsEqual(["save", "seek"]))

        events.values.removeAll()
        await player.playNext()
        #expect(try #require(events.values.firstIndex(of: "save")) < #require(events.values.firstIndex(of: "stop")))
        #expect(try #require(events.values.firstIndex(of: "stop")) < #require(events.values.firstIndex(of: "play")))

        events.values.removeAll()
        player.audioInterruptionBegan(id: transport.lastPlaybackID)
        await Task.yield()
        #expect(events.values.prefix(2).elementsEqual(["save", "pause"]))

        await player.playRadio()
        events.values.removeAll()
        player.audioRouteWasRemoved(id: transport.lastPlaybackID)
        await Task.yield()
        #expect(events.values.prefix(2).elementsEqual(["save", "pause"]))
    }

    @Test func switchingFromRadioToBriefSavesRadioBeforeStopAndPreservesBothQueues() async throws {
        let candidate = makeCandidate("one")
        let events = EventRecorder()
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(snapshot: makeSession(candidate.key), onSaveNow: { events.values.append("save") }),
            repository: RecordingRadioRepository(candidates: [candidate]),
            connectivityStatus: { .online }
        )
        _ = await radio.restore(autoplayEnabled: false)
        let brief = FakeBriefQueueCoordinator()
        brief.queue = [makeBriefItem()]
        brief.currentIndex = 0
        let transport = SpyAudioTransport { events.values.append($0) }
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true).container.viewContext
        )
        await player.playRadio()
        events.values.removeAll()

        await player.play(at: 0)

        #expect(try #require(events.values.firstIndex(of: "save")) < #require(events.values.firstIndex(of: "stop")))
        #expect(player.activeMode == .brief)
        #expect(brief.queue.count == 1)
        #expect(radio.entries.count == 1)
    }

    private func makeCandidate(_ id: String) -> RadioEpisodeCandidate {
        .init(
            key: .init(feedID: id, episodeID: id),
            originalPlaybackURL: URL(string: "https://example.com/\(id).mp3")!,
            canonicalEnclosureURL: "https://example.com/\(id).mp3",
            title: id,
            sourceName: "Source",
            publicationDate: .now,
            durationSeconds: 300,
            normalizedCoreDataProgress: 0,
            isCompleted: false,
            sourcePriority: 0,
            sourceFrequency: .hourly
        )
    }

    private func makeSession(_ key: RadioEpisodeKey, position: TimeInterval = 0) -> PersistedRadioSession {
        makeSession([key], current: key, position: position)
    }

    private func makeSession(_ keys: [RadioEpisodeKey], current: RadioEpisodeKey, position: TimeInterval = 0) -> PersistedRadioSession {
        .init(
            schemaVersion: 1,
            entries: keys.map { .init(key: $0, positionSeconds: $0 == current ? position : 0, disposition: .pending, playbackFailureCount: 0, lastPlaybackError: nil) },
            currentKey: current,
            savedAt: .now
        )
    }

    private func makeBriefItem() -> QueueItem {
        .init(
            id: UUID(), type: .liveNews, title: "Brief episode", source: "Brief",
            addedAt: .now, expiresAt: nil, articleID: nil, summaryState: .ready,
            cachedAudioURL: nil, episodeID: "brief", streamURL: URL(string: "https://example.com/brief.mp3"),
            lastPosition: 0, isListened: false
        )
    }
}

@MainActor
private final class EventRecorder { var values: [String] = [] }

@MainActor
final class SpyAudioTransport: AudioPlaybackTransporting {
    weak var delegate: SwiftAudioExServiceDelegate?
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var activeRemotePlaybackIdentity: RemotePlaybackAssetIdentity?
    private(set) var lastPlaybackID: TransportPlaybackID?
    private(set) var seeks: [TimeInterval] = []
    private(set) var loads: [(TransportPlaybackID, URL)] = []
    private(set) var policies: [RemoteCommandAvailability] = []
    private var playFailuresRemaining: Int
    private var failingURLs: Set<URL>
    private let event: (String) -> Void

    init(
        playFailuresRemaining: Int = 0,
        failingURLs: Set<URL> = [],
        event: @escaping (String) -> Void = { _ in }
    ) {
        self.playFailuresRemaining = playFailuresRemaining
        self.failingURLs = failingURLs
        self.event = event
    }
    func play(id: TransportPlaybackID, url: URL, title: String?, artist: String?) async throws {
        lastPlaybackID = id
        activeRemotePlaybackIdentity = nil
        loads.append((id, url))
        event("play")
        if failingURLs.contains(url) {
            throw SpyTransportError.loadFailed
        }
        if playFailuresRemaining > 0 {
            playFailuresRemaining -= 1
            throw SpyTransportError.loadFailed
        }
    }
    func pause() { event("pause") }
    func resume() { event("resume") }
    func stop() { event("stop") }
    func seek(to time: TimeInterval) { currentTime = time; seeks.append(time); event("seek") }
    func setRate(_ rate: Float) { event("rate") }
    func applyRemoteCommandAvailability(_ availability: RemoteCommandAvailability) { policies.append(availability) }
}

private enum SpyTransportError: Error { case loadFailed }

@MainActor
final class FakeBriefQueueCoordinator: BriefQueueCoordinating {
    var queue: [QueueItem] = [] { didSet { queueSubject.send(queue) } }
    var currentIndex = -1 { didSet { indexSubject.send(currentIndex) } }
    var currentPosition: TimeInterval
    var currentItem: QueueItem? {
        guard currentIndex >= 0, currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }
    var itemCount: Int { queue.count }
    private let queueSubject = CurrentValueSubject<[QueueItem], Never>([])
    private let indexSubject = CurrentValueSubject<Int, Never>(-1)
    var queuePublisher: AnyPublisher<[QueueItem], Never> { queueSubject.eraseToAnyPublisher() }
    var currentIndexPublisher: AnyPublisher<Int, Never> { indexSubject.eraseToAnyPublisher() }
    private(set) var saveCount = 0

    init(currentPosition: TimeInterval = 0) { self.currentPosition = currentPosition }
    func addArticle(_ article: Article, playNow: Bool, playNext: Bool) {}
    func addEpisode(_ episode: RSSEpisode, playNow: Bool, playNext: Bool) {}
    func removeItem(at index: Int) {}
    func clearQueue() { queue = [] }
    func setCurrentIndex(_ index: Int) { currentIndex = index }
    func updateCurrentPosition(_ position: TimeInterval) { currentPosition = position }
    func markCurrentAsListened() {}
    func updateCachedAudioURL(for itemID: UUID, url: URL?) {}
    func markItemFailed(for itemID: UUID, error: String) {}
    func autoRemoveIfListened(at index: Int) -> UUID? { nil }
    func saveStateNow() { saveCount += 1 }
}

@MainActor
final class RecordingRadioRepository: RadioEpisodeRepository {
    var values: [RadioEpisodeCandidate]
    private(set) var completed: [RadioEpisodeKey] = []
    private(set) var progress: [(RadioEpisodeKey, TimeInterval)] = []
    init(candidates: [RadioEpisodeCandidate]) { values = candidates }
    func candidates() throws -> [RadioEpisodeCandidate] { values }
    func candidate(for key: RadioEpisodeKey) throws -> RadioEpisodeCandidate? { values.first { $0.key == key } }
    func saveProgress(key: RadioEpisodeKey, seconds: TimeInterval, duration: TimeInterval?) throws { progress.append((key, seconds)) }
    func markCompleted(key: RadioEpisodeKey, at date: Date) throws { completed.append(key) }
    func restartForReplay(key: RadioEpisodeKey) throws -> RadioEpisodeCandidate? {
        values.first { $0.key == key }
    }
}
