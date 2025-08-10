//
//  SwiftAudioExIntegrationTests.swift
//  BriefeedTests
//
//  Tests for SwiftAudioEx integration
//  Written BEFORE implementation (TDD approach)
//

import XCTest
import AVFoundation
import CoreData
import MediaPlayer
@testable import Briefeed
// @testable import SwiftAudioEx // Will be imported when enabled

class SwiftAudioExIntegrationTests: XCTestCase {
    
    var audioService: SwiftAudioExService!
    var ttsService: TTSGeneratorService!
    var unifiedPlayer: UnifiedAudioPlayer!
    var testBundle: Bundle!
    var testContext: NSManagedObjectContext!
    
    override func setUp() {
        super.setUp()
        
        // Initialize services for testing
        audioService = SwiftAudioExService()
        ttsService = TTSGeneratorService()
        unifiedPlayer = UnifiedAudioPlayer()
        
        testBundle = Bundle(for: type(of: self))
        testContext = PersistenceController.preview.container.viewContext
    }
    
    override func tearDown() {
        audioService = nil
        ttsService = nil
        unifiedPlayer = nil
        super.tearDown()
    }
    
    // MARK: - Test 1: Service Initialization
    
    func testSwiftAudioExServiceInitialization() throws {
        // Given: A new SwiftAudioEx service
        let service = SwiftAudioExService()
        
        // Then: Service should be properly initialized
        XCTAssertNotNil(service)
        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(service.currentTime, 0)
        XCTAssertEqual(service.duration, 0)
        XCTAssertEqual(service.rate, 1.0)
    }
    
    // MARK: - Test 2: Play Audio File
    
    func testPlayAudioFile() async throws {
        // Given: An audio file URL
        let audioURL = Bundle.main.url(forResource: "test-audio", withExtension: "mp3")!
        
        // When: Playing the audio file
        try await audioService.play(url: audioURL)
        
        // Then: Audio should be playing
        XCTAssertTrue(audioService.isPlaying)
        XCTAssertGreaterThan(audioService.duration, 0)
        XCTAssertEqual(audioService.state, SwiftAudioPlayerState.playing)
    }
    
    // MARK: - Test 3: Speed Control (Up to 20x)
    
    func testSpeedControl() async throws {
        // Given: Audio is playing
        let audioURL = Bundle.main.url(forResource: "test-audio", withExtension: "mp3")!
        try await audioService.play(url: audioURL)
        
        // When: Setting various speeds
        let speeds: [Float] = [0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 20.0]
        
        for speed in speeds {
            audioService.setRate(speed)
            
            // Then: Speed should be set correctly
            XCTAssertEqual(audioService.rate, speed, accuracy: 0.01,
                          "Speed \(speed)x should be supported")
        }
    }
    
    // MARK: - Test 4: Seeking
    
    func testSeeking() async throws {
        // Given: Audio with known duration
        let audioURL = Bundle.main.url(forResource: "test-audio", withExtension: "mp3")!
        try await audioService.play(url: audioURL)
        
        let seekTimes: [TimeInterval] = [0, 10, 30, 60, 90]
        
        for seekTime in seekTimes {
            // When: Seeking to specific time
            audioService.seek(to: seekTime)
            
            // Then: Current time should update
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            XCTAssertEqual(audioService.currentTime, seekTime, accuracy: 0.5,
                          "Should seek to \(seekTime) seconds")
        }
    }
    
    // MARK: - Test 5: TTS Generation
    
    func testTTSGeneration() async throws {
        // Given: Text content
        let text = "This is a test article. It has multiple sentences. This will be converted to speech."
        
        // When: Generating TTS audio file
        let audioFile = try await ttsService.generateAudioFile(from: text)
        
        // Then: Audio file should exist
        XCTAssertNotNil(audioFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioFile.path))
        
        // And: File should be playable
        let asset = AVAsset(url: audioFile)
        XCTAssertTrue(asset.isPlayable)
        XCTAssertGreaterThan(asset.duration.seconds, 0)
    }
    
    // MARK: - Test 6: Article Playback (TTS + SwiftAudioEx)
    
    func testArticlePlayback() async throws {
        // Given: An article with content
        let article = createTestArticle(
            title: "Test Article",
            content: "This is test content that should be converted to speech and played."
        )
        
        // When: Playing the article
        try await unifiedPlayer.play(article: article)
        
        // Then: Should generate TTS and play
        XCTAssertTrue(unifiedPlayer.isPlaying)
        XCTAssertEqual(unifiedPlayer.currentTitle, "Test Article")
        XCTAssertNotNil(unifiedPlayer.currentAudioURL)
        XCTAssertGreaterThan(unifiedPlayer.duration, 0)
    }
    
    // MARK: - Test 7: RSS Episode Streaming
    
    func testRSSEpisodeStreaming() async throws {
        // Given: An RSS episode with audio URL
        let episode = createTestRSSEpisode(
            title: "Test Episode",
            audioURL: "https://example.com/episode.mp3"
        )
        
        // When: Playing the episode
        try await unifiedPlayer.play(episode: episode)
        
        // Then: Should stream directly
        XCTAssertTrue(unifiedPlayer.isPlaying)
        XCTAssertEqual(unifiedPlayer.currentTitle, "Test Episode")
        XCTAssertEqual(unifiedPlayer.currentAudioURL?.absoluteString, "https://example.com/episode.mp3")
        XCTAssertTrue(unifiedPlayer.isStreaming)
    }
    
    // MARK: - Test 8: Queue Management
    
    func testQueueWithMixedContent() async throws {
        // Given: Mixed queue with articles and RSS episodes
        let article = createTestArticle(title: "Article 1", content: "Content 1")
        let episode = createTestRSSEpisode(title: "Episode 1", audioURL: "https://example.com/ep1.mp3")
        
        let queue = [
            UnifiedAudioPlayer.QueueItem.article(article),
            UnifiedAudioPlayer.QueueItem.rssEpisode(episode)
        ]
        
        // When: Playing through queue
        try await unifiedPlayer.setQueue(queue)
        try await unifiedPlayer.play()
        
        // Then: Should play first item
        XCTAssertEqual(unifiedPlayer.currentIndex, 0)
        XCTAssertEqual(unifiedPlayer.currentTitle, "Article 1")
        
        // When: Skip to next
        try await unifiedPlayer.playNext()
        
        // Then: Should play RSS episode
        XCTAssertEqual(unifiedPlayer.currentIndex, 1)
        XCTAssertEqual(unifiedPlayer.currentTitle, "Episode 1")
        XCTAssertTrue(unifiedPlayer.isStreaming)
    }
    
    // MARK: - Test 9: Background Playback
    
    func testBackgroundPlayback() async throws {
        // Given: Audio is playing
        let audioURL = Bundle.main.url(forResource: "test-audio", withExtension: "mp3")!
        try await audioService.play(url: audioURL)
        XCTAssertTrue(audioService.isPlaying)
        
        // When: App goes to background
        NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        // Then: Audio should continue playing
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        XCTAssertTrue(audioService.isPlaying)
        XCTAssertTrue(audioService.backgroundPlaybackEnabled)
    }
    
    // MARK: - Test 10: Remote Control
    
    func testRemoteControlCommands() async throws {
        // Given: Audio is playing
        let audioURL = Bundle.main.url(forResource: "test-audio", withExtension: "mp3")!
        try await audioService.play(url: audioURL)
        
        // When: Remote control commands are sent
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Test play/pause
        _ = commandCenter.pauseCommand.target?(MPRemoteCommandEvent())
        XCTAssertFalse(audioService.isPlaying)
        
        _ = commandCenter.playCommand.target?(MPRemoteCommandEvent())
        XCTAssertTrue(audioService.isPlaying)
        
        // Test skip forward/backward
        let currentTime = audioService.currentTime
        _ = commandCenter.skipForwardCommand.target?(MPRemoteCommandEvent())
        XCTAssertGreaterThan(audioService.currentTime, currentTime)
        
        _ = commandCenter.skipBackwardCommand.target?(MPRemoteCommandEvent())
        XCTAssertLessThanOrEqual(audioService.currentTime, currentTime)
    }
    
    // MARK: - Test 11: State Persistence
    
    func testStatePersistence() async throws {
        // Given: Player with specific state
        let article = createTestArticle(title: "Test", content: "Content")
        try await unifiedPlayer.play(article: article)
        unifiedPlayer.seek(to: 45.0)
        unifiedPlayer.setRate(1.5)
        
        // When: Saving state
        let state = unifiedPlayer.saveState()
        
        // Then: State should contain all info
        XCTAssertEqual(state.currentTime, 45.0, accuracy: 0.5)
        XCTAssertEqual(state.playbackRate, 1.5)
        XCTAssertEqual(state.currentItemTitle, "Test")
        XCTAssertNotNil(state.queueItems)
        
        // When: Restoring to new player
        let newPlayer = UnifiedAudioPlayer()
        try await newPlayer.restoreState(state)
        
        // Then: State should be restored
        XCTAssertEqual(newPlayer.currentTime, 45.0, accuracy: 1.0)
        XCTAssertEqual(newPlayer.rate, 1.5)
        XCTAssertEqual(newPlayer.currentTitle, "Test")
    }
    
    // MARK: - Test 12: Memory Management
    
    func testMemoryManagement() async throws {
        // Given: Multiple audio files played
        for i in 1...10 {
            let article = createTestArticle(
                title: "Article \(i)",
                content: String(repeating: "Content \(i). ", count: 100)
            )
            
            try await unifiedPlayer.play(article: article)
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        // Then: Should not have memory leaks
        // Check cache size
        XCTAssertLessThanOrEqual(
            unifiedPlayer.cacheSize,
            100 * 1024 * 1024, // 100MB limit
            "Cache should not exceed 100MB"
        )
    }
    
    // MARK: - Test 13: Error Handling
    
    func testErrorHandling() async throws {
        // Test 1: Invalid URL
        do {
            let invalidURL = URL(string: "https://invalid.url/audio.mp3")!
            try await audioService.play(url: invalidURL)
            XCTFail("Should throw error for invalid URL")
        } catch {
            XCTAssertNotNil(error)
            XCTAssertEqual(audioService.state, SwiftAudioPlayerState.error(error))
        }
        
        // Test 2: Empty text for TTS
        do {
            _ = try await ttsService.generateAudioFile(from: "")
            XCTFail("Should throw error for empty text")
        } catch {
            XCTAssertEqual(error as? TTSError, TTSError.emptyText)
        }
    }
    
    // MARK: - Test 14: Progress Updates
    
    func testProgressUpdates() async throws {
        // Given: Delegate to track progress
        let expectation = XCTestExpectation(description: "Progress updates")
        var progressUpdates: [Float] = []
        
        class TestDelegate: SwiftAudioExServiceDelegate {
            var onProgress: ((Float) -> Void)?
            
            func audioStateChanged(to newState: SwiftAudioPlayerState, from oldState: SwiftAudioPlayerState) {
                // Not needed for this test
            }
            
            func audioProgressUpdated(progress: Float, currentTime: TimeInterval, duration: TimeInterval) {
                onProgress?(progress)
            }
            
            func audioRateChanged(to rate: Float) {
                // Not needed for this test
            }
            
            func audioDidFinishPlaying(successfully: Bool) {
                // Not needed for this test
            }
        }
        
        let delegate = TestDelegate()
        delegate.onProgress = { progress in
            progressUpdates.append(progress)
            if progress > 0.5 {
                expectation.fulfill()
            }
        }
        
        audioService.delegate = delegate
        
        // When: Playing audio
        let audioURL = Bundle.main.url(forResource: "test-audio", withExtension: "mp3")!
        try await audioService.play(url: audioURL)
        
        // Then: Should receive progress updates
        await fulfillment(of: [expectation], timeout: 5.0)
        XCTAssertFalse(progressUpdates.isEmpty)
        XCTAssertTrue(progressUpdates.contains { $0 > 0.5 })
    }
    
    // MARK: - Test 15: Now Playing Info
    
    func testNowPlayingInfo() async throws {
        // Given: Article being played
        let article = createTestArticle(
            title: "Test Article",
            content: "Content",
            author: "Test Author"
        )
        
        // When: Playing article
        try await unifiedPlayer.play(article: article)
        
        // Then: Now Playing info should be set
        let nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertNotNil(nowPlayingInfo)
        XCTAssertEqual(nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "Test Article")
        XCTAssertEqual(nowPlayingInfo?[MPMediaItemPropertyArtist] as? String, "Test Author")
        XCTAssertNotNil(nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime])
        XCTAssertNotNil(nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration])
    }
    
    // MARK: - Helper Methods
    
    private func createTestArticle(title: String, content: String, author: String = "Test Author") -> Article {
        let article = Article(context: testContext)
        article.id = UUID()
        article.title = title
        article.content = content
        article.author = author
        article.createdAt = Date()
        return article
    }
    
    private func createTestRSSEpisode(title: String, audioURL: String) -> RSSEpisode {
        let episode = RSSEpisode(context: testContext)
        episode.id = UUID().uuidString
        episode.title = title
        episode.audioUrl = audioURL
        episode.duration = 1800 // 30 minutes
        episode.publishedAt = Date()
        return episode
    }
}

// MARK: - Performance Tests

extension SwiftAudioExIntegrationTests {
    
    func testSeekingPerformance() throws {
        measure {
            // Measure seeking performance
            audioService.seek(to: 60.0)
        }
    }
    
    func testTTSGenerationPerformance() throws {
        let text = String(repeating: "Test sentence. ", count: 100)
        
        measure {
            Task {
                _ = try? await ttsService.generateAudioFile(from: text)
            }
        }
    }
    
    func testSpeedChangePerformance() throws {
        measure {
            // Measure speed change performance
            for speed in [0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 20.0] {
                audioService.setRate(Float(speed))
            }
        }
    }
}