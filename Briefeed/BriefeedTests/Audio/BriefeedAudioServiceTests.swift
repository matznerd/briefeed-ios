//
//  BriefeedAudioServiceTests.swift
//  BriefeedTests
//
//  Comprehensive test suite for BriefeedAudioService
//

import XCTest
import Combine
import AVFoundation
import CoreData
@testable import Briefeed

/// Comprehensive test suite for the new audio system
class BriefeedAudioServiceTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: BriefeedAudioService!
    private var cancellables: Set<AnyCancellable>!
    private var mockArticle: Article!
    private var mockRSSEpisode: RSSEpisode!
    private var context: NSManagedObjectContext!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Setup Core Data in-memory context
        context = PersistenceController.preview.container.viewContext
        
        // Create mock data
        mockArticle = createMockArticle()
        mockRSSEpisode = createMockRSSEpisode()
        
        // Initialize service
        await MainActor.run {
            sut = BriefeedAudioService.shared
            cancellables = Set<AnyCancellable>()
        }
    }
    
    override func tearDown() async throws {
        await MainActor.run {
            sut.stop()
            sut.clearQueue()
            cancellables.removeAll()
        }
        
        mockArticle = nil
        mockRSSEpisode = nil
        context = nil
        sut = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Article Playback Tests
    
    func testPlayArticle_Success() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Article plays successfully")
        var didStartLoading = false
        var didStartPlaying = false
        
        await MainActor.run {
            sut.$isLoading
                .dropFirst()
                .sink { isLoading in
                    if isLoading {
                        didStartLoading = true
                    }
                }
                .store(in: &cancellables)
            
            sut.$isPlaying
                .dropFirst()
                .sink { isPlaying in
                    if isPlaying {
                        didStartPlaying = true
                        expectation.fulfill()
                    }
                }
                .store(in: &cancellables)
        }
        
        // When
        await sut.playArticle(mockArticle)
        
        // Then
        await fulfillment(of: [expectation], timeout: 5.0)
        
        await MainActor.run {
            XCTAssertTrue(didStartLoading, "Should start loading")
            XCTAssertTrue(didStartPlaying, "Should start playing")
            XCTAssertNotNil(sut.currentPlaybackItem, "Should have current item")
            XCTAssertEqual(sut.currentPlaybackItem?.title, mockArticle.title, "Should play correct article")
            XCTAssertNil(sut.lastError, "Should not have error")
        }
    }
    
    func testPlayArticle_WithInvalidContent_HandlesError() async throws {
        // Given
        let invalidArticle = createMockArticle(withContent: "")
        let expectation = XCTestExpectation(description: "Error handled")
        
        await MainActor.run {
            sut.$lastError
                .dropFirst()
                .sink { error in
                    if error != nil {
                        expectation.fulfill()
                    }
                }
                .store(in: &cancellables)
        }
        
        // When
        await sut.playArticle(invalidArticle)
        
        // Then
        await fulfillment(of: [expectation], timeout: 3.0)
        
        await MainActor.run {
            XCTAssertNotNil(sut.lastError, "Should have error")
            XCTAssertFalse(sut.isPlaying, "Should not be playing")
        }
    }
    
    // MARK: - RSS Playback Tests
    
    func testPlayRSSEpisode_Success() async throws {
        // Given
        let expectation = XCTestExpectation(description: "RSS episode plays")
        
        await MainActor.run {
            sut.$isPlaying
                .dropFirst()
                .sink { isPlaying in
                    if isPlaying {
                        expectation.fulfill()
                    }
                }
                .store(in: &cancellables)
        }
        
        // When
        await sut.playRSSEpisode(mockRSSEpisode)
        
        // Then
        await fulfillment(of: [expectation], timeout: 3.0)
        
        await MainActor.run {
            XCTAssertTrue(sut.isPlaying, "Should be playing")
            XCTAssertNotNil(sut.currentPlaybackItem, "Should have current item")
            XCTAssertTrue(sut.currentPlaybackItem?.isRSS ?? false, "Should be RSS content")
        }
    }
    
    func testPlayRSSEpisode_WithInvalidURL_HandlesGracefully() async throws {
        // Given
        let invalidEpisode = createMockRSSEpisode(withURL: "not-a-url")
        
        // When
        await sut.playRSSEpisode(invalidEpisode)
        
        // Then
        await MainActor.run {
            XCTAssertFalse(sut.isPlaying, "Should not be playing")
            XCTAssertNil(sut.currentPlaybackItem, "Should not have current item")
        }
    }
    
    // MARK: - Queue Management Tests
    
    func testAddToQueue_Article() async throws {
        // When
        await sut.addToQueue(mockArticle)
        
        // Then
        await MainActor.run {
            XCTAssertEqual(sut.queue.count, 1, "Queue should have 1 item")
            XCTAssertEqual(sut.queue.first?.content.title, mockArticle.title, "Should have correct article")
        }
    }
    
    func testAddToQueue_RSSEpisode() async throws {
        // When
        await MainActor.run {
            sut.addToQueue(mockRSSEpisode)
        }
        
        // Then
        await MainActor.run {
            XCTAssertEqual(sut.queue.count, 1, "Queue should have 1 item")
            XCTAssertEqual(sut.queue.first?.content.contentType, .rssEpisode, "Should be RSS content")
        }
    }
    
    func testQueueNavigation_PlayNext() async throws {
        // Given
        await sut.addToQueue(mockArticle)
        let secondArticle = createMockArticle(title: "Second Article")
        await sut.addToQueue(secondArticle)
        
        // Start playing first item
        await sut.playArticle(mockArticle)
        
        // When
        await sut.playNext()
        
        // Then
        await MainActor.run {
            XCTAssertEqual(sut.queueIndex, 1, "Should move to next item")
            XCTAssertEqual(sut.currentPlaybackItem?.title, "Second Article", "Should play second item")
        }
    }
    
    func testQueueNavigation_PlayPrevious() async throws {
        // Given
        await sut.addToQueue(mockArticle)
        let secondArticle = createMockArticle(title: "Second Article")
        await sut.addToQueue(secondArticle)
        
        // Play second item
        await sut.playArticle(mockArticle)
        await sut.playNext()
        
        // When
        await sut.playPrevious()
        
        // Then
        await MainActor.run {
            XCTAssertEqual(sut.queueIndex, 0, "Should move to previous item")
            XCTAssertEqual(sut.currentPlaybackItem?.title, mockArticle.title, "Should play first item")
        }
    }
    
    func testRemoveFromQueue() async throws {
        // Given
        await sut.addToQueue(mockArticle)
        let secondArticle = createMockArticle(title: "Second")
        await sut.addToQueue(secondArticle)
        
        // When
        await MainActor.run {
            sut.removeFromQueue(at: 0)
        }
        
        // Then
        await MainActor.run {
            XCTAssertEqual(sut.queue.count, 1, "Should have 1 item")
            XCTAssertEqual(sut.queue.first?.content.title, "Second", "Should have second item")
        }
    }
    
    func testClearQueue() async throws {
        // Given
        await sut.addToQueue(mockArticle)
        await sut.addToQueue(createMockArticle(title: "Second"))
        
        // When
        await MainActor.run {
            sut.clearQueue()
        }
        
        // Then
        await MainActor.run {
            XCTAssertEqual(sut.queue.count, 0, "Queue should be empty")
            XCTAssertEqual(sut.queueIndex, -1, "Queue index should be reset")
            XCTAssertFalse(sut.isPlaying, "Should stop playing")
        }
    }
    
    // MARK: - Playback Control Tests
    
    func testPlayPauseToggle() async throws {
        // Given
        await sut.playArticle(mockArticle)
        
        // When - Pause
        await MainActor.run {
            sut.togglePlayPause()
        }
        
        // Then
        await MainActor.run {
            XCTAssertFalse(sut.isPlaying, "Should pause")
        }
        
        // When - Play
        await MainActor.run {
            sut.togglePlayPause()
        }
        
        // Then
        await MainActor.run {
            XCTAssertTrue(sut.isPlaying, "Should resume playing")
        }
    }
    
    func testSkipForward_Article() async throws {
        // Given
        await sut.playArticle(mockArticle)
        let initialTime = await MainActor.run { sut.currentTime }
        
        // When
        await MainActor.run {
            sut.skipForward()
        }
        
        // Then
        await MainActor.run {
            // Articles skip 15 seconds
            XCTAssertEqual(sut.currentTime, initialTime + 15, accuracy: 1.0, "Should skip 15 seconds")
        }
    }
    
    func testSkipBackward_Article() async throws {
        // Given
        await sut.playArticle(mockArticle)
        await MainActor.run {
            sut.seek(to: 30) // Start at 30 seconds
        }
        
        // When
        await MainActor.run {
            sut.skipBackward()
        }
        
        // Then
        await MainActor.run {
            // Articles skip back 15 seconds
            XCTAssertEqual(sut.currentTime, 15, accuracy: 1.0, "Should skip back 15 seconds")
        }
    }
    
    func testSetPlaybackRate() async throws {
        // When
        await MainActor.run {
            sut.setPlaybackRate(1.5)
        }
        
        // Then
        await MainActor.run {
            XCTAssertEqual(sut.playbackRate, 1.5, "Should set playback rate")
            XCTAssertEqual(UserDefaultsManager.shared.playbackSpeed, 1.5, "Should save to UserDefaults")
        }
    }
    
    func testSetPlaybackRate_ClampsValues() async throws {
        // When - Too fast
        await MainActor.run {
            sut.setPlaybackRate(3.0)
        }
        
        // Then
        await MainActor.run {
            XCTAssertEqual(sut.playbackRate, 2.0, "Should clamp to max 2.0")
        }
        
        // When - Too slow
        await MainActor.run {
            sut.setPlaybackRate(0.3)
        }
        
        // Then
        await MainActor.run {
            XCTAssertEqual(sut.playbackRate, 0.5, "Should clamp to min 0.5")
        }
    }
    
    // MARK: - State Management Tests
    
    func testStateTransitions() async throws {
        let expectation = XCTestExpectation(description: "State transitions correctly")
        var states: [AudioPlayerState] = []
        
        await MainActor.run {
            sut.state
                .sink { state in
                    states.append(state)
                    if states.count == 3 {
                        expectation.fulfill()
                    }
                }
                .store(in: &cancellables)
        }
        
        // Trigger state changes
        await sut.playArticle(mockArticle)
        await MainActor.run {
            sut.pause()
        }
        
        await fulfillment(of: [expectation], timeout: 3.0)
        
        // Verify state sequence
        XCTAssertEqual(states[0], .idle, "Should start idle")
        XCTAssertEqual(states[1], .loading, "Should transition to loading")
        XCTAssertEqual(states[2], .playing, "Should transition to playing")
    }
    
    // MARK: - Queue Persistence Tests
    
    func testQueuePersistence_SaveAndRestore() async throws {
        // Given - Add items to queue
        await sut.addToQueue(mockArticle)
        await sut.addToQueue(createMockArticle(title: "Second"))
        
        // When - Simulate app restart
        await MainActor.run {
            sut = nil
            sut = BriefeedAudioService.shared
        }
        
        // Then - Queue should be restored
        await MainActor.run {
            XCTAssertEqual(sut.queue.count, 2, "Queue should be restored")
            XCTAssertEqual(sut.queue.first?.content.title, mockArticle.title, "First item should match")
        }
    }
    
    // MARK: - Background Audio Tests
    
    func testBackgroundAudioConfiguration() async throws {
        // Given
        let session = AVAudioSession.sharedInstance()
        
        // When - Service initializes
        // (Already initialized in setUp)
        
        // Then
        XCTAssertEqual(session.category, .playback, "Should use playback category")
        XCTAssertTrue(session.categoryOptions.contains(.allowBluetooth), "Should allow Bluetooth")
        XCTAssertTrue(session.categoryOptions.contains(.allowAirPlay), "Should allow AirPlay")
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling_InvalidAudioFile() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Error handled")
        
        await MainActor.run {
            sut.$lastError
                .compactMap { $0 }
                .sink { _ in
                    expectation.fulfill()
                }
                .store(in: &cancellables)
        }
        
        // When - Try to play invalid audio
        let invalidItem = BriefeedAudioItem(
            content: ArticleAudioContent(article: mockArticle),
            audioURL: URL(string: "file:///invalid/path.mp3")!,
            isTemporary: false
        )
        
        await MainActor.run {
            // This should fail
            sut.currentItem = invalidItem
        }
        
        // Then
        await fulfillment(of: [expectation], timeout: 3.0)
        
        await MainActor.run {
            XCTAssertNotNil(sut.lastError, "Should have error")
            XCTAssertFalse(sut.isPlaying, "Should not be playing")
        }
    }
    
    // MARK: - Sleep Timer Tests
    
    func testSleepTimer_StopsPlayback() async throws {
        // Given
        await sut.playArticle(mockArticle)
        let expectation = XCTestExpectation(description: "Playback stops")
        
        await MainActor.run {
            sut.$isPlaying
                .dropFirst()
                .sink { isPlaying in
                    if !isPlaying {
                        expectation.fulfill()
                    }
                }
                .store(in: &cancellables)
            
            // When - Start very short sleep timer
            sut.startSleepTimer(option: .custom(seconds: 1))
        }
        
        // Then
        await fulfillment(of: [expectation], timeout: 3.0)
        
        await MainActor.run {
            XCTAssertFalse(sut.isPlaying, "Should stop playing")
        }
    }
    
    // MARK: - Performance Tests
    
    func testPerformance_QueueLargeNumberOfItems() throws {
        measure {
            let expectation = XCTestExpectation(description: "Queue items")
            
            Task {
                // Add 100 items to queue
                for i in 0..<100 {
                    let article = createMockArticle(title: "Article \(i)")
                    await sut.addToQueue(article)
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createMockArticle(
        title: String = "Test Article",
        withContent: String = "This is test content for the article."
    ) -> Article {
        let article = Article(context: context)
        article.id = UUID()
        article.title = title
        article.content = withContent
        article.author = "Test Author"
        article.url = "https://example.com/article"
        article.createdAt = Date()
        article.feed = createMockFeed()
        
        return article
    }
    
    private func createMockFeed() -> Feed {
        let feed = Feed(context: context)
        feed.id = UUID()
        feed.name = "Test Feed"
        feed.url = "https://example.com/feed.xml"
        
        return feed
    }
    
    private func createMockRSSEpisode(
        title: String = "Test Episode",
        withURL: String = "https://example.com/episode.mp3"
    ) -> RSSEpisode {
        let episode = RSSEpisode(context: context)
        episode.id = UUID()
        episode.title = title
        episode.audioUrl = withURL
        episode.pubDate = Date()
        episode.duration = 3600
        episode.feed = createMockRSSFeed()
        
        return episode
    }
    
    private func createMockRSSFeed() -> RSSFeed {
        let feed = RSSFeed(context: context)
        feed.id = UUID()
        feed.displayName = "Test RSS Feed"
        feed.url = "https://example.com/rss.xml"
        feed.isEnabled = true
        
        return feed
    }
}

// MARK: - AudioPlayerState Extension for Testing

extension AudioPlayerState: Equatable {
    public static func == (lhs: AudioPlayerState, rhs: AudioPlayerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.loading, .loading),
             (.playing, .playing),
             (.paused, .paused),
             (.stopped, .stopped):
            return true
        case (.error(_), .error(_)):
            return true // Consider all errors equal for testing
        default:
            return false
        }
    }
}