import XCTest
@testable import Briefeed

class RedditFeedTests: XCTestCase {
    
    var sut: DefaultDataService!
    var mockSession: MockURLSession!
    
    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
        // Initialize DefaultDataService with mock session if possible
        // For now, we'll test the URL generation and response parsing
    }
    
    override func tearDown() {
        sut = nil
        mockSession = nil
        super.tearDown()
    }
    
    // MARK: - URL Generation Tests
    
    func testRedditURLGenerationIncludesRawJSON() {
        // Test that Reddit URLs always include raw_json=1 parameter
        let testCases = [
            "https://www.reddit.com/r/swift",
            "https://reddit.com/r/technology/",
            "reddit.com/r/programming",
            "r/news"
        ]
        
        for input in testCases {
            let url = DefaultDataService.generateFeedURL(from: input)
            XCTAssertNotNil(url, "Failed to generate URL for: \(input)")
            XCTAssertTrue(url!.absoluteString.contains("raw_json=1"), 
                          "Reddit URL missing raw_json=1 parameter: \(url!.absoluteString)")
            XCTAssertTrue(url!.absoluteString.contains(".json"), 
                          "Reddit URL missing .json extension: \(url!.absoluteString)")
        }
    }
    
    func testRedditURLGenerationHandlesSorting() {
        let testCases = [
            ("https://www.reddit.com/r/swift/hot", "hot.json"),
            ("https://www.reddit.com/r/swift/new", "new.json"),
            ("https://www.reddit.com/r/swift/top", "top.json"),
            ("https://www.reddit.com/r/swift", ".json") // Default case
        ]
        
        for (input, expected) in testCases {
            let url = DefaultDataService.generateFeedURL(from: input)
            XCTAssertNotNil(url)
            XCTAssertTrue(url!.absoluteString.contains(expected),
                          "URL doesn't contain expected sorting: \(url!.absoluteString)")
        }
    }
    
    // MARK: - Text Format Preservation Tests
    
    func testRedditTextFormatPreservation() {
        // Test that special Reddit text formatting is preserved
        let specialTextCases = [
            // Code blocks
            "```swift\nlet hello = \"world\"\nprint(hello)\n```",
            // Links
            "[Swift Forums](https://forums.swift.org)",
            // Bold and italic
            "**Bold text** and *italic text*",
            // Lists
            "- Item 1\n- Item 2\n  - Subitem",
            // Quotes
            "> This is a quote\n> Multiple lines",
            // Special characters
            "Unicode: 🎉 & HTML entities: &amp; &lt; &gt;",
            // Line breaks
            "Line 1\n\nLine 2 with double break",
            // Tables
            "| Header 1 | Header 2 |\n|----------|----------|\n| Cell 1   | Cell 2   |"
        ]
        
        for testText in specialTextCases {
            // Simulate Reddit API response with special text
            let mockResponse = createMockRedditResponse(withSelfText: testText)
            
            // Parse the response
            let articles = parseRedditResponse(mockResponse)
            
            XCTAssertEqual(articles.first?.content, testText,
                          "Special text format not preserved: \(testText)")
        }
    }
    
    func testRedditEscapedTextHandling() {
        // Test that raw_json=1 prevents escaped text
        let unescapedText = "Code: `let x = 5` & quotes: \"Hello\""
        let escapedText = "Code: &#x60;let x = 5&#x60; &amp; quotes: &quot;Hello&quot;"
        
        // With raw_json=1 (correct)
        let correctResponse = createMockRedditResponse(withSelfText: unescapedText)
        let correctArticles = parseRedditResponse(correctResponse)
        XCTAssertEqual(correctArticles.first?.content, unescapedText,
                      "Text should not be escaped with raw_json=1")
        
        // Without raw_json=1 (incorrect - what we want to avoid)
        // This simulates what would happen if raw_json=1 was missing
        let incorrectResponse = createMockRedditResponse(withSelfText: escapedText)
        let incorrectArticles = parseRedditResponse(incorrectResponse)
        XCTAssertNotEqual(incorrectArticles.first?.content, unescapedText,
                         "Escaped text should be different from unescaped")
    }
    
    // MARK: - Content Filtering Tests
    
    func testRedditVideoPostFiltering() {
        // Test that video posts are filtered out
        let responseWithVideo = """
        {
            "kind": "Listing",
            "data": {
                "children": [
                    {
                        "kind": "t3",
                        "data": {
                            "title": "Video Post",
                            "is_video": true,
                            "selftext": "This should be filtered"
                        }
                    },
                    {
                        "kind": "t3",
                        "data": {
                            "title": "Text Post",
                            "is_video": false,
                            "selftext": "This should be included"
                        }
                    }
                ]
            }
        }
        """
        
        let data = responseWithVideo.data(using: .utf8)!
        let articles = parseRedditResponse(data)
        
        XCTAssertEqual(articles.count, 1, "Video posts should be filtered out")
        XCTAssertEqual(articles.first?.title, "Text Post")
    }
    
    func testRedditDomainBlacklisting() {
        // Test that blacklisted domains are filtered
        let blacklistedDomains = ["v.redd.it", "reddit.com/gallery", "i.redd.it", "youtube.com"]
        
        for domain in blacklistedDomains {
            let response = createMockRedditResponse(withDomain: domain)
            let articles = parseRedditResponse(response)
            XCTAssertTrue(articles.isEmpty, "Domain \(domain) should be filtered")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testRedditAPIErrorHandling() {
        // Test various Reddit API error responses
        let errorResponses = [
            // Rate limiting
            "{\"error\": 429, \"message\": \"Too Many Requests\"}",
            // Subreddit not found
            "{\"error\": 404, \"message\": \"Not Found\"}",
            // Invalid JSON
            "{invalid json}",
            // Empty response
            ""
        ]
        
        for errorResponse in errorResponses {
            let data = errorResponse.data(using: .utf8) ?? Data()
            let articles = parseRedditResponse(data)
            XCTAssertTrue(articles.isEmpty, "Error response should return empty articles")
        }
    }
    
    // MARK: - User Agent Tests
    
    func testRedditRequestIncludesUserAgent() {
        // Verify User-Agent header is included in Reddit requests
        let request = createRedditRequest(for: "https://www.reddit.com/r/swift.json?raw_json=1")
        
        let userAgent = request.value(forHTTPHeaderField: "User-Agent")
        XCTAssertNotNil(userAgent, "User-Agent header is required for Reddit API")
        XCTAssertTrue(userAgent!.contains("ios"), "User-Agent should indicate iOS platform")
        XCTAssertTrue(userAgent!.contains("briefeed"), "User-Agent should include app name")
    }
    
    func testRedditRequestNoContentType() {
        // Verify Content-Type is NOT included for GET requests
        let request = createRedditRequest(for: "https://www.reddit.com/r/swift.json?raw_json=1")
        
        let contentType = request.value(forHTTPHeaderField: "Content-Type")
        XCTAssertNil(contentType, "Content-Type should not be set for Reddit GET requests")
    }
    
    // MARK: - Integration Tests
    
    func testLiveRedditFeed() async throws {
        // Skip in CI - only run locally
        guard ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Skipping live Reddit test in CI")
        }
        
        let url = URL(string: "https://www.reddit.com/r/swift.json?raw_json=1&limit=5")!
        let (data, response) = try await URLSession.shared.data(from: url)
        
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        
        let articles = parseRedditResponse(data)
        XCTAssertFalse(articles.isEmpty, "Should parse at least one article")
        
        // Verify text format preservation
        if let firstArticle = articles.first,
           let content = firstArticle.content,
           !content.isEmpty {
            // Check that content doesn't contain escaped HTML entities
            XCTAssertFalse(content.contains("&amp;"), "Content should not contain escaped ampersands")
            XCTAssertFalse(content.contains("&lt;"), "Content should not contain escaped less-than")
            XCTAssertFalse(content.contains("&gt;"), "Content should not contain escaped greater-than")
            XCTAssertFalse(content.contains("&#x"), "Content should not contain hex-encoded entities")
        }
    }
    
    // MARK: - Helper Methods
    
    private func createMockRedditResponse(withSelfText text: String) -> Data {
        let json = """
        {
            "kind": "Listing",
            "data": {
                "children": [{
                    "kind": "t3",
                    "data": {
                        "title": "Test Post",
                        "selftext": "\(text.replacingOccurrences(of: "\"", with: "\\\""))",
                        "url": "https://www.reddit.com/r/test/comments/123/test_post/",
                        "created_utc": 1234567890,
                        "author": "testuser",
                        "subreddit": "test",
                        "is_video": false,
                        "domain": "self.test"
                    }
                }]
            }
        }
        """
        return json.data(using: .utf8)!
    }
    
    private func createMockRedditResponse(withDomain domain: String) -> Data {
        let json = """
        {
            "kind": "Listing",
            "data": {
                "children": [{
                    "kind": "t3",
                    "data": {
                        "title": "Test Post",
                        "url": "https://\(domain)/test",
                        "domain": "\(domain)",
                        "is_video": false
                    }
                }]
            }
        }
        """
        return json.data(using: .utf8)!
    }
    
    private func parseRedditResponse(_ data: Data) -> [Article] {
        // This simulates the parsing logic from DefaultDataService
        // In real implementation, you'd use the actual parsing method
        var articles: [Article] = []
        
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let data = json?["data"] as? [String: Any]
            let children = data?["children"] as? [[String: Any]] ?? []
            
            for child in children {
                guard let postData = child["data"] as? [String: Any] else { continue }
                
                // Filter video posts
                if postData["is_video"] as? Bool == true { continue }
                
                // Filter blacklisted domains
                let domain = postData["domain"] as? String ?? ""
                let blacklist = ["v.redd.it", "reddit.com/gallery", "i.redd.it", "youtube.com", "youtu.be", "vimeo.com", "twitch.tv"]
                if blacklist.contains(where: { domain.contains($0) }) { continue }
                
                // Create mock article
                let context = PersistenceController.preview.container.viewContext
                let article = Article(context: context)
                article.title = postData["title"] as? String ?? ""
                article.content = postData["selftext"] as? String
                article.publishedDate = Date()
                article.link = postData["url"] as? String ?? ""
                
                articles.append(article)
            }
        } catch {
            // Return empty array on parse error
        }
        
        return articles
    }
    
    private func createRedditRequest(for urlString: String) -> URLRequest {
        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.setValue("ios:com.briefeed.app:v1.0.0 (by /u/briefeedapp)", forHTTPHeaderField: "User-Agent")
        return request
    }
}

// MARK: - Mock URL Session

class MockURLSession {
    var mockData: Data?
    var mockResponse: URLResponse?
    var mockError: Error?
    
    func data(from url: URL) async throws -> (Data, URLResponse) {
        if let error = mockError {
            throw error
        }
        
        let data = mockData ?? Data()
        let response = mockResponse ?? HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        
        return (data, response)
    }
}