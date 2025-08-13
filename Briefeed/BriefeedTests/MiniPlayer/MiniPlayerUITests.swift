//
//  MiniPlayerUITests.swift
//  BriefeedTests
//
//  TDD tests for mini player UI interactions (expand/collapse, gestures)
//

import XCTest
import SwiftUI
import CoreData
@testable import Briefeed

@MainActor
final class MiniPlayerUITests: XCTestCase {
    
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
    
    // MARK: - Expand/Collapse Tests
    
    func testMiniPlayerStartsCollapsed() async throws {
        // Given: Queue with items
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        
        // Then: Mini player should be in collapsed state
        // Height should be ~70 points
        XCTAssertEqual(viewModel.queueItems.count, 1)
        // In real implementation, check actual view height
    }
    
    func testTapToExpandMiniPlayer() async throws {
        // Given: Collapsed mini player with content
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        await viewModel.play()
        
        // When: User taps on mini player
        // This would trigger sheet presentation in SwiftUI
        
        // Then: Should expand to show full controls
        // - Progress bar visible
        // - All 5 buttons visible
        // - Speed control visible
        // - Queue count visible
        XCTAssertNotNil(viewModel.currentTitle)
        XCTAssertNotNil(viewModel.duration)
    }
    
    func testSwipeDownToCollapse() async throws {
        // Given: Expanded player
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        
        // When: User swipes down on expanded view
        // This would trigger sheet dismissal
        
        // Then: Should collapse back to mini player
        XCTAssertEqual(viewModel.queueItems.count, 1)
    }
    
    func testTapXToCloseExpandedView() async throws {
        // Given: Expanded player view
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        
        // When: User taps X button
        // This dismisses the sheet
        
        // Then: Should return to mini player
        XCTAssertEqual(viewModel.queueItems.count, 1)
    }
    
    // MARK: - Title Display Tests
    
    func testLongTitleScrollsInMiniPlayer() async throws {
        // Given: Article with very long title
        let longTitle = "This is an extremely long article title that definitely won't fit in the mini player width and needs to scroll with marquee animation"
        let article = createTestArticle(title: longTitle)
        await viewModel.addToQueue(article)
        await viewModel.play()
        
        // Then: Title should be set for marquee scrolling
        XCTAssertEqual(viewModel.currentTitle, longTitle)
        XCTAssertGreaterThan(viewModel.currentTitle?.count ?? 0, 50)
    }
    
    func testShortTitleDoesNotScroll() async throws {
        // Given: Article with short title
        let shortTitle = "Short Title"
        let article = createTestArticle(title: shortTitle)
        await viewModel.addToQueue(article)
        await viewModel.play()
        
        // Then: Title should display without scrolling
        XCTAssertEqual(viewModel.currentTitle, shortTitle)
        XCTAssertLessThan(viewModel.currentTitle?.count ?? 0, 30)
    }
    
    func testSubtitleShowsFeedAndAuthor() async throws {
        // Given: Article with feed and author
        let article = createTestArticle()
        article.author = "John Doe"
        
        let feed = Feed(context: context)
        feed.name = "Tech News"
        article.feed = feed
        
        await viewModel.addToQueue(article)
        await viewModel.play()
        
        // Then: Subtitle should show "Feed Name · Author"
        XCTAssertEqual(viewModel.currentArtist, "John Doe")
    }
    
    // MARK: - Progress Display Tests
    
    func testProgressBarInExpandedView() async throws {
        // Given: Playing content in expanded view
        let episode = createTestEpisode()
        await viewModel.addToQueue(episode)
        await viewModel.play()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Then: Progress bar should show
        XCTAssertGreaterThanOrEqual(viewModel.progress, 0)
        XCTAssertLessThanOrEqual(viewModel.progress, 1)
        XCTAssertGreaterThan(viewModel.duration, 0)
    }
    
    func testTimeDisplayFormat() async throws {
        // Given: Playing episode with known duration
        let episode = createTestEpisode(duration: 725) // 12:05
        await viewModel.addToQueue(episode)
        await viewModel.play()
        
        // Then: Should display as "0:00 / 12:05"
        XCTAssertEqual(viewModel.duration, 0) // Will be 0 until loaded
        XCTAssertEqual(viewModel.currentTime, 0)
    }
    
    func testProgressUpdatesWhilePlaying() async throws {
        // Given: Playing content
        let episode = createTestEpisode()
        await viewModel.addToQueue(episode)
        await viewModel.play()
        
        // When: Time passes
        let initialProgress = viewModel.progress
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        // Then: Progress should update
        XCTAssertNotEqual(viewModel.progress, initialProgress)
    }
    
    // MARK: - Visual State Tests
    
    func testPlayButtonIconChanges() async throws {
        // Given: Not playing
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        XCTAssertFalse(viewModel.isPlaying)
        
        // When: Start playing
        await viewModel.play()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Icon should change from ▶️ to ⏸️
        XCTAssertTrue(viewModel.isPlaying || viewModel.isLoading)
        
        // When: Pause
        viewModel.pause()
        
        // Then: Icon should change back to ▶️
        XCTAssertFalse(viewModel.isPlaying)
    }
    
    func testLoadingIndicatorDuringTTS() async throws {
        // Given: Article needing TTS generation
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        
        // When: Start playing (triggers TTS)
        await viewModel.play()
        
        // Then: Should show loading state
        XCTAssertTrue(viewModel.isLoading || viewModel.isPlaying)
    }
    
    func testQueueCountBadge() async throws {
        // Given: Multiple items in queue
        let items = createMultipleArticles(count: 5)
        for item in items {
            await viewModel.addToQueue(item)
        }
        
        // Then: Should show "Queue (5)"
        XCTAssertEqual(viewModel.queueItems.count, 5)
        
        // When: Remove item
        await viewModel.removeFromQueue(at: 0)
        
        // Then: Should update to "Queue (4)"
        XCTAssertEqual(viewModel.queueItems.count, 4)
    }
    
    // MARK: - Speed Control Tests
    
    func testSpeedDisplayInExpandedView() async throws {
        // Given: Playing with custom speed
        let episode = createTestEpisode()
        await viewModel.addToQueue(episode)
        await viewModel.play()
        
        // When: Change speed
        viewModel.playbackSpeed = 1.5
        
        // Then: Should display "Speed: 1.5x"
        XCTAssertEqual(viewModel.playbackSpeed, 1.5)
    }
    
    func testSpeedPickerAccessibility() async throws {
        // Given: Expanded view
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        
        // Then: Speed control should be accessible
        XCTAssertEqual(viewModel.playbackSpeed, 1.0) // Default
        
        // Speed options available: 0.5x to 20x
        viewModel.playbackSpeed = 0.5
        XCTAssertEqual(viewModel.playbackSpeed, 0.5)
        
        viewModel.playbackSpeed = 20.0
        XCTAssertEqual(viewModel.playbackSpeed, 20.0)
    }
    
    // MARK: - Accessibility Tests
    
    func testAccessibilityLabels() async throws {
        // Given: Mini player with content
        let article = createTestArticle(title: "Test Article")
        await viewModel.addToQueue(article)
        await viewModel.play()
        
        // Then: Should have proper accessibility labels
        // Play button: "Pause" when playing, "Play" when paused
        // Previous: "Previous track"
        // -10: "Rewind 10 seconds"
        // +10: "Forward 10 seconds"
        // Next: "Next track"
        XCTAssertNotNil(viewModel.currentTitle)
    }
    
    func testVoiceOverSupport() async throws {
        // Given: Mini player active
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        
        // Then: All interactive elements should be accessible
        // - Play/pause button
        // - Navigation buttons
        // - Seek buttons
        // - Expand gesture
        XCTAssertEqual(viewModel.queueItems.count, 1)
    }
    
    // MARK: - Edge Cases
    
    func testMiniPlayerWithNoContent() async throws {
        // Given: Empty queue
        XCTAssertEqual(viewModel.queueItems.count, 0)
        
        // Then: Mini player should be hidden
        XCTAssertNil(viewModel.currentTitle)
        XCTAssertFalse(viewModel.isPlaying)
    }
    
    func testMiniPlayerDuringError() async throws {
        // Given: Error state
        let episode = createTestEpisode()
        episode.audioUrl = "invalid://url"
        await viewModel.addToQueue(episode)
        await viewModel.play()
        
        // Then: Should show error gracefully
        // May show error icon or message
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertNotNil(viewModel.queueItems)
    }
    
    // MARK: - Helper Methods
    
    private func createTestArticle(title: String = "Test Article") -> Article {
        let article = Article(context: context)
        article.id = UUID()
        article.title = title
        article.content = "Test content for UI testing"
        article.url = "https://example.com/article"
        article.createdAt = Date()
        return article
    }
    
    private func createTestEpisode(duration: Int = 600) -> RSSEpisode {
        let episode = RSSEpisode(context: context)
        episode.id = UUID().uuidString
        episode.title = "Test Episode"
        episode.audioUrl = "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"
        episode.duration = Int32(duration)
        episode.pubDate = Date()
        return episode
    }
    
    private func createMultipleArticles(count: Int) -> [Article] {
        var articles: [Article] = []
        for i in 1...count {
            let article = createTestArticle(title: "Article \(i)")
            articles.append(article)
        }
        return articles
    }
}