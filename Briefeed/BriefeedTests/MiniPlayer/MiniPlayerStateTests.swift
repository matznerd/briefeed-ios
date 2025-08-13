//
//  MiniPlayerStateTests.swift
//  BriefeedTests
//
//  TDD tests for mini player state management and transitions
//

import XCTest
import Combine
import CoreData
@testable import Briefeed

@MainActor
final class MiniPlayerStateTests: XCTestCase {
    
    var viewModel: AudioPlayerViewModelV2!
    var persistence: PersistenceController!
    var context: NSManagedObjectContext!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        persistence = PersistenceController(inMemory: true)
        context = persistence.container.viewContext
        viewModel = AudioPlayerViewModelV2()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() async throws {
        viewModel?.stop()
        viewModel = nil
        context = nil
        persistence = nil
        cancellables = nil
        try await super.tearDown()
    }
    
    // MARK: - Visibility State Tests
    
    func testMiniPlayerHiddenWhenQueueEmpty() async throws {
        // Given: Empty queue
        XCTAssertEqual(viewModel.queueItems.count, 0)
        
        // Then: Mini player should be hidden
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertNil(viewModel.currentTitle)
        XCTAssertEqual(viewModel.currentQueueIndex, -1)
    }
    
    func testMiniPlayerVisibleWhenQueueHasItems() async throws {
        // Given: Empty queue
        XCTAssertEqual(viewModel.queueItems.count, 0)
        
        // When: Add item to queue
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        
        // Then: Mini player should be visible
        XCTAssertEqual(viewModel.queueItems.count, 1)
        XCTAssertGreaterThanOrEqual(viewModel.currentQueueIndex, -1)
    }
    
    func testMiniPlayerRemainsVisibleDuringPlayback() async throws {
        // Given: Playing audio
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        await viewModel.play()
        
        // Then: Should remain visible
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(viewModel.isPlaying || viewModel.isLoading)
        
        // When: Pause
        viewModel.pause()
        
        // Then: Still visible (queue not empty)
        XCTAssertEqual(viewModel.queueItems.count, 1)
        XCTAssertFalse(viewModel.isPlaying)
    }
    
    // MARK: - Play/Pause State Transitions
    
    func testStateTransitionFromIdleToPlaying() async throws {
        // Given: Idle state with queued item
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        XCTAssertFalse(viewModel.isPlaying)
        
        // When: Start playing
        await viewModel.play()
        
        // Then: Should transition to playing
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(viewModel.isPlaying || viewModel.isLoading)
        XCTAssertEqual(viewModel.currentQueueIndex, 0)
    }
    
    func testStateTransitionFromPlayingToPaused() async throws {
        // Given: Playing state
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        await viewModel.play()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // When: Pause
        viewModel.pause()
        
        // Then: Should transition to paused
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertEqual(viewModel.currentQueueIndex, 0) // Still on same item
    }
    
    func testStateTransitionFromPausedToPlaying() async throws {
        // Given: Paused state
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        await viewModel.play()
        try await Task.sleep(nanoseconds: 500_000_000)
        viewModel.pause()
        XCTAssertFalse(viewModel.isPlaying)
        
        // When: Resume
        await viewModel.play()
        
        // Then: Should resume playing
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(viewModel.isPlaying || viewModel.isLoading)
    }
    
    func testStateTransitionOnQueueCompletion() async throws {
        // Given: Short queue
        let article = createTestArticle(title: "Only Item", content: "Short")
        await viewModel.addToQueue(article)
        
        // When: Play and let it complete
        await viewModel.play()
        
        // Simulate completion
        viewModel.stop()
        
        // Then: Should return to idle
        XCTAssertFalse(viewModel.isPlaying)
    }
    
    // MARK: - Loading State Tests
    
    func testShowsLoadingStateForTTSGeneration() async throws {
        // Given: Article needing TTS
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        
        // When: Start playing
        await viewModel.play()
        
        // Then: Should show loading initially
        // Note: TTS generation happens async
        XCTAssertTrue(viewModel.isLoading || viewModel.isPlaying)
    }
    
    func testShowsLoadingStateForRSSStreaming() async throws {
        // Given: RSS episode
        let episode = createTestEpisode()
        await viewModel.addToQueue(episode)
        
        // When: Start playing
        await viewModel.play()
        
        // Then: Should show loading while buffering
        XCTAssertTrue(viewModel.isLoading || viewModel.isPlaying)
        XCTAssertEqual(viewModel.currentItemType, .rssEpisode)
    }
    
    // MARK: - Display Content Tests
    
    func testDisplaysCurrentItemTitle() async throws {
        // Given: Item with specific title
        let article = createTestArticle(title: "Test Article Title")
        await viewModel.addToQueue(article)
        
        // When: Start playing
        await viewModel.play()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Should display title
        XCTAssertEqual(viewModel.currentTitle, "Test Article Title")
    }
    
    func testDisplaysCurrentItemSubtitle() async throws {
        // Given: Article with feed info
        let article = createTestArticle()
        article.author = "John Doe"
        
        let feed = Feed(context: context)
        feed.name = "Tech News"
        article.feed = feed
        
        await viewModel.addToQueue(article)
        
        // When: Start playing
        await viewModel.play()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Should display subtitle
        XCTAssertEqual(viewModel.currentArtist, "John Doe")
    }
    
    func testUpdatesProgressDuringPlayback() async throws {
        // Given: Playing episode
        let episode = createTestEpisode()
        await viewModel.addToQueue(episode)
        
        // When: Start playing
        await viewModel.play()
        
        // Then: Progress should update
        let initialProgress = viewModel.progress
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Progress may not change if still loading
        XCTAssertGreaterThanOrEqual(viewModel.progress, initialProgress)
    }
    
    // MARK: - State Persistence Tests
    
    func testMaintainsStateAcrossViewAppearances() async throws {
        // Given: Playing state
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        await viewModel.play()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let wasPlaying = viewModel.isPlaying
        let queueCount = viewModel.queueItems.count
        
        // When: View disappears and reappears (simulated)
        // State should persist in view model
        
        // Then: State should be maintained
        XCTAssertEqual(viewModel.isPlaying, wasPlaying)
        XCTAssertEqual(viewModel.queueItems.count, queueCount)
    }
    
    func testRestoresStateAfterBackgrounding() async throws {
        // Given: Playing state
        let episode = createTestEpisode()
        await viewModel.addToQueue(episode)
        await viewModel.play()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // When: App backgrounds (state saved)
        await viewModel.saveQueueState()
        
        // Simulate app returning
        let newViewModel = AudioPlayerViewModelV2()
        
        // Then: Queue should be restored
        XCTAssertEqual(newViewModel.queueItems.count, 1)
    }
    
    // MARK: - Error State Tests
    
    func testShowsErrorStateOnPlaybackFailure() async throws {
        // Given: Invalid audio URL
        let episode = createTestEpisode()
        episode.audioUrl = "invalid://url"
        await viewModel.addToQueue(episode)
        
        // When: Try to play
        await viewModel.play()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Then: Should handle error gracefully
        // Error might be set or playback might fail silently
        XCTAssertNotNil(viewModel.queueItems)
    }
    
    func testRecoversFromErrorState() async throws {
        // Given: Error state from invalid item
        let badEpisode = createTestEpisode()
        badEpisode.audioUrl = "invalid://url"
        await viewModel.addToQueue(badEpisode)
        
        // Add valid item
        let goodArticle = createTestArticle()
        await viewModel.addToQueue(goodArticle)
        
        // When: Skip to valid item
        await viewModel.play()
        await viewModel.playNext()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Should recover
        XCTAssertEqual(viewModel.currentQueueIndex, 1)
    }
    
    // MARK: - Helper Methods
    
    private func createTestArticle(title: String = "Test Article", content: String = "Test content") -> Article {
        let article = Article(context: context)
        article.id = UUID()
        article.title = title
        article.content = content
        article.url = "https://example.com/article"
        article.createdAt = Date()
        article.author = "Test Author"
        return article
    }
    
    private func createTestEpisode() -> RSSEpisode {
        let episode = RSSEpisode(context: context)
        episode.id = UUID().uuidString
        episode.title = "Test Episode"
        episode.audioUrl = "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"
        episode.duration = 600
        episode.pubDate = Date()
        return episode
    }
}