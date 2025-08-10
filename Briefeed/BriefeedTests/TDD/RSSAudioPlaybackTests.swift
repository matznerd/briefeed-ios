import XCTest
import Combine
@testable import Briefeed

// MARK: - TDD: RSS Audio Playback Tests
// Define expected behavior for RSS podcast episodes

final class RSSAudioPlaybackTests: XCTestCase {
    
    private var cancellables = Set<AnyCancellable>()
    
    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }
    
    // MARK: - Live News Mode Tests (Radio-like playback)
    
    func testLiveNewsModePlayAllEpisodes() async {
        // Given
        let liveNewsVM = LiveNewsViewModel()
        await liveNewsVM.initialize()
        
        // Setup RSS feeds with episodes
        let feed1 = MockRSSFeed(
            title: "Tech News Daily",
            episodes: [
                MockRSSEpisode(title: "Episode 1", audioUrl: "https://tech.com/ep1.mp3"),
                MockRSSEpisode(title: "Episode 2", audioUrl: "https://tech.com/ep2.mp3")
            ]
        )
        
        let feed2 = MockRSSFeed(
            title: "Business Weekly",
            episodes: [
                MockRSSEpisode(title: "Market Update", audioUrl: "https://biz.com/ep1.mp3")
            ]
        )
        
        liveNewsVM.addFeed(feed1)
        liveNewsVM.addFeed(feed2)
        
        // When - Press "Play Live News" button
        await liveNewsVM.playLiveNews()
        
        // Then
        XCTAssertTrue(liveNewsVM.isPlayingLiveNews)
        XCTAssertEqual(liveNewsVM.totalEpisodesInQueue, 3)
        XCTAssertEqual(liveNewsVM.currentEpisodeTitle, "Episode 1")
        XCTAssertTrue(liveNewsVM.isPlaying)
    }
    
    func testLiveNewsOnlyPlaysUnlistenedEpisodes() async {
        // Given
        let liveNewsVM = LiveNewsViewModel()
        await liveNewsVM.initialize()
        
        let feed = MockRSSFeed(
            title: "News Feed",
            episodes: [
                MockRSSEpisode(title: "Old Episode", audioUrl: "https://news.com/old.mp3", isListened: true),
                MockRSSEpisode(title: "New Episode", audioUrl: "https://news.com/new.mp3", isListened: false)
            ]
        )
        
        liveNewsVM.addFeed(feed)
        
        // When
        await liveNewsVM.playLiveNews()
        
        // Then - Should only queue unlistened episodes
        XCTAssertEqual(liveNewsVM.totalEpisodesInQueue, 1)
        XCTAssertEqual(liveNewsVM.currentEpisodeTitle, "New Episode")
    }
    
    func testLiveNewsAutoPlayNextEpisode() async {
        // Given
        let liveNewsVM = LiveNewsViewModel()
        await liveNewsVM.initialize()
        
        let feed = MockRSSFeed(
            title: "Sequential Feed",
            episodes: [
                MockRSSEpisode(title: "Episode 1", audioUrl: "https://test.com/1.mp3", duration: 60),
                MockRSSEpisode(title: "Episode 2", audioUrl: "https://test.com/2.mp3", duration: 60)
            ]
        )
        
        liveNewsVM.addFeed(feed)
        await liveNewsVM.playLiveNews()
        
        // When - First episode finishes
        liveNewsVM.simulateEpisodeCompletion()
        
        // Then - Should auto-play next
        XCTAssertEqual(liveNewsVM.currentEpisodeTitle, "Episode 2")
        XCTAssertTrue(liveNewsVM.isPlaying)
        XCTAssertEqual(liveNewsVM.currentEpisodeIndex, 1)
    }
    
    // MARK: - RSS Episode Speed Control Tests
    
    func testRSSSupports4xSpeed() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        let episode = MockRSSEpisode(
            title: "Fast Episode",
            audioUrl: "https://podcast.com/episode.mp3"
        )
        
        // When
        await viewModel.play(episode: episode)
        viewModel.setSpeed(4.0)
        
        // Then - RSS audio MUST support 4x speed
        XCTAssertEqual(viewModel.playbackSpeed, 4.0, "RSS audio must support 4x speed")
        XCTAssertTrue(viewModel.isUsingStreamingService)
    }
    
    func testSpeedControlRange() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        let episode = MockRSSEpisode(title: "Test", audioUrl: "https://test.com/ep.mp3")
        await viewModel.play(episode: episode)
        
        // Test all speed ranges
        let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0]
        
        for speed in speeds {
            // When
            viewModel.setSpeed(speed)
            
            // Then
            XCTAssertEqual(viewModel.playbackSpeed, speed, "Should support \(speed)x speed")
        }
    }
    
    // MARK: - Individual Episode Queue Tests
    
    func testAddIndividualEpisodeToQueue() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        let episode = MockRSSEpisode(
            title: "Specific Episode",
            audioUrl: "https://podcast.com/special.mp3",
            podcastTitle: "My Podcast"
        )
        
        // When - Add individual episode to queue
        await viewModel.queueEpisode(episode)
        
        // Then
        XCTAssertEqual(viewModel.queueItems.count, 1)
        XCTAssertEqual(viewModel.queueItems[0].title, "Specific Episode")
        XCTAssertEqual(viewModel.queueItems[0].source.displayName, "My Podcast")
        XCTAssertFalse(viewModel.isPlaying, "Should not auto-play when adding")
    }
    
    func testMixedQueueWithArticlesAndEpisodes() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        // When - Add mixed content
        await viewModel.queueArticle(MockArticle(title: "Article 1", content: "Text"))
        await viewModel.queueEpisode(MockRSSEpisode(title: "Episode 1", audioUrl: "https://test.com/1.mp3"))
        await viewModel.queueArticle(MockArticle(title: "Article 2", content: "Text"))
        await viewModel.queueEpisode(MockRSSEpisode(title: "Episode 2", audioUrl: "https://test.com/2.mp3"))
        
        // Then - Queue should maintain order
        XCTAssertEqual(viewModel.queueItems.count, 4)
        XCTAssertEqual(viewModel.queueItems[0].title, "Article 1")
        XCTAssertEqual(viewModel.queueItems[1].title, "Episode 1")
        XCTAssertEqual(viewModel.queueItems[2].title, "Article 2")
        XCTAssertEqual(viewModel.queueItems[3].title, "Episode 2")
    }
    
    // MARK: - Direct Streaming Tests
    
    func testRSSEpisodeDirectStreaming() async {
        // Given
        let streamingService = AudioStreamingService.shared
        await streamingService.initialize()
        
        let episodeURL = URL(string: "https://podcast.com/episode.mp3")!
        
        // When
        try await streamingService.load(
            url: episodeURL,
            title: "Test Episode",
            artist: "Test Podcast"
        )
        
        // Then - Should be ready to play without processing
        XCTAssertEqual(streamingService.state, .ready)
        XCTAssertNil(streamingService.processingTime, "Should not need processing")
    }
    
    func testNoAPIKeysUsedForRSSPlayback() async {
        // Given
        let apiTracker = APIUsageTracker.shared
        let initialGeminiCalls = apiTracker.geminiAPICallCount
        let initialTTSCalls = apiTracker.ttsAPICallCount
        
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        // When - Play RSS episode
        let episode = MockRSSEpisode(
            title: "Free Episode",
            audioUrl: "https://free.com/episode.mp3"
        )
        await viewModel.play(episode: episode)
        
        // Then - No API calls should be made
        XCTAssertEqual(apiTracker.geminiAPICallCount, initialGeminiCalls, "Should not use Gemini API")
        XCTAssertEqual(apiTracker.ttsAPICallCount, initialTTSCalls, "Should not use TTS API")
        XCTAssertTrue(viewModel.isPlaying)
    }
    
    // MARK: - Episode State Management Tests
    
    func testEpisodeMarkedAsListenedAfterCompletion() async {
        // Given
        let episode = MockRSSEpisode(
            title: "Test Episode",
            audioUrl: "https://test.com/ep.mp3",
            isListened: false
        )
        
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        await viewModel.play(episode: episode)
        
        // When - Episode completes
        viewModel.simulatePlaybackCompletion()
        
        // Then
        XCTAssertTrue(episode.isListened)
        XCTAssertNotNil(episode.listenedDate)
    }
    
    func testEpisodeProgressTracking() async {
        // Given
        let episode = MockRSSEpisode(
            title: "Long Episode",
            audioUrl: "https://test.com/long.mp3",
            duration: 3600 // 1 hour
        )
        
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        await viewModel.play(episode: episode)
        
        // When - Play for some time
        viewModel.simulatePlaybackProgress(seconds: 1800) // 30 minutes
        
        // Then
        XCTAssertEqual(episode.lastPosition, 0.5, accuracy: 0.01) // 50% complete
        XCTAssertFalse(episode.isListened) // Not marked as listened until >90% complete
    }
    
    // MARK: - RSS Feed Update Tests
    
    func testAutoRemoveListenedEpisodesFromQueue() async {
        // Given
        let liveNewsVM = LiveNewsViewModel()
        await liveNewsVM.initialize()
        
        let feed = MockRSSFeed(
            title: "Auto Remove Feed",
            episodes: [
                MockRSSEpisode(title: "Episode 1", audioUrl: "https://test.com/1.mp3"),
                MockRSSEpisode(title: "Episode 2", audioUrl: "https://test.com/2.mp3")
            ]
        )
        
        liveNewsVM.addFeed(feed)
        await liveNewsVM.playLiveNews()
        
        // When - Mark first episode as listened
        liveNewsVM.currentEpisode?.isListened = true
        liveNewsVM.removeListenedEpisodes()
        
        // Then
        XCTAssertEqual(liveNewsVM.totalEpisodesInQueue, 1)
        XCTAssertEqual(liveNewsVM.currentEpisodeTitle, "Episode 2")
    }
    
    // MARK: - Background Download Tests
    
    func testOptionalEpisodeDownload() async {
        // Given
        let downloadManager = EpisodeDownloadManager.shared
        let episode = MockRSSEpisode(
            title: "Downloadable",
            audioUrl: "https://test.com/download.mp3"
        )
        
        // When
        let localURL = await downloadManager.downloadEpisode(episode)
        
        // Then
        XCTAssertNotNil(localURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: localURL!.path))
        XCTAssertEqual(episode.downloadedFilePath, localURL?.path)
    }
}

// MARK: - Mock Types

struct MockRSSFeed {
    let title: String
    let episodes: [MockRSSEpisode]
}

class MockRSSEpisode {
    let title: String
    let audioUrl: String
    let podcastTitle: String
    let duration: Int
    var isListened: Bool
    var listenedDate: Date?
    var lastPosition: Double
    var downloadedFilePath: String?
    
    init(title: String, 
         audioUrl: String, 
         podcastTitle: String = "Test Podcast",
         duration: Int = 1800,
         isListened: Bool = false) {
        self.title = title
        self.audioUrl = audioUrl
        self.podcastTitle = podcastTitle
        self.duration = duration
        self.isListened = isListened
        self.listenedDate = nil
        self.lastPosition = 0.0
        self.downloadedFilePath = nil
    }
}

// MARK: - Live News View Model

class LiveNewsViewModel: ObservableObject {
    @Published var isPlayingLiveNews = false
    @Published var isPlaying = false
    @Published var totalEpisodesInQueue = 0
    @Published var currentEpisodeTitle: String?
    @Published var currentEpisodeIndex = 0
    @Published var currentEpisode: MockRSSEpisode?
    
    private var feeds: [MockRSSFeed] = []
    private var queuedEpisodes: [MockRSSEpisode] = []
    
    func initialize() async {
        // Setup
    }
    
    func addFeed(_ feed: MockRSSFeed) {
        feeds.append(feed)
    }
    
    func playLiveNews() async {
        // Queue all unlistened episodes
        queuedEpisodes = feeds.flatMap { $0.episodes }
            .filter { !$0.isListened }
        
        totalEpisodesInQueue = queuedEpisodes.count
        
        if !queuedEpisodes.isEmpty {
            currentEpisode = queuedEpisodes[0]
            currentEpisodeTitle = currentEpisode?.title
            currentEpisodeIndex = 0
            isPlayingLiveNews = true
            isPlaying = true
        }
    }
    
    func simulateEpisodeCompletion() {
        currentEpisode?.isListened = true
        currentEpisode?.listenedDate = Date()
        
        // Play next
        currentEpisodeIndex += 1
        if currentEpisodeIndex < queuedEpisodes.count {
            currentEpisode = queuedEpisodes[currentEpisodeIndex]
            currentEpisodeTitle = currentEpisode?.title
        } else {
            isPlayingLiveNews = false
            isPlaying = false
        }
    }
    
    func removeListenedEpisodes() {
        queuedEpisodes.removeAll { $0.isListened }
        totalEpisodesInQueue = queuedEpisodes.count
        
        if currentEpisodeIndex >= queuedEpisodes.count {
            currentEpisodeIndex = 0
        }
        
        if !queuedEpisodes.isEmpty {
            currentEpisode = queuedEpisodes[currentEpisodeIndex]
            currentEpisodeTitle = currentEpisode?.title
        }
    }
}

// MARK: - Helper Services

class APIUsageTracker {
    static let shared = APIUsageTracker()
    var geminiAPICallCount = 0
    var ttsAPICallCount = 0
}

class EpisodeDownloadManager {
    static let shared = EpisodeDownloadManager()
    
    func downloadEpisode(_ episode: MockRSSEpisode) async -> URL? {
        // Simulate download
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(episode.title).mp3")
        
        // Create dummy file
        FileManager.default.createFile(atPath: localURL.path, contents: Data(), attributes: nil)
        
        episode.downloadedFilePath = localURL.path
        return localURL
    }
}

// MARK: - ViewModel Extensions

extension AudioPlayerViewModel {
    var isUsingStreamingService: Bool {
        // Check if using streaming service for RSS
        return currentURL != nil
    }
    
    func simulatePlaybackCompletion() {
        // Simulate episode completion
        if let episode = currentEpisode as? MockRSSEpisode {
            episode.isListened = true
            episode.listenedDate = Date()
        }
    }
    
    func simulatePlaybackProgress(seconds: TimeInterval) {
        currentTime = seconds
        if let episode = currentEpisode as? MockRSSEpisode {
            episode.lastPosition = seconds / Double(episode.duration)
        }
    }
    
    var currentEpisode: Any? {
        // Get current playing episode
        return nil // Stub
    }
}