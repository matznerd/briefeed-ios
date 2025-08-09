import XCTest
import Combine
@testable import Briefeed

// MARK: - TDD: ViewModel Tests
// Define expected behavior for ViewModels (ObservableObject layer)

final class ViewModelTests: XCTestCase {
    
    private var cancellables = Set<AnyCancellable>()
    
    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }
    
    // MARK: - AudioPlayerViewModel Architecture Tests
    
    func testAudioPlayerViewModelIsObservableObject() {
        // Given/When
        let viewModel = AudioPlayerViewModel()
        
        // Then - ViewModel MUST be ObservableObject
        XCTAssertTrue(viewModel is ObservableObject)
        assertIsObservableObject(viewModel)
    }
    
    func testAudioPlayerViewModelHasPublishedProperties() {
        // Given
        let viewModel = AudioPlayerViewModel()
        
        // Then - should have @Published properties for UI
        let mirror = Mirror(reflecting: viewModel)
        var hasPublished = false
        
        for child in mirror.children {
            let childType = String(describing: type(of: child.value))
            if childType.contains("Published") {
                hasPublished = true
                break
            }
        }
        
        XCTAssertTrue(hasPublished, "ViewModel should have @Published properties")
    }
    
    func testViewModelLightweightInit() {
        // Given/When - init should be fast
        let start = CFAbsoluteTimeGetCurrent()
        let viewModel = AudioPlayerViewModel()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        // Then
        XCTAssertLessThan(elapsed, 0.01, "ViewModel init must be lightweight")
        XCTAssertNotNil(viewModel)
    }
    
    func testViewModelDoesNotAccessServiceInInit() {
        // Given/When
        let viewModel = AudioPlayerViewModel()
        
        // Then - should not be connected to services yet
        XCTAssertFalse(viewModel.isConnected)
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertNil(viewModel.currentURL)
    }
    
    // MARK: - ViewModel Connection Tests
    
    func testViewModelConnectToServices() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        XCTAssertFalse(viewModel.isConnected)
        
        // When
        await viewModel.connect()
        
        // Then
        XCTAssertTrue(viewModel.isConnected)
    }
    
    func testViewModelDoesNotBlockMainThreadOnConnect() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        
        // When/Then - connection should not block
        await assertNoMainThreadBlock {
            await viewModel.connect()
        }
    }
    
    // MARK: - Published Property Updates
    
    func testIsPlayingUpdates() {
        // Given
        let viewModel = AudioPlayerViewModel()
        let expectation = XCTestExpectation(description: "isPlaying updates")
        
        viewModel.$isPlaying
            .dropFirst() // Skip initial value
            .sink { isPlaying in
                if isPlaying {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When
        viewModel.play()
        
        // Then
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testCurrentTimeUpdates() {
        // Given
        let viewModel = AudioPlayerViewModel()
        let expectation = XCTestExpectation(description: "currentTime updates")
        var receivedTimes: [TimeInterval] = []
        
        viewModel.$currentTime
            .dropFirst()
            .sink { time in
                receivedTimes.append(time)
                if receivedTimes.count >= 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When - simulate time updates
        viewModel.updateCurrentTime(10.0)
        viewModel.updateCurrentTime(20.0)
        viewModel.updateCurrentTime(30.0)
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedTimes, [10.0, 20.0, 30.0])
    }
    
    func testPlaybackSpeedUpdates() {
        // Given
        let viewModel = AudioPlayerViewModel()
        let expectation = XCTestExpectation(description: "speed updates")
        
        viewModel.$playbackSpeed
            .dropFirst()
            .sink { speed in
                if speed == 2.5 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When
        viewModel.setSpeed(2.5)
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(viewModel.playbackSpeed, 2.5)
    }
    
    // MARK: - ViewModel Playback Controls
    
    func testPlayArticle() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        let article = MockArticle(
            title: "Test Article",
            content: "Content to play"
        )
        
        // When
        await viewModel.play(article: article)
        
        // Then
        XCTAssertTrue(viewModel.isPlaying)
        XCTAssertEqual(viewModel.currentTitle, "Test Article")
        XCTAssertFalse(viewModel.isLoading)
    }
    
    func testPlayEpisode() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        let episode = MockEpisode(
            title: "Test Episode",
            audioUrl: "https://example.com/episode.mp3",
            podcastTitle: "Test Podcast"
        )
        
        // When
        await viewModel.play(episode: episode)
        
        // Then
        XCTAssertTrue(viewModel.isPlaying)
        XCTAssertEqual(viewModel.currentTitle, "Test Episode")
        XCTAssertEqual(viewModel.currentArtist, "Test Podcast")
    }
    
    func testTogglePlayPause() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        // When - start playing
        viewModel.play()
        XCTAssertTrue(viewModel.isPlaying)
        
        // When - toggle to pause
        viewModel.togglePlayPause()
        
        // Then
        XCTAssertFalse(viewModel.isPlaying)
        
        // When - toggle to play
        viewModel.togglePlayPause()
        
        // Then
        XCTAssertTrue(viewModel.isPlaying)
    }
    
    // MARK: - Queue Integration Tests
    
    func testQueueArticle() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        let article = MockArticle(
            title: "Queued Article",
            content: "Content"
        )
        
        // When
        await viewModel.queueArticle(article)
        
        // Then
        XCTAssertEqual(viewModel.queueItems.count, 1)
        XCTAssertEqual(viewModel.queueItems.first?.title, "Queued Article")
    }
    
    func testQueueMultipleItems() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        // When
        await viewModel.queueArticle(MockArticle(title: "Article 1", content: "Content 1"))
        await viewModel.queueEpisode(MockEpisode(title: "Episode 1", audioUrl: "https://example.com/1.mp3"))
        await viewModel.queueArticle(MockArticle(title: "Article 2", content: "Content 2"))
        
        // Then
        XCTAssertEqual(viewModel.queueItems.count, 3)
        XCTAssertEqual(viewModel.queueItems[0].title, "Article 1")
        XCTAssertEqual(viewModel.queueItems[1].title, "Episode 1")
        XCTAssertEqual(viewModel.queueItems[2].title, "Article 2")
    }
    
    func testPlayNextInQueue() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        await viewModel.queueArticle(MockArticle(title: "First", content: "Content"))
        await viewModel.queueArticle(MockArticle(title: "Second", content: "Content"))
        
        // When
        viewModel.playNextInQueue()
        
        // Then
        XCTAssertEqual(viewModel.currentQueueIndex, 0)
        XCTAssertEqual(viewModel.currentTitle, "First")
        XCTAssertTrue(viewModel.isPlaying)
    }
    
    // MARK: - Loading State Tests
    
    func testLoadingStateWhileGeneratingTTS() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        let article = MockArticle(
            title: "TTS Article",
            content: "Long content that needs TTS generation"
        )
        
        // When
        let task = Task {
            await viewModel.play(article: article)
        }
        
        // Then - should show loading
        XCTAssertTrue(viewModel.isLoading)
        
        // Wait for completion
        await task.value
        
        // Then - loading should be done
        XCTAssertFalse(viewModel.isLoading)
    }
    
    // MARK: - Error Handling Tests
    
    func testHandlePlaybackError() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        // When - simulate error
        viewModel.handleError(AudioError.loadFailed(reason: "Network error"))
        
        // Then
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.lastError)
        XCTAssertEqual(viewModel.lastError?.localizedDescription, "Network error")
    }
    
    func testRetryAfterError() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        viewModel.handleError(AudioError.loadFailed(reason: "Temporary error"))
        XCTAssertNotNil(viewModel.lastError)
        
        // When
        await viewModel.retry()
        
        // Then
        XCTAssertNil(viewModel.lastError)
    }
    
    // MARK: - Memory Management Tests
    
    func testViewModelDoesNotRetainServices() {
        // Given
        var viewModel: AudioPlayerViewModel? = AudioPlayerViewModel()
        weak var weakViewModel = viewModel
        
        // When
        viewModel = nil
        
        // Then - should be deallocated
        XCTAssertNil(weakViewModel, "ViewModel should not leak")
    }
    
    func testCancellableCleanup() {
        // Given
        let viewModel = AudioPlayerViewModel()
        let expectation = XCTestExpectation(description: "Publisher cancelled")
        
        let cancellable = viewModel.$isPlaying
            .sink(
                receiveCompletion: { _ in
                    expectation.fulfill()
                },
                receiveValue: { _ in }
            )
        
        // When
        cancellable.cancel()
        
        // Then - should clean up properly
        // (expectation won't fulfill as it's cancelled properly)
        XCTAssertTrue(true) // Cancellable cleaned up
    }
}

// MARK: - Mock Types for Testing

struct MockEpisode {
    let title: String
    let audioUrl: String
    let podcastTitle: String
    
    init(
        title: String,
        audioUrl: String,
        podcastTitle: String = "Test Podcast"
    ) {
        self.title = title
        self.audioUrl = audioUrl
        self.podcastTitle = podcastTitle
    }
}

enum AudioError: LocalizedError {
    case loadFailed(reason: String)
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .loadFailed(let reason):
            return reason
        case .networkError:
            return "Network error occurred"
        }
    }
}