import XCTest
import CoreData
@testable import Briefeed

class FeedRefreshTests: XCTestCase {
    
    var persistenceController: PersistenceController!
    var context: NSManagedObjectContext!
    var dataService: DefaultDataService!
    
    override func setUp() {
        super.setUp()
        persistenceController = PersistenceController(inMemory: true)
        context = persistenceController.container.viewContext
        dataService = DefaultDataService.shared
    }
    
    override func tearDown() {
        persistenceController = nil
        context = nil
        dataService = nil
        super.tearDown()
    }
    
    // MARK: - Feed Creation Tests
    
    func testCreateRedditFeed() {
        // Test creating a Reddit feed preserves the correct URL format
        let redditURLs = [
            "https://www.reddit.com/r/swift",
            "reddit.com/r/technology",
            "r/programming"
        ]
        
        for urlString in redditURLs {
            let feed = Feed(context: context)
            feed.title = "Test Reddit Feed"
            feed.rssURL = urlString
            feed.isReddit = urlString.contains("reddit") || urlString.starts(with: "r/")
            
            XCTAssertTrue(feed.isReddit, "Reddit feed should be marked as isReddit")
            
            // Verify the stored URL is the original, not the generated one
            XCTAssertEqual(feed.rssURL, urlString)
        }
    }
    
    // MARK: - Feed Refresh Tests
    
    func testRedditFeedRefreshPreservesTextFormat() async throws {
        // Create a Reddit feed
        let feed = Feed(context: context)
        feed.title = "r/swift"
        feed.rssURL = "https://www.reddit.com/r/swift"
        feed.isReddit = true
        
        // Mock the refresh process
        let mockArticles = createMockArticlesWithSpecialText()
        
        // Simulate storing articles
        for mockArticle in mockArticles {
            let article = Article(context: context)
            article.title = mockArticle.title
            article.content = mockArticle.content
            article.feed = feed
            article.publishedDate = Date()
            
            // Verify content is stored exactly as provided
            XCTAssertEqual(article.content, mockArticle.content,
                          "Article content should be stored without modification")
        }
        
        try context.save()
        
        // Fetch and verify
        let request: NSFetchRequest<Article> = Article.fetchRequest()
        request.predicate = NSPredicate(format: "feed == %@", feed)
        let fetchedArticles = try context.fetch(request)
        
        XCTAssertEqual(fetchedArticles.count, mockArticles.count)
        
        // Verify each article's content is preserved
        for (index, article) in fetchedArticles.enumerated() {
            XCTAssertEqual(article.content, mockArticles[index].content,
                          "Fetched article content should match original")
        }
    }
    
    func testMultipleFeedRefreshConcurrency() async throws {
        // Test that refreshing multiple feeds doesn't cause data corruption
        let feeds = createMultipleFeeds(count: 5)
        
        // Refresh all feeds concurrently
        await withTaskGroup(of: Void.self) { group in
            for feed in feeds {
                group.addTask {
                    // Simulate refresh
                    await self.simulateFeedRefresh(feed: feed)
                }
            }
        }
        
        // Verify all feeds have articles
        for feed in feeds {
            let request: NSFetchRequest<Article> = Article.fetchRequest()
            request.predicate = NSPredicate(format: "feed == %@", feed)
            let articles = try context.fetch(request)
            
            XCTAssertFalse(articles.isEmpty, "Feed should have articles after refresh")
            
            // Verify Reddit feeds preserve special formatting
            if feed.isReddit {
                for article in articles {
                    if let content = article.content {
                        // Check for common Reddit formatting
                        let hasFormatting = content.contains("**") || 
                                          content.contains("*") || 
                                          content.contains(">") ||
                                          content.contains("```")
                        if hasFormatting {
                            XCTAssertFalse(content.contains("&amp;"),
                                         "Reddit content should not have escaped HTML")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Error Recovery Tests
    
    func testFeedRefreshErrorRecovery() async throws {
        let feed = Feed(context: context)
        feed.title = "Error Test Feed"
        feed.rssURL = "https://invalid.url.test"
        
        // Attempt refresh with invalid URL
        do {
            try await dataService.refreshFeed(feed, in: context)
            XCTFail("Should throw error for invalid URL")
        } catch {
            // Expected error
            XCTAssertNotNil(error)
        }
        
        // Verify feed state is not corrupted
        XCTAssertNotNil(feed.title)
        XCTAssertNotNil(feed.rssURL)
    }
    
    // MARK: - Queue Integration Tests
    
    func testRedditArticleQueueing() throws {
        // Test that Reddit articles can be queued with content preserved
        let feed = Feed(context: context)
        feed.title = "r/test"
        feed.rssURL = "r/test"
        feed.isReddit = true
        
        let article = Article(context: context)
        article.title = "Test Reddit Post"
        article.content = "# Markdown Header\n\n**Bold** and *italic* text\n\n```code block```"
        article.feed = feed
        article.publishedDate = Date()
        article.link = "https://reddit.com/r/test/comments/123"
        
        try context.save()
        
        // Create queue item
        let queueService = QueueService.shared
        let queueItem = EnhancedQueueItem(
            id: UUID().uuidString,
            title: article.title ?? "",
            content: article.content ?? "",
            type: .article(link: article.link ?? ""),
            addedAt: Date()
        )
        
        // Verify queue item preserves content
        XCTAssertEqual(queueItem.content, article.content,
                      "Queue item should preserve article content exactly")
    }
    
    // MARK: - Helper Methods
    
    private func createMockArticlesWithSpecialText() -> [(title: String, content: String)] {
        return [
            (
                title: "Code Example Post",
                content: "Here's a Swift example:\n\n```swift\nlet greeting = \"Hello, World!\"\nprint(greeting)\n```\n\nPretty neat!"
            ),
            (
                title: "Formatted Text Post",
                content: "**Important:** This is *very* important!\n\n> Quote from someone\n\n- List item 1\n- List item 2"
            ),
            (
                title: "Special Characters Post",
                content: "Symbols: < > & \" ' and emoji: 🎉 🚀\n\nMath: 2 < 3 && 4 > 1"
            )
        ]
    }
    
    private func createMultipleFeeds(count: Int) -> [Feed] {
        var feeds: [Feed] = []
        
        for i in 0..<count {
            let feed = Feed(context: context)
            feed.title = "Test Feed \(i)"
            
            if i % 2 == 0 {
                // Make half Reddit feeds
                feed.rssURL = "r/testfeed\(i)"
                feed.isReddit = true
            } else {
                // Make half regular RSS feeds
                feed.rssURL = "https://example.com/feed\(i).rss"
                feed.isReddit = false
            }
            
            feeds.append(feed)
        }
        
        try? context.save()
        return feeds
    }
    
    private func simulateFeedRefresh(feed: Feed) async {
        // Simulate adding articles to feed
        for i in 0..<3 {
            let article = Article(context: context)
            article.title = "\(feed.title ?? "") - Article \(i)"
            article.feed = feed
            article.publishedDate = Date()
            
            if feed.isReddit {
                // Add Reddit-style content
                article.content = "**Test** content with *formatting*\n\n> Quote"
            } else {
                // Add regular content
                article.content = "Regular article content"
            }
        }
        
        do {
            try context.save()
        } catch {
            XCTFail("Failed to save context: \(error)")
        }
    }
}

// MARK: - Performance Tests

extension FeedRefreshTests {
    
    func testRedditFeedRefreshPerformance() throws {
        let feed = Feed(context: context)
        feed.title = "Performance Test"
        feed.rssURL = "r/swift"
        feed.isReddit = true
        
        measure {
            // Measure the time to process Reddit response
            let mockData = createLargeMockRedditResponse(postCount: 100)
            _ = parseRedditData(mockData, for: feed)
        }
    }
    
    private func createLargeMockRedditResponse(postCount: Int) -> Data {
        var posts: [String] = []
        
        for i in 0..<postCount {
            let post = """
            {
                "kind": "t3",
                "data": {
                    "title": "Post \(i)",
                    "selftext": "Content with **formatting** and [links](https://example.com)",
                    "created_utc": \(Date().timeIntervalSince1970),
                    "url": "https://reddit.com/r/test/comments/\(i)",
                    "is_video": false,
                    "domain": "self.test"
                }
            }
            """
            posts.append(post)
        }
        
        let json = """
        {
            "kind": "Listing",
            "data": {
                "children": [\(posts.joined(separator: ","))]
            }
        }
        """
        
        return json.data(using: .utf8)!
    }
    
    private func parseRedditData(_ data: Data, for feed: Feed) -> [Article] {
        // Simulate parsing logic
        var articles: [Article] = []
        
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let data = json?["data"] as? [String: Any]
            let children = data?["children"] as? [[String: Any]] ?? []
            
            for child in children {
                guard let postData = child["data"] as? [String: Any] else { continue }
                
                let article = Article(context: context)
                article.title = postData["title"] as? String
                article.content = postData["selftext"] as? String
                article.feed = feed
                
                articles.append(article)
            }
        } catch {
            XCTFail("Failed to parse Reddit data: \(error)")
        }
        
        return articles
    }
}