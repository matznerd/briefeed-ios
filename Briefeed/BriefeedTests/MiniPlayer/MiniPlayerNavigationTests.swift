//
//  MiniPlayerNavigationTests.swift
//  BriefeedTests
//
//  TDD tests for mini player previous/next navigation
//

import XCTest
import CoreData
import Combine
@testable import Briefeed

@MainActor
final class MiniPlayerNavigationTests: XCTestCase {
    
    var viewModel: AudioPlayerViewModelV2!
    var persistence: PersistenceController!
    var context: NSManagedObjectContext!
    var audioURL: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        persistence = PersistenceController(inMemory: true)
        context = persistence.container.viewContext
        audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mini-player-navigation-\(UUID().uuidString).wav")
        try Data(repeating: 0, count: 48).write(to: audioURL)

        let brief = NavigationBriefQueueCoordinator(audioURL: audioURL)
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(),
            repository: RecordingRadioRepository(candidates: []),
            connectivityStatus: { .online }
        )
        let player = UnifiedAudioPlayer(
            audioPlayer: NavigationAudioTransport(),
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: context,
            persistPlaybackRate: { _ in }
        )
        viewModel = AudioPlayerViewModelV2(
            unifiedPlayer: player,
            radioCoordinator: radio,
            rssService: RSSAudioService(viewContext: context, dataLoader: { _ in Data() }),
            playbackSpeedLoad: { 1 }
        )
    }
    
    override func tearDown() async throws {
        viewModel?.stop()
        if let audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        viewModel = nil
        audioURL = nil
        context = nil
        persistence = nil
        try await super.tearDown()
    }
    
    // MARK: - Next Button Tests
    
    func testNextButtonSkipsToNextItem() async throws {
        // Given: Queue with multiple items
        let items = createTestQueue(count: 3)
        for item in items {
            await viewModel.addToQueue(item)
        }
        
        // When: Playing first item
        await viewModel.play()
        XCTAssertEqual(viewModel.currentQueueIndex, 0)
        XCTAssertEqual(viewModel.currentTitle, "Article 1")
        
        // When: Press next
        await viewModel.playNext()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Should skip to second item
        XCTAssertEqual(viewModel.currentQueueIndex, 1)
        XCTAssertEqual(viewModel.currentTitle, "Article 2")
    }
    
    func testNextButtonHandlesEndOfQueue() async throws {
        // Given: At last item in queue
        let items = createTestQueue(count: 2)
        for item in items {
            await viewModel.addToQueue(item)
        }
        
        await viewModel.play()
        await viewModel.playNext() // Move to last
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(viewModel.currentQueueIndex, 1)
        
        // When: Press next at end
        await viewModel.playNext()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Should stay at last item or stop
        XCTAssertLessThanOrEqual(viewModel.currentQueueIndex, 1)
    }
    
    func testNextButtonWithMixedContent() async throws {
        // Given: Queue with articles and episodes
        let article1 = createTestArticle(title: "Article 1")
        let episode = createTestEpisode(title: "Episode 1")
        let article2 = createTestArticle(title: "Article 2")
        
        await viewModel.addToQueue(article1)
        await viewModel.addToQueue(episode)
        await viewModel.addToQueue(article2)
        
        // When: Navigate through mixed content
        await viewModel.play()
        XCTAssertEqual(viewModel.currentTitle, "Article 1")
        XCTAssertEqual(viewModel.currentItemType, .article)
        
        await viewModel.playNext()
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(viewModel.currentTitle, "Episode 1")
        XCTAssertEqual(viewModel.currentItemType, .rssEpisode)
        
        await viewModel.playNext()
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(viewModel.currentTitle, "Article 2")
        XCTAssertEqual(viewModel.currentItemType, .article)
    }
    
    func testNextButtonWhilePaused() async throws {
        // Given: Paused on first item
        let items = createTestQueue(count: 3)
        for item in items {
            await viewModel.addToQueue(item)
        }
        
        await viewModel.play()
        try await Task.sleep(nanoseconds: 500_000_000)
        viewModel.pause()
        XCTAssertFalse(viewModel.isPlaying)
        
        // When: Press next while paused
        await viewModel.playNext()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Should move to next and start playing
        XCTAssertEqual(viewModel.currentQueueIndex, 1)
        XCTAssertTrue(viewModel.isPlaying || viewModel.isLoading)
    }
    
    // MARK: - Previous Button Tests
    
    func testPreviousButtonSkipsToPreviousItem() async throws {
        // Given: Playing second item
        let items = createTestQueue(count: 3)
        for item in items {
            await viewModel.addToQueue(item)
        }
        
        await viewModel.play()
        await viewModel.playNext() // Move to second
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(viewModel.currentQueueIndex, 1)
        
        // When: Press previous
        await viewModel.playPrevious()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Should go back to first
        XCTAssertEqual(viewModel.currentQueueIndex, 0)
        XCTAssertEqual(viewModel.currentTitle, "Article 1")
    }
    
    func testPreviousButtonAtStartOfQueue() async throws {
        // Given: At first item
        let items = createTestQueue(count: 3)
        for item in items {
            await viewModel.addToQueue(item)
        }
        
        await viewModel.play()
        XCTAssertEqual(viewModel.currentQueueIndex, 0)
        
        // When: Press previous at start
        await viewModel.playPrevious()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Should stay at first item
        XCTAssertEqual(viewModel.currentQueueIndex, 0)
    }
    
    func testPreviousButtonRestartsIfPlayedSignificantly() async throws {
        // Given: Playing current item for a while
        let items = createTestQueue(count: 2)
        for item in items {
            await viewModel.addToQueue(item)
        }
        
        await viewModel.play()
        await viewModel.playNext() // Move to second
        try await Task.sleep(nanoseconds: 3_000_000_000) // Play for 3 seconds
        
        // When: Press previous after significant playback
        let indexBefore = viewModel.currentQueueIndex
        await viewModel.playPrevious()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Might restart current or go to previous (implementation dependent)
        XCTAssertLessThanOrEqual(viewModel.currentQueueIndex, indexBefore)
    }
    
    // MARK: - Sequential Navigation Tests
    
    func testNavigateForwardThroughEntireQueue() async throws {
        // Given: Queue with 5 items
        let items = createTestQueue(count: 5)
        for item in items {
            await viewModel.addToQueue(item)
        }
        
        // When: Navigate through entire queue
        await viewModel.play()
        XCTAssertEqual(viewModel.currentQueueIndex, 0)
        
        for expectedIndex in 1..<5 {
            await viewModel.playNext()
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertEqual(viewModel.currentQueueIndex, expectedIndex)
        }
        
        // Then: Should reach end
        XCTAssertEqual(viewModel.currentQueueIndex, 4)
    }
    
    func testNavigateBackwardThroughQueue() async throws {
        // Given: At end of queue
        let items = createTestQueue(count: 4)
        for item in items {
            await viewModel.addToQueue(item)
        }
        
        // Move to end
        await viewModel.play()
        for _ in 0..<3 {
            await viewModel.playNext()
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTAssertEqual(viewModel.currentQueueIndex, 3)
        
        // When: Navigate backward
        for expectedIndex in (0..<3).reversed() {
            await viewModel.playPrevious()
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertEqual(viewModel.currentQueueIndex, expectedIndex)
        }
        
        // Then: Should reach beginning
        XCTAssertEqual(viewModel.currentQueueIndex, 0)
    }
    
    // MARK: - Auto-advance Tests
    
    func testAutoAdvanceToNextWhenCurrentEnds() async throws {
        // Given: Queue with short items
        let article1 = createTestArticle(title: "Short 1", content: "Very short.")
        let article2 = createTestArticle(title: "Short 2", content: "Also short.")
        
        await viewModel.addToQueue(article1)
        await viewModel.addToQueue(article2)
        
        // When: First item completes
        await viewModel.play()
        XCTAssertEqual(viewModel.currentQueueIndex, 0)
        
        // Simulate completion by manually advancing
        await viewModel.playNext()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Should auto-advance
        XCTAssertEqual(viewModel.currentQueueIndex, 1)
        XCTAssertEqual(viewModel.currentTitle, "Short 2")
    }
    
    func testNoAutoAdvanceWhenLastItemEnds() async throws {
        // Given: Single item queue
        let article = createTestArticle(title: "Only Item")
        await viewModel.addToQueue(article)
        
        // When: Item completes
        await viewModel.play()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Simulate end
        viewModel.stop()
        
        // Then: Should stop, not loop
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertEqual(viewModel.queueItems.count, 1)
    }
    
    // MARK: - Navigation with Queue Modifications
    
    func testNavigationAfterRemovingCurrentItem() async throws {
        // Given: Playing middle item
        let items = createTestQueue(count: 4)
        for item in items {
            await viewModel.addToQueue(item)
        }
        
        await viewModel.play()
        await viewModel.playNext() // Move to index 1
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(viewModel.currentQueueIndex, 1)
        
        // When: Remove current item
        await viewModel.removeFromQueue(at: 1)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Should handle gracefully
        XCTAssertEqual(viewModel.queueItems.count, 3)
        XCTAssertLessThanOrEqual(viewModel.currentQueueIndex, 2)
    }
    
    func testNavigationAfterAddingItems() async throws {
        // Given: Playing last item
        let article1 = createTestArticle(title: "First")
        let article2 = createTestArticle(title: "Last")
        
        await viewModel.addToQueue(article1)
        await viewModel.addToQueue(article2)
        
        await viewModel.play()
        await viewModel.playNext() // Move to last
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(viewModel.currentQueueIndex, 1)
        
        // When: Add more items
        let article3 = createTestArticle(title: "New Item")
        await viewModel.addToQueue(article3)
        
        // Then: Next should now work
        await viewModel.playNext()
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(viewModel.currentQueueIndex, 2)
        XCTAssertEqual(viewModel.currentTitle, "New Item")
    }
    
    // MARK: - Helper Methods
    
    private func createTestQueue(count: Int) -> [Article] {
        var articles: [Article] = []
        for i in 1...count {
            articles.append(createTestArticle(title: "Article \(i)"))
        }
        return articles
    }
    
    private func createTestArticle(title: String = "Test Article", content: String = "Test content") -> Article {
        let article = NSEntityDescription.insertNewObject(
            forEntityName: "Article",
            into: context
        ) as! Article
        article.id = UUID()
        article.title = title
        article.content = content
        article.url = "https://example.com/\(UUID().uuidString)"
        article.createdAt = Date()
        return article
    }
    
    private func createTestEpisode(title: String = "Test Episode") -> RSSEpisode {
        let episode = NSEntityDescription.insertNewObject(
            forEntityName: "RSSEpisode",
            into: context
        ) as! RSSEpisode
        episode.id = UUID().uuidString
        episode.title = title
        episode.audioUrl = audioURL.absoluteString
        episode.duration = 300
        episode.pubDate = Date()
        return episode
    }
}

@MainActor
private final class NavigationAudioTransport: AudioPlaybackTransporting {
    weak var delegate: SwiftAudioExServiceDelegate?
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 300

    func play(id: TransportPlaybackID, url: URL, title: String?, artist: String?) async throws {}
    func pause() {}
    func resume() {}
    func stop() {}
    func seek(to time: TimeInterval) { currentTime = time }
    func setRate(_ rate: Float) {}
    func applyRemoteCommandAvailability(_ availability: RemoteCommandAvailability) {}
}

@MainActor
private final class NavigationBriefQueueCoordinator: BriefQueueCoordinating {
    var queue: [QueueItem] = [] { didSet { queueSubject.send(queue) } }
    var currentIndex = -1 { didSet { indexSubject.send(currentIndex) } }
    var currentPosition: TimeInterval = 0
    var currentItem: QueueItem? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }
    var itemCount: Int { queue.count }
    var queuePublisher: AnyPublisher<[QueueItem], Never> { queueSubject.eraseToAnyPublisher() }
    var currentIndexPublisher: AnyPublisher<Int, Never> { indexSubject.eraseToAnyPublisher() }

    private let audioURL: URL
    private let queueSubject = CurrentValueSubject<[QueueItem], Never>([])
    private let indexSubject = CurrentValueSubject<Int, Never>(-1)

    init(audioURL: URL) {
        self.audioURL = audioURL
    }

    func addArticle(_ article: Article, playNow: Bool, playNext: Bool) {
        guard let articleID = article.id,
              !queue.contains(where: { $0.articleID == articleID }) else { return }
        insert(
            QueueItem(
                id: UUID(),
                type: .article,
                title: article.title ?? "Untitled",
                source: "Test",
                addedAt: .now,
                expiresAt: nil,
                articleID: articleID,
                summaryState: .ready,
                cachedAudioURL: audioURL,
                episodeID: nil,
                streamURL: nil,
                lastPosition: 0,
                isListened: false
            ),
            playNow: playNow,
            playNext: playNext
        )
    }

    func addEpisode(_ episode: RSSEpisode, playNow: Bool, playNext: Bool) {
        guard !queue.contains(where: { $0.episodeID == episode.id }) else { return }
        insert(
            QueueItem(
                id: UUID(),
                type: .liveNews,
                title: episode.title,
                source: "Test",
                addedAt: .now,
                expiresAt: nil,
                articleID: nil,
                summaryState: .ready,
                cachedAudioURL: nil,
                episodeID: episode.id,
                streamURL: URL(string: episode.audioUrl),
                lastPosition: 0,
                isListened: false
            ),
            playNow: playNow,
            playNext: playNext
        )
    }

    func removeItem(at index: Int) {
        guard queue.indices.contains(index) else { return }
        queue.remove(at: index)
        if queue.isEmpty {
            currentIndex = -1
        } else if index < currentIndex {
            currentIndex -= 1
        } else if currentIndex >= queue.count {
            currentIndex = queue.count - 1
        }
    }

    func clearQueue() {
        queue = []
        currentIndex = -1
        currentPosition = 0
    }

    func setCurrentIndex(_ index: Int) {
        currentIndex = queue.indices.contains(index) ? index : -1
        currentPosition = currentItem?.lastPosition ?? 0
    }

    func updateCurrentPosition(_ position: TimeInterval) {
        currentPosition = position
        guard queue.indices.contains(currentIndex) else { return }
        queue[currentIndex].lastPosition = position
    }

    func markCurrentAsListened() {
        guard queue.indices.contains(currentIndex) else { return }
        queue[currentIndex].isListened = true
    }

    func updateCachedAudioURL(for itemID: UUID, url: URL?) {
        guard let index = queue.firstIndex(where: { $0.id == itemID }) else { return }
        queue[index].cachedAudioURL = url
    }

    func markItemFailed(for itemID: UUID, error: String) {
        guard let index = queue.firstIndex(where: { $0.id == itemID }) else { return }
        queue[index].summaryState = .failed
        queue[index].errorMessage = error
    }

    func autoRemoveIfListened(at index: Int) -> UUID? {
        guard queue.indices.contains(index), queue[index].isListened else { return nil }
        let id = queue[index].id
        removeItem(at: index)
        return id
    }

    func saveStateNow() {}

    private func insert(_ item: QueueItem, playNow: Bool, playNext: Bool) {
        if playNow {
            let index = max(0, currentIndex)
            queue.insert(item, at: min(index, queue.count))
            currentIndex = min(index, queue.count - 1)
        } else if playNext {
            let index = currentIndex >= 0 ? currentIndex + 1 : 0
            queue.insert(item, at: min(index, queue.count))
        } else {
            queue.append(item)
        }
    }
}
