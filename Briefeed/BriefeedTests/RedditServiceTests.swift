//
//  RedditServiceTests.swift
//  BriefeedTests
//
//  Created by Briefeed Team on 7/24/25.
//

import Testing
import Foundation
@testable import Briefeed

struct RedditServiceTests {
    
    // Helper to create test instances
    func makeSystemUnderTest() -> (sut: RedditService, mock: MockNetworkService) {
        let mockNetworkService = MockNetworkService()
        let sut = RedditService(networkService: mockNetworkService)
        return (sut, mockNetworkService)
    }
    
    // MARK: - URL Generation Tests
    
    @Test("Fetch subreddit generates correct URL")
    func testFetchSubredditGeneratesCorrectURL() async throws {
        // Given
        let subreddit = "swift"
        let expectedURL = "https://www.reddit.com/r/swift.json?limit=25&raw_json=1"
        
        // When
        let (sut, mockNetworkService) = makeSystemUnderTest()
        _ = try? await sut.fetchSubreddit(name: subreddit)
        
        // Then
        #expect(mockNetworkService.lastRequestedURL == expectedURL)
    }
    
    @Test("Fetch subreddit with pagination token")
    func testFetchSubredditWithPaginationToken() async throws {
        // Given
        let subreddit = "news"
        let afterToken = "t3_abc123"
        let expectedURL = "https://www.reddit.com/r/news.json?limit=25&raw_json=1&after=t3_abc123"
        
        // When
        let (sut, mockNetworkService) = makeSystemUnderTest()
        _ = try? await sut.fetchSubreddit(name: subreddit, after: afterToken)
        
        // Then
        #expect(mockNetworkService.lastRequestedURL == expectedURL)
    }
    
    // MARK: - Response Parsing Tests
    
    @Test("Parse valid Reddit response")
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
                        "selftext": "This is test content",
                        "created_utc": 1629000000,
                        "permalink": "/r/swift/comments/abc123/test_post/"
                    }
                }],
                "after": "t3_xyz789"
            }
        }
        """
        
        let mockData = json.data(using: .utf8)!
        let (sut, mockNetworkService) = makeSystemUnderTest()
        mockNetworkService.mockResponse = mockData
        
        // When
        let result = try await sut.fetchSubreddit(name: "swift")
        
        // Then
        #expect(result.posts.count == 1)
        #expect(result.posts[0].id == "abc123")
        #expect(result.posts[0].title == "Test Post")
    }
    
    @Test("Handle invalid JSON response")
    func testHandleInvalidJSONResponse() async throws {
        // Given
        let invalidJSON = "{ invalid json }"
        let mockData = invalidJSON.data(using: .utf8)!
        let (sut, mockNetworkService) = makeSystemUnderTest()
        mockNetworkService.mockResponse = mockData
        
        // When/Then
        do {
            _ = try await sut.fetchSubreddit(name: "swift")
            Issue.record("Should have thrown an error for invalid JSON")
        } catch {
            #expect(error != nil)
        }
    }
    
    // MARK: - Content Filtering Tests
    
    @Test("Filter empty posts from response")
    func testFilterEmptyPostsFromResponse() async throws {
        // Given
        let json = """
        {
            "kind": "Listing",
            "data": {
                "children": [
                    {
                        "kind": "t3",
                        "data": {
                            "id": "post1",
                            "title": "Valid Post",
                            "selftext": "Content here",
                            "author": "user1",
                            "created_utc": 1629000000,
                            "permalink": "/r/swift/comments/post1/"
                        }
                    },
                    {
                        "kind": "t3",
                        "data": {
                            "id": "post2",
                            "title": "",
                            "selftext": "",
                            "author": "user2",
                            "created_utc": 1629000000,
                            "permalink": "/r/swift/comments/post2/"
                        }
                    }
                ]
            }
        }
        """
        
        let mockData = json.data(using: .utf8)!
        let (sut, mockNetworkService) = makeSystemUnderTest()
        mockNetworkService.mockResponse = mockData
        
        // When
        let result = try await sut.fetchSubreddit(name: "swift")
        
        // Then
        #expect(result.posts.count == 1)
        #expect(result.posts[0].id == "post1")
    }
}

// MARK: - Mock Network Service

class MockNetworkService: NetworkServiceProtocol {
    var lastRequestedURL: String?
    var mockResponse: Data?
    var shouldThrowError = false
    
    func fetchData(from urlString: String, cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy, timeout: TimeInterval = 30) async throws -> Data {
        lastRequestedURL = urlString
        
        if shouldThrowError {
            throw URLError(.badServerResponse)
        }
        
        if let mockResponse = mockResponse {
            return mockResponse
        }
        
        // Return empty JSON as default
        return "{}".data(using: .utf8)!
    }
    
    func fetchDataWithResponse(from urlString: String, cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy, timeout: TimeInterval = 30) async throws -> (data: Data, response: URLResponse) {
        let data = try await fetchData(from: urlString, cachePolicy: cachePolicy, timeout: timeout)
        let response = HTTPURLResponse(url: URL(string: urlString)!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}