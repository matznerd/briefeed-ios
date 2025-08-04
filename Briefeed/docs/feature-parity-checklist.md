# Feature Parity Checklist: BriefeedAudioService vs AudioService

## ✅ Already Implemented in BriefeedAudioService

### Core Playback
- ✅ `playArticle(_:)` - Play articles with TTS generation
- ✅ `playRSSEpisode(_:)` - Play RSS episodes
- ✅ `play()`, `pause()`, `stop()` - Basic controls
- ✅ `togglePlayPause()` - Toggle control
- ✅ `skipForward()`, `skipBackward()` - Skip with correct intervals (15s/30s)
- ✅ `seek(to:)` - Direct seeking
- ✅ `setPlaybackRate(_:)` - Speed control

### Queue Management
- ✅ `addToQueue(_:)` for both Article and RSSEpisode
- ✅ `removeFromQueue(at:)` - Remove specific item
- ✅ `clearQueue()` - Clear entire queue
- ✅ `playNext()`, `playPrevious()` - Queue navigation
- ✅ Queue persistence with UserDefaults
- ✅ Background TTS generation for queued articles

### State Management
- ✅ `@Published currentItem: BriefeedAudioItem?`
- ✅ `@Published currentPlaybackItem: CurrentPlaybackItem?`
- ✅ `@Published isPlaying: Bool`
- ✅ `@Published isLoading: Bool`
- ✅ `@Published currentTime: TimeInterval`
- ✅ `@Published duration: TimeInterval`
- ✅ `@Published playbackRate: Float`
- ✅ `@Published queue: [BriefeedAudioItem]`
- ✅ `@Published queueIndex: Int`
- ✅ `@Published lastError: Error?`

### Advanced Features
- ✅ Sleep timer support
- ✅ Playback history tracking
- ✅ Audio caching
- ✅ TTS generation (Gemini + device fallback)
- ✅ Error handling

## ❌ Missing from BriefeedAudioService

### Critical Missing Features

1. **Published Properties for UI Compatibility**
```swift
// Old AudioService has these, needed by UI:
@Published var currentArticle: Article?
@Published var volume: Float = 1.0
@Published var state: CurrentValueSubject<AudioPlayerState, Never>
@Published var progress: CurrentValueSubject<Float, Never>
```

2. **Convenience Methods**
```swift
// Methods UI components expect:
func playNow(_ article: Article) async
func playAfterCurrent(_ article: Article) async
func restoreQueueState(articles: [Article])
func setSpeechRate(_ rate: Float) // UI uses this name
```

3. **Background Audio Session**
```swift
// Proper configuration needed:
func configureBackgroundAudio() throws
// Setup remote commands (play/pause from lock screen)
// Setup Now Playing info
// Handle interruptions (phone calls)
// Handle route changes (headphones)
```

4. **State Management**
```swift
// AudioPlayerState enum compatibility:
enum AudioPlayerState {
    case idle, loading, playing, paused, stopped, error(Error)
}
// Need to expose this state for UI
```

5. **RSS-Specific Methods**
```swift
// From AudioService+RSS:
func playRSSEpisode(url: URL, title: String, episode: RSSEpisode?) async
func resumeRSSEpisode(_ episode: RSSEpisode) async
var isPlayingRSS: Bool { get }
func playWithRSSSupport()
func pauseWithRSSSupport()
```

6. **Queue Insertion**
```swift
// Insert at specific position:
func insertInQueue(_ article: Article, at index: Int) async
func moveQueueItem(from: Int, to: Int)
```

7. **SwiftAudioEx Integration Issues**
```swift
// Need to properly handle:
- AVPlayerWrapperState changes
- Remote command setup
- Now Playing info updates
- Audio session interruptions
```

## 🔧 Implementation Plan

### Step 1: Add Missing Published Properties
```swift
extension BriefeedAudioService {
    // For backward compatibility
    @Published var currentArticle: Article? {
        didSet {
            // Update currentPlaybackItem
        }
    }
    
    // State publisher for UI
    var state: CurrentValueSubject<AudioPlayerState, Never> = .init(.idle)
    
    // Progress publisher
    var progress: CurrentValueSubject<Float, Never> = .init(0.0)
}
```

### Step 2: Add Convenience Methods
```swift
extension BriefeedAudioService {
    func playNow(_ article: Article) async {
        clearQueue()
        await playArticle(article)
    }
    
    func playAfterCurrent(_ article: Article) async {
        let insertIndex = max(0, queueIndex + 1)
        await insertInQueue(article, at: insertIndex)
    }
    
    func setSpeechRate(_ rate: Float) {
        setPlaybackRate(rate) // Alias for compatibility
    }
}
```

### Step 3: Fix Background Audio
```swift
private func setupAudioPlayer() {
    // Configure remote commands
    audioPlayer.remoteCommands = [
        .play, .pause, .skipForward, .skipBackward,
        .changePlaybackPosition, .changePlaybackRate
    ]
    
    // Handle events
    audioPlayer.event.stateChange.addListener(self, handleStateChange)
    audioPlayer.event.updateDuration.addListener(self, handleDurationUpdate)
    audioPlayer.event.secondElapse.addListener(self, handleTimeUpdate)
    audioPlayer.event.playbackEnd.addListener(self, handlePlaybackEnd)
    
    // Setup Now Playing
    setupNowPlaying()
}
```

### Step 4: Handle State Transitions
```swift
private func handleStateChange(_ state: AVPlayerWrapperState) {
    switch state {
    case .loading:
        self.state.send(.loading)
        isLoading = true
        isPlaying = false
    case .playing:
        self.state.send(.playing)
        isLoading = false
        isPlaying = true
    case .paused:
        self.state.send(.paused)
        isLoading = false
        isPlaying = false
    case .idle, .ready:
        self.state.send(.idle)
        isLoading = false
        isPlaying = false
    case .failed(let error):
        self.state.send(.error(error))
        isLoading = false
        isPlaying = false
        lastError = error
    }
}
```

### Step 5: Add RSS-Specific Support
```swift
extension BriefeedAudioService {
    func playRSSEpisode(url: URL, title: String, episode: RSSEpisode?) async {
        if let episode = episode {
            await playRSSEpisode(episode)
        } else {
            // Create temporary episode or handle URL directly
            await play(from: url, title: title)
        }
    }
    
    var isPlayingRSS: Bool {
        currentItem?.content.contentType == .rssEpisode && isPlaying
    }
}
```

## 📝 Test Coverage Needed

### Unit Tests
```swift
// BriefeedAudioServiceTests.swift
class BriefeedAudioServiceTests: XCTestCase {
    func testPlayArticle() async
    func testPlayRSSEpisode() async
    func testQueueManagement() async
    func testStateTransitions() async
    func testBackgroundAudio() async
    func testRemoteCommands() async
    func testQueuePersistence() async
    func testErrorHandling() async
    func testSleepTimer() async
    func testPlaybackHistory() async
}
```

### Integration Tests
```swift
// AudioIntegrationTests.swift
class AudioIntegrationTests: XCTestCase {
    func testEndToEndArticlePlayback() async
    func testEndToEndRSSPlayback() async
    func testMixedQueuePlayback() async
    func testAppLifecycleHandling() async
    func testInterruptionHandling() async
    func testRouteChangeHandling() async
}
```

### UI Tests
```swift
// AudioUITests.swift
class AudioUITests: XCTestCase {
    func testMiniPlayerUpdates()
    func testExpandedPlayerControls()
    func testQueueViewUpdates()
    func testLockScreenControls()
    func testControlCenterIntegration()
}
```

## 🎯 Success Criteria

1. **All UI components work without modification** when switching to BriefeedAudioService
2. **No regression in functionality** - everything that worked before still works
3. **All tests pass** - 100% test coverage for critical paths
4. **Performance is equal or better** - audio starts within 1 second
5. **Memory usage is stable** - no leaks, proper cleanup
6. **Background audio works reliably** - survives app backgrounding
7. **Error handling is robust** - graceful degradation, user feedback

## 🚀 Ready for Migration When:

- [ ] All missing features implemented
- [ ] All tests written and passing
- [ ] Manual testing checklist completed
- [ ] Performance profiling shows no issues
- [ ] Memory leaks checked with Instruments
- [ ] Beta tested with TestFlight users
- [ ] Documentation updated