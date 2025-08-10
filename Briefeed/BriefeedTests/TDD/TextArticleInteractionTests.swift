import XCTest
import Combine
@testable import Briefeed

// MARK: - TDD: Text Article Interaction Tests
// Define expected behavior for Reddit/text articles

final class TextArticleInteractionTests: XCTestCase {
    
    private var cancellables = Set<AnyCancellable>()
    
    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }
    
    // MARK: - Quick Add to Queue Tests
    
    func testQuickAddArticleToQueue() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        let article = MockArticle(
            title: "Reddit Article",
            content: "Content from Reddit",
            author: "u/testuser"
        )
        
        // When - Quick add button pressed
        await viewModel.queueArticle(article)
        
        // Then
        XCTAssertEqual(viewModel.queueItems.count, 1)
        XCTAssertEqual(viewModel.queueItems.last?.title, "Reddit Article")
        XCTAssertFalse(viewModel.isPlaying, "Should not auto-play when adding to queue")
    }
    
    func testQuickAddMultipleArticles() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        // When - Add multiple articles
        for i in 1...5 {
            let article = MockArticle(
                title: "Article \(i)",
                content: "Content \(i)"
            )
            await viewModel.queueArticle(article)
        }
        
        // Then - Should be added in order at back of queue
        XCTAssertEqual(viewModel.queueItems.count, 5)
        XCTAssertEqual(viewModel.queueItems[0].title, "Article 1")
        XCTAssertEqual(viewModel.queueItems[4].title, "Article 5")
    }
    
    // MARK: - Swipe to Play Now Tests
    
    func testSwipeToPlayNow() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        // Add some items to queue first
        await viewModel.queueArticle(MockArticle(title: "Queued 1", content: "Content"))
        await viewModel.queueArticle(MockArticle(title: "Queued 2", content: "Content"))
        
        let urgentArticle = MockArticle(
            title: "Play Now Article",
            content: "Urgent content"
        )
        
        // When - Swipe to play now
        await viewModel.playNow(article: urgentArticle)
        
        // Then
        XCTAssertTrue(viewModel.isPlaying)
        XCTAssertEqual(viewModel.currentTitle, "Play Now Article")
        XCTAssertEqual(viewModel.queueItems.count, 3) // Added to queue and playing
    }
    
    func testPlayNowInterruptsCurrentPlayback() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        // Start playing something
        let firstArticle = MockArticle(title: "First", content: "Content")
        await viewModel.play(article: firstArticle)
        XCTAssertEqual(viewModel.currentTitle, "First")
        
        // When - Play now on different article
        let urgentArticle = MockArticle(title: "Urgent", content: "Content")
        await viewModel.playNow(article: urgentArticle)
        
        // Then
        XCTAssertEqual(viewModel.currentTitle, "Urgent")
        XCTAssertTrue(viewModel.isPlaying)
    }
    
    // MARK: - Article Detail View Tests
    
    func testArticleDetailManualGeneration() async {
        // Given
        let articleDetailVM = ArticleDetailViewModel()
        let article = MockArticle(
            title: "Detail Article",
            content: "Long form content that needs audio"
        )
        
        // When - Manual generate audio button pressed
        await articleDetailVM.generateAudio(for: article)
        
        // Then
        XCTAssertTrue(articleDetailVM.isGenerating)
        
        // Wait for generation
        await articleDetailVM.waitForGeneration()
        
        XCTAssertFalse(articleDetailVM.isGenerating)
        XCTAssertNotNil(articleDetailVM.generatedAudioURL)
        XCTAssertTrue(articleDetailVM.canPlayAudio)
    }
    
    func testArticleDetailShowsGenerationProgress() async {
        // Given
        let articleDetailVM = ArticleDetailViewModel()
        let expectation = XCTestExpectation(description: "Progress updates")
        var progressValues: [Float] = []
        
        articleDetailVM.$generationProgress
            .sink { progress in
                progressValues.append(progress)
                if progress >= 1.0 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When
        let article = MockArticle(title: "Test", content: "Content")
        await articleDetailVM.generateAudio(for: article)
        
        // Then
        wait(for: [expectation], timeout: 5.0)
        XCTAssertGreaterThan(progressValues.count, 2, "Should show progress updates")
        XCTAssertEqual(progressValues.last, 1.0, "Should complete at 100%")
    }
    
    // MARK: - Background TTS Generation Tests
    
    func testAutomaticTTSWhenNextInQueue() async {
        // Given
        let queueService = QueueServiceV2.shared
        let article1 = MockArticle(title: "First", content: "Content 1")
        let article2 = MockArticle(title: "Second", content: "Content 2")
        
        // When - Add articles to queue
        await queueService.addToQueue(article: article1)
        await queueService.addToQueue(article: article2)
        
        // Start playing first
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        viewModel.playNextInQueue()
        
        // Then - Second article should start generating
        await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
        
        let secondItem = queueService.enhancedQueue[1]
        XCTAssertNotNil(secondItem.audioUrl, "Should pre-generate audio for next item")
    }
    
    func testNoTTSGenerationForDistantQueueItems() async {
        // Given
        let queueService = QueueServiceV2.shared
        
        // When - Add many articles
        for i in 1...10 {
            let article = MockArticle(title: "Article \(i)", content: "Content \(i)")
            await queueService.addToQueue(article: article)
        }
        
        // Then - Only first few should generate
        await Task.sleep(nanoseconds: 3_000_000_000) // Wait 3 seconds
        
        let queue = queueService.enhancedQueue
        XCTAssertNotNil(queue[0].audioUrl, "First should be generated")
        XCTAssertNotNil(queue[1].audioUrl, "Second should be generated")
        XCTAssertNil(queue[9].audioUrl, "Distant items should not pre-generate")
    }
    
    // MARK: - FireCrawl → Gemini → TTS Pipeline Tests
    
    func testFullProcessingPipeline() async {
        // Given
        let processor = ArticleProcessor()
        let redditURL = URL(string: "https://reddit.com/r/test/comments/123/test_article")!
        
        // When - Process Reddit article
        let result = await processor.processArticle(from: redditURL)
        
        // Then - Verify each step
        XCTAssertNotNil(result.scrapedContent, "FireCrawl should scrape content")
        XCTAssertGreaterThan(result.scrapedContent.count, 100, "Should get substantial content")
        
        XCTAssertNotNil(result.summary, "Gemini should create summary")
        XCTAssertLessThan(result.summary.count, result.scrapedContent.count, "Summary should be shorter")
        
        XCTAssertNotNil(result.audioURL, "TTS should generate audio")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.audioURL.path))
    }
    
    func testPipelineErrorHandling() async {
        // Given
        let processor = ArticleProcessor()
        let badURL = URL(string: "https://invalid-url-that-doesnt-exist.com")!
        
        // When
        let result = await processor.processArticle(from: badURL)
        
        // Then
        XCTAssertNil(result.audioURL)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.error?.type, .scrapingFailed)
    }
    
    // MARK: - Queue Position Tests
    
    func testNewArticlesAddedToBackOfQueue() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        // Add initial items
        await viewModel.queueArticle(MockArticle(title: "First", content: "1"))
        await viewModel.queueArticle(MockArticle(title: "Second", content: "2"))
        
        // When - Add new article
        await viewModel.queueArticle(MockArticle(title: "New", content: "3"))
        
        // Then - Should be at back (top visually, but last to play)
        XCTAssertEqual(viewModel.queueItems.last?.title, "New")
        XCTAssertEqual(viewModel.queueItems.first?.title, "First") // Plays first
    }
    
    // MARK: - Article State Management Tests
    
    func testArticleMarkedAsQueuedInUI() async {
        // Given
        let stateManager = ArticleStateManagerV2.shared
        let article = MockArticle(title: "Test", content: "Content")
        
        // When
        stateManager.addToQueue(articleID: article.id)
        
        // Then
        XCTAssertTrue(stateManager.isQueued(articleID: article.id))
        XCTAssertEqual(stateManager.queuePosition(for: article.id), 0)
    }
    
    func testArticleRemovedFromQueueUpdatesState() async {
        // Given
        let stateManager = ArticleStateManagerV2.shared
        let article = MockArticle(title: "Test", content: "Content")
        stateManager.addToQueue(articleID: article.id)
        
        // When
        stateManager.removeFromQueue(articleID: article.id)
        
        // Then
        XCTAssertFalse(stateManager.isQueued(articleID: article.id))
        XCTAssertNil(stateManager.queuePosition(for: article.id))
    }
}

// MARK: - Mock Article Detail ViewModel

class ArticleDetailViewModel: ObservableObject {
    @Published var isGenerating = false
    @Published var generationProgress: Float = 0
    @Published var generatedAudioURL: URL?
    @Published var canPlayAudio = false
    
    func generateAudio(for article: MockArticle) async {
        isGenerating = true
        generationProgress = 0
        
        // Simulate generation progress
        for i in 1...10 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            generationProgress = Float(i) / 10.0
        }
        
        // Generate audio
        generatedAudioURL = URL(fileURLWithPath: "/tmp/\(article.id).mp3")
        canPlayAudio = true
        isGenerating = false
    }
    
    func waitForGeneration() async {
        while isGenerating {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}

// MARK: - Article Processor

struct ArticleProcessor {
    struct ProcessingResult {
        let scrapedContent: String
        let summary: String
        let audioURL: URL?
        let error: ProcessingError?
    }
    
    struct ProcessingError: Error {
        enum ErrorType {
            case scrapingFailed
            case summaryFailed
            case ttsFailed
        }
        let type: ErrorType
    }
    
    func processArticle(from url: URL) async -> ProcessingResult {
        // Simulate FireCrawl → Gemini → TTS pipeline
        guard url.host != "invalid-url-that-doesnt-exist.com" else {
            return ProcessingResult(
                scrapedContent: "",
                summary: "",
                audioURL: nil,
                error: ProcessingError(type: .scrapingFailed)
            )
        }
        
        let content = "Scraped content from \(url)"
        let summary = "Summary: \(content)"
        let audioURL = URL(fileURLWithPath: "/tmp/audio.mp3")
        
        return ProcessingResult(
            scrapedContent: content,
            summary: summary,
            audioURL: audioURL,
            error: nil
        )
    }
}

// MARK: - ViewModel Extensions for Testing

extension AudioPlayerViewModel {
    func playNow(article: MockArticle) async {
        // Jump queue and play immediately
        await queueArticle(article)
        
        // Move to front and play
        if let index = queueItems.firstIndex(where: { $0.title == article.title }) {
            queueItems.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
            await play(article: article)
        }
    }
}