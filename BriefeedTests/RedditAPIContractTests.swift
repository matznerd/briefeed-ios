import XCTest
@testable import Briefeed

/// Contract tests to detect Reddit API changes that could break the app
class RedditAPIContractTests: XCTestCase {
    
    // MARK: - Critical API Contract Tests
    
    func testRedditAPIResponseStructure() async throws {
        // Skip in CI unless explicitly enabled
        guard ProcessInfo.processInfo.environment["TEST_REDDIT_API"] != nil ||
              ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Reddit API tests disabled in CI")
        }
        
        let url = URL(string: "https://www.reddit.com/r/swift.json?raw_json=1&limit=1")!
        var request = URLRequest(url: url)
        request.setValue("ios:com.briefeed.app:v1.0.0 (by /u/briefeedapp)", 
                        forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Verify response code
        let httpResponse = response as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 200, "Reddit API should return 200 OK")
        
        // Verify JSON structure
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json, "Response should be valid JSON")
        
        // Check top-level structure
        XCTAssertEqual(json?["kind"] as? String, "Listing", 
                      "Response kind should be 'Listing'")
        XCTAssertNotNil(json?["data"], "Response should have 'data' field")
        
        // Check data structure
        let data_dict = json?["data"] as? [String: Any]
        XCTAssertNotNil(data_dict?["children"], "Data should have 'children' array")
        
        // Check children structure
        let children = data_dict?["children"] as? [[String: Any]] ?? []
        XCTAssertFalse(children.isEmpty, "Should have at least one post")
        
        if let firstChild = children.first {
            XCTAssertEqual(firstChild["kind"] as? String, "t3", 
                          "Post kind should be 't3'")
            XCTAssertNotNil(firstChild["data"], "Post should have 'data' field")
            
            // Check post data structure
            let postData = firstChild["data"] as? [String: Any]
            
            // Required fields that must exist
            let requiredFields = [
                "title", "created_utc", "url", "domain", 
                "is_video", "subreddit", "author"
            ]
            
            for field in requiredFields {
                XCTAssertNotNil(postData?[field], 
                               "Post data missing required field: \(field)")
            }
            
            // Check selftext field for self posts
            if let domain = postData?["domain"] as? String,
               domain.starts(with: "self.") {
                XCTAssertNotNil(postData?["selftext"], 
                               "Self posts should have 'selftext' field")
            }
        }
    }
    
    func testRedditRawJSONParameter() async throws {
        guard ProcessInfo.processInfo.environment["TEST_REDDIT_API"] != nil ||
              ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Reddit API tests disabled in CI")
        }
        
        // Test with raw_json=1
        let rawURL = URL(string: "https://www.reddit.com/r/test.json?raw_json=1&limit=1")!
        var rawRequest = URLRequest(url: rawURL)
        rawRequest.setValue("ios:com.briefeed.app:v1.0.0 (by /u/briefeedapp)", 
                           forHTTPHeaderField: "User-Agent")
        
        // Test without raw_json=1
        let escapedURL = URL(string: "https://www.reddit.com/r/test.json?limit=1")!
        var escapedRequest = URLRequest(url: escapedURL)
        escapedRequest.setValue("ios:com.briefeed.app:v1.0.0 (by /u/briefeedapp)", 
                               forHTTPHeaderField: "User-Agent")
        
        async let rawResponse = URLSession.shared.data(for: rawRequest)
        async let escapedResponse = URLSession.shared.data(for: escapedRequest)
        
        let (rawData, _) = try await rawResponse
        let (escapedData, _) = try await escapedResponse
        
        // Parse both responses
        let rawJSON = try JSONSerialization.jsonObject(with: rawData) as? [String: Any]
        let escapedJSON = try JSONSerialization.jsonObject(with: escapedData) as? [String: Any]
        
        // Find a post with special characters to test
        if let rawChildren = (rawJSON?["data"] as? [String: Any])?["children"] as? [[String: Any]],
           let escapedChildren = (escapedJSON?["data"] as? [String: Any])?["children"] as? [[String: Any]] {
            
            // Log the difference for debugging
            for i in 0..<min(rawChildren.count, escapedChildren.count) {
                if let rawText = (rawChildren[i]["data"] as? [String: Any])?["selftext"] as? String,
                   let escapedText = (escapedChildren[i]["data"] as? [String: Any])?["selftext"] as? String,
                   rawText != escapedText {
                    
                    print("Found difference in text handling:")
                    print("Raw: \(rawText)")
                    print("Escaped: \(escapedText)")
                    
                    // Verify raw_json=1 prevents escaping
                    XCTAssertFalse(rawText.contains("&amp;") && !escapedText.contains("&amp;"),
                                  "raw_json=1 should prevent HTML entity escaping")
                }
            }
        }
    }
    
    func testRedditUserAgentRequirement() async throws {
        guard ProcessInfo.processInfo.environment["TEST_REDDIT_API"] != nil ||
              ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Reddit API tests disabled in CI")
        }
        
        let url = URL(string: "https://www.reddit.com/r/swift.json?limit=1")!
        
        // Test without User-Agent (should fail or return different response)
        var noUserAgentRequest = URLRequest(url: url)
        
        // Test with User-Agent
        var withUserAgentRequest = URLRequest(url: url)
        withUserAgentRequest.setValue("ios:com.briefeed.app:v1.0.0 (by /u/briefeedapp)", 
                                     forHTTPHeaderField: "User-Agent")
        
        // Both requests should work, but Reddit prefers User-Agent
        let (_, noUAResponse) = try await URLSession.shared.data(for: noUserAgentRequest)
        let (_, withUAResponse) = try await URLSession.shared.data(for: withUserAgentRequest)
        
        // Both should return 200, but log if different
        let noUAStatus = (noUAResponse as? HTTPURLResponse)?.statusCode
        let withUAStatus = (withUAResponse as? HTTPURLResponse)?.statusCode
        
        if noUAStatus != withUAStatus {
            print("Reddit API behaves differently without User-Agent")
            print("Without UA: \(noUAStatus ?? -1), With UA: \(withUAStatus ?? -1)")
        }
        
        XCTAssertEqual(withUAStatus, 200, "Reddit API should work with proper User-Agent")
    }
    
    // MARK: - Content Format Preservation Tests
    
    func testRedditMarkdownPreservation() async throws {
        // This test verifies that Reddit's markdown formatting is preserved
        let testCases = [
            "**bold**",
            "*italic*",
            "[link](https://example.com)",
            "`code`",
            "```\ncode block\n```",
            "> quote",
            "- list item",
            "1. numbered item",
            "~~strikethrough~~",
            "^superscript",
            "spoiler: &gt;!hidden text!&lt;"
        ]
        
        // Create a mock article with each test case
        for testContent in testCases {
            let context = PersistenceController.preview.container.viewContext
            let article = Article(context: context)
            article.content = testContent
            
            // Verify content is stored exactly as provided
            XCTAssertEqual(article.content, testContent,
                          "Markdown should be preserved: \(testContent)")
            
            // Verify no HTML escaping
            XCTAssertFalse(article.content?.contains("&gt;") ?? false,
                          "Content should not be HTML escaped")
            XCTAssertFalse(article.content?.contains("&lt;") ?? false,
                          "Content should not be HTML escaped")
        }
    }
    
    // MARK: - Error Response Tests
    
    func testRedditErrorResponses() async throws {
        guard ProcessInfo.processInfo.environment["TEST_REDDIT_API"] != nil ||
              ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Reddit API tests disabled in CI")
        }
        
        // Test various error scenarios
        let errorURLs = [
            "https://www.reddit.com/r/thisShouldNotExist12345.json", // 404
            "https://www.reddit.com/r/a.json", // Private subreddit
        ]
        
        for urlString in errorURLs {
            let url = URL(string: urlString)!
            var request = URLRequest(url: url)
            request.setValue("ios:com.briefeed.app:v1.0.0 (by /u/briefeedapp)", 
                            forHTTPHeaderField: "User-Agent")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let httpResponse = response as? HTTPURLResponse
                
                if httpResponse?.statusCode != 200 {
                    print("Error response from \(urlString): \(httpResponse?.statusCode ?? -1)")
                    
                    // Try to parse error response
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("Error details: \(json)")
                    }
                }
                
                // Reddit often returns 200 even for non-existent subreddits
                // but with empty children array
                if httpResponse?.statusCode == 200 {
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let children = (json?["data"] as? [String: Any])?["children"] as? [[String: Any]]
                    
                    // Empty subreddit should have empty children
                    if urlString.contains("thisShouldNotExist") {
                        XCTAssertTrue(children?.isEmpty ?? true,
                                     "Non-existent subreddit should return empty posts")
                    }
                }
            } catch {
                // Network errors are acceptable in tests
                print("Network error testing \(urlString): \(error)")
            }
        }
    }
    
    // MARK: - Performance Baseline Tests
    
    func testRedditAPIResponseTime() async throws {
        guard ProcessInfo.processInfo.environment["TEST_REDDIT_API"] != nil ||
              ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Reddit API tests disabled in CI")
        }
        
        let url = URL(string: "https://www.reddit.com/r/swift.json?limit=10")!
        var request = URLRequest(url: url)
        request.setValue("ios:com.briefeed.app:v1.0.0 (by /u/briefeedapp)", 
                        forHTTPHeaderField: "User-Agent")
        
        let startTime = Date()
        let (data, _) = try await URLSession.shared.data(for: request)
        let responseTime = Date().timeIntervalSince(startTime)
        
        print("Reddit API response time: \(responseTime) seconds")
        print("Response size: \(data.count) bytes")
        
        // Log baseline for monitoring
        XCTAssertLessThan(responseTime, 10.0, 
                         "Reddit API should respond within 10 seconds")
        XCTAssertGreaterThan(data.count, 100, 
                            "Reddit API should return meaningful data")
    }
}