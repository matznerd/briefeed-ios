# AudioStreaming Implementation Guide for Briefeed

## Executive Summary

Based on our failed attempt with SwiftAudioEx and the UI freeze investigation, this guide provides a comprehensive plan for implementing AudioStreaming (https://github.com/dimitris-c/AudioStreaming) correctly in Briefeed, avoiding all the architectural pitfalls we discovered.

## Why AudioStreaming Instead of SwiftAudioEx

### AudioStreaming Advantages
1. **Lower-level control** - Uses AVAudioEngine directly
2. **Simpler architecture** - No complex event systems
3. **Better streaming support** - Built for Shoutcast/ICY streams
4. **Lighter weight** - Less overhead than SwiftAudioEx
5. **More predictable** - Direct control over initialization

### What We Used (SwiftAudioEx) vs What Was Recommended (AudioStreaming)

**SwiftAudioEx Issues:**
- Complex event-driven architecture
- Expects specific singleton/ViewModel pattern
- Heavy initialization with RemoteCommandController
- Not designed for our ObservableObject singleton pattern

**AudioStreaming Benefits:**
- Simple AudioPlayer class
- Direct playback control
- No forced architectural patterns
- Lightweight initialization

## Critical Lessons from Previous Attempt

### 1. The 11.5 Second Freeze Root Cause
```swift
// ❌ NEVER DO THIS
class AudioService: ObservableObject {
    static let shared = AudioService()
    @Published var isPlaying = false  // Triggers UI updates
    
    init() {
        // Heavy work here blocks for 11+ seconds
        loadFromDisk()
        setupCoreData()
        configureAudio()
    }
}
```

### 2. The Singleton ObservableObject Anti-Pattern
```swift
// ❌ WRONG: Singleton as ObservableObject
final class BriefeedAudioService: ObservableObject {
    static let shared = BriefeedAudioService()
    @Published var state: AudioState = .idle
}

// ❌ WRONG: Using singleton in @StateObject
struct ContentView: View {
    @StateObject private var audio = BriefeedAudioService.shared
}
```

### 3. The @MainActor Trap
```swift
// ❌ Even in background tasks, @MainActor forces main thread
Task.detached {
    let service = await MainActorService.shared  // Still blocks main thread!
}
```

## Correct AudioStreaming Architecture

### Layer 1: Core Audio Service (Plain Singleton)
```swift
import AudioStreaming

// Plain singleton - NOT ObservableObject
final class AudioStreamingService {
    static let shared = AudioStreamingService()
    
    private let audioPlayer: AudioPlayer
    private var currentUrl: URL?
    
    // Lightweight init - no heavy work
    private init() {
        self.audioPlayer = AudioPlayer()
        // That's it! No heavy initialization
    }
    
    // Heavy work in explicit initialize method
    func initialize() async {
        // Configure audio session
        // Setup remote commands
        // Load saved state
    }
    
    // MARK: - Playback Controls
    func play(url: URL) {
        audioPlayer.play(url: url)
        currentUrl = url
    }
    
    func pause() {
        audioPlayer.pause()
    }
    
    func resume() {
        audioPlayer.resume()
    }
    
    func stop() {
        audioPlayer.stop()
    }
    
    func seek(to time: TimeInterval) {
        audioPlayer.seek(to: time)
    }
    
    // MARK: - Queue Management
    func queue(url: URL) {
        audioPlayer.queue(url: url)
    }
    
    func queue(urls: [URL]) {
        audioPlayer.queue(urls: urls)
    }
}
```

### Layer 2: View Model (ObservableObject)
```swift
@MainActor
final class AudioPlayerViewModel: ObservableObject {
    // Published properties for UI
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentTitle = ""
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    // Reference to service (NOT singleton access in init!)
    private var audioService: AudioStreamingService?
    private var updateTimer: Timer?
    
    init() {
        // Lightweight init - no service access
    }
    
    // Called AFTER view construction
    func connect() async {
        // NOW we can access the service
        self.audioService = AudioStreamingService.shared
        
        // Initialize service in background
        await audioService?.initialize()
        
        // Setup delegate
        audioService?.audioPlayer.delegate = self
        
        // Start update timer
        startUpdateTimer()
    }
    
    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.updatePlaybackState()
        }
    }
    
    private func updatePlaybackState() {
        guard let player = audioService?.audioPlayer else { return }
        
        // Only update if changed
        let newIsPlaying = player.state == .playing
        if isPlaying != newIsPlaying {
            isPlaying = newIsPlaying
        }
        
        // Update times
        currentTime = player.progress
        duration = player.duration
    }
    
    // MARK: - Public Methods
    func play(url: URL) {
        audioService?.play(url: url)
    }
    
    func togglePlayPause() {
        if isPlaying {
            audioService?.pause()
        } else {
            audioService?.resume()
        }
    }
}

// MARK: - AudioPlayerDelegate
extension AudioPlayerViewModel: AudioPlayerDelegate {
    func audioPlayerStateChanged(player: AudioPlayer, with newState: AudioPlayerState, previous: AudioPlayerState) {
        Task { @MainActor in
            // Update UI state based on player state
            switch newState {
            case .playing:
                isPlaying = true
                isLoading = false
            case .paused:
                isPlaying = false
            case .stopped:
                isPlaying = false
                currentTime = 0
            case .loading:
                isLoading = true
            case .failed:
                isPlaying = false
                isLoading = false
            default:
                break
            }
        }
    }
    
    func audioPlayerDidFinishPlaying(player: AudioPlayer, entryId: AudioEntryId, stopReason: AudioPlayerStopReason, progress: Double, duration: Double) {
        Task { @MainActor in
            // Handle track completion
            if stopReason == .natural {
                // Play next in queue if available
            }
        }
    }
}
```

### Layer 3: View Implementation
```swift
struct ContentView: View {
    // Create fresh instance, not singleton reference
    @StateObject private var audioViewModel = AudioPlayerViewModel()
    
    var body: some View {
        TabView {
            // Your tabs
        }
        .task {
            // Connect AFTER view construction
            await audioViewModel.connect()
        }
    }
}

struct MiniAudioPlayer: View {
    // Use EnvironmentObject to share the same instance
    @EnvironmentObject var audioViewModel: AudioPlayerViewModel
    
    var body: some View {
        HStack {
            // Player UI
            Button(action: { audioViewModel.togglePlayPause() }) {
                Image(systemName: audioViewModel.isPlaying ? "pause.fill" : "play.fill")
            }
            
            Text(audioViewModel.currentTitle)
            
            if audioViewModel.isLoading {
                ProgressView()
            }
        }
    }
}
```

### Layer 4: App-Level Setup
```swift
@main
struct BriefeedApp: App {
    @StateObject private var audioViewModel = AudioPlayerViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioViewModel)  // Share across app
        }
    }
}
```

## Queue Service Integration

### Separate Queue Management
```swift
// QueueService remains independent
final class QueueServiceV3 {
    static let shared = QueueServiceV3()
    
    private var queue: [QueuedItem] = []
    private let audioService = AudioStreamingService.shared
    
    private init() {
        // Load saved queue from UserDefaults
        loadQueue()
    }
    
    func addToQueue(_ item: QueuedItem) {
        queue.append(item)
        saveQueue()
        
        // If nothing playing, start playback
        if audioService.audioPlayer.state == .idle {
            playNext()
        }
    }
    
    private func playNext() {
        guard !queue.isEmpty else { return }
        let item = queue.removeFirst()
        audioService.play(url: item.audioUrl)
        saveQueue()
    }
}
```

## Implementation Steps

### Phase 1: Foundation (Week 1)
1. **Remove SwiftAudioEx completely**
   ```bash
   # Remove from Package.swift dependencies
   # Delete all SwiftAudioEx imports
   # Clean build folder
   ```

2. **Add AudioStreaming**
   ```swift
   // Package.swift
   dependencies: [
       .package(url: "https://github.com/dimitris-c/AudioStreaming.git", from: "2.0.0")
   ]
   ```

3. **Create AudioStreamingService**
   - Plain singleton class
   - Lightweight init
   - Async initialize method

### Phase 2: View Model Layer (Week 2)
1. **Create AudioPlayerViewModel**
   - ObservableObject with @Published properties
   - NO singleton access in init
   - Async connect method

2. **Implement AudioPlayerDelegate**
   - Handle state changes
   - Update @Published properties
   - Use Task { @MainActor in } for UI updates

3. **Add update timer**
   - Poll for progress updates
   - Throttle to avoid excessive updates

### Phase 3: Queue Integration (Week 3)
1. **Update QueueService**
   - Use AudioStreaming APIs
   - Maintain queue persistence
   - Handle playback completion

2. **Add queue UI**
   - Queue list view
   - Reorder support
   - Clear queue option

### Phase 4: Features (Week 4)
1. **TTS Integration**
   - Generate audio files
   - Queue for playback
   - Cache management

2. **RSS Episode Support**
   - Stream RSS audio URLs
   - Track listen status
   - Resume playback

3. **Remote Commands**
   - Play/pause from Control Center
   - Next/previous track
   - Now Playing info

### Phase 5: Testing & Polish (Week 5)
1. **Performance Testing**
   - Measure init times (<10ms)
   - Check main thread blocks
   - Profile with Instruments

2. **Error Handling**
   - Network failures
   - Invalid URLs
   - Codec issues

3. **UI Polish**
   - Smooth animations
   - Loading states
   - Error messages

## Critical Success Metrics

### Must Have (Launch Blockers)
- [ ] App launches in <1 second
- [ ] UI responds immediately on launch
- [ ] No main thread blocks >16ms
- [ ] Service init <10ms
- [ ] No "Publishing changes from within view updates" errors

### Should Have (Quality)
- [ ] Smooth 60fps scrolling during playback
- [ ] Memory usage <100MB
- [ ] Battery usage <5% per hour
- [ ] Background playback works
- [ ] Interruption handling (calls, etc.)

### Nice to Have (Polish)
- [ ] Gapless playback
- [ ] Crossfade between tracks
- [ ] Playback speed adjustment
- [ ] Sleep timer
- [ ] Equalizer

## Common Pitfalls to Avoid

### 1. Don't Create Circular Dependencies
```swift
// ❌ WRONG
class ServiceA {
    let serviceB = ServiceB.shared  // In init
}
class ServiceB {
    let serviceA = ServiceA.shared  // In init
}

// ✅ CORRECT
class ServiceA {
    private var serviceB: ServiceB?
    func configure(with serviceB: ServiceB) {
        self.serviceB = serviceB
    }
}
```

### 2. Don't Mix Patterns
```swift
// ❌ WRONG: Singleton AND ObservableObject
class AudioService: ObservableObject {
    static let shared = AudioService()
}

// ✅ CORRECT: Choose one pattern
class AudioService {  // Plain singleton
    static let shared = AudioService()
}
// OR
class AudioViewModel: ObservableObject {  // Instance-based
    // No static shared
}
```

### 3. Don't Do Heavy Work in Init
```swift
// ❌ WRONG
init() {
    loadFromDisk()
    fetchFromNetwork()
    setupComplexState()
}

// ✅ CORRECT
init() {
    // Only property initialization
}

func initialize() async {
    await loadFromDisk()
    await fetchFromNetwork()
    await setupComplexState()
}
```

### 4. Don't Access Services During View Construction
```swift
// ❌ WRONG
struct ContentView: View {
    @StateObject private var model = MyModel()
    
    init() {
        model.loadData()  // View not ready!
    }
}

// ✅ CORRECT
struct ContentView: View {
    @StateObject private var model = MyModel()
    
    var body: some View {
        Text("Hello")
            .task {
                await model.loadData()  // After view construction
            }
    }
}
```

## Testing Strategy

### Unit Tests
```swift
func testServiceInitTime() async {
    let start = CFAbsoluteTimeGetCurrent()
    _ = AudioStreamingService.shared
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    XCTAssertLessThan(elapsed, 0.01)  // Must init in <10ms
}

func testNoMainThreadBlock() async {
    let expectation = XCTestExpectation()
    
    Task.detached {
        _ = AudioStreamingService.shared
        await MainActor.run {
            expectation.fulfill()  // Should not block
        }
    }
    
    await fulfillment(of: [expectation], timeout: 0.1)
}
```

### UI Tests
```swift
func testUIResponsiveOnLaunch() {
    let app = XCUIApplication()
    app.launch()
    
    // Should be able to tap immediately
    let tabBar = app.tabBars.firstMatch
    XCTAssertTrue(tabBar.waitForExistence(timeout: 1.0))
    
    let feedTab = tabBar.buttons["Feed"]
    feedTab.tap()
    
    // Should switch immediately
    XCTAssertTrue(app.navigationBars["Feed"].exists)
}
```

## Monitoring & Rollback

### Add Metrics
```swift
class PerformanceMonitor {
    static func trackServiceInit(_ name: String, time: TimeInterval) {
        if time > 0.01 {
            // Alert: Service init too slow
            print("⚠️ \(name) init took \(time)s")
        }
    }
    
    static func trackMainThreadBlock(_ duration: TimeInterval) {
        if duration > 0.016 {  // One frame at 60fps
            // Alert: Main thread blocked
            print("🔴 Main thread blocked for \(duration)s")
        }
    }
}
```

### Feature Flags
```swift
struct FeatureFlags {
    static var useAudioStreaming: Bool {
        UserDefaults.standard.bool(forKey: "UseAudioStreaming")
    }
}

// In AudioPlayerViewModel
func connect() async {
    if FeatureFlags.useAudioStreaming {
        self.audioService = AudioStreamingService.shared
    } else {
        // Fallback to old implementation
    }
}
```

### Gradual Rollout
1. **Week 1**: Internal testing only
2. **Week 2**: 10% of users via feature flag
3. **Week 3**: 50% of users if metrics good
4. **Week 4**: 100% rollout
5. **Week 5**: Remove old code

## Conclusion

The key to successful AudioStreaming implementation is:

1. **Correct Architecture**: Service → ViewModel → View
2. **Lightweight Init**: No heavy work in constructors
3. **Progressive Loading**: UI first, features second
4. **Clear Separation**: Audio logic vs UI state
5. **Careful Testing**: Measure everything

By following this guide and avoiding the pitfalls we discovered, the AudioStreaming implementation should provide a smooth, responsive audio experience without the UI freezes we encountered with SwiftAudioEx.

Remember: **Architecture matters more than the library choice**. AudioStreaming gives us the flexibility to implement the correct architecture without fighting the library's assumptions.