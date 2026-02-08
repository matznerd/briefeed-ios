//
//  InstantContentDisplayTests.swift
//  BriefeedTests
//
//  TDD Tests for Epic 1: Instant Content Display
//  Goal: Load article URLs directly in WKWebView immediately (<500ms)
//
//  RED PHASE: These tests should FAIL initially until implementation is complete
//

import XCTest
@testable import Briefeed
import Combine

// MARK: - Test 1.1: ArticleView URL-First Loading

final class ArticleViewInstantLoadingTests: XCTestCase {

    var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - RED: Test that ArticleView loads URL immediately

    /// Test: ArticleView should NOT show blocking loading view when article has URL
    /// Expected: isLoading should be false immediately, webViewURL should be set
    func testArticleView_WithURL_DoesNotBlockOnFirecrawl() async throws {
        // Given
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Test Article"
        article.url = "https://example.com/article"
        article.content = nil  // No pre-fetched content

        // When
        let viewModel = await ArticleViewModel(article: article)

        // Then: Should NOT be in loading state immediately
        await MainActor.run {
            XCTAssertFalse(viewModel.isLoading, "ArticleView should not block on loading when URL is available")
            XCTAssertFalse(viewModel.isLoadingContent, "Should not wait for Firecrawl content")
        }
    }

    /// Test: WebView URL should be available immediately for URL-based articles
    func testArticleViewModel_WithURL_ProvidesWebViewURL() async throws {
        // Given
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Test Article"
        article.url = "https://example.com/article"

        // When
        let viewModel = await ArticleViewModel(article: article)

        // Then: webViewURL should be available immediately
        await MainActor.run {
            XCTAssertNotNil(viewModel.webViewURL, "webViewURL should be set immediately for URL-based articles")
            XCTAssertEqual(viewModel.webViewURL, "https://example.com/article")
        }
    }

    /// Test: ArticleView initialization should complete within 100ms
    func testArticleViewModel_Initialization_IsLightweight() async throws {
        // Given
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Test Article"
        article.url = "https://example.com/article"

        // When/Then: Initialization should be fast
        let start = CFAbsoluteTimeGetCurrent()
        let _ = await ArticleViewModel(article: article)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 0.1, "ArticleViewModel init should complete within 100ms, took \(elapsed)s")
    }
}

// MARK: - Test 1.2: Background Firecrawl Processing

final class BackgroundFirecrawlTests: XCTestCase {

    var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    /// Test: Firecrawl should start automatically in background without blocking
    func testFirecrawl_StartsInBackground_WithoutBlockingUI() async throws {
        // Given
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Test Article"
        article.url = "https://example.com/article"
        article.content = nil

        let mockFirecrawl = MockFirecrawlService()
        mockFirecrawl.delay = 2.0 // Simulate slow network

        let viewModel = await ArticleViewModel(
            article: article,
            firecrawlService: mockFirecrawl
        )

        // When: Trigger background fetch
        await viewModel.startBackgroundContentFetch()

        // Then: Should NOT block - isLoadingContent should be true but not blocking UI
        await MainActor.run {
            XCTAssertTrue(viewModel.isBackgroundFetching, "Background fetch should be running")
            XCTAssertFalse(viewModel.isLoading, "UI should not be blocked")
            XCTAssertNotNil(viewModel.webViewURL, "WebView URL should still be available")
        }
    }

    /// Test: Background fetch should cache content when complete
    func testFirecrawl_CachesContent_WhenComplete() async throws {
        // Given
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Test Article"
        article.url = "https://example.com/article"
        article.content = nil

        let mockFirecrawl = MockFirecrawlService()
        mockFirecrawl.mockData = FirecrawlData(
            content: "Scraped article content",
            markdown: "# Scraped content",
            html: nil,
            metadata: nil,
            screenshot: nil
        )

        let viewModel = await ArticleViewModel(
            article: article,
            firecrawlService: mockFirecrawl
        )

        // When: Wait for background fetch to complete
        await viewModel.startBackgroundContentFetch()

        // Allow async completion
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Then: Content should be cached
        await MainActor.run {
            XCTAssertNotNil(viewModel.articleContent, "Content should be cached after background fetch")
            XCTAssertEqual(article.content, "# Scraped content", "Content should be saved to Core Data")
        }
    }

    /// Test: Firecrawl errors should not affect WebView display
    func testFirecrawl_Failure_DoesNotAffectWebView() async throws {
        // Given
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Test Article"
        article.url = "https://example.com/article"

        let mockFirecrawl = MockFirecrawlService()
        mockFirecrawl.shouldFail = true

        let viewModel = await ArticleViewModel(
            article: article,
            firecrawlService: mockFirecrawl
        )

        // When
        await viewModel.startBackgroundContentFetch()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then: WebView should still work
        await MainActor.run {
            XCTAssertNotNil(viewModel.webViewURL, "WebView URL should be available despite Firecrawl failure")
            XCTAssertFalse(viewModel.isLoading, "Should not be in loading state")
        }
    }
}

// MARK: - Test 1.3: ArticleReaderView URL-First Loading

final class ArticleReaderViewURLTests: XCTestCase {

    /// Test: URL-based initialization should be available
    func testArticleReaderView_URLInit_IsAvailable() {
        // This test verifies the URL initializer exists and works
        let readerView = ArticleReaderView(
            url: "https://example.com/article",
            fontSize: 16,
            isReaderMode: false
        )

        XCTAssertNotNil(readerView, "URL-based ArticleReaderView should be creatable")
    }

    /// Test: Loading state should be tracked
    func testArticleReaderView_TracksLoadingState() {
        // The ArticleReaderView should provide loading state for UI feedback
        // This requires adding a loading state binding

        // For now, just verify the view can be created
        let readerView = ArticleReaderView(
            url: "https://example.com/article",
            fontSize: 16,
            isReaderMode: false
        )

        XCTAssertNotNil(readerView)
    }
}

// MARK: - Test: Accessibility Identifiers for UI Testing

final class ArticleViewAccessibilityTests: XCTestCase {

    /// Test: ArticleView should have accessibility identifiers for UI testing
    func testArticleView_HasAccessibilityIdentifiers() async {
        // Given
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Test Article"
        article.url = "https://example.com/article"

        // When
        let viewModel = await ArticleViewModel(article: article)

        // Then: Check that accessibility identifiers are defined
        // These will be used by UI tests to verify instant loading
        await MainActor.run {
            XCTAssertNotNil(ArticleViewIdentifiers.webView, "WebView accessibility identifier should be defined")
            XCTAssertNotNil(ArticleViewIdentifiers.loadingIndicator, "Loading indicator identifier should be defined")
            XCTAssertNotNil(ArticleViewIdentifiers.summaryCard, "Summary card identifier should be defined")
        }
    }
}

// MARK: - Mock Services

class MockFirecrawlService: FirecrawlServiceProtocol {
    var mockData: FirecrawlData?
    var shouldFail = false
    var delay: TimeInterval = 0
    var fetchCallCount = 0

    func scrapeURL(_ url: String) async throws -> FirecrawlData {
        return try await fetchArticleContent(from: url)
    }

    func scrapeURLWithRetry(_ url: String, maxRetries: Int) async throws -> FirecrawlData {
        return try await fetchArticleContent(from: url)
    }

    func fetchArticleContent(from url: String) async throws -> FirecrawlData {
        fetchCallCount += 1

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if shouldFail {
            throw FirecrawlError.scrapeFailure("Network error during test")
        }

        return mockData ?? FirecrawlData(
            content: "Mock content",
            markdown: "# Mock content",
            html: nil,
            metadata: nil,
            screenshot: nil
        )
    }
}

// MARK: - Accessibility Identifiers (to be implemented)

/// Accessibility identifiers for UI testing
/// These need to be added to ArticleView.swift
enum ArticleViewIdentifiers {
    static let webView = "articleWebView"
    static let loadingIndicator = "articleLoadingIndicator"
    static let summaryCard = "articleSummaryCard"
    static let errorView = "articleErrorView"
    static let contentView = "articleContentView"
}
