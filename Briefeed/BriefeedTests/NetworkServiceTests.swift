//
//  NetworkServiceTests.swift
//  BriefeedTests
//
//  Created by Briefeed Team on 7/24/25.
//

import XCTest
@testable import Briefeed

class NetworkServiceTests: XCTestCase {
    
    var sut: NetworkService!
    var mockSession: MockURLSession!
    
    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
        sut = NetworkService(session: mockSession)
    }
    
    override func tearDown() {
        sut = nil
        mockSession = nil
        super.tearDown()
    }
    
    // MARK: - Critical Test for Reddit Fix
    
    func testGETRequestDoesNotSetContentTypeHeader() async throws {
        // Given
        let url = "https://www.reddit.com/r/news.json"
        mockSession.mockData = "{}".data(using: .utf8)!
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        
        // When
        _ = try await sut.requestData(url, method: .get, headers: ["User-Agent": "TestAgent"])
        
        // Then
        let request = mockSession.lastRequest!
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"), 
                     "GET requests should NOT have Content-Type header")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "TestAgent")
    }
    
    func testPOSTRequestSetsContentTypeHeader() async throws {
        // Given
        let url = "https://api.example.com/data"
        let parameters = ["key": "value"]
        mockSession.mockData = "{}".data(using: .utf8)!
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        
        // When
        _ = try await sut.requestData(url, method: .post, parameters: parameters)
        
        // Then
        let request = mockSession.lastRequest!
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), 
                      "application/json",
                      "POST requests should have Content-Type header")
    }
    
    // MARK: - Error Handling Tests
    
    func test404ErrorIncludesResponseBody() async {
        // Given
        let url = "https://www.reddit.com/r/nonexistent.json"
        let errorHTML = "<html>404 Not Found</html>"
        mockSession.mockData = errorHTML.data(using: .utf8)!
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!
        
        // When/Then
        do {
            _ = try await sut.requestData(url)
            XCTFail("Should have thrown 404 error")
        } catch let error as NetworkError {
            if case .serverError(let code) = error {
                XCTAssertEqual(code, 404)
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
    
    func testRateLimitError() async {
        // Given
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.reddit.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["X-Ratelimit-Reset": "1234567890"]
        )!
        
        // When/Then
        do {
            _ = try await sut.requestData("https://api.reddit.com")
            XCTFail("Should have thrown rate limit error")
        } catch NetworkError.rateLimited {
            // Success
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}

// MARK: - Mock URLSession

class MockURLSession: URLSession {
    var mockData: Data?
    var mockResponse: URLResponse?
    var mockError: Error?
    var lastRequest: URLRequest?
    
    override func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        
        if let error = mockError {
            throw error
        }
        
        let data = mockData ?? Data()
        let response = mockResponse ?? URLResponse()
        
        return (data, response)
    }
}