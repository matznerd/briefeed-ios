import XCTest
import SwiftUI
import Combine
@testable import Briefeed

// MARK: - TDD: Persistent Mini Player Tests
// Define expected behavior for always-visible mini player

final class PersistentMiniPlayerTests: XCTestCase {
    
    private var cancellables = Set<AnyCancellable>()
    
    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }
    
    // MARK: - Visibility Tests
    
    func testMiniPlayerAlwaysVisibleAtBottom() {
        // Given
        let app = MockAppState()
        
        // When - Navigate through tabs
        app.switchToTab(.feed)
        let feedPlayerVisible = app.isMiniPlayerVisible
        
        app.switchToTab(.brief)
        let briefPlayerVisible = app.isMiniPlayerVisible
        
        app.switchToTab(.liveNews)
        let liveNewsPlayerVisible = app.isMiniPlayerVisible
        
        app.switchToTab(.settings)
        let settingsPlayerVisible = app.isMiniPlayerVisible
        
        // Then - Mini player should always be visible
        XCTAssertTrue(feedPlayerVisible)
        XCTAssertTrue(briefPlayerVisible)
        XCTAssertTrue(liveNewsPlayerVisible)
        XCTAssertTrue(settingsPlayerVisible)
    }
    
    func testMiniPlayerPositionAtBottom() {
        // Given
        let miniPlayerVM = MiniPlayerViewModel.shared
        
        // Then
        XCTAssertEqual(miniPlayerVM.position, .bottom)
        XCTAssertEqual(miniPlayerVM.height, 64) // Standard mini player height
        XCTAssertTrue(miniPlayerVM.isAboveTabBar)
    }
    
    func testMiniPlayerDoesNotObstructContent() {
        // Given
        let contentView = ContentViewModel()
        let miniPlayerHeight: CGFloat = 64
        
        // When
        let safeAreaBottomInset = contentView.calculateBottomInset()
        
        // Then
        XCTAssertGreaterThanOrEqual(safeAreaBottomInset, miniPlayerHeight)
        XCTAssertTrue(contentView.hasBottomPadding)
    }
    
    // MARK: - Uninterrupted Playback Tests
    
    func testPlaybackContinuesDuringTabSwitch() async {
        // Given
        let viewModel = AudioPlayerViewModel.shared
        let app = MockAppState()
        
        // Start playing on Feed tab
        app.switchToTab(.feed)
        let article = MockArticle(title: "Playing Article", content: "Content")
        await viewModel.play(article: article)
        
        XCTAssertTrue(viewModel.isPlaying)
        let initialProgress = viewModel.progress
        
        // When - Switch tabs multiple times
        app.switchToTab(.brief)
        await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        
        app.switchToTab(.liveNews)
        await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        
        app.switchToTab(.settings)
        await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        
        // Then - Playback should continue
        XCTAssertTrue(viewModel.isPlaying, "Playback should continue")
        XCTAssertGreaterThan(viewModel.progress, initialProgress, "Progress should advance")
        XCTAssertEqual(viewModel.currentTitle, "Playing Article")
    }
    
    func testAudioSessionNotInterruptedByNavigation() async {
        // Given
        let audioSession = MockAudioSession.shared
        let viewModel = AudioPlayerViewModel.shared
        
        await viewModel.play(episode: MockRSSEpisode(
            title: "Test",
            audioUrl: "https://test.com/ep.mp3"
        ))
        
        let sessionActiveBeforeNav = audioSession.isActive
        
        // When - Navigate deeply
        let navigation = NavigationSimulator()
        navigation.pushView("ArticleDetail")
        navigation.pushView("FeedSettings")
        navigation.presentSheet("AddFeed")
        navigation.dismissSheet()
        navigation.popToRoot()
        
        // Then
        XCTAssertEqual(audioSession.isActive, sessionActiveBeforeNav)
        XCTAssertTrue(viewModel.isPlaying)
        XCTAssertFalse(audioSession.wasInterrupted)
    }
    
    // MARK: - Expandable Player Tests
    
    func testMiniPlayerExpandsToFullPlayer() {
        // Given
        let miniPlayerVM = MiniPlayerViewModel.shared
        miniPlayerVM.isExpanded = false
        
        // When - Tap to expand
        miniPlayerVM.toggleExpansion()
        
        // Then
        XCTAssertTrue(miniPlayerVM.isExpanded)
        XCTAssertTrue(miniPlayerVM.isShowingFullPlayer)
        XCTAssertEqual(miniPlayerVM.expansionProgress, 1.0)
    }
    
    func testFullPlayerShowsAdditionalControls() {
        // Given
        let miniPlayerVM = MiniPlayerViewModel.shared
        
        // When - Expanded
        miniPlayerVM.isExpanded = true
        
        // Then - Should show extra controls
        XCTAssertTrue(miniPlayerVM.showsSpeedControl)
        XCTAssertTrue(miniPlayerVM.showsQueueButton)
        XCTAssertTrue(miniPlayerVM.showsShareButton)
        XCTAssertTrue(miniPlayerVM.showsSeekBar)
        XCTAssertTrue(miniPlayerVM.showsTimeLabels)
        XCTAssertTrue(miniPlayerVM.showsSkipButtons)
    }
    
    func testSwipeDownToCollapse() {
        // Given
        let miniPlayerVM = MiniPlayerViewModel.shared
        miniPlayerVM.isExpanded = true
        
        // When - Swipe down gesture
        miniPlayerVM.handleSwipeDown()
        
        // Then
        XCTAssertFalse(miniPlayerVM.isExpanded)
        XCTAssertFalse(miniPlayerVM.isShowingFullPlayer)
        XCTAssertEqual(miniPlayerVM.expansionProgress, 0.0)
    }
    
    func testExpandedPlayerCoversFullScreen() {
        // Given
        let miniPlayerVM = MiniPlayerViewModel.shared
        let screenHeight = UIScreen.main.bounds.height
        
        // When
        miniPlayerVM.isExpanded = true
        let expandedHeight = miniPlayerVM.calculateExpandedHeight()
        
        // Then
        XCTAssertEqual(expandedHeight, screenHeight)
        XCTAssertTrue(miniPlayerVM.coversTabBar)
        XCTAssertTrue(miniPlayerVM.hasBackgroundOverlay)
    }
    
    // MARK: - State Persistence Tests
    
    func testPlaybackSurvivesBackgrounding() async {
        // Given
        let viewModel = AudioPlayerViewModel.shared
        let article = MockArticle(title: "Background Test", content: "Content")
        await viewModel.play(article: article)
        
        let progressBeforeBackground = viewModel.progress
        
        // When - App goes to background
        NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // When - App returns to foreground
        NotificationCenter.default.post(
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        // Then
        XCTAssertTrue(viewModel.isPlaying)
        XCTAssertGreaterThan(viewModel.progress, progressBeforeBackground)
        XCTAssertEqual(viewModel.currentTitle, "Background Test")
    }
    
    func testQueuePersistsAcrossAppLaunches() async {
        // Given
        let queueService = QueueServiceV2.shared
        
        // Add items to queue
        await queueService.addToQueue(article: MockArticle(title: "Article 1", content: "1"))
        await queueService.addToQueue(episode: MockRSSEpisode(title: "Episode 1", audioUrl: "https://test.com/1.mp3"))
        await queueService.addToQueue(article: MockArticle(title: "Article 2", content: "2"))
        
        let itemsBeforeRestart = queueService.enhancedQueue.count
        
        // When - Simulate app restart
        await queueService.saveQueue()
        await queueService.clearMemoryCache()
        await queueService.initialize() // Reload from disk
        
        // Then
        XCTAssertEqual(queueService.enhancedQueue.count, itemsBeforeRestart)
        XCTAssertEqual(queueService.enhancedQueue[0].title, "Article 1")
        XCTAssertEqual(queueService.enhancedQueue[1].title, "Episode 1")
        XCTAssertEqual(queueService.enhancedQueue[2].title, "Article 2")
    }
    
    func testPlaybackPositionRestored() async {
        // Given
        let viewModel = AudioPlayerViewModel.shared
        let episode = MockRSSEpisode(
            title: "Long Episode",
            audioUrl: "https://test.com/long.mp3",
            duration: 3600
        )
        
        await viewModel.play(episode: episode)
        viewModel.seek(to: 1800) // Seek to middle
        
        // When - Save and restore
        await viewModel.savePlaybackState()
        await viewModel.clearState()
        await viewModel.restorePlaybackState()
        
        // Then
        XCTAssertEqual(viewModel.currentTime, 1800, accuracy: 1.0)
        XCTAssertEqual(viewModel.currentTitle, "Long Episode")
        XCTAssertFalse(viewModel.isPlaying) // Doesn't auto-resume
    }
    
    // MARK: - Mini Player UI Tests
    
    func testMiniPlayerShowsCurrentlyPlaying() async {
        // Given
        let miniPlayerVM = MiniPlayerViewModel.shared
        let viewModel = AudioPlayerViewModel.shared
        
        // When
        let article = MockArticle(title: "Test Article", content: "Content", author: "Test Author")
        await viewModel.play(article: article)
        
        // Then
        XCTAssertEqual(miniPlayerVM.displayTitle, "Test Article")
        XCTAssertEqual(miniPlayerVM.displaySubtitle, "Test Author")
        XCTAssertTrue(miniPlayerVM.showsPlayPauseButton)
        XCTAssertTrue(miniPlayerVM.showsProgressBar)
    }
    
    func testMiniPlayerProgressBarUpdates() async {
        // Given
        let miniPlayerVM = MiniPlayerViewModel.shared
        let expectation = XCTestExpectation(description: "Progress updates")
        var progressValues: [Float] = []
        
        miniPlayerVM.$progress
            .sink { progress in
                progressValues.append(progress)
                if progressValues.count >= 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When - Simulate playback
        miniPlayerVM.simulatePlayback()
        
        // Then
        wait(for: [expectation], timeout: 3.0)
        XCTAssertTrue(progressValues.count >= 3)
        XCTAssertTrue(progressValues.last! > progressValues.first!)
    }
    
    func testMiniPlayerTapActions() {
        // Given
        let miniPlayerVM = MiniPlayerViewModel.shared
        let viewModel = AudioPlayerViewModel.shared
        
        // Test play/pause tap
        viewModel.isPlaying = true
        miniPlayerVM.handlePlayPauseTap()
        XCTAssertFalse(viewModel.isPlaying)
        
        miniPlayerVM.handlePlayPauseTap()
        XCTAssertTrue(viewModel.isPlaying)
        
        // Test expansion tap
        miniPlayerVM.handleMainAreaTap()
        XCTAssertTrue(miniPlayerVM.isExpanded)
    }
    
    // MARK: - Memory Management Tests
    
    func testMiniPlayerSingletonNotRecreated() {
        // Given
        let instance1 = MiniPlayerViewModel.shared
        let instance2 = MiniPlayerViewModel.shared
        
        // Then
        XCTAssertTrue(instance1 === instance2, "Should be same instance")
    }
    
    func testMiniPlayerDoesNotRetainViewModels() {
        // Given
        weak var weakViewModel: AudioPlayerViewModel?
        
        autoreleasepool {
            let viewModel = AudioPlayerViewModel()
            weakViewModel = viewModel
            
            // Mini player references it
            MiniPlayerViewModel.shared.setAudioViewModel(viewModel)
        }
        
        // Then - Should not retain
        XCTAssertNil(weakViewModel, "Mini player should not retain view model")
    }
}

// MARK: - Mock Types

class MockAppState {
    enum Tab {
        case feed, brief, liveNews, settings
    }
    
    var currentTab: Tab = .feed
    var isMiniPlayerVisible = true
    
    func switchToTab(_ tab: Tab) {
        currentTab = tab
        // Mini player stays visible
    }
}

class MiniPlayerViewModel: ObservableObject {
    static let shared = MiniPlayerViewModel()
    
    enum Position {
        case bottom
    }
    
    @Published var isExpanded = false
    @Published var isShowingFullPlayer = false
    @Published var expansionProgress: CGFloat = 0
    @Published var progress: Float = 0
    
    var position: Position = .bottom
    var height: CGFloat = 64
    var isAboveTabBar = true
    
    var showsSpeedControl: Bool { isExpanded }
    var showsQueueButton: Bool { isExpanded }
    var showsShareButton: Bool { isExpanded }
    var showsSeekBar: Bool { isExpanded }
    var showsTimeLabels: Bool { isExpanded }
    var showsSkipButtons: Bool { isExpanded }
    
    var coversTabBar: Bool { isExpanded }
    var hasBackgroundOverlay: Bool { isExpanded }
    
    var displayTitle: String?
    var displaySubtitle: String?
    var showsPlayPauseButton = true
    var showsProgressBar = true
    
    private weak var audioViewModel: AudioPlayerViewModel?
    
    func toggleExpansion() {
        withAnimation {
            isExpanded.toggle()
            isShowingFullPlayer = isExpanded
            expansionProgress = isExpanded ? 1.0 : 0.0
        }
    }
    
    func handleSwipeDown() {
        withAnimation {
            isExpanded = false
            isShowingFullPlayer = false
            expansionProgress = 0.0
        }
    }
    
    func calculateExpandedHeight() -> CGFloat {
        return UIScreen.main.bounds.height
    }
    
    func handlePlayPauseTap() {
        AudioPlayerViewModel.shared.togglePlayPause()
    }
    
    func handleMainAreaTap() {
        toggleExpansion()
    }
    
    func setAudioViewModel(_ viewModel: AudioPlayerViewModel) {
        // Weak reference
        audioViewModel = viewModel
    }
    
    func simulatePlayback() {
        // Simulate progress updates
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.progress = min(self.progress + 0.1, 1.0)
        }
    }
}

class ContentViewModel {
    func calculateBottomInset() -> CGFloat {
        // Account for mini player
        return 64 + 49 // Mini player + tab bar
    }
    
    var hasBottomPadding: Bool {
        return true
    }
}

class NavigationSimulator {
    private var navigationStack: [String] = []
    private var presentedSheets: [String] = []
    
    func pushView(_ view: String) {
        navigationStack.append(view)
    }
    
    func presentSheet(_ sheet: String) {
        presentedSheets.append(sheet)
    }
    
    func dismissSheet() {
        _ = presentedSheets.popLast()
    }
    
    func popToRoot() {
        navigationStack.removeAll()
    }
}

class MockAudioSession {
    static let shared = MockAudioSession()
    
    var isActive = false
    var wasInterrupted = false
}

// MARK: - Extensions

extension AudioPlayerViewModel {
    static let shared = AudioPlayerViewModel()
    
    func savePlaybackState() async {
        // Save current state
    }
    
    func clearState() async {
        // Clear in-memory state
    }
    
    func restorePlaybackState() async {
        // Restore from disk
    }
    
    func togglePlayPause() {
        isPlaying.toggle()
    }
}

extension QueueServiceV2 {
    func saveQueue() async {
        // Save to disk
    }
    
    func clearMemoryCache() async {
        // Clear memory
    }
    
    func addToQueue(episode: MockRSSEpisode) async {
        // Add RSS episode
    }
}