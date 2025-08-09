import XCTest
@testable import Briefeed

// MARK: - TDD: Queue Management Tests
// Define expected queue behavior before implementation

final class QueueManagementTests: XCTestCase {
    
    // MARK: - Queue Basic Operations
    
    func testAddItemToQueue() {
        // Given
        let queue = QueueServiceV3.shared
        let audioURL = URL(string: "https://example.com/audio1.mp3")!
        let item = QueueItem(
            title: "Test Article",
            subtitle: "Author Name",
            audioURL: audioURL,
            type: .article(id: "article-1")
        )
        
        // When
        queue.addToQueue(item)
        
        // Then
        XCTAssertEqual(queue.items.count, 1)
        XCTAssertEqual(queue.items.first?.title, "Test Article")
        XCTAssertEqual(queue.items.first?.audioURL, audioURL)
    }
    
    func testAddMultipleItemsToQueue() {
        // Given
        let queue = QueueServiceV3.shared
        queue.clear()
        
        let items = [
            QueueItem(title: "Article 1", subtitle: "Author 1", audioURL: URL(string: "https://example.com/1.mp3")!, type: .article(id: "1")),
            QueueItem(title: "Episode 1", subtitle: "Podcast 1", audioURL: URL(string: "https://example.com/2.mp3")!, type: .episode(id: "2")),
            QueueItem(title: "Article 2", subtitle: "Author 2", audioURL: URL(string: "https://example.com/3.mp3")!, type: .article(id: "3"))
        ]
        
        // When
        items.forEach { queue.addToQueue($0) }
        
        // Then
        XCTAssertEqual(queue.items.count, 3)
        XCTAssertEqual(queue.items[0].title, "Article 1")
        XCTAssertEqual(queue.items[1].title, "Episode 1")
        XCTAssertEqual(queue.items[2].title, "Article 2")
    }
    
    func testRemoveItemFromQueue() {
        // Given
        let queue = QueueServiceV3.shared
        queue.clear()
        let item1 = QueueItem(title: "Item 1", subtitle: "", audioURL: URL(string: "https://example.com/1.mp3")!, type: .article(id: "1"))
        let item2 = QueueItem(title: "Item 2", subtitle: "", audioURL: URL(string: "https://example.com/2.mp3")!, type: .article(id: "2"))
        queue.addToQueue(item1)
        queue.addToQueue(item2)
        
        // When
        queue.removeFromQueue(at: 0)
        
        // Then
        XCTAssertEqual(queue.items.count, 1)
        XCTAssertEqual(queue.items.first?.title, "Item 2")
    }
    
    func testClearQueue() {
        // Given
        let queue = QueueServiceV3.shared
        queue.addToQueue(QueueItem(title: "Item 1", subtitle: "", audioURL: URL(string: "https://example.com/1.mp3")!, type: .article(id: "1")))
        queue.addToQueue(QueueItem(title: "Item 2", subtitle: "", audioURL: URL(string: "https://example.com/2.mp3")!, type: .article(id: "2")))
        
        // When
        queue.clear()
        
        // Then
        XCTAssertEqual(queue.items.count, 0)
        XCTAssertTrue(queue.isEmpty)
    }
    
    // MARK: - Queue Reordering
    
    func testReorderQueueItems() {
        // Given
        let queue = QueueServiceV3.shared
        queue.clear()
        let items = (1...5).map {
            QueueItem(title: "Item \($0)", subtitle: "", audioURL: URL(string: "https://example.com/\($0).mp3")!, type: .article(id: "\($0)"))
        }
        items.forEach { queue.addToQueue($0) }
        
        // When - move item at index 4 to index 1
        queue.reorderQueue(from: 4, to: 1)
        
        // Then
        XCTAssertEqual(queue.items[0].title, "Item 1")
        XCTAssertEqual(queue.items[1].title, "Item 5") // Moved item
        XCTAssertEqual(queue.items[2].title, "Item 2")
        XCTAssertEqual(queue.items[3].title, "Item 3")
        XCTAssertEqual(queue.items[4].title, "Item 4")
    }
    
    func testBatchReorder() {
        // Given
        let queue = QueueServiceV3.shared
        queue.clear()
        let items = (1...5).map {
            QueueItem(title: "Item \($0)", subtitle: "", audioURL: URL(string: "https://example.com/\($0).mp3")!, type: .article(id: "\($0)"))
        }
        items.forEach { queue.addToQueue($0) }
        
        // When - move multiple items
        queue.moveItems(from: [0, 2], to: 3)
        
        // Then
        XCTAssertEqual(queue.items[0].title, "Item 2")
        XCTAssertEqual(queue.items[1].title, "Item 4")
        XCTAssertEqual(queue.items[2].title, "Item 1") // Moved
        XCTAssertEqual(queue.items[3].title, "Item 3") // Moved
        XCTAssertEqual(queue.items[4].title, "Item 5")
    }
    
    // MARK: - Queue Playback
    
    func testPlayNextInQueue() {
        // Given
        let queue = QueueServiceV3.shared
        let audioService = AudioStreamingService.shared
        queue.clear()
        
        let items = [
            QueueItem(title: "Item 1", subtitle: "", audioURL: URL(string: "https://example.com/1.mp3")!, type: .article(id: "1")),
            QueueItem(title: "Item 2", subtitle: "", audioURL: URL(string: "https://example.com/2.mp3")!, type: .article(id: "2"))
        ]
        items.forEach { queue.addToQueue($0) }
        
        // When
        queue.playNext()
        
        // Then
        XCTAssertEqual(queue.currentIndex, 0)
        XCTAssertEqual(queue.currentItem?.title, "Item 1")
        XCTAssertEqual(audioService.currentURL, items[0].audioURL)
        XCTAssertTrue(audioService.isPlaying)
    }
    
    func testAutoPlayNextItem() {
        // Given
        let queue = QueueServiceV3.shared
        let audioService = AudioStreamingService.shared
        queue.clear()
        
        let items = [
            QueueItem(title: "Item 1", subtitle: "", audioURL: URL(string: "https://example.com/1.mp3")!, type: .article(id: "1")),
            QueueItem(title: "Item 2", subtitle: "", audioURL: URL(string: "https://example.com/2.mp3")!, type: .article(id: "2"))
        ]
        items.forEach { queue.addToQueue($0) }
        
        // When - play first item
        queue.playNext()
        // Simulate first item finishing
        audioService.simulatePlaybackFinished()
        
        // Then - should auto-play next
        XCTAssertEqual(queue.currentIndex, 1)
        XCTAssertEqual(queue.currentItem?.title, "Item 2")
        XCTAssertEqual(audioService.currentURL, items[1].audioURL)
        XCTAssertTrue(audioService.isPlaying)
    }
    
    func testSkipToNextInQueue() {
        // Given
        let queue = QueueServiceV3.shared
        queue.clear()
        let items = (1...3).map {
            QueueItem(title: "Item \($0)", subtitle: "", audioURL: URL(string: "https://example.com/\($0).mp3")!, type: .article(id: "\($0)"))
        }
        items.forEach { queue.addToQueue($0) }
        queue.playNext() // Start with first
        
        // When
        queue.skipToNext()
        
        // Then
        XCTAssertEqual(queue.currentIndex, 1)
        XCTAssertEqual(queue.currentItem?.title, "Item 2")
    }
    
    func testSkipToPreviousInQueue() {
        // Given
        let queue = QueueServiceV3.shared
        queue.clear()
        let items = (1...3).map {
            QueueItem(title: "Item \($0)", subtitle: "", audioURL: URL(string: "https://example.com/\($0).mp3")!, type: .article(id: "\($0)"))
        }
        items.forEach { queue.addToQueue($0) }
        queue.currentIndex = 2 // Start at third item
        
        // When
        queue.skipToPrevious()
        
        // Then
        XCTAssertEqual(queue.currentIndex, 1)
        XCTAssertEqual(queue.currentItem?.title, "Item 2")
    }
    
    // MARK: - Queue Persistence
    
    func testSaveQueueState() {
        // Given
        let queue = QueueServiceV3.shared
        queue.clear()
        let items = [
            QueueItem(title: "Persisted 1", subtitle: "", audioURL: URL(string: "https://example.com/1.mp3")!, type: .article(id: "1")),
            QueueItem(title: "Persisted 2", subtitle: "", audioURL: URL(string: "https://example.com/2.mp3")!, type: .article(id: "2"))
        ]
        items.forEach { queue.addToQueue($0) }
        queue.currentIndex = 1
        
        // When
        queue.saveState()
        
        // Then
        let savedData = UserDefaults.standard.data(forKey: "QueueState")
        XCTAssertNotNil(savedData, "Queue state should be saved")
    }
    
    func testRestoreQueueState() {
        // Given - save a queue state
        let queue = QueueServiceV3.shared
        queue.clear()
        let items = [
            QueueItem(title: "Restored 1", subtitle: "", audioURL: URL(string: "https://example.com/1.mp3")!, type: .article(id: "1")),
            QueueItem(title: "Restored 2", subtitle: "", audioURL: URL(string: "https://example.com/2.mp3")!, type: .article(id: "2"))
        ]
        items.forEach { queue.addToQueue($0) }
        queue.currentIndex = 1
        queue.saveState()
        
        // When - clear and restore
        queue.clear()
        queue.restoreState()
        
        // Then
        XCTAssertEqual(queue.items.count, 2)
        XCTAssertEqual(queue.items[0].title, "Restored 1")
        XCTAssertEqual(queue.items[1].title, "Restored 2")
        XCTAssertEqual(queue.currentIndex, 1)
    }
    
    // MARK: - Queue with Different Content Types
    
    func testMixedContentQueue() {
        // Given
        let queue = QueueServiceV3.shared
        queue.clear()
        
        // When - add mixed content
        queue.addToQueue(QueueItem(
            title: "Article Title",
            subtitle: "Author",
            audioURL: URL(string: "https://example.com/article.mp3")!,
            type: .article(id: "art-1")
        ))
        
        queue.addToQueue(QueueItem(
            title: "Podcast Episode",
            subtitle: "Podcast Name",
            audioURL: URL(string: "https://example.com/episode.mp3")!,
            type: .episode(id: "ep-1")
        ))
        
        // Then
        XCTAssertEqual(queue.items.count, 2)
        
        // Check first item is article
        if case .article(let id) = queue.items[0].type {
            XCTAssertEqual(id, "art-1")
        } else {
            XCTFail("First item should be article")
        }
        
        // Check second item is episode
        if case .episode(let id) = queue.items[1].type {
            XCTAssertEqual(id, "ep-1")
        } else {
            XCTFail("Second item should be episode")
        }
    }
    
    // MARK: - Queue Status
    
    func testQueueEmpty() {
        // Given
        let queue = QueueServiceV3.shared
        queue.clear()
        
        // Then
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.count, 0)
        XCTAssertNil(queue.currentItem)
    }
    
    func testQueueNotEmpty() {
        // Given
        let queue = QueueServiceV3.shared
        queue.clear()
        
        // When
        queue.addToQueue(QueueItem(
            title: "Item",
            subtitle: "",
            audioURL: URL(string: "https://example.com/1.mp3")!,
            type: .article(id: "1")
        ))
        
        // Then
        XCTAssertFalse(queue.isEmpty)
        XCTAssertEqual(queue.count, 1)
    }
    
    func testQueueProgress() {
        // Given
        let queue = QueueServiceV3.shared
        queue.clear()
        let items = (1...5).map {
            QueueItem(title: "Item \($0)", subtitle: "", audioURL: URL(string: "https://example.com/\($0).mp3")!, type: .article(id: "\($0)"))
        }
        items.forEach { queue.addToQueue($0) }
        
        // When
        queue.currentIndex = 2
        
        // Then
        XCTAssertEqual(queue.remainingCount, 3) // Items 3, 4, 5 remaining
        XCTAssertEqual(queue.completedCount, 2) // Items 1, 2 completed
        XCTAssertEqual(queue.progress, 0.4) // 2 of 5 = 40%
    }
}