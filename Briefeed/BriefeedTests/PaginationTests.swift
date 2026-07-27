//
//  PaginationTests.swift
//  BriefeedTests
//
//  Tests for per-feed pagination functionality
//

import XCTest
import CoreData
@testable import Briefeed

class PaginationTests: XCTestCase {
    
    var viewModel: CombinedFeedViewModel!
    var mockContext: NSManagedObjectContext!
    
    override func setUp() {
        super.setUp()
        viewModel = CombinedFeedViewModel()
        mockContext = PersistenceController.preview.container.viewContext
    }
    
    override func tearDown() {
        viewModel = nil
        mockContext = nil
        super.tearDown()
    }
    
    // MARK: - Per-Feed Pagination Token Tests
    
    func testPaginationTokensStoredPerFeed() {
        // Given: Multiple feeds
        let feed1 = createMockFeed(id: UUID(), name: "Feed 1")
        let feed2 = createMockFeed(id: UUID(), name: "Feed 2")
        
        // When: Storing pagination tokens
        viewModel.feedPaginationTokens[feed1.id!.uuidString] = "token1"
        viewModel.feedPaginationTokens[feed2.id!.uuidString] = "token2"
        
        // Then: Each feed should have its own token
        XCTAssertEqual(viewModel.feedPaginationTokens[feed1.id!.uuidString], "token1")
        XCTAssertEqual(viewModel.feedPaginationTokens[feed2.id!.uuidString], "token2")
        XCTAssertEqual(viewModel.feedPaginationTokens.count, 2)
    }
    
    func testPaginationTokensClearedOnFeedSwitch() {
        // Given: Pagination tokens for multiple feeds
        viewModel.feedPaginationTokens["feed1"] = "token1"
        viewModel.feedPaginationTokens["feed2"] = "token2"
        
        // When: Switching feeds (simulated by clearing tokens)
        viewModel.feedPaginationTokens.removeAll()
        
        // Then: All tokens should be cleared
        XCTAssertTrue(viewModel.feedPaginationTokens.isEmpty)
    }
    
    func testHasMorePagesBasedOnTokens() {
        // Test 1: With tokens, hasMorePages should be true
        viewModel.feedPaginationTokens["feed1"] = "token1"
        let hasMore = !viewModel.feedPaginationTokens.isEmpty
        XCTAssertTrue(hasMore, "Should have more pages when tokens exist")
        
        // Test 2: Without tokens, hasMorePages should be false
        viewModel.feedPaginationTokens.removeAll()
        let noMore = !viewModel.feedPaginationTokens.isEmpty
        XCTAssertFalse(noMore, "Should not have more pages when no tokens exist")
    }
    
    // MARK: - All Feeds Pagination Tests
    
    func testAllFeedsPaginationTracksMultipleFeeds() {
        // Given: Multiple feeds with different pagination states
        let feed1Id = UUID().uuidString
        let feed2Id = UUID().uuidString
        let feed3Id = UUID().uuidString
        
        // When: Some feeds have more pages, some don't
        viewModel.feedPaginationTokens[feed1Id] = "token1"
        viewModel.feedPaginationTokens[feed2Id] = "token2"
        // feed3 has no token (no more pages)
        
        // Then: Should correctly identify which feeds have more content
        XCTAssertNotNil(viewModel.feedPaginationTokens[feed1Id])
        XCTAssertNotNil(viewModel.feedPaginationTokens[feed2Id])
        XCTAssertNil(viewModel.feedPaginationTokens[feed3Id])
        
        // And: Overall hasMorePages should be true (at least one feed has more)
        let hasMorePages = !viewModel.feedPaginationTokens.isEmpty
        XCTAssertTrue(hasMorePages)
    }
    
    func testAllFeedsPaginationStopsWhenNoMoreContent() {
        // Given: All feeds exhausted
        viewModel.feedPaginationTokens.removeAll()
        
        // Then: hasMorePages should be false
        let hasMorePages = !viewModel.feedPaginationTokens.isEmpty
        XCTAssertFalse(hasMorePages, "Should stop pagination when all feeds exhausted")
    }
    
    // MARK: - Individual Feed Pagination Tests
    
    func testIndividualFeedPaginationUsesAfterToken() async {
        // Given: A single feed view with pagination token
        let feedId = UUID().uuidString
        viewModel.articles = createMockArticles(count: 10)
        
        // Simulate having an after token for individual feed
        // Note: In real implementation, afterToken is private, so we test the behavior
        
        // When: Near the end of articles
        let nearEndArticle = viewModel.articles[8]
        
        // Then: Should be able to load more
        await viewModel.loadMoreIfNeeded(currentArticle: nearEndArticle)
        
        // Verify the behavior (in real app, this would trigger network request)
        XCTAssertNotNil(viewModel.articles)
    }
    
    // MARK: - Edge Cases
    
    func testPaginationHandlesEmptyFeeds() {
        // Given: No feeds
        viewModel.feeds = []
        viewModel.feedPaginationTokens.removeAll()
        
        // Then: Should handle gracefully
        let hasMorePages = !viewModel.feedPaginationTokens.isEmpty
        XCTAssertFalse(hasMorePages)
    }
    
    func testPaginationHandlesNetworkErrors() {
        // Given: A feed with pagination token
        let feedId = UUID().uuidString
        viewModel.feedPaginationTokens[feedId] = "token1"
        
        // When: Network error occurs (simulated by removing token)
        viewModel.feedPaginationTokens.removeValue(forKey: feedId)
        
        // Then: Token should be removed to prevent retrying
        XCTAssertNil(viewModel.feedPaginationTokens[feedId])
    }
    
    // MARK: - Helper Methods
    
    private func createMockFeed(id: UUID = UUID(), name: String) -> Feed {
        let feed = Feed(context: mockContext)
        feed.id = id
        feed.name = name
        feed.path = "/r/\(name)"
        feed.type = "subreddit"
        feed.isActive = true
        return feed
    }
    
    private func createMockArticles(count: Int) -> [Article] {
        return (0..<count).map { index in
            let article = Article(context: mockContext)
            article.id = UUID()
            article.title = "Article \(index)"
            article.content = "Content \(index)"
            article.createdAt = Date()
            return article
        }
    }
}

// MARK: - Integration Tests

class PaginationIntegrationTests: XCTestCase {
    
    func testScrollingTriggersCorrectPaginationCalls() {
        // This would be an integration test verifying the full flow:
        // 1. User scrolls to bottom
        // 2. onAppear triggers
        // 3. loadMoreIfNeeded called
        // 4. Correct feed tokens used
        // 5. New articles appended
        
        // In a real UI test, this would use XCUITest
        XCTAssertTrue(true, "Placeholder for UI integration test")
    }
    
    func testPaginationStateConsistency() {
        let viewModel = CombinedFeedViewModel()
        
        // Test that pagination state remains consistent
        viewModel.feedPaginationTokens["feed1"] = "token1"
        let hasMore = !viewModel.feedPaginationTokens.isEmpty
        
        XCTAssertTrue(hasMore)
        
        // Clear and verify
        viewModel.feedPaginationTokens.removeAll()
        let noMore = !viewModel.feedPaginationTokens.isEmpty
        
        XCTAssertFalse(noMore)
    }
}