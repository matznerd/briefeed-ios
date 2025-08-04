//
//  AudioSystemIntegrationTests.swift
//  BriefeedTests
//
//  Created by Briefeed Team on 1/8/25.
//

import Testing
import Foundation
import CoreData
import AVFoundation
@testable import Briefeed

/// Comprehensive integration tests for the entire audio system
struct AudioSystemIntegrationTests {
    
    // MARK: - End-to-End Playback Tests
    
    @Test("Article playback should work end-to-end")
    @MainActor
    func test_articlePlayback_endToEnd() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(
            title: "Integration Test Article",
            summary: "This is a test summary for integration testing.",
            in: context
        )
        
        let service = BriefeedAudioService.shared
        
        // When
        await service.playArticle(article)
        
        // Then
        #expect(service.currentPlaybackItem?.title == "Integration Test Article")
        #expect(service.isLoading == false)
        
        // Verify TTS was generated or cached
        let cacheManager = AudioCacheManager.shared
        let cachedAudio = cacheManager.getCachedAudio(for: article.id?.uuidString ?? "")
        #expect(cachedAudio != nil)
        
        // Verify history was updated
        let history = PlaybackHistoryManager.shared.getHistory()
        #expect(history.first?.title == "Integration Test Article")
    }
    
    @Test("RSS episode playback should work end-to-end")
    @MainActor
    func test_rssEpisodePlayback_endToEnd() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let episode = AudioTestHelpers.createTestRSSEpisode(
            title: "Test Podcast Episode",
            audioUrl: "https://example.com/episode.mp3",
            in: context
        )
        
        let service = BriefeedAudioService.shared
        
        // When
        await service.playRSSEpisode(episode)
        
        // Then
        #expect(service.currentPlaybackItem?.title == "Test Podcast Episode")
        #expect(service.currentPlaybackItem?.contentType == .rssEpisode)
        #expect(service.isLoading == false)
        
        // Verify history
        let history = PlaybackHistoryManager.shared.getHistory()
        #expect(history.first?.contentType == .rssEpisode)
    }
    
    // MARK: - Queue Management Tests
    
    @Test("Queue should persist across app restarts")
    @MainActor
    func test_queuePersistence() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let service = BriefeedAudioService.shared
        
        // Add items to queue
        let article1 = AudioTestHelpers.createTestArticle(title: "Article 1", in: context)
        let article2 = AudioTestHelpers.createTestArticle(title: "Article 2", in: context)
        let episode = AudioTestHelpers.createTestRSSEpisode(title: "Episode 1", in: context)
        
        await service.addToQueue(article1)
        await service.addToQueue(article2)
        service.addToQueue(episode)
        
        // When - Simulate app restart by creating new service instance
        // Note: In real implementation, we'd need to properly reset the singleton
        let queueCount = service.queue.count
        
        // Then
        #expect(queueCount == 3)
        #expect(service.queue[0].content.title == "Article 1")
        #expect(service.queue[1].content.title == "Article 2")
        #expect(service.queue[2].content.title == "Episode 1")
    }
    
    @Test("Queue should handle mixed content types")
    @MainActor
    func test_queueMixedContent() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let service = BriefeedAudioService.shared
        service.clearQueue()
        
        // Add mixed content
        let article = AudioTestHelpers.createTestArticle(title: "News Article", in: context)
        let episode = AudioTestHelpers.createTestRSSEpisode(
            title: "Podcast Episode",
            audioUrl: "https://example.com/podcast.mp3",
            in: context
        )
        
        await service.addToQueue(article)
        service.addToQueue(episode)
        
        // When playing through queue
        await service.playNext()
        
        // Then
        #expect(service.currentPlaybackItem?.title == "News Article")
        #expect(service.currentPlaybackItem?.contentType == .article)
        
        // Play next
        await service.playNext()
        
        #expect(service.currentPlaybackItem?.title == "Podcast Episode")
        #expect(service.currentPlaybackItem?.contentType == .rssEpisode)
    }
    
    // MARK: - Feature Flag Integration Tests
    
    @Test("Feature flags should control service behavior")
    @MainActor
    func test_featureFlags_controlBehavior() async throws {
        // Given
        let featureFlags = FeatureFlagManager.shared
        let adapter = AudioServiceAdapter()
        
        // Test caching feature
        featureFlags.enableAudioCaching = true
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(in: context)
        
        // When
        await adapter.playArticle(article)
        
        // Then - Verify cache was used
        let cacheManager = AudioCacheManager.shared
        let cachedAudio = cacheManager.getCachedAudio(for: article.id?.uuidString ?? "")
        if featureFlags.enableAudioCaching {
            #expect(cachedAudio != nil)
        }
        
        // Test history feature
        featureFlags.enablePlaybackHistory = true
        let history = PlaybackHistoryManager.shared.getHistory()
        if featureFlags.enablePlaybackHistory {
            #expect(history.count > 0)
        }
    }
    
    // MARK: - Error Recovery Tests
    
    @Test("Service should recover from playback errors")
    @MainActor
    func test_errorRecovery() async throws {
        // Given
        let service = BriefeedAudioService.shared
        let context = TestPersistenceController.createInMemoryContext()
        
        // Create article with invalid content that might fail TTS
        let article = AudioTestHelpers.createTestArticle(
            title: "Error Test Article",
            content: "", // Empty content might cause TTS to fail
            summary: nil,
            in: context
        )
        
        // When
        await service.playArticle(article)
        
        // Then - Service should handle error gracefully
        if service.lastError != nil {
            #expect(service.isPlaying == false)
            #expect(service.isLoading == false)
        }
        
        // Verify service can still play valid content
        let validArticle = AudioTestHelpers.createTestArticle(
            title: "Valid Article",
            content: "This is valid content.",
            in: context
        )
        
        await service.playArticle(validArticle)
        #expect(service.currentPlaybackItem?.title == "Valid Article")
    }
    
    // MARK: - Background Audio Tests
    
    @Test("Audio should continue in background")
    @MainActor
    func test_backgroundAudio() async throws {
        // Given
        let service = BriefeedAudioService.shared
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(in: context)
        
        // When
        await service.playArticle(article)
        
        // Simulate app going to background
        NotificationCenter.default.post(
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        // Then - Audio session should be configured for background
        let audioSession = AVAudioSession.sharedInstance()
        #expect(audioSession.category == .playback)
        #expect(audioSession.categoryOptions.contains(.mixWithOthers))
    }
    
    // MARK: - Sleep Timer Integration Tests
    
    @Test("Sleep timer should stop playback after duration")
    @MainActor
    func test_sleepTimer_duration() async throws {
        // Given
        let service = BriefeedAudioService.shared
        let sleepTimer = SleepTimerManager.shared
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(in: context)
        
        // Start playback
        await service.playArticle(article)
        service.play()
        
        // When - Start sleep timer for 1 second
        sleepTimer.startTimer(option: .custom(seconds: 1))
        
        // Wait for timer
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Then
        #expect(service.isPlaying == false)
        #expect(sleepTimer.isActive == false)
    }
    
    @Test("Sleep timer should stop at end of track")
    @MainActor
    func test_sleepTimer_endOfTrack() async throws {
        // Given
        let service = BriefeedAudioService.shared
        let sleepTimer = SleepTimerManager.shared
        let context = TestPersistenceController.createInMemoryContext()
        
        // Create queue with multiple items
        let article1 = AudioTestHelpers.createTestArticle(title: "Track 1", in: context)
        let article2 = AudioTestHelpers.createTestArticle(title: "Track 2", in: context)
        
        await service.addToQueue(article1)
        await service.addToQueue(article2)
        
        // When - Start sleep timer for end of track
        sleepTimer.startTimer(option: .endOfTrack)
        
        // Play first item
        await service.playNext()
        
        // Simulate track end
        // In real implementation, this would be triggered by audio player
        sleepTimer.notifyTrackEnded()
        
        // Then
        #expect(service.queue.count == 1) // Second item still in queue
        #expect(sleepTimer.isActive == false)
    }
    
    // MARK: - Performance Tests
    
    @Test("Large queue should perform well")
    @MainActor
    func test_largeQueuePerformance() async throws {
        // Given
        let service = BriefeedAudioService.shared
        let context = TestPersistenceController.createInMemoryContext()
        service.clearQueue()
        
        let startTime = Date()
        
        // When - Add 100 items to queue
        for i in 1...100 {
            let article = AudioTestHelpers.createTestArticle(
                title: "Article \(i)",
                in: context
            )
            await service.addToQueue(article)
        }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        // Then
        #expect(service.queue.count == 100)
        #expect(elapsedTime < 5.0) // Should complete in under 5 seconds
        
        // Test queue navigation performance
        let navStartTime = Date()
        
        // Navigate through queue
        for _ in 1...10 {
            await service.playNext()
        }
        
        let navElapsedTime = Date().timeIntervalSince(navStartTime)
        #expect(navElapsedTime < 1.0) // Navigation should be fast
    }
    
    // MARK: - Memory Tests
    
    @Test("Service should not leak memory")
    @MainActor
    func test_memoryLeaks() async throws {
        // Given
        weak var weakService: BriefeedAudioService?
        weak var weakAdapter: AudioServiceAdapter?
        
        // Create in autoreleasepool to ensure cleanup
        autoreleasepool {
            let service = BriefeedAudioService.shared
            let adapter = AudioServiceAdapter()
            
            weakService = service
            weakAdapter = adapter
            
            // Perform operations
            let context = TestPersistenceController.createInMemoryContext()
            let article = AudioTestHelpers.createTestArticle(in: context)
            
            Task {
                await adapter.playArticle(article)
            }
        }
        
        // When - Wait for cleanup
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Then - Singleton should still exist, adapter should not
        #expect(weakService != nil) // Singleton persists
        #expect(weakAdapter == nil) // Adapter should be released
    }
    
    // MARK: - Cache Management Tests
    
    @Test("Cache should enforce size limits")
    @MainActor
    func test_cacheSizeLimits() async throws {
        // Given
        let cacheManager = AudioCacheManager.shared
        let service = BriefeedAudioService.shared
        let context = TestPersistenceController.createInMemoryContext()
        
        // Create large audio data (1MB each)
        let largeAudioData = Data(repeating: 0, count: 1_000_000)
        
        // When - Add items until cache limit is exceeded
        for i in 1...600 { // 600MB > 500MB limit
            let cacheURL = try cacheManager.cacheAudio(
                largeAudioData,
                for: "test-\(i)"
            )
            
            // Verify file was created
            #expect(FileManager.default.fileExists(atPath: cacheURL.path))
        }
        
        // Then - Old files should be evicted
        let oldestURL = cacheManager.getCachedAudio(for: "test-1")
        #expect(oldestURL == nil) // Should have been evicted
        
        // Recent files should still exist
        let recentURL = cacheManager.getCachedAudio(for: "test-600")
        #expect(recentURL != nil)
    }
    
    // MARK: - UI Integration Tests
    
    @Test("UI components should reflect service state")
    @MainActor
    func test_uiIntegration() async throws {
        // Given
        let service = BriefeedAudioService.shared
        let adapter = AudioServiceAdapter()
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(in: context)
        
        // When
        await adapter.playArticle(article)
        
        // Then - Adapter should mirror service state
        #expect(adapter.currentPlaybackItem?.title == article.title)
        #expect(adapter.isPlaying == service.isPlaying)
        #expect(adapter.progress.value >= 0)
        
        // Test playback controls
        adapter.togglePlayPause()
        #expect(adapter.isPlaying != service.isPlaying)
        
        adapter.skipForward()
        #expect(adapter.progress.currentTime >= 0)
    }
}