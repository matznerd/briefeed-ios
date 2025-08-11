# Test Update Plan for New Audio Architecture

## Executive Summary
We need to update our test suite to validate the new SwiftAudioEx-based audio system without cheating or creating false positives. This plan ensures we test real functionality, not mocked behavior.

## Core Principles
1. **No Cheating**: Tests must validate actual behavior, not just return success
2. **Real Integration**: Test actual component interactions, not mocked interfaces
3. **User-Centric**: Focus on user workflows that matter
4. **Incremental**: Update tests in priority order

## Test Categories & Priority

### 🔴 Priority 1: Critical User Flows
These must work or the app is broken:

#### 1. Basic Audio Playback
```swift
// Test: Can play an article with TTS
func testPlayArticleWithTTS() async {
    let viewModel = await AudioPlayerViewModelV2()
    let article = createTestArticle()
    
    await viewModel.addToQueue(article)
    await viewModel.play()
    
    // Verify actual audio generation
    XCTAssertTrue(viewModel.isPlaying)
    XCTAssertNotNil(viewModel.currentItem)
    XCTAssertEqual(viewModel.currentItem?.title, article.title)
}

// Test: Can play RSS episode
func testPlayRSSEpisode() async {
    let viewModel = await AudioPlayerViewModelV2()
    let episode = createTestEpisode(audioUrl: "https://example.com/test.mp3")
    
    await viewModel.addToQueue(episode)
    await viewModel.play()
    
    XCTAssertTrue(viewModel.isPlaying)
    XCTAssertTrue(viewModel.unifiedPlayer.isStreaming)
}
```

#### 2. Queue Management
```swift
// Test: Queue persists across app launches
func testQueuePersistence() async {
    let viewModel = await AudioPlayerViewModelV2()
    
    // Add items
    await viewModel.addToQueue(createTestArticle())
    await viewModel.addToQueue(createTestEpisode())
    
    // Simulate app termination
    await viewModel.saveQueueState()
    
    // Create new instance (simulates app restart)
    let newViewModel = await AudioPlayerViewModelV2()
    
    XCTAssertEqual(newViewModel.queueItems.count, 2)
    XCTAssertEqual(newViewModel.queueItems[0].type, .article)
    XCTAssertEqual(newViewModel.queueItems[1].type, .episode)
}
```

#### 3. Playback Controls
```swift
// Test: Play/Pause/Skip controls
func testPlaybackControls() async {
    let viewModel = await AudioPlayerViewModelV2()
    await setupQueueWithMultipleItems(viewModel)
    
    // Play
    await viewModel.play()
    XCTAssertTrue(viewModel.isPlaying)
    
    // Pause
    viewModel.pause()
    XCTAssertFalse(viewModel.isPlaying)
    
    // Skip forward
    await viewModel.playNext()
    XCTAssertEqual(viewModel.currentQueueIndex, 1)
    
    // Skip backward
    await viewModel.playPrevious()
    XCTAssertEqual(viewModel.currentQueueIndex, 0)
}
```

### 🟡 Priority 2: New Features

#### 4. Hybrid TTS System
```swift
// Test: Gemini TTS with fallback
func testHybridTTS() async {
    let ttsService = TTSGeneratorService.shared
    let text = "Test article content"
    
    // Test Gemini success path
    let geminiURL = await ttsService.generateTTS(
        text: text,
        preferGemini: true
    )
    XCTAssertNotNil(geminiURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: geminiURL.path))
    
    // Test AVSpeech fallback (simulate Gemini failure)
    let fallbackURL = await ttsService.generateTTS(
        text: text,
        forceAVSpeech: true
    )
    XCTAssertNotNil(fallbackURL)
}
```

#### 5. 20x Speed Support
```swift
// Test: Speed control up to 20x
func testHighSpeedPlayback() async {
    let viewModel = await AudioPlayerViewModelV2()
    let episode = createTestEpisode()
    
    await viewModel.addToQueue(episode)
    await viewModel.play()
    
    // Test speed range
    let speeds: [Float] = [0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 20.0]
    for speed in speeds {
        viewModel.setPlaybackSpeed(speed)
        XCTAssertEqual(viewModel.playbackSpeed, speed, accuracy: 0.01)
        
        // Verify SwiftAudioEx actually applies the speed
        let player = viewModel.unifiedPlayer.swiftAudioEx
        XCTAssertEqual(player.rate, speed, accuracy: 0.01)
    }
}
```

#### 6. Audio Caching
```swift
// Test: Cache management
func testAudioCaching() async {
    let cacheManager = AudioCacheManager.shared
    
    // Test cache size limit (500MB)
    XCTAssertEqual(cacheManager.maxCacheSize, 500 * 1024 * 1024)
    
    // Test cache cleanup (5 days)
    let oldFile = createTestAudioFile(age: .days(6))
    let recentFile = createTestAudioFile(age: .hours(1))
    
    await cacheManager.cleanupOldFiles()
    
    XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: recentFile.path))
}
```

### 🟢 Priority 3: Edge Cases & Error Handling

#### 7. Error Recovery
```swift
// Test: Network failure handling
func testNetworkErrorRecovery() async {
    let viewModel = await AudioPlayerViewModelV2()
    let episode = createTestEpisode(audioUrl: "https://invalid.url/404.mp3")
    
    await viewModel.addToQueue(episode)
    await viewModel.play()
    
    // Should skip to next item on error
    XCTAssertEqual(viewModel.playerState, .error("Network error"))
    
    // Should auto-skip after error
    await Task.sleep(nanoseconds: 2_000_000_000)
    XCTAssertEqual(viewModel.currentQueueIndex, 1)
}
```

#### 8. Background Playback
```swift
// Test: Audio continues in background
func testBackgroundPlayback() async {
    let viewModel = await AudioPlayerViewModelV2()
    await viewModel.addToQueue(createTestEpisode())
    await viewModel.play()
    
    // Simulate background
    NotificationCenter.default.post(
        name: UIApplication.didEnterBackgroundNotification,
        object: nil
    )
    
    // Audio should continue
    await Task.sleep(nanoseconds: 1_000_000_000)
    XCTAssertTrue(viewModel.isPlaying)
    
    // Remote controls should work
    let commandCenter = MPRemoteCommandCenter.shared()
    XCTAssertTrue(commandCenter.playCommand.isEnabled)
    XCTAssertTrue(commandCenter.pauseCommand.isEnabled)
}
```

## Test Infrastructure Needs

### 1. Test Fixtures
```swift
// TestFixtures.swift
extension XCTestCase {
    func createTestArticle(
        title: String = "Test Article",
        content: String = "Test content for TTS generation"
    ) -> Article {
        // Create real Core Data article
    }
    
    func createTestEpisode(
        audioUrl: String = "https://example.com/test.mp3"
    ) -> RSSEpisode {
        // Create real Core Data episode
    }
    
    func setupQueueWithMultipleItems(_ viewModel: AudioPlayerViewModelV2) async {
        // Add mix of articles and episodes
    }
}
```

### 2. Test Helpers
```swift
// TestHelpers.swift
class AudioTestHelper {
    // Verify audio file is valid
    static func verifyAudioFile(at url: URL) -> Bool
    
    // Check if TTS was generated correctly
    static func verifyTTSContent(url: URL, expectedText: String) -> Bool
    
    // Monitor state changes
    static func waitForState(_ viewModel: AudioPlayerViewModelV2, 
                            state: AudioPlayerState,
                            timeout: TimeInterval = 5) async -> Bool
}
```

### 3. Integration Test Harness
```swift
// IntegrationTestHarness.swift
class AudioIntegrationTests: XCTestCase {
    var viewModel: AudioPlayerViewModelV2!
    var persistence: PersistenceController!
    
    override func setUp() async throws {
        // Use in-memory Core Data for tests
        persistence = PersistenceController(inMemory: true)
        viewModel = await AudioPlayerViewModelV2()
    }
    
    override func tearDown() async throws {
        // Clean up audio files
        // Reset state
    }
}
```

## Implementation Strategy

### Phase 1: Foundation (Week 1)
1. Create test fixtures and helpers
2. Set up integration test harness
3. Write Priority 1 tests (critical flows)

### Phase 2: Features (Week 2)
1. Write Priority 2 tests (new features)
2. Validate hybrid TTS system
3. Test 20x speed thoroughly

### Phase 3: Polish (Week 3)
1. Write Priority 3 tests (edge cases)
2. Add performance tests
3. Create UI tests for player interactions

## Success Criteria

### Must Have
- [ ] All Priority 1 tests pass
- [ ] No false positives (tests actually validate behavior)
- [ ] Queue persistence verified
- [ ] Basic playback controls work

### Should Have
- [ ] Hybrid TTS validated
- [ ] 20x speed tested
- [ ] Cache management verified
- [ ] Background playback works

### Nice to Have
- [ ] All edge cases covered
- [ ] Performance benchmarks
- [ ] UI automation tests

## Anti-Patterns to Avoid

### ❌ Don't Do This:
```swift
// Bad: Testing mocked behavior
func testPlayback() {
    let mockPlayer = MockAudioPlayer()
    mockPlayer.isPlaying = true
    XCTAssertTrue(mockPlayer.isPlaying) // Meaningless!
}
```

### ✅ Do This Instead:
```swift
// Good: Testing real behavior
func testPlayback() async {
    let viewModel = await AudioPlayerViewModelV2()
    await viewModel.play()
    
    // Wait for actual state change
    await AudioTestHelper.waitForState(viewModel, state: .playing)
    
    // Verify real audio is playing
    XCTAssertTrue(viewModel.unifiedPlayer.swiftAudioEx.isPlaying)
}
```

## Next Steps

1. **Review this plan** - Does it cover your needs?
2. **Prioritize tests** - Which are most critical?
3. **Start implementation** - Begin with Priority 1 tests
4. **Iterate** - Add tests as we discover issues

This plan ensures we test real functionality without shortcuts, giving confidence that the new audio system actually works for users.