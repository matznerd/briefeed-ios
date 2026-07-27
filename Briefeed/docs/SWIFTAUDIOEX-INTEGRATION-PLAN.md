# SwiftAudioEx Integration Plan

## Overview
Replace current TTS-only system with SwiftAudioEx for proper audio playback with full controls.

## Current Problems
1. **No Real Audio Player**: Using AVSpeechSynthesizer (TTS) which isn't a real audio player
2. **No Seeking**: Can't scrub through audio
3. **Limited Speed**: Max 2x (TTS limitation)
4. **No RSS Support**: Can't play podcast episodes
5. **UI Not Updating**: Player shows "No story playing" even when playing

## SwiftAudioEx Benefits
- ✅ Real audio player with full controls
- ✅ Seeking/scrubbing support
- ✅ Speed control up to 20x
- ✅ Background audio
- ✅ Now Playing info
- ✅ Remote control support
- ✅ Streaming URLs (RSS podcasts)

## Architecture Design

### 1. Audio Service Layer
```swift
protocol AudioPlaybackService {
    func play(url: URL) async throws
    func play(data: Data) async throws
    func pause()
    func resume()
    func stop()
    func seek(to: TimeInterval)
    func setRate(_ rate: Float)
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var isPlaying: Bool { get }
}

// Two implementations:
class SwiftAudioExService: AudioPlaybackService { 
    // For audio files and streaming
}

class TTSService: AudioPlaybackService {
    // For text-to-speech generation
}
```

### 2. Audio Pipeline
```
Article → Generate TTS → Save as audio file → Play with SwiftAudioEx
RSS Episode → Direct URL → Stream with SwiftAudioEx
```

### 3. State Management
```swift
class UnifiedAudioPlayer {
    private let audioPlayer: SwiftAudioEx.AudioPlayer
    private let ttsGenerator: TTSService
    
    func play(item: QueueItem) async {
        switch item {
        case .article(let article):
            // 1. Generate TTS audio file
            let audioFile = await ttsGenerator.generate(article.content)
            // 2. Play with SwiftAudioEx
            audioPlayer.load(audioFile)
            audioPlayer.play()
            
        case .rssEpisode(let episode):
            // Direct streaming
            audioPlayer.load(episode.audioURL)
            audioPlayer.play()
        }
    }
}
```

## Test Plan

### Unit Tests

```swift
// Test 1: Audio Player Initialization
func testAudioPlayerInitialization() {
    let player = SwiftAudioExService()
    XCTAssertNotNil(player)
    XCTAssertFalse(player.isPlaying)
    XCTAssertEqual(player.currentTime, 0)
}

// Test 2: Play Audio File
func testPlayAudioFile() async {
    let player = SwiftAudioExService()
    let testAudioURL = Bundle.main.url(forResource: "test", withExtension: "mp3")!
    
    await player.play(url: testAudioURL)
    XCTAssertTrue(player.isPlaying)
    XCTAssertGreaterThan(player.duration, 0)
}

// Test 3: Speed Control
func testSpeedControl() async {
    let player = SwiftAudioExService()
    await player.play(url: testAudioURL)
    
    player.setRate(2.0)
    XCTAssertEqual(player.rate, 2.0)
    
    player.setRate(20.0)
    XCTAssertEqual(player.rate, 20.0)
}

// Test 4: Seeking
func testSeeking() async {
    let player = SwiftAudioExService()
    await player.play(url: testAudioURL)
    
    player.seek(to: 30.0)
    XCTAssertEqual(player.currentTime, 30.0, accuracy: 0.5)
}

// Test 5: TTS Generation
func testTTSGeneration() async {
    let tts = TTSService()
    let text = "Hello world"
    
    let audioFile = await tts.generate(text)
    XCTAssertNotNil(audioFile)
    XCTAssertTrue(FileManager.default.fileExists(atPath: audioFile.path))
}

// Test 6: Queue Integration
func testQueueWithSwiftAudioEx() async {
    let player = UnifiedAudioPlayer()
    let article = createTestArticle()
    
    await player.play(item: .article(article))
    XCTAssertTrue(player.isPlaying)
    XCTAssertEqual(player.currentTitle, article.title)
}

// Test 7: RSS Streaming
func testRSSStreaming() async {
    let player = UnifiedAudioPlayer()
    let episode = createTestRSSEpisode()
    
    await player.play(item: .rssEpisode(episode))
    XCTAssertTrue(player.isPlaying)
    XCTAssertEqual(player.currentTitle, episode.title)
}

// Test 8: Background Playback
func testBackgroundPlayback() async {
    let player = SwiftAudioExService()
    await player.play(url: testAudioURL)
    
    // Simulate app backgrounding
    NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    
    XCTAssertTrue(player.isPlaying)
}

// Test 9: Remote Control
func testRemoteControl() async {
    let player = SwiftAudioExService()
    await player.play(url: testAudioURL)
    
    // Simulate remote control events
    player.handleRemoteCommand(.play)
    XCTAssertTrue(player.isPlaying)
    
    player.handleRemoteCommand(.pause)
    XCTAssertFalse(player.isPlaying)
}

// Test 10: State Persistence
func testStatePersistence() async {
    let player = UnifiedAudioPlayer()
    await player.play(item: testItem)
    player.seek(to: 45.0)
    
    let state = player.saveState()
    
    let newPlayer = UnifiedAudioPlayer()
    await newPlayer.restoreState(state)
    
    XCTAssertEqual(newPlayer.currentTime, 45.0, accuracy: 1.0)
    XCTAssertEqual(newPlayer.currentTitle, testItem.title)
}
```

### Integration Tests

```swift
// Test 11: Full Article Playback Flow
func testArticlePlaybackFlow() async {
    // 1. Add article to queue
    // 2. Generate TTS
    // 3. Play with SwiftAudioEx
    // 4. Verify UI updates
    // 5. Test controls (pause, seek, speed)
}

// Test 12: RSS Episode Playback Flow
func testRSSPlaybackFlow() async {
    // 1. Add RSS episode to queue
    // 2. Stream directly
    // 3. Verify UI updates
    // 4. Test controls
}

// Test 13: Mixed Queue
func testMixedQueue() async {
    // 1. Add both articles and RSS episodes
    // 2. Play through queue
    // 3. Verify smooth transitions
}
```

## Implementation Steps

### Phase 1: Setup (Day 1)
1. Add SwiftAudioEx dependency
2. Create AudioPlaybackService protocol
3. Implement SwiftAudioExService
4. Write unit tests

### Phase 2: TTS Integration (Day 2)
1. Modify TTS to generate audio files
2. Cache audio files
3. Connect TTS output to SwiftAudioEx
4. Test article playback

### Phase 3: RSS Integration (Day 3)
1. Implement RSS streaming
2. Handle different audio formats
3. Test with real RSS feeds
4. Add error handling

### Phase 4: UI Integration (Day 4)
1. Update AudioPlayerViewModel
2. Connect SwiftAudioEx events to UI
3. Implement seeking UI
4. Add speed controls up to 20x

### Phase 5: Polish (Day 5)
1. Background playback
2. Remote control
3. Now Playing info
4. State persistence

## Dependencies

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/doublesymmetry/SwiftAudioEx.git", from: "1.0.0")
]
```

## Migration Strategy

1. **Keep existing TTS service** for text generation
2. **Add SwiftAudioEx** alongside, not replacing initially
3. **Feature flag** to switch between old and new
4. **Gradual rollout** with testing

## Success Criteria

- [ ] Audio plays without "No story playing" bug
- [ ] Seeking works smoothly
- [ ] Speed control up to 20x
- [ ] RSS episodes stream properly
- [ ] Background playback works
- [ ] All tests pass
- [ ] No UI freezes
- [ ] State persists correctly

## Risk Mitigation

1. **Risk**: SwiftAudioEx compatibility issues
   - **Mitigation**: Test on all iOS versions
   
2. **Risk**: Large audio files from TTS
   - **Mitigation**: Implement chunking and streaming
   
3. **Risk**: Memory issues with caching
   - **Mitigation**: LRU cache with size limits

## Code Example

```swift
import SwiftAudioEx

class SwiftAudioExService: NSObject, AudioPlaybackService {
    private let player = AudioPlayer()
    weak var delegate: AudioServiceDelegate?
    
    override init() {
        super.init()
        setupPlayer()
    }
    
    private func setupPlayer() {
        player.delegate = self
        player.remoteCommandController.isEnabled = true
    }
    
    func play(url: URL) async throws {
        let item = DefaultAudioItem(
            audioUrl: url.absoluteString,
            sourceType: .stream
        )
        
        try await player.load(item: item)
        player.play()
    }
    
    func setRate(_ rate: Float) {
        player.rate = rate // Supports up to 20x!
    }
    
    func seek(to time: TimeInterval) {
        player.seek(to: time)
    }
}

extension SwiftAudioExService: AudioPlayerDelegate {
    func audioPlayer(_ player: AudioPlayer, didChangeState state: AudioPlayerState) {
        // Update UI through delegate
        switch state {
        case .playing:
            delegate?.audioStateChanged(to: .playing, from: .paused)
        case .paused:
            delegate?.audioStateChanged(to: .paused, from: .playing)
        // etc...
        }
    }
    
    func audioPlayer(_ player: AudioPlayer, didUpdateProgress progress: TimeInterval, duration: TimeInterval) {
        delegate?.audioProgressUpdated(
            progress: Float(progress / duration),
            currentTime: progress,
            duration: duration
        )
    }
}
```

## Timeline

- **Week 1**: Core integration + tests
- **Week 2**: UI updates + polish
- **Week 3**: Testing + bug fixes
- **Week 4**: Release

## Next Steps

1. Review and approve plan
2. Create feature branch
3. Start with Phase 1
4. Daily progress updates