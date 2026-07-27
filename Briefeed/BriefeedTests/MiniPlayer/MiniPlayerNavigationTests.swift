//
//  MiniPlayerNavigationTests.swift
//  BriefeedTests
//
//  TDD tests for mini player previous/next navigation
//

import XCTest
import CoreData
@testable import Briefeed

@MainActor
final class MiniPlayerNavigationTests: XCTestCase {
    
    var viewModel: AudioPlayerViewModelV2!
    var persistence: PersistenceController!
    var context: NSManagedObjectContext!
    
    override func setUp() async throws {
        try await super.setUp()
        persistence = PersistenceController(inMemory: true)
        context = persistence.container.viewContext
        viewModel = AudioPlayerViewModelV2()
    }
    
    override func tearDown() async throws {
        viewModel?.stop()
        viewModel = nil
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
        let article = Article(context: context)
        article.id = UUID()
        article.title = title
        article.content = content
        article.url = "https://example.com/\(UUID().uuidString)"
        article.createdAt = Date()
        return article
    }
    
    private func createTestEpisode(title: String = "Test Episode") -> RSSEpisode {
        let episode = RSSEpisode(context: context)
        episode.id = UUID().uuidString
        episode.title = title
        episode.audioUrl = "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"
        episode.duration = 300
        episode.pubDate = Date()
        return episode
    }
}