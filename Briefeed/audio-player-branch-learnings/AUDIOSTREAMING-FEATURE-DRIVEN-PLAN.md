# AudioStreaming Feature-Driven Implementation Plan

## Yes, You Should Use AudioStreaming - But Architecture First!

You're absolutely right that these features would significantly improve Briefeed. Here's how to get them WITHOUT repeating the UI freeze disaster:

## The Features You Want (And Should Have)

### 🎯 Unified Audio Engine
- **Single library for everything** - No more juggling three systems
- **AVAudioEngine power** - Professional-grade audio processing
- **Consistent behavior** - Same controls for all audio types

### 🚀 Superior Speed Control  
- **3x, 4x, even 5x playback** - For power users who consume content fast
- **Pitch correction** - Maintains natural voice at high speeds
- **Per-content speed memory** - Different speeds for podcasts vs articles

### ✅ Feature Compatibility
- Queue management 
- Remote commands
- Background audio
- Progress tracking
- Skip controls
- All your existing features, but better

## The Right Way to Implement AudioStreaming

### Architecture Layers (THIS IS CRITICAL)

```
┌─────────────────────────────────────────┐
│            USER INTERFACE                │
│         (SwiftUI Views)                  │
└─────────────────────────────────────────┘
                    │
                    │ @EnvironmentObject
                    ▼
┌─────────────────────────────────────────┐
│         AudioPlayerViewModel             │
│        (ObservableObject)                │
│   @Published properties for UI           │
│   Handles all UI state                   │
└─────────────────────────────────────────┘
                    │
                    │ Uses (not inherits!)
                    ▼
┌─────────────────────────────────────────┐
│      AudioStreamingService               │
│        (Plain Singleton)                 │
│   NO @Published, NO ObservableObject     │
│   Just AudioStreaming wrapper            │
└─────────────────────────────────────────┘
                    │
                    │ Wraps
                    ▼
┌─────────────────────────────────────────┐
│         AudioStreaming Library           │
│            (AudioPlayer)                 │
└─────────────────────────────────────────┘
```

## Implementation That Won't Freeze

### Layer 1: AudioStreaming Service (Plain Singleton)

```swift
import AudioStreaming

/// Plain singleton service - NOT ObservableObject!
final class AudioStreamingService {
    static let shared = AudioStreamingService()
    
    // The actual AudioStreaming player
    private let audioPlayer: AudioPlayer
    
    // Current playback info (plain properties)
    private(set) var currentURL: URL?
    private(set) var playbackRate: Float = 1.0
    
    // Delegate for state changes
    weak var delegate: AudioStreamingServiceDelegate?
    
    // CRITICAL: Lightweight init!
    private init() {
        // Only create the player, nothing else
        self.audioPlayer = AudioPlayer()
        
        // Delegate will be set later
        self.audioPlayer.delegate = self
    }
    
    // Heavy initialization in separate method
    func initialize() async {
        // Configure audio session
        await configureAudioSession()
        
        // Setup remote commands
        await setupRemoteCommands()
        
        // Restore saved state
        await restorePlaybackState()
    }
    
    // MARK: - Playback Controls
    
    func play(url: URL, speed: Float = 1.0) {
        audioPlayer.play(url: url)
        audioPlayer.rate = speed
        currentURL = url
        playbackRate = speed
    }
    
    func pause() {
        audioPlayer.pause()
    }
    
    func resume() {
        audioPlayer.resume()
    }
    
    func setSpeed(_ speed: Float) {
        audioPlayer.rate = speed
        playbackRate = speed
        // Save preference
        UserDefaults.standard.set(speed, forKey: "LastPlaybackSpeed")
    }
    
    func seek(to time: TimeInterval) {
        audioPlayer.seek(to: time)
    }
    
    // MARK: - Queue Management
    
    func queue(urls: [URL]) {
        audioPlayer.queue(urls: urls)
    }
    
    func skipToNext() {
        // AudioStreaming handles queue internally
        audioPlayer.next()
    }
    
    func skipToPrevious() {
        audioPlayer.previous()
    }
}

// MARK: - AudioPlayerDelegate
extension AudioStreamingService: AudioPlayerDelegate {
    func audioPlayerStateChanged(player: AudioPlayer, with newState: AudioPlayerState, previous: AudioPlayerState) {
        // Notify delegate, don't update UI directly!
        delegate?.audioStateChanged(to: newState, from: previous)
    }
    
    func audioPlayerDidFinishPlaying(player: AudioPlayer, entryId: AudioEntryId, stopReason: AudioPlayerStopReason, progress: Double, duration: Double) {
        delegate?.audioDidFinish(stopReason: stopReason)
    }
    
    func audioPlayerPlaybackProgressUpdated(player: AudioPlayer, progress: Double, duration: Double) {
        delegate?.audioProgressUpdated(progress: progress, duration: duration)
    }
}

// Delegate protocol for state changes
protocol AudioStreamingServiceDelegate: AnyObject {
    func audioStateChanged(to newState: AudioPlayerState, from oldState: AudioPlayerState)
    func audioDidFinish(stopReason: AudioPlayerStopReason)
    func audioProgressUpdated(progress: Double, duration: Double)
}
```

### Layer 2: ViewModel (ObservableObject for UI)

```swift
import SwiftUI
import AudioStreaming

@MainActor
final class AudioPlayerViewModel: ObservableObject {
    // MARK: - Published Properties (UI State)
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var playbackSpeed: Float = 1.0
    @Published private(set) var currentTitle = ""
    @Published private(set) var currentArtist = ""
    @Published private(set) var currentArtwork: UIImage?
    
    // Queue state
    @Published private(set) var queueItems: [QueueItem] = []
    @Published private(set) var currentQueueIndex = -1
    
    // Speed options for UI
    let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0]
    
    // Service reference (not initialized in init!)
    private var audioService: AudioStreamingService?
    private var progressTimer: Timer?
    
    // MARK: - Initialization
    
    init() {
        // CRITICAL: Lightweight init, no service access!
        // Everything happens in connect()
    }
    
    // MARK: - Service Connection
    
    /// Call this from .task modifier AFTER view construction
    func connect() async {
        // NOW we can access the service
        self.audioService = AudioStreamingService.shared
        
        // Set ourselves as delegate
        audioService?.delegate = self
        
        // Initialize service in background
        await audioService?.initialize()
        
        // Load saved speed preference
        loadSpeedPreference()
        
        // Start progress timer
        startProgressTimer()
    }
    
    // MARK: - Playback Controls
    
    func play(article: Article) async {
        isLoading = true
        currentTitle = article.title ?? "Unknown"
        currentArtist = article.author ?? ""
        
        do {
            // Generate or retrieve TTS audio
            let audioURL = try await generateTTSAudio(for: article)
            
            // Play with saved speed
            audioService?.play(url: audioURL, speed: playbackSpeed)
            
            isLoading = false
        } catch {
            print("Failed to play article: \(error)")
            isLoading = false
        }
    }
    
    func play(episode: RSSEpisode) {
        currentTitle = episode.title ?? "Unknown"
        currentArtist = episode.podcastTitle ?? ""
        
        guard let audioURL = URL(string: episode.audioUrl ?? "") else { return }
        
        // Play podcast at current speed
        audioService?.play(url: audioURL, speed: playbackSpeed)
    }
    
    func togglePlayPause() {
        if isPlaying {
            audioService?.pause()
        } else {
            audioService?.resume()
        }
    }
    
    func skipForward(_ seconds: TimeInterval = 30) {
        let newTime = currentTime + seconds
        audioService?.seek(to: min(newTime, duration))
    }
    
    func skipBackward(_ seconds: TimeInterval = 15) {
        let newTime = currentTime - seconds
        audioService?.seek(to: max(newTime, 0))
    }
    
    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        audioService?.setSpeed(speed)
        saveSpeedPreference(speed)
    }
    
    // MARK: - Queue Management
    
    func queueArticle(_ article: Article) async {
        // Generate audio in background
        Task.detached {
            do {
                let audioURL = try await self.generateTTSAudio(for: article)
                await MainActor.run {
                    self.addToQueue(QueueItem(article: article, audioURL: audioURL))
                }
            } catch {
                print("Failed to queue article: \(error)")
            }
        }
    }
    
    func queueEpisode(_ episode: RSSEpisode) {
        guard let urlString = episode.audioUrl,
              let audioURL = URL(string: urlString) else { return }
        
        addToQueue(QueueItem(episode: episode, audioURL: audioURL))
    }
    
    private func addToQueue(_ item: QueueItem) {
        queueItems.append(item)
        
        // If nothing playing, start playback
        if !isPlaying && queueItems.count == 1 {
            playNextInQueue()
        }
    }
    
    func playNextInQueue() {
        guard currentQueueIndex < queueItems.count - 1 else { return }
        
        currentQueueIndex += 1
        let item = queueItems[currentQueueIndex]
        
        currentTitle = item.title
        currentArtist = item.artist
        
        audioService?.play(url: item.audioURL, speed: playbackSpeed)
    }
    
    // MARK: - Private Helpers
    
    private func generateTTSAudio(for article: Article) async throws -> URL {
        // Your existing TTS generation logic
        // Can use Gemini API or any other service
        // Return the audio file URL
        fatalError("Implement TTS generation")
    }
    
    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.updateProgress()
        }
    }
    
    private func updateProgress() {
        // Only update if actually playing
        guard isPlaying else { return }
        
        // Get current values from service
        if let player = audioService?.audioPlayer {
            let newTime = player.progress
            let newDuration = player.duration
            
            // Only update if changed
            if abs(newTime - currentTime) > 0.1 {
                currentTime = newTime
            }
            if abs(newDuration - duration) > 0.1 {
                duration = newDuration
            }
        }
    }
    
    private func loadSpeedPreference() {
        playbackSpeed = UserDefaults.standard.float(forKey: "LastPlaybackSpeed")
        if playbackSpeed == 0 {
            playbackSpeed = 1.0
        }
    }
    
    private func saveSpeedPreference(_ speed: Float) {
        UserDefaults.standard.set(speed, forKey: "LastPlaybackSpeed")
    }
}

// MARK: - AudioStreamingServiceDelegate
extension AudioPlayerViewModel: AudioStreamingServiceDelegate {
    func audioStateChanged(to newState: AudioPlayerState, from oldState: AudioPlayerState) {
        // Update UI state based on audio state
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
            // Handle error
        default:
            break
        }
    }
    
    func audioDidFinish(stopReason: AudioPlayerStopReason) {
        if stopReason == .natural {
            // Play next in queue
            playNextInQueue()
        }
    }
    
    func audioProgressUpdated(progress: Double, duration: Double) {
        // Updates handled by timer to avoid excessive updates
    }
}

// MARK: - Queue Item Model
struct QueueItem: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let audioURL: URL
    let type: QueueItemType
    
    enum QueueItemType {
        case article(Article)
        case episode(RSSEpisode)
    }
    
    init(article: Article, audioURL: URL) {
        self.title = article.title ?? "Unknown"
        self.artist = article.author ?? ""
        self.audioURL = audioURL
        self.type = .article(article)
    }
    
    init(episode: RSSEpisode, audioURL: URL) {
        self.title = episode.title ?? "Unknown"
        self.artist = episode.podcastTitle ?? ""
        self.audioURL = audioURL
        self.type = .episode(episode)
    }
}
```

### Layer 3: View Implementation

```swift
// BriefeedApp.swift
@main
struct BriefeedApp: App {
    @StateObject private var audioViewModel = AudioPlayerViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioViewModel)
        }
    }
}

// ContentView.swift
struct ContentView: View {
    @EnvironmentObject var audioViewModel: AudioPlayerViewModel
    
    var body: some View {
        TabView {
            // Your tabs
        }
        .safeAreaInset(edge: .bottom) {
            MiniAudioPlayer()
        }
        .task {
            // Connect AFTER view construction
            await audioViewModel.connect()
        }
    }
}

// MiniAudioPlayer.swift
struct MiniAudioPlayer: View {
    @EnvironmentObject var audioViewModel: AudioPlayerViewModel
    
    var body: some View {
        HStack {
            // Play/Pause
            Button(action: audioViewModel.togglePlayPause) {
                Image(systemName: audioViewModel.isPlaying ? "pause.fill" : "play.fill")
            }
            
            // Title
            VStack(alignment: .leading) {
                Text(audioViewModel.currentTitle)
                    .lineLimit(1)
                Text(audioViewModel.currentArtist)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Speed Control
            Menu {
                ForEach(audioViewModel.speedOptions, id: \.self) { speed in
                    Button(action: { audioViewModel.setSpeed(speed) }) {
                        HStack {
                            Text("\(speed, specifier: "%.2f")x")
                            if speed == audioViewModel.playbackSpeed {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text("\(audioViewModel.playbackSpeed, specifier: "%.1f")x")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
            
            // Skip Forward
            Button(action: { audioViewModel.skipForward() }) {
                Image(systemName: "goforward.30")
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
    }
}
```

## Feature Implementation Timeline

### Week 1: Core Architecture ✅
- [ ] Create AudioStreamingService (plain singleton)
- [ ] Create AudioPlayerViewModel (ObservableObject)
- [ ] Wire up basic playback
- [ ] Test that UI doesn't freeze

### Week 2: Speed Control 🚀
- [ ] Implement speed adjustment UI
- [ ] Add speed presets (1x, 1.5x, 2x, 3x, 4x)
- [ ] Save speed preferences per content type
- [ ] Test pitch correction at high speeds

### Week 3: Queue Management 📋
- [ ] Implement queue UI
- [ ] Add drag-to-reorder
- [ ] Queue persistence
- [ ] Auto-play next item

### Week 4: Advanced Features 🎯
- [ ] Background audio generation for queue
- [ ] Smart prefetching
- [ ] Offline support
- [ ] Analytics

## Critical Success Factors

### Must Work:
1. **NO UI FREEZES** - Architecture must be correct
2. **Speed control to 4x** - Core feature requirement
3. **Seamless playback** - No gaps or stutters
4. **Queue persistence** - Survives app restart

### Performance Targets:
- App launch: <1 second
- Service init: <10ms
- Audio start: <500ms
- Speed change: Instant
- Memory: <150MB

## Why This Will Work

### Architecture Fixes:
1. ✅ No Singleton + ObservableObject mixing
2. ✅ Lightweight initialization
3. ✅ Clear separation of concerns
4. ✅ Proper async patterns

### Feature Delivery:
1. ✅ Unified audio engine (AudioStreaming)
2. ✅ Speed control beyond 2x
3. ✅ Professional audio quality
4. ✅ All existing features maintained

## The Key Difference

**Before (Frozen):**
- Mixed patterns
- Heavy init
- Circular dependencies
- Wrong architecture

**After (Working):**
- Clean layers
- Lightweight init
- One-way data flow
- Correct architecture

## Go/No-Go Decision

### YES, implement AudioStreaming because:
- You need speed control beyond 2x ✅
- You want unified audio handling ✅
- The features justify the effort ✅
- We know how to avoid the pitfalls ✅

### But do it RIGHT:
- Architecture first
- Incremental migration
- Test at each step
- Keep the old code as fallback

This plan gives you all the features you want while avoiding the architectural mistakes that caused the UI freeze.