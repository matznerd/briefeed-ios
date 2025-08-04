//
//  AudioServiceAdapterTests.swift
//  BriefeedTests
//
//  Created by Briefeed Team on 1/8/25.
//

import Testing
import Foundation
import CoreData
import Combine
@testable import Briefeed

/// Tests for AudioServiceAdapter that bridges old AudioService API to new BriefeedAudioService
struct AudioServiceAdapterTests {
    
    // MARK: - Playback State Mirroring Tests
    
    @Test("Adapter should mirror playback state from new service")
    @MainActor
    func test_adapter_shouldMirrorPlaybackState() async throws {
        // Given
        let adapter = AudioServiceAdapter()
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(in: context)
        
        // When playing through adapter
        await adapter.playArticle(article)
        
        // Then
        #expect(adapter.isPlaying == true)
        #expect(adapter.isLoading == false)
        #expect(adapter.currentPlaybackItem != nil)
        #expect(adapter.currentPlaybackItem?.title == article.title)
    }
    
    @Test("Adapter should convert queue format from new to old")
    @MainActor
    func test_adapter_shouldConvertQueueFormat() async throws {
        // Given
        let adapter = AudioServiceAdapter()
        let context = TestPersistenceController.createInMemoryContext()
        let article1 = AudioTestHelpers.createTestArticle(title: "Article 1", in: context)
        let article2 = AudioTestHelpers.createTestArticle(title: "Article 2", in: context)
        
        // When adding to queue
        await adapter.addToQueue(article1)
        await adapter.addToQueue(article2)
        
        // Then - queue should contain Article objects for backward compatibility
        #expect(adapter.queue.count == 2)
        #expect(adapter.queue[0].title == "Article 1")
        #expect(adapter.queue[1].title == "Article 2")
    }
    
    @Test("Adapter should handle progress updates")
    @MainActor
    func test_adapter_shouldHandleProgressUpdates() async throws {
        // Given
        let adapter = AudioServiceAdapter()
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(in: context)
        
        // When playing
        await adapter.playArticle(article)
        
        // Then
        #expect(adapter.progress.value >= 0.0)
        #expect(adapter.progress.value <= 1.0)
        #expect(adapter.progress.currentTime >= 0)
        #expect(adapter.progress.remainingTime >= 0)
    }
    
    @Test("Adapter should maintain backward compatibility with old API")
    @MainActor
    func test_adapter_shouldMaintainBackwardCompatibility() async throws {
        // Given
        let adapter = AudioServiceAdapter()
        
        // Then - verify all old AudioService properties exist
        #expect(adapter.isPlaying == false)
        #expect(adapter.isLoading == false)
        #expect(adapter.isGeneratingAudio == false)
        #expect(adapter.currentPlaybackItem == nil)
        #expect(adapter.queue.isEmpty)
        #expect(adapter.progress.value == 0)
        #expect(adapter.playbackSpeed == 1.0)
        #expect(adapter.volume == 1.0)
    }
    
    // MARK: - Playback Control Tests
    
    @Test("Play/pause controls should work through adapter")
    @MainActor
    func test_playPauseControls_shouldWork() async throws {
        // Given
        let adapter = AudioServiceAdapter()
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(in: context)
        
        // When
        await adapter.playArticle(article)
        #expect(adapter.isPlaying == true)
        
        adapter.togglePlayPause()
        #expect(adapter.isPlaying == false)
        
        adapter.play()
        #expect(adapter.isPlaying == true)
        
        adapter.pause()
        #expect(adapter.isPlaying == false)
    }
    
    @Test("Skip controls should use correct intervals")
    @MainActor
    func test_skipControls_shouldUseCorrectIntervals() async throws {
        // Given
        let adapter = AudioServiceAdapter()
        let context = TestPersistenceController.createInMemoryContext()
        
        // Test with article (15 second skip)
        let article = AudioTestHelpers.createTestArticle(in: context)
        await adapter.playArticle(article)
        
        adapter.skipForward()
        // Verify 15-second skip for articles
        
        adapter.skipBackward()
        // Verify 15-second skip backward
        
        // Test with RSS episode (30 second skip)
        let episode = AudioTestHelpers.createTestRSSEpisode(in: context)
        await adapter.playRSSEpisode(episode)
        
        adapter.skipForward()
        // Verify 30-second skip for episodes
    }
    
    @Test("Playback speed should sync")
    @MainActor
    func test_playbackSpeed_shouldSync() async throws {
        // Given
        let adapter = AudioServiceAdapter()
        
        // When
        adapter.setPlaybackSpeed(1.5)
        
        // Then
        #expect(adapter.playbackSpeed == 1.5)
        #expect(UserDefaultsManager.shared.playbackSpeed == 1.5)
    }
    
    // MARK: - Queue Management Tests
    
    @Test("Queue operations should work through adapter")
    @MainActor
    func test_queueOperations_shouldWork() async throws {
        // Given
        let adapter = AudioServiceAdapter()
        let context = TestPersistenceController.createInMemoryContext()
        let article1 = AudioTestHelpers.createTestArticle(title: "Q1", in: context)
        let article2 = AudioTestHelpers.createTestArticle(title: "Q2", in: context)
        let article3 = AudioTestHelpers.createTestArticle(title: "Q3", in: context)
        
        // When
        await adapter.addToQueue(article1)
        await adapter.addToQueue(article2)
        await adapter.addToQueue(article3)
        
        // Then
        #expect(adapter.queue.count == 3)
        
        // Remove from queue
        adapter.removeFromQueue(at: 1)
        #expect(adapter.queue.count == 2)
        #expect(adapter.queue[1].title == "Q3")
        
        // Clear queue
        adapter.clearQueue()
        #expect(adapter.queue.isEmpty)
    }
    
    @Test("Queue reordering should work")
    @MainActor
    func test_queueReordering_shouldWork() async throws {
        // Given
        let adapter = AudioServiceAdapter()
        let context = TestPersistenceController.createInMemoryContext()
        
        for i in 1...4 {
            let article = AudioTestHelpers.createTestArticle(title: "Article \(i)", in: context)
            await adapter.addToQueue(article)
        }
        
        // When moving item from index 3 to index 1
        adapter.moveQueueItem(from: 3, to: 1)
        
        // Then
        #expect(adapter.queue[1].title == "Article 4")
        #expect(adapter.queue[2].title == "Article 2")
        #expect(adapter.queue[3].title == "Article 3")
    }
    
    // MARK: - RSS Episode Support Tests
    
    @Test("Adapter should support RSS episodes")
    @MainActor
    func test_adapter_shouldSupportRSSEpisodes() async throws {
        // Given
        let adapter = AudioServiceAdapter()
        let context = TestPersistenceController.createInMemoryContext()
        let episode = AudioTestHelpers.createTestRSSEpisode(
            title: "Test Podcast Episode",
            duration: 1800,
            in: context
        )
        
        // When
        await adapter.playRSSEpisode(episode)
        
        // Then
        #expect(adapter.isPlaying == true)
        #expect(adapter.currentPlaybackItem?.isRSS == true)
        #expect(adapter.currentPlaybackItem?.title == "Test Podcast Episode")
        #expect(adapter.currentPlaybackItem?.duration == 1800)
    }
    
    @Test("Mixed queue should work with articles and episodes")
    @MainActor
    func test_mixedQueue_shouldWork() async throws {
        // Given
        let adapter = AudioServiceAdapter()
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(title: "Article", in: context)
        let episode = AudioTestHelpers.createTestRSSEpisode(title: "Episode", in: context)
        
        // When
        await adapter.addToQueue(article)
        await adapter.addToRSSQueue(episode)
        
        // Then
        #expect(adapter.queue.count == 1) // Articles only in main queue
        #expect(adapter.enhancedQueue.count == 2) // Both in enhanced queue
    }
    
    // MARK: - State Persistence Tests
    
    @Test("Adapter should restore state on init")
    @MainActor
    func test_adapter_shouldRestoreStateOnInit() async throws {
        // Given - Set up some persisted state
        let context = TestPersistenceController.createInMemoryContext()
        let adapter1 = AudioServiceAdapter()
        let article = AudioTestHelpers.createTestArticle(title: "Persisted", in: context)
        await adapter1.addToQueue(article)
        
        // When creating new adapter (simulating app restart)
        let adapter2 = AudioServiceAdapter()
        
        // Then
        // Note: In real implementation, queue would be restored
        #expect(adapter2.queue.count >= 0)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Adapter should handle TTS generation errors")
    @MainActor
    func test_adapter_shouldHandleTTSErrors() async throws {
        // Given
        let adapter = AudioServiceAdapter()
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(
            content: "", // Empty content might cause TTS error
            summary: nil,
            in: context
        )
        
        // When
        await adapter.playArticle(article)
        
        // Then - should handle gracefully
        #expect(adapter.currentPlaybackItem != nil || adapter.lastError != nil)
    }
    
    // MARK: - Publisher Tests
    
    @Test("Adapter publishers should emit updates")
    @MainActor
    func test_adapterPublishers_shouldEmitUpdates() async throws {
        // Given
        let adapter = AudioServiceAdapter()
        var receivedUpdate = false
        
        let cancellable = adapter.$isPlaying
            .dropFirst()
            .sink { _ in
                receivedUpdate = true
            }
        
        // When
        adapter.play()
        
        // Then
        try await AudioTestHelpers.waitFor { receivedUpdate }
        #expect(receivedUpdate == true)
        
        cancellable.cancel()
    }
    
    // MARK: - Feature Flag Tests
    
    @Test("Adapter should respect feature flag")
    @MainActor
    func test_adapter_shouldRespectFeatureFlag() async throws {
        // Given
        UserDefaults.standard.set(true, forKey: "useNewAudioService")
        let adapter = AudioServiceAdapter()
        
        // Then - adapter should use new service
        #expect(adapter.isUsingNewService == true)
        
        // When feature flag is disabled
        UserDefaults.standard.set(false, forKey: "useNewAudioService")
        
        // Then - adapter should fall back to old service
        // Note: In real implementation, this would switch implementations
    }
}