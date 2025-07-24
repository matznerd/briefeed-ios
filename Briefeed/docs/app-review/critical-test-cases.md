# Critical Test Cases for Debugging Briefeed Issues

## Priority 1: Reddit Feed Import Failure

### Diagnostic Test Suite

These tests are designed to pinpoint exactly where Reddit import is failing.

#### 1. Network Layer Tests
```swift
// Test if Reddit API is reachable
func testRedditAPIReachability() async throws {
    let url = URL(string: "https://www.reddit.com/r/swift.json")!
    let (_, response) = try await URLSession.shared.data(from: url)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
}

// Test User-Agent requirement
func testRedditRequiresUserAgent() async throws {
    let url = URL(string: "https://www.reddit.com/r/swift.json")!
    
    // Without User-Agent
    var request1 = URLRequest(url: url)
    do {
        _ = try await URLSession.shared.data(for: request1)
        XCTFail("Should fail without User-Agent")
    } catch {
        // Expected
    }
    
    // With User-Agent
    var request2 = URLRequest(url: url)
    request2.setValue("Briefeed iOS App", forHTTPHeaderField: "User-Agent")
    let (_, response) = try await URLSession.shared.data(for: request2)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
}
```

#### 2. URL Parsing Tests
```swift
// Test Reddit URL pattern recognition
func testRedditURLPatternMatching() {
    let testCases = [
        ("https://www.reddit.com/r/swift", true, "r/swift"),
        ("https://reddit.com/r/iOSProgramming/", true, "r/iOSProgramming"),
        ("https://old.reddit.com/r/apple", true, "r/apple"),
        ("https://www.reddit.com/user/spez/m/programming", true, "m/programming"),
        ("https://reddit.com", false, nil),
        ("https://example.com", false, nil)
    ]
    
    for (url, shouldMatch, expectedName) in testCases {
        let result = RedditService.parseRedditURL(url)
        XCTAssertEqual(result.isValid, shouldMatch, "URL: \(url)")
        if shouldMatch {
            XCTAssertEqual(result.name, expectedName)
        }
    }
}
```

#### 3. JSON Parsing Tests
```swift
// Test actual Reddit JSON structure
func testParseRealRedditJSON() throws {
    let json = """
    {
        "kind": "Listing",
        "data": {
            "after": "t3_abc123",
            "children": [
                {
                    "kind": "t3",
                    "data": {
                        "title": "Swift 6.0 Released",
                        "selftext": "",
                        "url": "https://swift.org/blog/swift-6-released/",
                        "author": "swiftlang",
                        "created_utc": 1704067200,
                        "subreddit": "swift",
                        "domain": "swift.org",
                        "is_video": false,
                        "is_self": false
                    }
                }
            ]
        }
    }
    """
    
    let data = json.data(using: .utf8)!
    let response = try JSONDecoder().decode(RedditResponse.self, from: data)
    
    XCTAssertEqual(response.data.children.count, 1)
    XCTAssertEqual(response.data.children[0].data.title, "Swift 6.0 Released")
}

// Test malformed JSON handling
func testHandleMalformedRedditJSON() {
    let badJSON = "{ invalid json }"
    let data = badJSON.data(using: .utf8)!
    
    XCTAssertThrowsError(try JSONDecoder().decode(RedditResponse.self, from: data))
}
```

#### 4. Core Data Integration Tests
```swift
// Test Reddit post to Article conversion
func testRedditPostToArticleConversion() {
    let context = PersistenceController.preview.container.viewContext
    
    let post = RedditPost(
        title: "Test Post",
        selftext: "Content",
        url: "https://example.com",
        author: "testuser",
        created_utc: 1704067200,
        subreddit: "swift",
        domain: "example.com",
        is_video: false,
        is_self: false
    )
    
    let article = post.toArticle(context: context)
    
    XCTAssertEqual(article.title, "Test Post")
    XCTAssertEqual(article.author, "testuser")
    XCTAssertEqual(article.link, "https://example.com")
    XCTAssertNotNil(article.pubDate)
}
```

#### 5. Feed Creation Tests
```swift
// Test Reddit feed creation in Core Data
func testCreateRedditFeed() throws {
    let context = PersistenceController.preview.container.viewContext
    
    let feed = Feed(context: context)
    feed.title = "r/swift"
    feed.url = "https://www.reddit.com/r/swift"
    feed.type = "reddit"
    feed.id = UUID()
    
    try context.save()
    
    let fetchRequest: NSFetchRequest<Feed> = Feed.fetchRequest()
    fetchRequest.predicate = NSPredicate(format: "type == %@", "reddit")
    
    let results = try context.fetch(fetchRequest)
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results[0].title, "r/swift")
}
```

### Integration Test for Complete Flow
```swift
func testCompleteRedditImportFlow() async throws {
    // 1. Test URL validation
    let url = "https://www.reddit.com/r/swift"
    XCTAssertTrue(RedditService.isValidRedditURL(url))
    
    // 2. Test network request
    let redditService = RedditService()
    let posts = try await redditService.fetchSubreddit("swift")
    XCTAssertGreaterThan(posts.count, 0)
    
    // 3. Test Core Data persistence
    let context = PersistenceController.preview.container.viewContext
    let feed = Feed(context: context)
    feed.title = "r/swift"
    feed.url = url
    
    // 4. Test article creation
    for post in posts.prefix(5) {
        let article = post.toArticle(context: context)
        article.feed = feed
    }
    
    try context.save()
    
    // 5. Verify persistence
    let articleRequest: NSFetchRequest<Article> = Article.fetchRequest()
    articleRequest.predicate = NSPredicate(format: "feed == %@", feed)
    let articles = try context.fetch(articleRequest)
    
    XCTAssertEqual(articles.count, min(posts.count, 5))
}
```

## Priority 2: Queue Persistence Issues

### Critical Test Cases

#### 1. Queue State Persistence
```swift
func testQueueSurvivesAppTermination() {
    // Save queue
    let queue = QueueService.shared
    queue.addToQueue([mockArticle1, mockArticle2])
    
    // Simulate app termination
    queue.saveQueue()
    QueueService.resetShared() // Force singleton reset
    
    // Restore queue
    let restoredQueue = QueueService.shared
    XCTAssertEqual(restoredQueue.queueItems.count, 2)
}
```

#### 2. Queue Data Integrity
```swift
func testQueueDataIntegrity() {
    let originalItem = EnhancedQueueItem(
        id: "test-123",
        title: "Test Article",
        content: "Long content...",
        author: "Author",
        source: "Source",
        type: .article,
        audioText: "Audio version",
        isSummary: true
    )
    
    // Encode
    let encoded = try JSONEncoder().encode(originalItem)
    
    // Decode
    let decoded = try JSONDecoder().decode(EnhancedQueueItem.self, from: encoded)
    
    XCTAssertEqual(decoded.id, originalItem.id)
    XCTAssertEqual(decoded.title, originalItem.title)
    XCTAssertEqual(decoded.type, originalItem.type)
}
```

## Priority 3: Audio Service State Management

### Critical Test Cases

#### 1. Audio Session Configuration
```swift
func testAudioSessionConfiguration() {
    let audioService = AudioService.shared
    
    XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
    XCTAssertTrue(AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers))
}
```

#### 2. Playback State Consistency
```swift
func testPlaybackStateConsistency() async {
    let audio = AudioService.shared
    
    // Initial state
    XCTAssertFalse(audio.isPlaying)
    XCTAssertNil(audio.currentItem)
    
    // Add item and play
    audio.setQueueItems([mockQueueItem])
    audio.play()
    
    // Wait for state update
    try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
    
    XCTAssertTrue(audio.isPlaying)
    XCTAssertNotNil(audio.currentItem)
    
    // Pause
    audio.pause()
    XCTAssertFalse(audio.isPlaying)
    XCTAssertNotNil(audio.currentItem) // Should retain current item
}
```

## Priority 4: API Integration Tests

### Gemini Service Tests
```swift
func testGeminiAPIKeyValidation() async {
    // Missing API key
    UserDefaults.standard.removeObject(forKey: "geminiAPIKey")
    let service1 = GeminiService()
    
    do {
        _ = try await service1.generateSummary(for: "test")
        XCTFail("Should throw missing API key error")
    } catch {
        XCTAssertTrue(error is GeminiError)
    }
    
    // Valid API key
    UserDefaults.standard.set("test-key", forKey: "geminiAPIKey")
    let service2 = GeminiService()
    XCTAssertNotNil(service2) // Should initialize
}
```

### Firecrawl Service Tests
```swift
func testFirecrawlContentExtraction() async throws {
    let service = FirecrawlService()
    
    // Test with mock response
    let mockHTML = "<html><body><p>Article content</p></body></html>"
    let extracted = service.extractContent(from: mockHTML)
    
    XCTAssertEqual(extracted, "Article content")
}
```

## Priority 5: UI State Synchronization

### Critical Test Cases

#### 1. Feed List Updates
```swift
func testFeedListUpdatesOnAdd() async {
    let viewModel = FeedListViewModel()
    let initialCount = viewModel.feeds.count
    
    // Add feed
    await viewModel.addFeed(url: "https://example.com/feed.xml")
    
    XCTAssertEqual(viewModel.feeds.count, initialCount + 1)
    XCTAssertFalse(viewModel.isLoading)
}
```

#### 2. Queue UI Updates
```swift
func testQueueUIUpdatesOnReorder() {
    let viewModel = BriefViewModel()
    viewModel.queueItems = [item1, item2, item3]
    
    // Reorder
    viewModel.moveItem(from: IndexSet(integer: 2), to: 0)
    
    XCTAssertEqual(viewModel.queueItems[0].id, item3.id)
    XCTAssertEqual(viewModel.queueItems[1].id, item1.id)
}
```

## Debugging Workflow

### Step 1: Run Network Diagnostics
```bash
# Test Reddit API directly
curl -H "User-Agent: Briefeed Test" https://www.reddit.com/r/swift.json | jq .
```

### Step 2: Enable Verbose Logging
```swift
// Add to AppDelegate or BriefeedApp
let subsystem = "com.briefeed.app"

extension OSLog {
    static let reddit = OSLog(subsystem: subsystem, category: "Reddit")
    static let queue = OSLog(subsystem: subsystem, category: "Queue")
    static let audio = OSLog(subsystem: subsystem, category: "Audio")
}

// Use in services
os_log("Fetching Reddit feed: %@", log: .reddit, type: .info, url)
```

### Step 3: Add Debug UI
```swift
// Debug view for testing
struct DebugView: View {
    var body: some View {
        List {
            Section("Reddit Import") {
                Button("Test Reddit API") {
                    Task {
                        await testRedditAPI()
                    }
                }
                
                Button("Test URL Parsing") {
                    testURLParsing()
                }
            }
            
            Section("Queue") {
                Button("Test Queue Save/Load") {
                    testQueuePersistence()
                }
            }
        }
    }
}
```

## Test Execution Order

1. **Network Tests First** - Verify external dependencies
2. **Data Model Tests** - Ensure data structures are correct
3. **Service Tests** - Test business logic
4. **Integration Tests** - Test component interactions
5. **UI Tests** - Verify user-facing functionality

## Success Criteria

- All Reddit import tests pass
- Queue persistence works across app launches
- Audio state remains consistent
- No memory leaks in long-running tests
- UI updates reflect data changes immediately

These critical test cases will help identify the root causes of the Reddit import failure and other issues in the app.