//
//  RedditServiceTests.swift
//  BriefeedTests
//
//  Created by Briefeed Team on 7/24/25.
//

import Testing
@testable import Briefeed

struct RedditServiceTests {
    
    var sut: RedditService!
    var mockNetworkService: MockNetworkService!
    
    override func setUp() {
        super.setUp()
        mockNetworkService = MockNetworkService()
        sut = RedditService(networkService: mockNetworkService)
    }
    
    override func tearDown() {
        sut = nil
        mockNetworkService = nil
        super.tearDown()
    }
    
    // MARK: - URL Generation Tests
    
    func testFetchSubredditGeneratesCorrectURL() async throws {
        // Given
        let subreddit = "swift"
        let expectedURL = "https://www.reddit.com/r/swift.json?limit=25&raw_json=1"
        
        // When
        _ = try? await sut.fetchSubreddit(name: subreddit)
        
        // Then
        XCTAssertEqual(mockNetworkService.lastRequestedURL, expectedURL)
    }
    
    func testFetchSubredditWithPaginationToken() async throws {
        // Given
        let subreddit = "news"
        let afterToken = "t3_abc123"
        let expectedURL = "https://www.reddit.com/r/news.json?limit=25&raw_json=1&after=t3_abc123"
        
        // When
        _ = try? await sut.fetchSubreddit(name: subreddit, after: afterToken)
        
        // Then
        XCTAssertEqual(mockNetworkService.lastRequestedURL, expectedURL)
    }
    
    // MARK: - Response Parsing Tests
    
    func testParseValidRedditResponse() async throws {
        // Given
        let json = """
        {
            "kind": "Listing",
            "data": {
                "children": [{
                    "kind": "t3",
                    "data": {
                        "id": "abc123",
                        "title": "Test Post",
                        "author": "testuser",
                        "subreddit": "swift",
                        "url": "https://example.com",
                        "created_utc": 1234567890,
                        "score": 100,
                        "num_comments": 50,
                        "permalink": "/r/swift/comments/abc123/test_post/",
                        "is_video": false,
                        "is_self": false
                    }
                }],
                "after": "t3_def456"
            }
        }
        """
        mockNetworkService.mockResponse = json.data(using: .utf8)!
        
        // When
        let response = try await sut.fetchSubreddit(name: "swift")
        
        // Then
        XCTAssertEqual(response.data.children.count, 1)
        XCTAssertEqual(response.data.children[0].data.title, "Test Post")
        XCTAssertEqual(response.data.after, "t3_def456")
    }
    
    // MARK: - Error Handling Tests
    
    func testHandleNetworkError() async {
        // Given
        mockNetworkService.shouldThrowError = .networkUnavailable
        
        // When/Then
        do {
            _ = try await sut.fetchSubreddit(name: "swift")
            XCTFail("Should have thrown network error")
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    // MARK: - Content Filtering Tests
    
    func testFiltersVideoContent() async throws {
        // Given
        let json = """
        {
            "kind": "Listing",
            "data": {
                "children": [
                    {
                        "kind": "t3",
                        "data": {
                            "id": "video123",
                            "title": "Video Post",
                            "is_video": true,
                            "domain": "v.redd.it"
                        }
                    },
                    {
                        "kind": "t3",
                        "data": {
                            "id": "article123",
                            "title": "Article Post",
                            "is_video": false,
                            "domain": "example.com"
                        }
                    }
                ]
            }
        }
        """
        mockNetworkService.mockResponse = json.data(using: .utf8)!
        
        // When
        let response = try await sut.fetchSubreddit(name: "test")
        
        // Then
        XCTAssertEqual(response.data.children.count, 1)
        XCTAssertEqual(response.data.children[0].data.id, "article123")
    }
}

// MARK: - Mock Network Service

class MockNetworkService: NetworkServiceProtocol {
    var mockResponse: Data?
    var shouldThrowError: NetworkError?
    var lastRequestedURL: String?
    var requestCount = 0
    
    func request<T: Decodable>(_ endpoint: String, method: HTTPMethod, parameters: [String: Any]?, headers: [String: String]?) async throws -> T {
        lastRequestedURL = endpoint
        requestCount += 1
        
        if let error = shouldThrowError {
            throw error
        }
        
        guard let data = mockResponse else {
            throw NetworkError.noData
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    func requestData(_ endpoint: String, method: HTTPMethod, parameters: [String: Any]?, headers: [String: String]?) async throws -> Data {
        lastRequestedURL = endpoint
        requestCount += 1
        
        if let error = shouldThrowError {
            throw error
        }
        
        return mockResponse ?? Data()
    }
}