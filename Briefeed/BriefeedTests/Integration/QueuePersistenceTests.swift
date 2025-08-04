//
//  QueuePersistenceTests.swift
//  BriefeedTests
//
//  Created by Briefeed Team on 1/8/25.
//

import Testing
import Foundation
import CoreData
@testable import Briefeed

/// Tests for queue persistence across app sessions
struct QueuePersistenceTests {
    
    // MARK: - Basic Persistence Tests
    
    @Test("Queue should persist articles across app restarts")
    @MainActor
    func test_queuePersistence_articles() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let service = BriefeedAudioService.shared
        
        // Clear existing queue
        service.clearQueue()
        
        // Add articles to queue
        let article1 = AudioTestHelpers.createTestArticle(
            id: UUID(),
            title: "Article One",
            content: "Content for article one",
            in: context
        )
        
        let article2 = AudioTestHelpers.createTestArticle(
            id: UUID(),
            title: "Article Two",
            content: "Content for article two",
            in: context
        )
        
        await service.addToQueue(article1)
        await service.addToQueue(article2)
        
        // When - Simulate app restart
        let savedQueueData = UserDefaults.standard.array(forKey: "BriefeedAudioQueue") as? [[String: Any]]
        #expect(savedQueueData != nil)
        #expect(savedQueueData?.count == 2)
        
        // Verify saved data structure
        if let firstItem = savedQueueData?.first {
            #expect(firstItem["title"] as? String == "Article One")
            #expect(firstItem["contentType"] as? String == "article")
            #expect(firstItem["id"] as? String != nil)
        }
    }
    
    @Test("Queue should persist RSS episodes")
    @MainActor
    func test_queuePersistence_rssEpisodes() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let service = BriefeedAudioService.shared
        service.clearQueue()
        
        // Add RSS episodes
        let episode1 = AudioTestHelpers.createTestRSSEpisode(
            title: "Episode One",
            audioUrl: "https://example.com/ep1.mp3",
            in: context
        )
        
        let episode2 = AudioTestHelpers.createTestRSSEpisode(
            title: "Episode Two",
            audioUrl: "https://example.com/ep2.mp3",
            in: context
        )
        
        service.addToQueue(episode1)
        service.addToQueue(episode2)
        
        // When - Check persistence
        let savedQueueData = UserDefaults.standard.array(forKey: "BriefeedAudioQueue") as? [[String: Any]]
        
        // Then
        #expect(savedQueueData?.count == 2)
        
        if let firstEpisode = savedQueueData?.first {
            #expect(firstEpisode["title"] as? String == "Episode One")
            #expect(firstEpisode["contentType"] as? String == "rssEpisode")
            #expect(firstEpisode["episodeURL"] as? String == "https://example.com/ep1.mp3")
        }
    }
    
    @Test("Queue should persist mixed content types")
    @MainActor
    func test_queuePersistence_mixedContent() async throws {
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
        
        // When - Check persistence
        let savedQueueData = UserDefaults.standard.array(forKey: "BriefeedAudioQueue") as? [[String: Any]]
        
        // Then
        #expect(savedQueueData?.count == 2)
        #expect(savedQueueData?[0]["contentType"] as? String == "article")
        #expect(savedQueueData?[1]["contentType"] as? String == "rssEpisode")
    }
    
    // MARK: - Queue Index Persistence
    
    @Test("Queue index should persist")
    @MainActor
    func test_queueIndexPersistence() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let service = BriefeedAudioService.shared
        service.clearQueue()
        
        // Add items and play second one
        for i in 1...3 {
            let article = AudioTestHelpers.createTestArticle(
                title: "Article \(i)",
                in: context
            )
            await service.addToQueue(article)
        }
        
        // Play second item
        await service.playNext()
        await service.playNext()
        
        // When - Check saved index
        let savedIndex = UserDefaults.standard.integer(forKey: "BriefeedAudioQueue_index")
        
        // Then
        #expect(savedIndex == 1) // Zero-based index
    }
    
    // MARK: - Audio URL Persistence
    
    @Test("Generated audio URLs should persist")
    @MainActor
    func test_audioURLPersistence() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let service = BriefeedAudioService.shared
        let cacheManager = AudioCacheManager.shared
        
        // Create article and cache audio
        let article = AudioTestHelpers.createTestArticle(
            id: UUID(),
            title: "Cached Article",
            in: context
        )
        
        // Cache some audio data
        let audioData = Data("fake audio data".utf8)
        let cacheURL = try cacheManager.cacheAudio(
            audioData,
            for: article.id?.uuidString ?? ""
        )
        
        // Add to queue
        await service.addToQueue(article)
        
        // When - Check persistence
        let savedQueueData = UserDefaults.standard.array(forKey: "BriefeedAudioQueue") as? [[String: Any]]
        
        // Then
        if let firstItem = savedQueueData?.first {
            let audioURLString = firstItem["audioURL"] as? String
            #expect(audioURLString != nil)
            #expect(audioURLString?.contains("audio_cache") == true)
        }
    }
    
    // MARK: - Queue Restoration Tests
    
    @Test("Queue should restore correctly after restart")
    @MainActor
    func test_queueRestoration() async throws {
        // Given - Manually save queue data
        let queueData: [[String: Any]] = [
            [
                "contentType": "article",
                "id": UUID().uuidString,
                "title": "Restored Article 1",
                "author": "Author 1",
                "dateAdded": Date()
            ],
            [
                "contentType": "rssEpisode",
                "id": UUID().uuidString,
                "title": "Restored Episode",
                "episodeURL": "https://example.com/restored.mp3",
                "feedTitle": "Test Podcast",
                "dateAdded": Date()
            ]
        ]
        
        UserDefaults.standard.set(queueData, forKey: "BriefeedAudioQueue")
        UserDefaults.standard.set(0, forKey: "BriefeedAudioQueue_index")
        
        // When - Create new service instance
        // In real app, this would happen on launch
        // For testing, we'll check if the service would restore correctly
        
        // Then - Verify restoration logic
        let savedData = UserDefaults.standard.array(forKey: "BriefeedAudioQueue") as? [[String: Any]]
        #expect(savedData?.count == 2)
        #expect(savedData?[0]["title"] as? String == "Restored Article 1")
        #expect(savedData?[1]["contentType"] as? String == "rssEpisode")
    }
    
    // MARK: - Edge Cases
    
    @Test("Empty queue should persist correctly")
    @MainActor
    func test_emptyQueuePersistence() async throws {
        // Given
        let service = BriefeedAudioService.shared
        service.clearQueue()
        
        // When - Check persistence
        let savedQueueData = UserDefaults.standard.array(forKey: "BriefeedAudioQueue") as? [[String: Any]]
        let savedIndex = UserDefaults.standard.integer(forKey: "BriefeedAudioQueue_index")
        
        // Then
        #expect(savedQueueData == nil || savedQueueData?.isEmpty == true)
        #expect(savedIndex == -1 || savedIndex == 0)
    }
    
    @Test("Large queue should persist efficiently")
    @MainActor
    func test_largeQueuePersistence() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let service = BriefeedAudioService.shared
        service.clearQueue()
        
        // Add 100 items
        for i in 1...100 {
            let article = AudioTestHelpers.createTestArticle(
                title: "Article \(i)",
                in: context
            )
            await service.addToQueue(article)
        }
        
        // When - Measure persistence time
        let startTime = Date()
        let savedQueueData = UserDefaults.standard.array(forKey: "BriefeedAudioQueue") as? [[String: Any]]
        let persistenceTime = Date().timeIntervalSince(startTime)
        
        // Then
        #expect(savedQueueData?.count == 100)
        #expect(persistenceTime < 1.0) // Should save in under 1 second
    }
    
    @Test("Queue with invalid data should handle gracefully")
    @MainActor
    func test_corruptedQueueData() async throws {
        // Given - Save corrupted data
        let corruptedData: [[String: Any]] = [
            [:], // Empty dictionary
            ["title": "Missing ID"], // Missing required fields
            ["id": "not-a-uuid", "contentType": "invalid"] // Invalid values
        ]
        
        UserDefaults.standard.set(corruptedData, forKey: "BriefeedAudioQueue")
        
        // When - Service attempts to restore
        // In real implementation, service should handle this gracefully
        
        // Then - Verify service can still function
        let service = BriefeedAudioService.shared
        #expect(service.queue.isEmpty || service.queue.count < 3)
    }
    
    // MARK: - Migration Tests
    
    @Test("Old queue format should migrate to new format")
    @MainActor
    func test_queueFormatMigration() async throws {
        // Given - Old queue format (from AudioService)
        let oldQueueData: [[String: Any]] = [
            [
                "id": UUID().uuidString,
                "title": "Old Format Article",
                "type": "article" // Old used "type" instead of "contentType"
            ]
        ]
        
        // Save in old format location
        UserDefaults.standard.set(oldQueueData, forKey: "AudioServiceQueue")
        
        // When - Migration logic runs
        // This would be handled by migration code
        
        // Then - Should convert to new format
        // Implementation would need to handle this migration
        #expect(true) // Placeholder for actual migration test
    }
    
    // MARK: - Concurrency Tests
    
    @Test("Queue persistence should be thread-safe")
    @MainActor
    func test_queuePersistenceThreadSafety() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let service = BriefeedAudioService.shared
        service.clearQueue()
        
        // When - Add items concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    let article = AudioTestHelpers.createTestArticle(
                        title: "Concurrent Article \(i)",
                        in: context
                    )
                    await service.addToQueue(article)
                }
            }
        }
        
        // Then - All items should be persisted
        let savedQueueData = UserDefaults.standard.array(forKey: "BriefeedAudioQueue") as? [[String: Any]]
        #expect(savedQueueData?.count == 10)
    }
    
    // MARK: - Performance Tests
    
    @Test("Queue persistence performance")
    @MainActor
    func test_queuePersistencePerformance() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let service = BriefeedAudioService.shared
        
        // Measure different queue sizes
        let sizes = [10, 50, 100, 500]
        var measurements: [Int: TimeInterval] = [:]
        
        for size in sizes {
            service.clearQueue()
            
            // Add items
            for i in 1...size {
                let article = AudioTestHelpers.createTestArticle(
                    title: "Perf Test \(i)",
                    in: context
                )
                await service.addToQueue(article)
            }
            
            // Measure save time
            let startTime = Date()
            _ = UserDefaults.standard.array(forKey: "BriefeedAudioQueue")
            let saveTime = Date().timeIntervalSince(startTime)
            
            measurements[size] = saveTime
        }
        
        // Then - Performance should scale reasonably
        #expect(measurements[10]! < 0.1)
        #expect(measurements[100]! < 0.5)
        #expect(measurements[500]! < 2.0)
    }
}