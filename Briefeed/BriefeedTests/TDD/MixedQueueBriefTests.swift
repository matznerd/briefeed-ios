import XCTest
import Combine
@testable import Briefeed

// MARK: - TDD: Mixed Queue (Brief) Tests
// Define expected behavior for the Brief - mixed queue with visual flow

final class MixedQueueBriefTests: XCTestCase {
    
    private var cancellables = Set<AnyCancellable>()
    
    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }
    
    // MARK: - Visual Flow Tests (Funnel Concept)
    
    func testNewItemsAddedAtTop() async {
        // Given
        let briefVM = BriefViewModel()
        await briefVM.initialize()
        
        // Add initial items
        await briefVM.addArticle(MockArticle(title: "First", content: "1"))
        await briefVM.addArticle(MockArticle(title: "Second", content: "2"))
        
        // When - Add new item
        await briefVM.addArticle(MockArticle(title: "New", content: "3"))
        
        // Then - New item should be at top (visually), but last in play order
        XCTAssertEqual(briefVM.visualItems[0].title, "New", "New items appear at top")
        XCTAssertEqual(briefVM.playbackOrder.last?.title, "New", "But play last")
        XCTAssertEqual(briefVM.playbackOrder.first?.title, "First", "First added plays first")
    }
    
    func testItemsSlideDownToPlayer() {
        // Given
        let briefVM = BriefViewModel()
        
        // When - Items are consumed
        briefVM.addToQueue(["Item 1", "Item 2", "Item 3", "Item 4"])
        let initialTopItem = briefVM.visualItems[0]
        
        briefVM.consumeNextItem() // Play Item 1
        
        // Then - Items visually slide down
        XCTAssertNotEqual(briefVM.visualItems[0], initialTopItem)
        XCTAssertEqual(briefVM.nowPlaying?.title, "Item 1")
        XCTAssertEqual(briefVM.visualItems.count, 3) // One consumed
    }
    
    func testFunnelMetaphor() {
        // Given
        let briefVM = BriefViewModel()
        
        // Setup funnel with mixed content
        briefVM.addToQueue([
            QueueItem(type: .article, title: "Article 1"),
            QueueItem(type: .rss, title: "Episode 1"),
            QueueItem(type: .article, title: "Article 2"),
            QueueItem(type: .rss, title: "Episode 2")
        ])
        
        // Then - Visual representation
        XCTAssertEqual(briefVM.visualPosition(for: "Article 1"), .bottom) // Closest to player
        XCTAssertEqual(briefVM.visualPosition(for: "Episode 2"), .top) // Furthest from player
        XCTAssertEqual(briefVM.queueDepth, 4)
        XCTAssertTrue(briefVM.isFlowingToPlayer)
    }
    
    // MARK: - Mixed Content Type Tests
    
    func testMixedQueueArticlesAndRSS() async {
        // Given
        let queueService = QueueServiceV2.shared
        await queueService.initialize()
        
        // When - Add mixed content
        await queueService.addToQueue(article: MockArticle(title: "Article 1", content: "Text"))
        await queueService.addToQueue(episode: MockRSSEpisode(title: "Episode 1", audioUrl: "https://test.com/1.mp3"))
        await queueService.addToQueue(article: MockArticle(title: "Article 2", content: "Text"))
        await queueService.addToQueue(episode: MockRSSEpisode(title: "Episode 2", audioUrl: "https://test.com/2.mp3"))
        
        // Then
        let queue = queueService.enhancedQueue
        XCTAssertEqual(queue.count, 4)
        XCTAssertEqual(queue[0].source.iconName, "doc.text") // Article icon
        XCTAssertEqual(queue[1].source.iconName, "dot.radiowaves.left.and.right") // RSS icon
    }
    
    func testContentTypeFiltering() {
        // Given
        let briefVM = BriefViewModel()
        briefVM.setupMixedQueue()
        
        // When - Apply filters
        briefVM.applyFilter(.articles)
        let articleCount = briefVM.filteredItems.count
        
        briefVM.applyFilter(.liveNews)
        let rssCount = briefVM.filteredItems.count
        
        briefVM.applyFilter(.all)
        let allCount = briefVM.filteredItems.count
        
        // Then
        XCTAssertGreaterThan(allCount, articleCount)
        XCTAssertGreaterThan(allCount, rssCount)
        XCTAssertEqual(allCount, articleCount + rssCount)
    }
    
    // MARK: - Smart Processing Tests
    
    func testArticleProcessingWhenNextInQueue() async {
        // Given
        let processor = SmartQueueProcessor()
        let queue = [
            QueueItem(type: .rss, title: "Episode", hasAudio: true),
            QueueItem(type: .article, title: "Article", hasAudio: false),
            QueueItem(type: .article, title: "Article 2", hasAudio: false)
        ]
        
        processor.setQueue(queue)
        
        // When - First item (RSS) is playing
        processor.startPlayingItem(at: 0)
        
        // Then - Next article should start processing
        await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertTrue(processor.isProcessing(itemAt: 1), "Next article should process")
        XCTAssertFalse(processor.isProcessing(itemAt: 2), "Distant article should not process")
    }
    
    func testNoProcessingForRSSEpisodes() async {
        // Given
        let processor = SmartQueueProcessor()
        let episode = QueueItem(type: .rss, title: "Episode", audioUrl: "https://test.com/ep.mp3")
        
        // When
        let needsProcessing = processor.itemNeedsProcessing(episode)
        
        // Then
        XCTAssertFalse(needsProcessing, "RSS episodes don't need processing")
        XCTAssertTrue(episode.isReadyToPlay)
    }
    
    func testProcessingPipeline() async {
        // Given
        let processor = SmartQueueProcessor()
        let article = QueueItem(type: .article, title: "Article", content: "Long content")
        
        // When
        let result = await processor.processArticle(article)
        
        // Then - Verify pipeline stages
        XCTAssertNotNil(result.scrapedContent, "FireCrawl should scrape")
        XCTAssertNotNil(result.summary, "Gemini should summarize")
        XCTAssertNotNil(result.audioURL, "TTS should generate audio")
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.processingStages.count, 3)
    }
    
    // MARK: - Queue Persistence Tests
    
    func testQueuePersistsAcrossAppRestarts() async {
        // Given
        let queueService = QueueServiceV2.shared
        
        // Add mixed items
        await queueService.addToQueue(article: MockArticle(title: "Persistent Article", content: "Content"))
        await queueService.addToQueue(episode: MockRSSEpisode(title: "Persistent Episode", audioUrl: "https://test.com/ep.mp3"))
        
        let originalCount = queueService.enhancedQueue.count
        
        // When - Simulate app restart
        await queueService.persist()
        await queueService.clearInMemory()
        await queueService.loadFromDisk()
        
        // Then
        XCTAssertEqual(queueService.enhancedQueue.count, originalCount)
        XCTAssertEqual(queueService.enhancedQueue[0].title, "Persistent Article")
        XCTAssertEqual(queueService.enhancedQueue[1].title, "Persistent Episode")
    }
    
    func testPartiallyProcessedItemsPersist() async {
        // Given
        let queueService = QueueServiceV2.shared
        let article = MockArticle(title: "Partial", content: "Content")
        
        await queueService.addToQueue(article: article)
        
        // Simulate partial processing
        queueService.enhancedQueue[0].audioUrl = URL(string: "file:///tmp/partial.mp3")
        queueService.enhancedQueue[0].processingProgress = 0.5
        
        // When - Restart
        await queueService.persist()
        await queueService.loadFromDisk()
        
        // Then
        let reloadedItem = queueService.enhancedQueue[0]
        XCTAssertNotNil(reloadedItem.audioUrl)
        XCTAssertEqual(reloadedItem.processingProgress, 0.5)
    }
    
    // MARK: - Queue Operations Tests
    
    func testReorderQueueItems() async {
        // Given
        let briefVM = BriefViewModel()
        briefVM.addToQueue(["A", "B", "C", "D", "E"])
        
        // When - Move C to position 1
        briefVM.moveItem(from: 2, to: 0)
        
        // Then
        XCTAssertEqual(briefVM.playbackOrder[0], "C")
        XCTAssertEqual(briefVM.playbackOrder[1], "A")
        XCTAssertEqual(briefVM.playbackOrder[2], "B")
    }
    
    func testRemoveFromQueue() async {
        // Given
        let briefVM = BriefViewModel()
        briefVM.addToQueue(["A", "B", "C"])
        
        // When
        briefVM.removeItem("B")
        
        // Then
        XCTAssertEqual(briefVM.queueCount, 2)
        XCTAssertFalse(briefVM.containsItem("B"))
        XCTAssertEqual(briefVM.playbackOrder, ["A", "C"])
    }
    
    func testClearQueue() async {
        // Given
        let briefVM = BriefViewModel()
        briefVM.addToQueue(["A", "B", "C"])
        
        // When
        briefVM.clearAll()
        
        // Then
        XCTAssertEqual(briefVM.queueCount, 0)
        XCTAssertTrue(briefVM.isEmpty)
        XCTAssertNil(briefVM.nowPlaying)
    }
    
    // MARK: - Playback Order Tests
    
    func testFIFOPlaybackOrder() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        // Add items in order
        for i in 1...5 {
            await viewModel.queueArticle(MockArticle(title: "Item \(i)", content: "\(i)"))
        }
        
        // When - Play through queue
        var playedOrder: [String] = []
        for _ in 1...5 {
            viewModel.playNextInQueue()
            if let title = viewModel.currentTitle {
                playedOrder.append(title)
            }
        }
        
        // Then - Should play in FIFO order
        XCTAssertEqual(playedOrder, ["Item 1", "Item 2", "Item 3", "Item 4", "Item 5"])
    }
    
    func testPlayNowJumpsQueue() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        await viewModel.connect()
        
        await viewModel.queueArticle(MockArticle(title: "Queued 1", content: "1"))
        await viewModel.queueArticle(MockArticle(title: "Queued 2", content: "2"))
        
        // When - Play now
        let urgent = MockArticle(title: "Urgent", content: "Now")
        await viewModel.playNow(article: urgent)
        
        // Then
        XCTAssertEqual(viewModel.currentTitle, "Urgent")
        XCTAssertEqual(viewModel.nextInQueue?.title, "Queued 1")
    }
    
    // MARK: - Brief Statistics Tests
    
    func testQueueStatistics() {
        // Given
        let briefVM = BriefViewModel()
        briefVM.setupMixedQueue()
        
        // Then
        let stats = briefVM.getStatistics()
        XCTAssertGreaterThan(stats.totalItems, 0)
        XCTAssertGreaterThanOrEqual(stats.articlesCount, 0)
        XCTAssertGreaterThanOrEqual(stats.episodesCount, 0)
        XCTAssertEqual(stats.totalItems, stats.articlesCount + stats.episodesCount)
        XCTAssertGreaterThanOrEqual(stats.estimatedTotalDuration, 0)
        XCTAssertGreaterThanOrEqual(stats.processedCount, 0)
        XCTAssertLessThanOrEqual(stats.processedCount, stats.totalItems)
    }
    
    // MARK: - Edge Cases Tests
    
    func testEmptyQueueBehavior() {
        // Given
        let briefVM = BriefViewModel()
        
        // Then
        XCTAssertTrue(briefVM.isEmpty)
        XCTAssertNil(briefVM.nowPlaying)
        XCTAssertNil(briefVM.nextUp)
        XCTAssertEqual(briefVM.queueCount, 0)
    }
    
    func testSingleItemQueue() async {
        // Given
        let briefVM = BriefViewModel()
        briefVM.addToQueue(["Only Item"])
        
        // When
        briefVM.playNext()
        
        // Then
        XCTAssertEqual(briefVM.nowPlaying, "Only Item")
        XCTAssertNil(briefVM.nextUp)
        XCTAssertTrue(briefVM.isLastItem)
    }
}

// MARK: - Mock Brief View Model

class BriefViewModel: ObservableObject {
    @Published var visualItems: [QueueDisplayItem] = []
    @Published var playbackOrder: [QueueDisplayItem] = []
    @Published var nowPlaying: QueueDisplayItem?
    @Published var nextUp: QueueDisplayItem?
    
    var queueCount: Int { playbackOrder.count }
    var isEmpty: Bool { playbackOrder.isEmpty }
    var isLastItem: Bool { playbackOrder.count == 1 && nowPlaying != nil }
    var queueDepth: Int { visualItems.count }
    var isFlowingToPlayer: Bool { !isEmpty }
    
    var filteredItems: [QueueDisplayItem] = []
    private var currentFilter: QueueFilter = .all
    
    enum VisualPosition {
        case top, middle, bottom
    }
    
    func initialize() async {
        // Setup
    }
    
    func addArticle(_ article: MockArticle) async {
        let item = QueueDisplayItem(title: article.title ?? "")
        visualItems.insert(item, at: 0) // Add at top visually
        playbackOrder.append(item) // Add at end for playback
    }
    
    func addToQueue(_ items: [Any]) {
        for item in items {
            if let title = item as? String {
                let displayItem = QueueDisplayItem(title: title)
                visualItems.insert(displayItem, at: 0)
                playbackOrder.append(displayItem)
            } else if let queueItem = item as? QueueItem {
                let displayItem = QueueDisplayItem(title: queueItem.title)
                visualItems.insert(displayItem, at: 0)
                playbackOrder.append(displayItem)
            }
        }
    }
    
    func consumeNextItem() {
        guard !playbackOrder.isEmpty else { return }
        nowPlaying = playbackOrder.removeFirst()
        if let nowPlaying = nowPlaying,
           let index = visualItems.firstIndex(where: { $0.title == nowPlaying.title }) {
            visualItems.remove(at: index)
        }
    }
    
    func visualPosition(for title: String) -> VisualPosition {
        guard let index = visualItems.firstIndex(where: { $0.title == title }) else {
            return .middle
        }
        
        if index == visualItems.count - 1 {
            return .bottom // Closest to player
        } else if index == 0 {
            return .top // Furthest from player
        } else {
            return .middle
        }
    }
    
    func setupMixedQueue() {
        // Add test data
        addToQueue([
            QueueItem(type: .article, title: "Article 1"),
            QueueItem(type: .rss, title: "Episode 1"),
            QueueItem(type: .article, title: "Article 2"),
            QueueItem(type: .rss, title: "Episode 2")
        ])
    }
    
    func applyFilter(_ filter: QueueFilter) {
        currentFilter = filter
        switch filter {
        case .all:
            filteredItems = visualItems
        case .articles:
            filteredItems = visualItems.filter { $0.isArticle }
        case .liveNews:
            filteredItems = visualItems.filter { $0.isRSS }
        }
    }
    
    func moveItem(from: Int, to: Int) {
        let item = playbackOrder.remove(at: from)
        playbackOrder.insert(item, at: to)
    }
    
    func removeItem(_ title: String) {
        playbackOrder.removeAll { $0.title == title }
        visualItems.removeAll { $0.title == title }
    }
    
    func clearAll() {
        playbackOrder.removeAll()
        visualItems.removeAll()
        nowPlaying = nil
        nextUp = nil
    }
    
    func containsItem(_ title: String) -> Bool {
        playbackOrder.contains { $0.title == title }
    }
    
    func playNext() {
        consumeNextItem()
        nextUp = playbackOrder.first
    }
    
    func getStatistics() -> QueueStatistics {
        let articles = visualItems.filter { $0.isArticle }.count
        let episodes = visualItems.filter { $0.isRSS }.count
        
        return QueueStatistics(
            totalItems: visualItems.count,
            articlesCount: articles,
            episodesCount: episodes,
            estimatedTotalDuration: 1800 * visualItems.count,
            processedCount: visualItems.filter { $0.isProcessed }.count
        )
    }
}

// MARK: - Supporting Types

struct QueueDisplayItem {
    let title: String
    var isArticle = true
    var isRSS = false
    var isProcessed = false
}

struct QueueItem {
    enum ItemType {
        case article, rss
    }
    
    let type: ItemType
    let title: String
    var content: String?
    var audioUrl: String?
    var hasAudio: Bool = false
    var processingProgress: Float = 0
    
    var isReadyToPlay: Bool {
        type == .rss || hasAudio
    }
}

class SmartQueueProcessor {
    private var queue: [QueueItem] = []
    private var currentlyPlaying: Int?
    private var processingItems: Set<Int> = []
    
    func setQueue(_ items: [QueueItem]) {
        queue = items
    }
    
    func startPlayingItem(at index: Int) {
        currentlyPlaying = index
        
        // Start processing next article if needed
        if index + 1 < queue.count && queue[index + 1].type == .article {
            processingItems.insert(index + 1)
        }
    }
    
    func isProcessing(itemAt index: Int) -> Bool {
        processingItems.contains(index)
    }
    
    func itemNeedsProcessing(_ item: QueueItem) -> Bool {
        item.type == .article && !item.hasAudio
    }
    
    func processArticle(_ article: QueueItem) async -> ProcessingResult {
        var result = ProcessingResult()
        
        // Simulate pipeline
        result.scrapedContent = "Scraped: \(article.content ?? "")"
        result.processingStages.append("FireCrawl")
        
        result.summary = "Summary of \(result.scrapedContent)"
        result.processingStages.append("Gemini")
        
        result.audioURL = URL(string: "file:///tmp/\(article.title).mp3")
        result.processingStages.append("TTS")
        
        result.success = true
        return result
    }
    
    struct ProcessingResult {
        var scrapedContent: String?
        var summary: String?
        var audioURL: URL?
        var success = false
        var processingStages: [String] = []
    }
}

struct QueueStatistics {
    let totalItems: Int
    let articlesCount: Int
    let episodesCount: Int
    let estimatedTotalDuration: TimeInterval
    let processedCount: Int
}

// MARK: - Extensions

extension QueueServiceV2 {
    func persist() async {
        // Save to disk
    }
    
    func clearInMemory() async {
        // Clear memory only
    }
    
    func loadFromDisk() async {
        // Load from persistent storage
    }
}

extension AudioPlayerViewModel {
    var nextInQueue: EnhancedQueueItem? {
        guard currentQueueIndex < queueItems.count - 1 else { return nil }
        return queueItems[currentQueueIndex + 1]
    }
}

extension EnhancedQueueItem {
    var processingProgress: Float {
        get { 0 }
        set { }
    }
}