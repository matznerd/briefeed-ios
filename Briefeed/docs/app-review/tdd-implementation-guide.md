# TDD Implementation Guide for Briefeed Features

## Overview
This guide provides specific TDD implementation steps for each major feature in Briefeed, with focus on fixing broken functionality.

## TDD Best Practices for iOS/SwiftUI

### Core Principles
1. **Red-Green-Refactor Cycle**
   - Write a failing test first (Red)
   - Write minimal code to pass the test (Green)
   - Refactor for clarity and efficiency (Refactor)

2. **Test First, Code Second**
   - Never write production code without a failing test
   - Each test should drive a specific piece of functionality

3. **One Assertion Per Test**
   - Keep tests focused and easy to debug
   - Multiple assertions should be separate test methods

4. **Fast and Isolated Tests**
   - Unit tests should run in milliseconds
   - No network calls, file I/O, or database access in unit tests

5. **Descriptive Test Names**
   ```swift
   // Good
   func testFetchRedditSubreddit_WithValidName_ReturnsPostsArray()
   
   // Bad
   func testFetch()
   ```

### SwiftUI-Specific Testing

1. **ViewInspector for SwiftUI Views**
   ```swift
   import ViewInspector
   
   func testBriefViewShowsEmptyState() throws {
       let view = BriefView()
       let text = try view.inspect().text()
       XCTAssertEqual(try text.string(), "No items in queue")
   }
   ```

2. **@Published Property Testing**
   ```swift
   func testPublishedPropertyUpdates() {
       let viewModel = QueueViewModel()
       let expectation = expectation(description: "Queue updates")
       
       let cancellable = viewModel.$queueItems
           .dropFirst() // Skip initial value
           .sink { _ in expectation.fulfill() }
       
       viewModel.addItem(mockItem)
       wait(for: [expectation], timeout: 1.0)
   }
   ```

3. **Async/Await Testing**
   ```swift
   func testAsyncServiceCall() async throws {
       // Given
       let service = RedditService(networkService: mockNetwork)
       
       // When
       let posts = try await service.fetchSubreddit("swift")
       
       // Then
       XCTAssertEqual(posts.count, 25)
   }
   ```

### Clean Architecture Testing

Based on Briefeed's architecture:

1. **Service Layer Testing with Protocols**
   ```swift
   // Define protocol for testability
   protocol RedditServiceProtocol {
       func fetchSubreddit(_ name: String) async throws -> [RedditPost]
   }
   
   // Mock implementation
   class MockRedditService: RedditServiceProtocol {
       var stubbedPosts: [RedditPost] = []
       var fetchCallCount = 0
       
       func fetchSubreddit(_ name: String) async throws -> [RedditPost] {
           fetchCallCount += 1
           return stubbedPosts
       }
   }
   ```

2. **Core Data Testing with In-Memory Store**
   ```swift
   class CoreDataTestCase: XCTestCase {
       var container: NSPersistentContainer!
       
       override func setUp() {
           super.setUp()
           container = NSPersistentContainer(name: "Briefeed")
           let description = NSPersistentStoreDescription()
           description.type = NSInMemoryStoreType
           container.persistentStoreDescriptions = [description]
           container.loadPersistentStores { _, error in
               XCTAssertNil(error)
           }
       }
   }
   ```

3. **Dependency Injection for Testing**
   ```swift
   class FeedViewModel: ObservableObject {
       private let redditService: RedditServiceProtocol
       
       init(redditService: RedditServiceProtocol = RedditService.shared) {
           self.redditService = redditService
       }
   }
   ```

### Testing Commands (from CLAUDE.md)

```bash
# Run all tests
xcodebuild test -project Briefeed.xcodeproj -scheme Briefeed -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test class
xcodebuild test -project Briefeed.xcodeproj -scheme Briefeed -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:BriefeedTests/RedditServiceTests

# Run with code coverage
xcodebuild test -project Briefeed.xcodeproj -scheme Briefeed -destination 'platform=iOS Simulator,name=iPhone 15' -enableCodeCoverage YES
```

### Briefeed-Specific Testing Patterns

Based on the architecture described in CLAUDE.md:

1. **Service Layer Testing**
   ```swift
   // QueueService Testing
   class QueueServiceTests: XCTestCase {
       func testQueuePersistenceAcrossLaunches() {
           // Test that queue state is saved to UserDefaults
           let service = QueueService()
           service.addToQueue([mockItem])
           
           // Simulate app restart
           let newService = QueueService()
           XCTAssertEqual(newService.queueItems.count, 1)
       }
   }
   
   // AudioService Testing
   class AudioServiceTests: XCTestCase {
       func testAVSpeechSynthesizerConfiguration() {
           let service = AudioService()
           // Test mix-with-others capability
           XCTAssertTrue(AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers))
       }
   }
   ```

2. **Core Data Entity Testing**
   ```swift
   // Test Article, Feed, RSSFeed, RSSEpisode entities
   class CoreDataEntityTests: CoreDataTestCase {
       func testArticleCreation() {
           let article = Article(context: container.viewContext)
           article.title = "Test Article"
           article.link = "https://example.com"
           
           try! container.viewContext.save()
           
           let request: NSFetchRequest<Article> = Article.fetchRequest()
           let results = try! container.viewContext.fetch(request)
           XCTAssertEqual(results.count, 1)
       }
   }
   ```

3. **State Management Testing**
   ```swift
   // UserDefaultsManager Testing
   class UserDefaultsManagerTests: XCTestCase {
       override func tearDown() {
           UserDefaults.standard.removeObject(forKey: "theme")
           super.tearDown()
       }
       
       func testThemePreference() {
           UserDefaultsManager.shared.theme = .dark
           XCTAssertEqual(UserDefaultsManager.shared.theme, .dark)
       }
   }
   ```

4. **Background Processing Testing**
   ```swift
   // Test background summary generation
   func testBackgroundSummaryGeneration() async {
       let queueService = QueueService()
       let article = createMockArticle()
       
       queueService.addToQueue([article])
       
       // Wait for background processing
       await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
       
       XCTAssertNotNil(article.summary)
   }
   ```

5. **Error Handling Testing (async/await)**
   ```swift
   func testServiceErrorPropagation() async {
       let service = GeminiService()
       
       do {
           _ = try await service.generateSummary(for: "test")
           XCTFail("Should throw error")
       } catch {
           XCTAssertTrue(error is GeminiError)
       }
   }
   ```

## Feature 1: Reddit Feed Import (BROKEN - Priority 1)

### Current Issue
Reddit feeds may not import correctly. Need tests to diagnose the exact failure point.

### TDD Implementation Steps

#### Step 1: Write failing tests for Reddit URL validation
```swift
// Test 1: Valid Reddit URLs
func testValidRedditURLRecognition() {
    let validURLs = [
        "https://www.reddit.com/r/swift",
        "https://reddit.com/r/iOSProgramming",
        "https://old.reddit.com/r/apple",
        "https://www.reddit.com/user/example/m/mymultireddit"
    ]
    
    for url in validURLs {
        XCTAssertTrue(RedditService.isRedditURL(url))
    }
}

// Test 2: Invalid Reddit URLs
func testInvalidRedditURLRejection() {
    let invalidURLs = [
        "https://example.com",
        "https://reddit.com", // Missing subreddit
        "https://www.reddit.com/", // Root URL
    ]
    
    for url in invalidURLs {
        XCTAssertFalse(RedditService.isRedditURL(url))
    }
}
```

#### Step 2: Write failing tests for Reddit API response handling
```swift
// Test 3: Successful API response
func testParseValidRedditResponse() async throws {
    let json = """
    {
        "kind": "Listing",
        "data": {
            "children": [{
                "kind": "t3",
                "data": {
                    "title": "Test Post",
                    "selftext": "Content",
                    "url": "https://example.com/article",
                    "author": "testuser",
                    "created_utc": 1234567890,
                    "subreddit": "swift"
                }
            }]
        }
    }
    """
    
    let posts = try RedditService.parseResponse(json.data(using: .utf8)!)
    XCTAssertEqual(posts.count, 1)
    XCTAssertEqual(posts[0].title, "Test Post")
}

// Test 4: Handle rate limit response
func testHandleRateLimitResponse() async {
    let response = HTTPURLResponse(
        url: URL(string: "https://reddit.com")!,
        statusCode: 429,
        httpVersion: nil,
        headerFields: ["X-Ratelimit-Reset": "1234567890"]
    )
    
    do {
        _ = try await RedditService.handleResponse(response)
        XCTFail("Should throw rate limit error")
    } catch let error as RedditError {
        XCTAssertEqual(error, .rateLimited)
    }
}
```

#### Step 3: Write integration test for full import flow
```swift
// Test 5: End-to-end Reddit feed import
func testRedditFeedImportFlow() async throws {
    // Given
    let mockRedditService = MockRedditService()
    mockRedditService.mockPosts = [createMockRedditPost()]
    let feedService = FeedService(redditService: mockRedditService)
    
    // When
    try await feedService.importRedditFeed("https://reddit.com/r/swift")
    
    // Then
    let feeds = feedService.getAllFeeds()
    XCTAssertEqual(feeds.count, 1)
    XCTAssertEqual(feeds[0].title, "r/swift")
    XCTAssertEqual(feeds[0].articles.count, 1)
}
```

### Implementation to Fix Reddit Import

Based on test failures, implement fixes:

```swift
// RedditService+Import.swift
extension RedditService {
    static func isRedditURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        let host = url.host?.lowercased() ?? ""
        
        // Check for reddit domains
        guard host.contains("reddit.com") else { return false }
        
        // Check for valid paths
        let path = url.path
        return path.hasPrefix("/r/") || path.hasPrefix("/user/")
    }
    
    func importFeed(from url: String) async throws -> Feed {
        guard Self.isRedditURL(url) else {
            throw RedditError.invalidURL
        }
        
        // Extract subreddit/multireddit name
        let components = url.components(separatedBy: "/")
        guard let typeIndex = components.firstIndex(where: { $0 == "r" || $0 == "m" }),
              typeIndex + 1 < components.count else {
            throw RedditError.invalidURL
        }
        
        let name = components[typeIndex + 1]
        let isMultireddit = components[typeIndex] == "m"
        
        // Create feed
        let feed = Feed(context: viewContext)
        feed.title = isMultireddit ? "m/\(name)" : "r/\(name)"
        feed.url = url
        feed.type = "reddit"
        
        // Fetch initial posts
        let posts = try await fetchSubreddit(name)
        for post in posts {
            let article = post.toArticle(in: viewContext)
            article.feed = feed
        }
        
        return feed
    }
}
```

## Feature 2: Queue Persistence

### TDD Implementation Steps

#### Step 1: Test queue state persistence
```swift
func testQueuePersistsAcrossAppLaunches() {
    // Given
    let queue = QueueService()
    let testItems = [
        QueuedItem(id: "1", title: "Article 1"),
        QueuedItem(id: "2", title: "Article 2")
    ]
    
    // When
    queue.addItems(testItems)
    queue.saveQueue()
    
    // Simulate app restart
    let newQueue = QueueService()
    
    // Then
    XCTAssertEqual(newQueue.items.count, 2)
    XCTAssertEqual(newQueue.items[0].title, "Article 1")
}
```

#### Step 2: Test queue order preservation
```swift
func testQueueOrderPreservation() {
    // Given
    let queue = QueueService()
    queue.addItems([item1, item2, item3])
    
    // When
    queue.moveItem(from: 2, to: 0)
    queue.saveQueue()
    let restoredQueue = QueueService()
    
    // Then
    XCTAssertEqual(restoredQueue.items[0].id, item3.id)
}
```

## Feature 3: Audio Playback State Management

### TDD Implementation Steps

#### Step 1: Test playback state transitions
```swift
func testPlaybackStateTransitions() {
    let audio = AudioService()
    
    // Initial state
    XCTAssertEqual(audio.playbackState, .stopped)
    
    // Play
    audio.play()
    XCTAssertEqual(audio.playbackState, .playing)
    
    // Pause
    audio.pause()
    XCTAssertEqual(audio.playbackState, .paused)
    
    // Stop
    audio.stop()
    XCTAssertEqual(audio.playbackState, .stopped)
}
```

#### Step 2: Test queue advancement
```swift
func testAutoAdvanceToNextItem() {
    // Given
    let audio = AudioService()
    audio.setQueue([item1, item2])
    
    // When
    audio.play()
    audio.simulateItemCompletion()
    
    // Then
    XCTAssertEqual(audio.currentItem?.id, item2.id)
    XCTAssertEqual(audio.playbackState, .playing)
}
```

## Feature 4: AI Summary Generation

### TDD Implementation Steps

#### Step 1: Test successful summary generation
```swift
func testGeminiSummaryGeneration() async throws {
    // Given
    let mockGemini = MockGeminiService()
    mockGemini.mockResponse = "This is a summary"
    
    // When
    let summary = try await mockGemini.generateSummary(for: "Long article text")
    
    // Then
    XCTAssertEqual(summary, "This is a summary")
}
```

#### Step 2: Test error handling
```swift
func testGeminiAPIKeyMissing() async {
    // Given
    let gemini = GeminiService(apiKey: nil)
    
    // When/Then
    do {
        _ = try await gemini.generateSummary(for: "Text")
        XCTFail("Should throw missing API key error")
    } catch GeminiError.missingAPIKey {
        // Success
    }
}
```

## Feature 5: Feed Refresh and Updates

### TDD Implementation Steps

#### Step 1: Test feed refresh
```swift
func testFeedRefreshUpdatesArticles() async throws {
    // Given
    let feed = createMockFeed(articleCount: 2)
    let feedService = FeedService()
    
    // When
    let newArticles = try await feedService.refresh(feed)
    
    // Then
    XCTAssertGreaterThan(newArticles.count, 0)
    XCTAssertTrue(feed.lastUpdated > Date().addingTimeInterval(-60))
}
```

## Feature 6: RSS Podcast Support

### TDD Implementation Steps

#### Step 1: Test podcast feed parsing
```swift
func testParsePodcastRSSFeed() throws {
    // Given
    let podcastXML = """
    <rss version="2.0">
        <channel>
            <title>Test Podcast</title>
            <item>
                <title>Episode 1</title>
                <enclosure url="https://example.com/ep1.mp3" type="audio/mpeg"/>
                <pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
            </item>
        </channel>
    </rss>
    """
    
    // When
    let episodes = try RSSParser.parsePodcast(podcastXML)
    
    // Then
    XCTAssertEqual(episodes.count, 1)
    XCTAssertEqual(episodes[0].audioURL, "https://example.com/ep1.mp3")
}
```

## Testing Best Practices

### 1. Test Naming Convention
```
test<MethodName>_<Scenario>_<ExpectedResult>
```
Example: `testFetchReddit_WithInvalidURL_ThrowsError`

### 2. Arrange-Act-Assert Pattern
```swift
func testExample() {
    // Arrange (Given)
    let service = MyService()
    let input = "test"
    
    // Act (When)
    let result = service.process(input)
    
    // Assert (Then)
    XCTAssertEqual(result, "expected")
}
```

### 3. Mock Creation
```swift
class MockRedditService: RedditServiceProtocol {
    var fetchSubredditCalled = false
    var mockResponse: [RedditPost] = []
    var mockError: Error?
    
    func fetchSubreddit(_ name: String) async throws -> [RedditPost] {
        fetchSubredditCalled = true
        if let error = mockError { throw error }
        return mockResponse
    }
}
```

### 4. Async Testing
```swift
func testAsyncOperation() async throws {
    // Use async/await for testing async code
    let result = try await service.fetchData()
    XCTAssertNotNil(result)
}
```

## Debugging Strategy for Reddit Import

### Step 1: Network Request Inspection
```swift
func testActualRedditAPICall() async throws {
    // WARNING: This hits real API - use sparingly
    let url = URL(string: "https://www.reddit.com/r/swift.json")!
    var request = URLRequest(url: url)
    request.setValue("Briefeed iOS App", forHTTPHeaderField: "User-Agent")
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    print("Status Code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
    print("Headers: \((response as? HTTPURLResponse)?.allHeaderFields ?? [:])")
    print("Response: \(String(data: data, encoding: .utf8) ?? "nil")")
    
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
}
```

### Step 2: Error Logging
```swift
extension RedditService {
    func fetchWithDetailedLogging(_ url: String) async throws -> Data {
        os_log("Fetching Reddit URL: %@", log: .reddit, type: .info, url)
        
        do {
            let data = try await fetch(url)
            os_log("Success: Received %d bytes", log: .reddit, type: .info, data.count)
            return data
        } catch {
            os_log("Failed: %@", log: .reddit, type: .error, error.localizedDescription)
            throw error
        }
    }
}
```

### Step 3: Response Validation
```swift
func validateRedditResponse(_ data: Data) throws {
    // Check if JSON is valid
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw RedditError.invalidJSON
    }
    
    // Check for error response
    if let error = json["error"] as? String {
        throw RedditError.apiError(error)
    }
    
    // Check for expected structure
    guard let _ = json["data"] as? [String: Any] else {
        throw RedditError.unexpectedFormat
    }
}
```

## Continuous Integration Setup

### Test Execution Script
```bash
#!/bin/bash
# run-tests.sh

echo "Running Unit Tests..."
xcodebuild test \
    -project Briefeed.xcodeproj \
    -scheme Briefeed \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -only-testing:BriefeedTests \
    | xcpretty

echo "Running Integration Tests..."
xcodebuild test \
    -project Briefeed.xcodeproj \
    -scheme Briefeed \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -only-testing:BriefeedIntegrationTests \
    | xcpretty

echo "Generating Coverage Report..."
xcov generate --project Briefeed.xcodeproj --scheme Briefeed
```

## Next Steps

1. **Immediate**: Implement Reddit service tests to diagnose import issue
2. **Week 1**: Core service unit tests
3. **Week 2**: Integration tests for critical paths
4. **Week 3**: UI automation for user flows
5. **Week 4**: Performance and stress testing

This TDD approach will systematically identify and fix issues while building a robust test suite for future development.