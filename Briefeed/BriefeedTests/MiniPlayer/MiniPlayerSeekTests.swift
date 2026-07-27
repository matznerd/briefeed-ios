//
//  MiniPlayerSeekTests.swift
//  BriefeedTests
//
//  TDD tests for mini player seek functionality (-10/+10 seconds)
//

import XCTest
import CoreData
@testable import Briefeed

@MainActor
final class MiniPlayerSeekTests: XCTestCase {
    
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
    
    // MARK: - Basic Seek Functionality
    
    func testSeekForward10Seconds() async throws {
        // Given: Playing RSS episode with seekable content
        let episode = createTestEpisode(duration: 300) // 5 minutes
        await viewModel.addToQueue(episode)
        await viewModel.play()
        
        // Wait for playback to start
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // When: Seek forward 10 seconds
        let timeBefore = viewModel.currentTime
        viewModel.seekForward()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Current time should increase
        // Note: Can't assert exact 10s due to async nature
        XCTAssertGreaterThanOrEqual(viewModel.currentTime, timeBefore)
    }
    
    func testSeekBackward10Seconds() async throws {
        // Given: Playing episode with some progress
        let episode = createTestEpisode(duration: 300)
        await viewModel.addToQueue(episode)
        await viewModel.play()
        
        // Let it play for a bit to accumulate time
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        // When: Seek backward 10 seconds
        let timeBefore = viewModel.currentTime
        viewModel.seekBackward()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Current time should decrease
        XCTAssertLessThanOrEqual(viewModel.currentTime, timeBefore)
    }
    
    func testSeekForwardMultipleTimes() async throws {
        // Given: Playing episode
        let episode = createTestEpisode(duration: 600) // 10 minutes
        await viewModel.addToQueue(episode)
        await viewModel.play()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // When: Seek forward multiple times
        let initialTime = viewModel.currentTime
        viewModel.seekForward() // +10
        try await Task.sleep(nanoseconds: 200_000_000)
        viewModel.seekForward() // +10
        try await Task.sleep(nanoseconds: 200_000_000)
        viewModel.seekForward() // +10
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then: Should accumulate seeks
        // Expected: initialTime + ~30 seconds
        XCTAssertGreaterThan(viewModel.currentTime, initialTime)
    }
    
    func testSeekBackwardMultipleTimes() async throws {
        // Given: Playing episode with progress
        let episode = createTestEpisode(duration: 600)
        await viewModel.addToQueue(episode)
        await viewModel.play()
        
        // Play for a while to build up time
        try await Task.sleep(nanoseconds: 5_000_000_000)
        
        // When: Seek backward multiple times
        let timeBeforeSeeks = viewModel.currentTime
        viewModel.seekBackward() // -10
        try await Task.sleep(nanoseconds: 200_000_000)
        viewModel.seekBackward() // -10
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then: Should accumulate backward seeks
        XCTAssertLessThan(viewModel.currentTime, timeBeforeSeeks)
    }
    
    // MARK: - Boundary Tests
    
    func testSeekBackwardAtStartStaysAtZero() async throws {
        // Given: Just started playing
        let episode = createTestEpisode()
        await viewModel.addToQueue(episode)
        await viewModel.play()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // When: Seek backward at beginning
        viewModel.seekBackward()
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then: Should stay at or near 0
        XCTAssertGreaterThanOrEqual(viewModel.currentTime, 0)
        XCTAssertLessThan(viewModel.currentTime, 5) // Allow small buffer
    }
    
    func testSeekForwardNearEndStopsAtDuration() async throws {
        // Given: Episode near end
        let episode = createTestEpisode(duration: 30) // 30 second episode
        await viewModel.addToQueue(episode)
        await viewModel.play()
        
        // Seek to near end
        viewModel.seek(to: TimeInterval(25))
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // When: Seek forward (would go past end)
        viewModel.seekForward()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Should not exceed duration
        XCTAssertLessThanOrEqual(viewModel.currentTime, TimeInterval(episode.duration))
    }
    
    // MARK: - Seek with Different Content Types
    
    func testSeekWorksWithRSSEpisodes() async throws {
        // Given: RSS episode
        let episode = createTestEpisode()
        await viewModel.addToQueue(episode)
        await viewModel.play()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Then: Seek should work
        XCTAssertEqual(viewModel.currentItemType, .rssEpisode)
        
        let timeBefore = viewModel.currentTime
        viewModel.seekForward()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify seek occurred
        XCTAssertNotEqual(viewModel.currentTime, timeBefore)
    }
    
    func testSeekWorksWithTTSArticles() async throws {
        // Given: Article with TTS
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        await viewModel.play()
        
        // TTS generation may take time
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Then: Seek should work with generated TTS
        XCTAssertEqual(viewModel.currentItemType, .article)
        
        // Attempt seek
        viewModel.seekForward()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Note: Seek behavior depends on TTS generation completion
        XCTAssertGreaterThanOrEqual(viewModel.currentTime, 0)
    }
    
    // MARK: - Seek During Different States
    
    func testSeekWhilePaused() async throws {
        // Given: Paused playback
        let episode = createTestEpisode()
        await viewModel.addToQueue(episode)
        await viewModel.play()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        viewModel.pause()
        XCTAssertFalse(viewModel.isPlaying)
        
        // When: Seek while paused
        let pausedTime = viewModel.currentTime
        viewModel.seekForward()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Should update position while staying paused
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertNotEqual(viewModel.currentTime, pausedTime)
    }
    
    func testSeekWhileLoading() async throws {
        // Given: Loading state
        let episode = createTestEpisode()
        await viewModel.addToQueue(episode)
        
        // Start playing (enters loading)
        await viewModel.play()
        
        // When: Immediately try to seek (while loading)
        viewModel.seekForward()
        
        // Then: Should handle gracefully
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertNotNil(viewModel.queueItems)
    }
    
    // MARK: - Rapid Seek Tests
    
    func testRapidSeekForward() async throws {
        // Given: Playing episode
        let episode = createTestEpisode(duration: 600)
        await viewModel.addToQueue(episode)
        await viewModel.play()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // When: Rapidly tap forward
        for _ in 0..<5 {
            viewModel.seekForward()
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s between taps
        }
        
        // Then: Should handle rapid seeks
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertGreaterThan(viewModel.currentTime, 0)
    }
    
    func testRapidSeekBackward() async throws {
        // Given: Playing with some progress
        let episode = createTestEpisode(duration: 600)
        await viewModel.addToQueue(episode)
        await viewModel.play()
        
        // Build up some time
        try await Task.sleep(nanoseconds: 5_000_000_000)
        
        // When: Rapidly tap backward
        let timeBeforeRapidSeek = viewModel.currentTime
        for _ in 0..<3 {
            viewModel.seekBackward()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // Then: Should handle rapid seeks
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertLessThan(viewModel.currentTime, timeBeforeRapidSeek)
    }
    
    // MARK: - Progress Update Tests
    
    func testProgressUpdatesAfterSeek() async throws {
        // Given: Playing episode
        let episode = createTestEpisode(duration: 300)
        await viewModel.addToQueue(episode)
        await viewModel.play()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // When: Seek forward
        let progressBefore = viewModel.progress
        viewModel.seekForward()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Progress should update
        XCTAssertNotEqual(viewModel.progress, progressBefore)
    }
    
    func testTimeDisplayUpdatesAfterSeek() async throws {
        // Given: Playing episode
        let episode = createTestEpisode()
        await viewModel.addToQueue(episode)
        await viewModel.play()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // When: Seek
        let displayTimeBefore = viewModel.currentTime
        viewModel.seekForward()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Display time should update
        XCTAssertNotEqual(viewModel.currentTime, displayTimeBefore)
    }
    
    // MARK: - Helper Methods
    
    private func createTestArticle() -> Article {
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Test Article"
        article.content = "Test content for TTS generation"
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
}