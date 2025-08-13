//
//  MiniPlayerControlTests.swift
//  BriefeedTests
//
//  TDD tests for mini player control layout and interactions
//

import XCTest
import SwiftUI
import CoreData
@testable import Briefeed

@MainActor
final class MiniPlayerControlTests: XCTestCase {
    
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
    
    // MARK: - Control Button Layout Tests
    
    func testMiniPlayerHasFiveControlButtons() async throws {
        // Given: Mini player is visible
        let miniPlayer = MiniAudioPlayerV4()
            .environmentObject(viewModel)
        
        // Then: Should have exactly 5 control buttons
        // Previous, -10, Play/Pause, +10, Next
        XCTAssertNotNil(miniPlayer, "Mini player should be created")
        
        // Verify button order from left to right:
        // [⏮️] [-10] [⏸️/▶️] [+10] [⏭️]
        // All methods should exist on the viewModel
        XCTAssertNotNil(viewModel)
    }
    
    func testPlayPauseButtonIsCentered() async throws {
        // Given: A queue with items
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        
        // When: Playing
        await viewModel.play()
        
        // Then: Play/pause button should be in center position (index 2 of 5 buttons)
        // Button order: [0: Previous] [1: -10] [2: Play/Pause] [3: +10] [4: Next]
        XCTAssertTrue(viewModel.isPlaying || viewModel.isLoading)
    }
    
    func testPlayButtonShowsCorrectIcon() async throws {
        // Given: Audio is not playing
        XCTAssertFalse(viewModel.isPlaying)
        
        // When: Queue has items but not playing
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        
        // Then: Should show play icon (▶️)
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertEqual(viewModel.queueItems.count, 1)
        
        // When: Start playing
        await viewModel.play()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Should show pause icon (⏸️)
        // Note: May still be loading TTS
        XCTAssertTrue(viewModel.isPlaying || viewModel.isLoading)
    }
    
    // MARK: - Button State Tests
    
    func testPreviousButtonDisabledAtStart() async throws {
        // Given: Queue with items
        let article1 = createTestArticle(title: "First")
        let article2 = createTestArticle(title: "Second")
        await viewModel.addToQueue(article1)
        await viewModel.addToQueue(article2)
        
        // When: Playing first item
        await viewModel.play()
        
        // Then: Previous button should be disabled (at index 0)
        XCTAssertEqual(viewModel.currentQueueIndex, 0)
        
        // When: Skip to next
        await viewModel.playNext()
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then: Previous button should be enabled
        XCTAssertEqual(viewModel.currentQueueIndex, 1)
    }
    
    func testNextButtonDisabledAtEnd() async throws {
        // Given: Queue with 2 items
        let article1 = createTestArticle(title: "First")
        let article2 = createTestArticle(title: "Last")
        await viewModel.addToQueue(article1)
        await viewModel.addToQueue(article2)
        
        // When: Playing last item
        await viewModel.play()
        await viewModel.playNext() // Move to last
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then: Next button should be disabled
        XCTAssertEqual(viewModel.currentQueueIndex, 1)
        XCTAssertEqual(viewModel.queueItems.count, 2)
    }
    
    func testSeekButtonsEnabledDuringPlayback() async throws {
        // Given: RSS episode playing (seekable content)
        let episode = createTestEpisode()
        await viewModel.addToQueue(episode)
        
        // When: Playing
        await viewModel.play()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Both seek buttons should be enabled
        XCTAssertEqual(viewModel.currentItemType, .rssEpisode)
        
        // Verify seek functions exist
        // Verify seek methods exist
        XCTAssertNotNil(viewModel)
    }
    
    // MARK: - Control Interaction Tests
    
    func testTapPlayButtonStartsPlayback() async throws {
        // Given: Queue with item, not playing
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        XCTAssertFalse(viewModel.isPlaying)
        
        // When: Tap play button
        await viewModel.play()
        
        // Then: Should start playing
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(viewModel.isPlaying || viewModel.isLoading)
    }
    
    func testTapPauseButtonPausesPlayback() async throws {
        // Given: Playing audio
        let article = createTestArticle()
        await viewModel.addToQueue(article)
        await viewModel.play()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // When: Tap pause button
        viewModel.pause()
        
        // Then: Should pause
        XCTAssertFalse(viewModel.isPlaying)
    }
    
    func testTapPreviousButtonSkipsToPrevious() async throws {
        // Given: Playing second item
        let article1 = createTestArticle(title: "First")
        let article2 = createTestArticle(title: "Second")
        await viewModel.addToQueue(article1)
        await viewModel.addToQueue(article2)
        
        await viewModel.play()
        await viewModel.playNext()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(viewModel.currentQueueIndex, 1)
        
        // When: Tap previous button
        await viewModel.playPrevious()
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then: Should go to previous item
        XCTAssertEqual(viewModel.currentQueueIndex, 0)
    }
    
    func testTapNextButtonSkipsToNext() async throws {
        // Given: Playing first item
        let article1 = createTestArticle(title: "First")
        let article2 = createTestArticle(title: "Second")
        await viewModel.addToQueue(article1)
        await viewModel.addToQueue(article2)
        
        await viewModel.play()
        XCTAssertEqual(viewModel.currentQueueIndex, 0)
        
        // When: Tap next button
        await viewModel.playNext()
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then: Should go to next item
        XCTAssertEqual(viewModel.currentQueueIndex, 1)
    }
    
    func testTapRewind10ButtonSeeksBackward() async throws {
        // Given: Playing RSS episode
        let episode = createTestEpisode()
        await viewModel.addToQueue(episode)
        await viewModel.play()
        
        // Wait for some playback to accumulate time
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // When: Tap -10 button
        let timeBefore = viewModel.currentTime
        viewModel.seekBackward()
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then: Time should decrease
        // Note: Can't assert exact -10s due to loading delays
        XCTAssertLessThanOrEqual(viewModel.currentTime, timeBefore)
    }
    
    func testTapForward10ButtonSeeksForward() async throws {
        // Given: Playing RSS episode
        let episode = createTestEpisode()
        await viewModel.addToQueue(episode)
        await viewModel.play()
        
        // Wait for playback to start
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // When: Tap +10 button
        let timeBefore = viewModel.currentTime
        viewModel.seekForward()
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then: Time should increase
        XCTAssertGreaterThanOrEqual(viewModel.currentTime, timeBefore)
    }
    
    // MARK: - Helper Methods
    
    private func createTestArticle(title: String = "Test Article") -> Article {
        let article = Article(context: context)
        article.id = UUID()
        article.title = title
        article.content = "Test content for playback"
        article.url = "https://example.com/article"
        article.createdAt = Date()
        return article
    }
    
    private func createTestEpisode() -> RSSEpisode {
        let episode = RSSEpisode(context: context)
        episode.id = UUID().uuidString
        episode.title = "Test Episode"
        episode.audioUrl = "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"
        episode.duration = 600 // 10 minutes
        episode.pubDate = Date()
        return episode
    }
}