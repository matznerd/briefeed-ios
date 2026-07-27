//
//  InfiniteScrollTests.swift
//  BriefeedTests
//
//  Test-Driven Development for infinite scroll functionality
//

import XCTest
import CoreData
@testable import Briefeed

class InfiniteScrollTests: XCTestCase {
    
    var viewModel: CombinedFeedViewModel!
    var mockContext: NSManagedObjectContext!
    
    override func setUp() {
        super.setUp()
        
        // Create in-memory Core Data stack for testing
        let container = NSPersistentContainer(name: "Briefeed")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
        }
        
        mockContext = container.viewContext
        viewModel = CombinedFeedViewModel()
    }
    
    override func tearDown() {
        viewModel = nil
        mockContext = nil
        super.tearDown()
    }
    
    // MARK: - Test: Load More Articles When Reaching Bottom
    
    func testLoadMoreArticlesWhenReachingBottom() async {
        // Given: Initial articles are loaded
        let initialArticleCount = 10
        await loadInitialArticles(count: initialArticleCount)
        
        XCTAssertEqual(viewModel.articles.count, initialArticleCount, "Should have initial articles loaded")
        XCTAssertFalse(viewModel.isLoadingMore, "Should not be loading more initially")
        
        // When: User scrolls to the last article
        let lastArticle = viewModel.articles.last!
        await viewModel.loadMoreIfNeeded(currentArticle: lastArticle)
        
        // Then: This test should FAIL with current implementation (empty method)
        // The current loadMoreIfNeeded does nothing, so this assertion will fail
        XCTAssertTrue(viewModel.isLoadingMore || viewModel.articles.count > initialArticleCount, 
                     "Should either be loading more or have loaded additional articles - THIS WILL FAIL UNTIL IMPLEMENTED")
    }
    
    func testDoesNotLoadMoreWhenNotAtBottom() async {
        // Given: Initial articles are loaded
        let initialArticleCount = 10
        await loadInitialArticles(count: initialArticleCount)
        
        // When: User is viewing an article in the middle
        let middleArticle = viewModel.articles[4]
        await viewModel.loadMoreIfNeeded(currentArticle: middleArticle)
        
        // Then: No additional loading should occur
        XCTAssertFalse(viewModel.isLoadingMore, "Should not load more when not at bottom")
        XCTAssertEqual(viewModel.articles.count, initialArticleCount, "Article count should remain the same")
    }
    
    func testLoadMoreWithPagination() async {
        // Given: Feed supports pagination
        let feed = createMockFeed(withPagination: true)
        viewModel.feeds = [feed]
        
        // Load initial batch
        await viewModel.refresh(feedId: feed.id?.uuidString ?? "")
        let initialCount = viewModel.articles.count
        
        // When: Request more articles
        if let lastArticle = viewModel.articles.last {
            await viewModel.loadMoreIfNeeded(currentArticle: lastArticle)
        }
        
        // Then: Should have pagination token and load more articles
        XCTAssertNotNil(viewModel.nextPageToken, "Should have pagination token")
        XCTAssertTrue(viewModel.articles.count > initialCount || viewModel.isLoadingMore, 
                     "Should load more articles with pagination")
    }
    
    func testPreventsDuplicateLoadRequests() async {
        // Given: Initial articles loaded
        await loadInitialArticles(count: 10)
        
        guard let lastArticle = viewModel.articles.last else {
            XCTFail("No articles loaded")
            return
        }
        
        // When: Multiple load requests are made simultaneously
        let loadTask1 = Task { await viewModel.loadMoreIfNeeded(currentArticle: lastArticle) }
        let loadTask2 = Task { await viewModel.loadMoreIfNeeded(currentArticle: lastArticle) }
        
        await loadTask1.value
        await loadTask2.value
        
        // Then: Only one load operation should occur
        XCTAssertTrue(viewModel.loadRequestCount <= 1, "Should prevent duplicate load requests")
    }
    
    func testHandlesEndOfFeed() async {
        // Given: All available articles are loaded
        viewModel.hasReachedEnd = false
        await loadInitialArticles(count: 5)
        
        // Simulate that we've reached the end
        viewModel.hasReachedEnd = true
        
        // When: User scrolls to bottom
        if let lastArticle = viewModel.articles.last {
            await viewModel.loadMoreIfNeeded(currentArticle: lastArticle)
        }
        
        // Then: Should not attempt to load more
        XCTAssertFalse(viewModel.isLoadingMore, "Should not load when end is reached")
        XCTAssertTrue(viewModel.hasReachedEnd, "Should maintain end state")
    }
    
    func testLoadMoreThreshold() async {
        // Given: Articles loaded with threshold setting
        let totalArticles = 20
        await loadInitialArticles(count: totalArticles)
        
        // When: User is within threshold distance from bottom (e.g., 3 articles from end)
        let thresholdIndex = totalArticles - 3
        let thresholdArticle = viewModel.articles[thresholdIndex]
        await viewModel.loadMoreIfNeeded(currentArticle: thresholdArticle)
        
        // Then: Should trigger loading more articles
        XCTAssertTrue(viewModel.isLoadingMore || viewModel.articles.count > totalArticles,
                     "Should load more when within threshold")
    }
    
    // MARK: - Helper Methods
    
    private func loadInitialArticles(count: Int) async {
        var articles: [Article] = []
        for i in 0..<count {
            let article = Article(context: mockContext)
            article.id = UUID()
            article.title = "Test Article \(i)"
            article.createdAt = Date().addingTimeInterval(TimeInterval(-i * 3600))
            article.url = "https://example.com/article\(i)"
            articles.append(article)
        }
        
        await MainActor.run {
            viewModel.articles = articles
        }
    }
    
    private func createMockFeed(withPagination: Bool) -> Feed {
        let feed = Feed(context: mockContext)
        feed.id = UUID()
        feed.name = "Test Feed"
        feed.type = "subreddit"
        feed.path = "/r/test"
        feed.isActive = true
        return feed
    }
}

// MARK: - Test Properties Extension

extension CombinedFeedViewModel {
    // Properties needed for testing that aren't in the current implementation
    var nextPageToken: String? {
        // This will need to be implemented
        return nil
    }
    
    var hasReachedEnd: Bool {
        get { false }  // This will need to be implemented
        set { }
    }
    
    var loadRequestCount: Int {
        // This will need to be implemented for testing duplicate prevention
        return 0
    }
}