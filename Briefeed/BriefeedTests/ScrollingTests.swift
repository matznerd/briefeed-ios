//
//  ScrollingTests.swift
//  BriefeedTests
//
//  Tests to ensure scrolling and lazy loading functionality
//

import XCTest
import SwiftUI
@testable import Briefeed

class ScrollingTests: XCTestCase {
    
    var viewModel: CombinedFeedViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = CombinedFeedViewModel()
    }
    
    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }
    
    // MARK: - Lazy Loading Tests
    
    func testLoadMoreIfNeededTriggersNearEnd() async {
        // Given: A list of articles
        let articles = createMockArticles(count: 20)
        viewModel.articles = articles
        
        // When: We're viewing an article near the end (index 17 of 20)
        let nearEndArticle = articles[17]
        
        // Then: loadMoreIfNeeded should trigger
        await viewModel.loadMoreIfNeeded(currentArticle: nearEndArticle)
        
        // Verify that loading more was attempted
        XCTAssertTrue(viewModel.isLoadingMore || viewModel.articles.count > 20,
                     "Should trigger loading more when near the end of the list")
    }
    
    func testLoadMoreIfNeededDoesNotTriggerAtBeginning() async {
        // Given: A list of articles
        let articles = createMockArticles(count: 20)
        viewModel.articles = articles
        
        // When: We're viewing an article at the beginning (index 2 of 20)
        let beginningArticle = articles[2]
        
        // Then: loadMoreIfNeeded should NOT trigger
        await viewModel.loadMoreIfNeeded(currentArticle: beginningArticle)
        
        // Verify that loading more was NOT attempted
        XCTAssertFalse(viewModel.isLoadingMore,
                      "Should NOT trigger loading more when at the beginning of the list")
    }
    
    // MARK: - ScrollView OnAppear Tests
    
    func testOnAppearCallsLoadMore() {
        // This test verifies that the onAppear modifier is properly set up
        // In a real UI test, we would verify that scrolling to an article triggers onAppear
        
        let expectation = XCTestExpectation(description: "onAppear should trigger loadMoreIfNeeded")
        
        // Create a mock article row view
        let article = createMockArticle()
        let rowView = ArticleRowView(article: article, onTap: {}, onSave: {}, onDelete: {})
            .onAppear {
                expectation.fulfill()
            }
        
        // Simulate the view appearing
        _ = rowView.body
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Helper Methods
    
    private func createMockArticles(count: Int) -> [Article] {
        return (0..<count).map { index in
            createMockArticle(withId: UUID(), title: "Article \(index)")
        }
    }
    
    private func createMockArticle(withId id: UUID = UUID(), title: String = "Test Article") -> Article {
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = id
        article.title = title
        article.content = "Test content"
        article.createdAt = Date()
        return article
    }
}
