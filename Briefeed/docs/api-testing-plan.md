# API Testing Plan for Briefeed

## Overview
This document outlines a comprehensive testing strategy for all external API integrations in Briefeed to ensure reliability and catch breaking changes early.

## APIs to Test

### 1. Gemini TTS API
- **Endpoint**: `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent`
- **Critical Fields**: Snake_case formatting requirements
- **Response Format**: Base64 encoded PCM audio data

### 2. Gemini Summary API
- **Endpoint**: `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent`
- **Purpose**: Article summarization
- **Response Format**: JSON with text content

### 3. Firecrawl API
- **Endpoint**: `https://api.firecrawl.dev/v0/scrape`
- **Purpose**: Web scraping for article content
- **Authentication**: API key required

### 4. Reddit API
- **Endpoint**: `https://www.reddit.com/r/{subreddit}.json`
- **Purpose**: Fetch Reddit posts
- **Special Requirements**: User-Agent header, no Content-Type for GET

## Test Categories

### 1. Unit Tests (Mocked)
- Test request formatting
- Test response parsing
- Test error handling
- Test retry logic

### 2. Integration Tests (Live API)
- Test actual API connectivity
- Test rate limiting behavior
- Test authentication
- Test response validation

### 3. Contract Tests
- Verify API response structure hasn't changed
- Test field names and types
- Test required vs optional fields

## Implementation Plan

### Phase 1: Test Infrastructure (Week 1)

#### 1.1 Create Base Test Classes
```swift
// APITestCase.swift
class APITestCase: XCTestCase {
    var mockSession: MockURLSession!
    
    func loadMockResponse(_ filename: String) -> Data
    func assertJSONEqual(_ actual: Data, _ expected: Data)
}
```

#### 1.2 Mock Response System
```swift
// MockResponses/
├── gemini_tts_success.json
├── gemini_tts_error_400.json
├── gemini_summary_success.json
├── reddit_success.json
├── reddit_rate_limit.json
└── firecrawl_success.json
```

#### 1.3 API Response Validators
```swift
protocol APIResponseValidator {
    func validate(_ response: Data) throws
}
```

### Phase 2: Gemini API Tests (Week 1-2)

#### 2.1 Gemini TTS Tests
```swift
class GeminiTTSTests: APITestCase {
    // Request formatting tests
    func testTTSRequestUsesSnakeCase()
    func testTTSRequestIncludesAllRequiredFields()
    func testTTSRequestVoiceNameValidation()
    
    // Response handling tests
    func testTTSResponseParsing()
    func testTTSBase64AudioDecoding()
    func testTTSErrorHandling()
    
    // Integration tests
    func testLiveGeminiTTSCall()
    func testTTSRateLimiting()
}
```

#### 2.2 Gemini Summary Tests
```swift
class GeminiSummaryTests: APITestCase {
    func testSummaryRequestFormat()
    func testSummaryResponseParsing()
    func testSummaryTokenLimits()
    func testSummaryErrorCodes()
}
```

### Phase 3: Reddit API Tests (Week 2)

```swift
class RedditAPITests: APITestCase {
    func testRedditRequestHeaders()
    func testRedditNoContentTypeOnGET()
    func testRedditJSONParsing()
    func testRedditPagination()
    func testRedditRateLimiting()
}
```

### Phase 4: Firecrawl API Tests (Week 2)

```swift
class FirecrawlAPITests: APITestCase {
    func testFirecrawlAuthentication()
    func testFirecrawlScrapeRequest()
    func testFirecrawlErrorHandling()
    func testFirecrawlRateLimits()
}
```

### Phase 5: Integration Test Suite (Week 3)

```swift
class APIIntegrationTests: XCTestCase {
    func testFullArticleFlowWithAPIs()
    func testAPIFailureRecovery()
    func testAPITimeouts()
    func testNetworkErrorHandling()
}
```

## Test Fixtures

### Mock Response Builder
```swift
class MockResponseBuilder {
    static func geminiTTSSuccess(voice: String) -> Data
    static func geminiError(code: Int, message: String) -> Data
    static func redditListing(posts: Int) -> Data
}
```

### API Monitor
```swift
class APIMonitor {
    func recordAPICall(endpoint: String, status: Int)
    func getAPIHealth() -> APIHealthReport
}
```

## Continuous Monitoring

### 1. Daily Health Checks
- Automated daily test run against live APIs
- Alert on breaking changes
- Track API response times

### 2. Version Detection
- Monitor API version changes
- Alert on deprecation notices
- Track new feature availability

### 3. Error Tracking
- Log all API errors with context
- Track error patterns
- Identify systematic issues

## Success Metrics

- **Test Coverage**: 90%+ for API-related code
- **API Uptime**: Track and report on API availability
- **Response Time**: Monitor API performance
- **Error Rate**: < 1% API errors in production
- **Breaking Change Detection**: Catch within 24 hours

## Implementation Timeline

### Week 1
- Set up test infrastructure
- Create mock response system
- Write Gemini TTS tests

### Week 2
- Complete Gemini Summary tests
- Write Reddit API tests
- Write Firecrawl tests

### Week 3
- Create integration test suite
- Set up continuous monitoring
- Document findings

### Week 4
- Performance testing
- Load testing
- Final documentation

## Next Steps

1. Create test files structure
2. Generate mock API responses
3. Implement base test classes
4. Start with highest priority APIs (Gemini TTS)