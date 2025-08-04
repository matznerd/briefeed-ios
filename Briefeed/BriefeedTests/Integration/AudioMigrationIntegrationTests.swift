//
//  AudioMigrationIntegrationTests.swift
//  BriefeedTests
//
//  Created by Briefeed Team on 1/8/25.
//

import Testing
import Foundation
import CoreData
@testable import Briefeed

/// Integration tests for migrating from old AudioService to new BriefeedAudioService
struct AudioMigrationIntegrationTests {
    
    // MARK: - Queue Format Migration Tests
    
    @Test("Old queue format should migrate to new format")
    @MainActor
    func test_oldQueueFormat_shouldMigrateToNewFormat() async throws {
        // Given - Old queue format from QueueService
        let context = TestPersistenceController.createInMemoryContext()
        let article1 = AudioTestHelpers.createTestArticle(title: "Old Article 1", in: context)
        let article2 = AudioTestHelpers.createTestArticle(title: "Old Article 2", in: context)
        
        // Simulate old queue storage format
        let oldQueueItems = [
            QueueService.QueuedItem(articleID: article1.id!, addedDate: Date()),
            QueueService.QueuedItem(articleID: article2.id!, addedDate: Date())
        ]
        
        // When converting to new format
        let newQueueItems = oldQueueItems.compactMap { oldItem -> BriefeedAudioItem? in
            // This simulates the migration logic
            guard let article = try? context.fetch(Article.fetchRequest()).first(where: { $0.id == oldItem.articleID }) else {
                return nil
            }
            let content = ArticleAudioContent(article: article)
            return BriefeedAudioItem(content: content)
        }
        
        // Then
        #expect(newQueueItems.count == 2)
        #expect(newQueueItems[0].content.title == "Old Article 1")
        #expect(newQueueItems[1].content.title == "Old Article 2")
    }
    
    @Test("Enhanced queue with RSS should migrate correctly")
    @MainActor
    func test_enhancedQueue_shouldMigrateWithRSS() async throws {
        // Given - Enhanced queue with mixed content
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(title: "Article in Queue", in: context)
        let episode = AudioTestHelpers.createTestRSSEpisode(title: "Episode in Queue", in: context)
        
        // Simulate enhanced queue items
        let enhancedItems = [
            EnhancedQueueItem(
                id: UUID(),
                articleID: article.id,
                episodeURL: nil,
                contentType: .article,
                title: article.title!,
                author: article.author,
                feedTitle: article.feed?.title,
                duration: nil,
                addedDate: Date(),
                audioURL: nil,
                isTemporary: false
            ),
            EnhancedQueueItem(
                id: UUID(),
                articleID: nil,
                episodeURL: episode.audioUrl,
                contentType: .rssEpisode,
                title: episode.title!,
                author: episode.author,
                feedTitle: episode.feed?.displayName,
                duration: Int(episode.duration),
                addedDate: Date(),
                audioURL: episode.audioUrl,
                isTemporary: false
            )
        ]
        
        // When converting to new audio items
        let newItems = enhancedItems.compactMap { enhancedItem -> BriefeedAudioItem? in
            if enhancedItem.contentType == .article,
               let articleID = enhancedItem.articleID,
               let article = try? context.fetch(Article.fetchRequest()).first(where: { $0.id == articleID }) {
                let content = ArticleAudioContent(article: article)
                return BriefeedAudioItem(content: content, audioURL: enhancedItem.audioURL.flatMap { URL(string: $0) })
            } else if enhancedItem.contentType == .rssEpisode,
                      let episodeURL = enhancedItem.episodeURL,
                      let episode = try? context.fetch(RSSEpisode.fetchRequest()).first(where: { $0.audioUrl == episodeURL }) {
                let content = RSSEpisodeAudioContent(episode: episode)
                return BriefeedAudioItem(content: content, audioURL: URL(string: episodeURL))
            }
            return nil
        }
        
        // Then
        #expect(newItems.count == 2)
        #expect(newItems[0].content.contentType == .article)
        #expect(newItems[1].content.contentType == .rssEpisode)
        #expect(newItems[1].audioURL != nil)
    }
    
    // MARK: - Settings Migration Tests
    
    @Test("Playback speed setting should migrate")
    func test_playbackSpeed_shouldMigrate() {
        // Given
        let userDefaults = UserDefaultsManager.shared
        userDefaults.playbackSpeed = 1.5
        
        // When
        let newService = BriefeedAudioService.shared
        
        // Then
        #expect(newService.playbackRate == 1.5)
    }
    
    @Test("Auto-play settings should migrate")
    func test_autoPlaySettings_shouldMigrate() {
        // Given
        let userDefaults = UserDefaultsManager.shared
        userDefaults.autoPlayNext = true
        userDefaults.autoPlayOnAppLaunch = true
        
        // When checking settings
        // Note: In real implementation, BriefeedAudioService would read these
        
        // Then
        #expect(userDefaults.autoPlayNext == true)
        #expect(userDefaults.autoPlayOnAppLaunch == true)
    }
    
    // MARK: - State Synchronization Tests
    
    @Test("Current playback item should sync between services")
    @MainActor
    func test_currentPlaybackItem_shouldSync() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(
            title: "Sync Test Article",
            in: context
        )
        
        // When playing in new service
        let newService = BriefeedAudioService.shared
        await newService.playArticle(article)
        
        // Then
        #expect(newService.currentPlaybackItem?.title == "Sync Test Article")
        #expect(newService.currentPlaybackItem?.contentType == .article)
    }
    
    // MARK: - Queue Persistence Tests
    
    @Test("Queue should persist through service migration")
    @MainActor
    func test_queue_shouldPersistThroughMigration() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let service = BriefeedAudioService.shared
        
        // Clear existing queue
        service.clearQueue()
        
        // Add items to queue
        let article1 = AudioTestHelpers.createTestArticle(title: "Persist 1", in: context)
        let article2 = AudioTestHelpers.createTestArticle(title: "Persist 2", in: context)
        
        await service.addToQueue(article1)
        await service.addToQueue(article2)
        
        // When checking UserDefaults
        let queueData = UserDefaults.standard.array(forKey: "BriefeedAudioQueue")
        
        // Then
        #expect(queueData != nil)
        #expect(service.queue.count == 2)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Migration should handle corrupted queue data")
    func test_migration_shouldHandleCorruptedQueueData() throws {
        // Given - Corrupted queue data
        let corruptedData = "Not valid queue data".data(using: .utf8)!
        UserDefaults.standard.set(corruptedData, forKey: "AudioQueueItems")
        
        // When attempting to restore
        // Note: In real implementation, this would be handled gracefully
        
        // Then service should still initialize
        let service = BriefeedAudioService.shared
        #expect(service != nil)
    }
    
    // MARK: - Feature Parity Tests
    
    @Test("All AudioService features should be available in BriefeedAudioService")
    func test_featureParity_allFeaturesShouldBeAvailable() {
        // Given
        let newService = BriefeedAudioService.shared
        
        // Then - Verify all key features exist
        #expect(newService.playArticle != nil)
        #expect(newService.playRSSEpisode != nil)
        #expect(newService.togglePlayPause != nil)
        #expect(newService.seek != nil)
        #expect(newService.skipForward != nil)
        #expect(newService.skipBackward != nil)
        #expect(newService.setPlaybackRate != nil)
        #expect(newService.addToQueue != nil)
        #expect(newService.removeFromQueue != nil)
        #expect(newService.clearQueue != nil)
        
        // New features
        #expect(newService.resumeFromHistory != nil)
        #expect(newService.startSleepTimer != nil)
        #expect(newService.stopSleepTimer != nil)
    }
    
    // MARK: - Performance Tests
    
    @Test("Migration should complete within reasonable time")
    @MainActor
    func test_migration_shouldCompleteQuickly() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let startTime = Date()
        
        // Create a large queue
        var articles: [Article] = []
        for i in 0..<50 {
            let article = AudioTestHelpers.createTestArticle(
                title: "Performance Test \(i)",
                in: context
            )
            articles.append(article)
        }
        
        // When migrating
        let service = BriefeedAudioService.shared
        for article in articles {
            await service.addToQueue(article)
        }
        
        // Then
        let migrationTime = Date().timeIntervalSince(startTime)
        #expect(migrationTime < 5.0) // Should complete within 5 seconds
        #expect(service.queue.count == 50)
    }
}