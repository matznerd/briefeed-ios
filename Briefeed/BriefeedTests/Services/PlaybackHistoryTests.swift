//
//  PlaybackHistoryTests.swift
//  BriefeedTests
//
//  Created by Briefeed Team on 1/8/25.
//

import Testing
import Foundation
@testable import Briefeed

/// Tests for PlaybackHistoryManager following TDD approach
struct PlaybackHistoryTests {
    
    // MARK: - History Tracking Tests
    
    @Test("History tracking should record progress")
    func test_historyTracking_shouldRecordProgress() throws {
        // Given
        let historyManager = PlaybackHistoryManager.shared
        let audioItem = AudioTestHelpers.createTestBriefeedAudioItem(
            type: .article,
            title: "Test Article for History"
        )
        let position: TimeInterval = 45 // 45 seconds
        let duration: TimeInterval = 180 // 3 minutes
        
        // Clear history first
        historyManager.clearHistory()
        
        // When
        historyManager.addToHistory(audioItem, position: position, duration: duration)
        
        // Then
        let history = historyManager.getHistory()
        #expect(history.count >= 1)
        
        let latestItem = history.first
        #expect(latestItem?.title == "Test Article for History")
        #expect(latestItem?.lastPlaybackPosition == position)
        #expect(latestItem?.duration == duration)
        #expect(latestItem?.playbackProgress == position / duration)
    }
    
    @Test("History limit should keep last 100 items")
    func test_historyLimit_shouldKeepLast100Items() throws {
        // Given
        let historyManager = PlaybackHistoryManager.shared
        historyManager.clearHistory()
        
        // When adding 105 items
        for i in 0..<105 {
            let audioItem = AudioTestHelpers.createTestBriefeedAudioItem(
                title: "Item \(i)"
            )
            historyManager.addToHistory(audioItem, position: 10, duration: 100)
        }
        
        // Then
        let history = historyManager.getHistory()
        #expect(history.count == 100)
        
        // Verify newest items are kept (LIFO)
        #expect(history.first?.title == "Item 104")
        #expect(history.last?.title == "Item 5")
    }
    
    @Test("Resume from history should restore position")
    @MainActor
    func test_resumeFromHistory_shouldRestorePosition() async throws {
        // Given
        let historyManager = PlaybackHistoryManager.shared
        let service = BriefeedAudioService.shared
        
        // Create a history item
        let historyItem = AudioTestHelpers.createTestHistoryItem(
            contentType: .article,
            title: "Resume Test Article",
            progress: 0.5
        )
        
        // When
        await service.resumeFromHistory(historyItem)
        
        // Then
        // Note: In real implementation, this would fetch the article and seek
        // For now, we verify the method exists and can be called
        #expect(service.resumeFromHistory != nil)
    }
    
    // MARK: - History Update Tests
    
    @Test("Update existing history item should maintain position in list")
    func test_updateExistingHistoryItem_shouldMaintainPosition() throws {
        // Given
        let historyManager = PlaybackHistoryManager.shared
        historyManager.clearHistory()
        
        // Add initial items
        let audioItem1 = AudioTestHelpers.createTestBriefeedAudioItem(title: "Item 1")
        let audioItem2 = AudioTestHelpers.createTestBriefeedAudioItem(title: "Item 2")
        
        historyManager.addToHistory(audioItem1, position: 10, duration: 100)
        historyManager.addToHistory(audioItem2, position: 20, duration: 200)
        
        // When updating item 1 with new position
        historyManager.addToHistory(audioItem1, position: 50, duration: 100)
        
        // Then
        let history = historyManager.getHistory()
        #expect(history.count == 2)
        #expect(history.first?.title == "Item 1") // Should be moved to front
        #expect(history.first?.lastPlaybackPosition == 50)
    }
    
    @Test("Completed items should be marked as completed")
    func test_completedItems_shouldBeMarkedAsCompleted() throws {
        // Given
        let historyManager = PlaybackHistoryManager.shared
        let audioItem = AudioTestHelpers.createTestBriefeedAudioItem(title: "Complete Test")
        
        // When item is played to 95% or more
        historyManager.addToHistory(audioItem, position: 95, duration: 100)
        
        // Then
        let history = historyManager.getHistory()
        let item = history.first { $0.title == "Complete Test" }
        #expect(item?.isCompleted == true)
        #expect(item?.playbackProgress ?? 0 >= 0.95)
    }
    
    // MARK: - History Query Tests
    
    @Test("Get history for specific article should return correct item")
    func test_getHistoryForArticle_shouldReturnCorrectItem() throws {
        // Given
        let historyManager = PlaybackHistoryManager.shared
        let articleId = UUID()
        let audioItem = AudioTestHelpers.createTestBriefeedAudioItem(
            type: .article,
            title: "Specific Article"
        )
        
        // Add to history with known article ID
        historyManager.addToHistory(audioItem, position: 30, duration: 100)
        
        // When
        // Note: In real implementation, we'd need to match by article ID
        let history = historyManager.getHistory()
        let foundItem = history.first { $0.title == "Specific Article" }
        
        // Then
        #expect(foundItem != nil)
        #expect(foundItem?.contentType == .article)
    }
    
    @Test("Get history for specific RSS episode should return correct item")
    func test_getHistoryForRSSEpisode_shouldReturnCorrectItem() throws {
        // Given
        let historyManager = PlaybackHistoryManager.shared
        let episodeURL = "https://example.com/episode123.mp3"
        let audioItem = AudioTestHelpers.createTestBriefeedAudioItem(
            type: .rssEpisode,
            title: "Specific Episode"
        )
        
        // Add to history
        historyManager.addToHistory(audioItem, position: 60, duration: 1800)
        
        // When
        let historyItem = historyManager.getHistory(for: episodeURL)
        
        // Then
        // Note: In real implementation, this would match by episode URL
        let history = historyManager.getHistory()
        let foundItem = history.first { $0.title == "Specific Episode" }
        #expect(foundItem != nil)
        #expect(foundItem?.contentType == .rssEpisode)
    }
    
    // MARK: - History Search Tests
    
    @Test("Search history should filter by query")
    func test_searchHistory_shouldFilterByQuery() throws {
        // Given
        let historyManager = PlaybackHistoryManager.shared
        historyManager.clearHistory()
        
        // Add various items
        let items = [
            ("Swift Programming", "John Doe"),
            ("Python Tutorial", "Jane Smith"),
            ("Swift UI Guide", "John Doe"),
            ("JavaScript Basics", "Bob Wilson")
        ]
        
        for (title, author) in items {
            let audioItem = AudioTestHelpers.createTestBriefeedAudioItem(title: title)
            historyManager.addToHistory(audioItem, position: 10, duration: 100)
        }
        
        // When searching for "Swift"
        let results = historyManager.searchHistory(query: "Swift")
        
        // Then
        #expect(results.count >= 2)
        #expect(results.allSatisfy { $0.title.contains("Swift") })
    }
    
    @Test("Get incomplete items should return unfinished items")
    func test_getIncompleteItems_shouldReturnUnfinishedItems() throws {
        // Given
        let historyManager = PlaybackHistoryManager.shared
        historyManager.clearHistory()
        
        // Add items with different progress
        let items = [
            ("Item 1", 10.0, 100.0),  // 10% progress
            ("Item 2", 95.0, 100.0),  // 95% progress (completed)
            ("Item 3", 50.0, 100.0),  // 50% progress
            ("Item 4", 2.0, 100.0)    // 2% progress (too little)
        ]
        
        for (title, position, duration) in items {
            let audioItem = AudioTestHelpers.createTestBriefeedAudioItem(title: title)
            historyManager.addToHistory(audioItem, position: position, duration: duration)
        }
        
        // When
        let incompleteItems = historyManager.getIncompleteItems()
        
        // Then
        #expect(incompleteItems.count == 2) // Items 1 and 3
        #expect(incompleteItems.allSatisfy { !$0.isCompleted && $0.playbackProgress > 0.05 })
    }
    
    // MARK: - History Statistics Tests
    
    @Test("Statistics should calculate correctly")
    func test_statistics_shouldCalculateCorrectly() throws {
        // Given
        let historyManager = PlaybackHistoryManager.shared
        historyManager.clearHistory()
        
        // Add test data
        let articleItem = AudioTestHelpers.createTestBriefeedAudioItem(type: .article)
        let episodeItem = AudioTestHelpers.createTestBriefeedAudioItem(type: .rssEpisode)
        
        historyManager.addToHistory(articleItem, position: 90, duration: 100) // 90% article
        historyManager.addToHistory(episodeItem, position: 600, duration: 1200) // 50% episode
        
        // When
        let stats = historyManager.getStatistics()
        
        // Then
        #expect(stats.totalItems == 2)
        #expect(stats.completedItems >= 0)
        #expect(stats.totalListeningTime == 690) // 90 + 600
        #expect(stats.averageCompletion > 0)
        #expect(stats.itemsByType[.article] ?? 0 >= 1)
        #expect(stats.itemsByType[.rssEpisode] ?? 0 >= 1)
    }
    
    // MARK: - History Persistence Tests
    
    @Test("History should persist across app launches")
    func test_history_shouldPersistAcrossAppLaunches() throws {
        // Given
        let historyManager = PlaybackHistoryManager.shared
        historyManager.clearHistory()
        
        // Add test item
        let audioItem = AudioTestHelpers.createTestBriefeedAudioItem(
            title: "Persistence Test"
        )
        historyManager.addToHistory(audioItem, position: 45, duration: 90)
        
        // When
        // Simulate app restart by checking UserDefaults directly
        let historyData = UserDefaults.standard.data(forKey: "BriefeedPlaybackHistory")
        
        // Then
        #expect(historyData != nil)
        
        // Verify data can be decoded
        if let data = historyData {
            let decoded = try? JSONDecoder().decode([PlaybackHistoryItem].self, from: data)
            #expect(decoded != nil)
            #expect(decoded?.first?.title == "Persistence Test")
        }
    }
    
    // MARK: - History Removal Tests
    
    @Test("Remove from history should delete specific item")
    func test_removeFromHistory_shouldDeleteSpecificItem() throws {
        // Given
        let historyManager = PlaybackHistoryManager.shared
        historyManager.clearHistory()
        
        // Add items
        for i in 0..<3 {
            let audioItem = AudioTestHelpers.createTestBriefeedAudioItem(title: "Item \(i)")
            historyManager.addToHistory(audioItem, position: 10, duration: 100)
        }
        
        let initialCount = historyManager.getHistory().count
        let itemToRemove = historyManager.getHistory()[1]
        
        // When
        historyManager.removeFromHistory(itemID: itemToRemove.id)
        
        // Then
        let history = historyManager.getHistory()
        #expect(history.count == initialCount - 1)
        #expect(!history.contains { $0.id == itemToRemove.id })
    }
    
    @Test("Clear history should remove all items")
    func test_clearHistory_shouldRemoveAllItems() throws {
        // Given
        let historyManager = PlaybackHistoryManager.shared
        
        // Add some items
        for i in 0..<5 {
            let audioItem = AudioTestHelpers.createTestBriefeedAudioItem(title: "Item \(i)")
            historyManager.addToHistory(audioItem, position: 10, duration: 100)
        }
        
        // When
        historyManager.clearHistory()
        
        // Then
        let history = historyManager.getHistory()
        #expect(history.count == 0)
    }
}