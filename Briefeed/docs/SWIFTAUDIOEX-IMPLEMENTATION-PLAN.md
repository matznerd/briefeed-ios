# SwiftAudioEx Implementation Plan
## From TDD Tests to Working Implementation

### 🎯 Current State
- ✅ TDD tests written and committed (failing as expected)
- ✅ Skeleton services created (SwiftAudioExService)
- ✅ Gemini models updated to gemini-2.5-flash-lite
- ❌ SwiftAudioEx package not added
- ❌ No actual implementation yet

### 📋 Implementation Phases

## Phase 1: Foundation Layer (Day 1)
**Goal**: Set up core infrastructure for audio caching and SwiftAudioEx

### 1.1 Add SwiftAudioEx Package
```swift
// Package.swift or via Xcode:
// https://github.com/doublesymmetry/SwiftAudioEx
// Version: Latest stable (2.x)
```

### 1.2 Create Core Data Models
```swift
// CachedAudio entity:
- articleID: UUID
- filePath: String
- textHash: String (SHA256)
- generatedAt: Date
- lastAccessedAt: Date
- fileSize: Int64
- voice: String?
- generationMethod: String (gemini/avspeech)
```

### 1.3 Implement AudioCacheManager
```swift
class AudioCacheManager {
    // Cache directory: ~/Library/Caches/tts_audio/
    // Max size: 500MB
    // Auto-cleanup: Files older than 5 days
    // LRU eviction when size exceeded
    
    func getCacheDirectory() -> URL
    func calculateCacheSize() -> Int64
    func cleanupOldFiles(olderThan days: Int)
    func evictLRU(toSize: Int64)
    func cacheKey(for text: String) -> String
}
```

## Phase 2: TTS Generation Pipeline (Day 2-3)
**Goal**: Implement complete TTS generation with caching

### 2.1 TTSGeneratorService
```swift
class TTSGeneratorService {
    private let geminiService: GeminiTTSService
    private let avSpeechService: AVSpeechTTSService
    private let cacheManager: AudioCacheManager
    private let coreDataManager: CoreDataStack
    
    func generateAudioFile(from text: String) async throws -> URL {
        // 1. Check cache first (by text hash)
        // 2. Try Gemini TTS
        // 3. Fallback to AVSpeech
        // 4. Save to cache
        // 5. Track in Core Data
        // 6. Return file URL
    }
    
    func preGenerateForQueue(queue: [QueueItem], currentIndex: Int) async {
        // Generate current + next 2 items
        // Run in background with low priority
        // Don't block UI
    }
}
```

### 2.2 Gemini TTS Implementation
```swift
extension GeminiTTSService {
    func generateSpeech(from text: String, voice: String) async throws -> Data {
        // API endpoint: /v1beta/models/gemini-2.5-flash-lite-tts:generateContent
        // Response format: Base64 encoded PCM
        // Convert PCM to MP3/M4A
        // Handle rate limiting
        // Implement exponential backoff
    }
}
```

### 2.3 AVSpeech Fallback
```swift
class AVSpeechTTSService {
    func generateAudioFile(from text: String) async throws -> URL {
        // Use AVSpeechSynthesizer
        // Write to file using AVAudioFile
        // Match format with Gemini output
        // Return file URL
    }
}
```

## Phase 3: SwiftAudioEx Integration (Day 4)
**Goal**: Full audio playback with all features

### 3.1 SwiftAudioExService Implementation
```swift
class SwiftAudioExService {
    private let player = AudioPlayer()
    
    // Core playback
    func play(url: URL) async throws
    func pause()
    func resume()
    func stop()
    
    // Speed control (0.5x - 20x)
    func setRate(_ rate: Float)
    
    // Seeking
    func seek(to time: TimeInterval)
    func skipForward(_ seconds: TimeInterval = 30)
    func skipBackward(_ seconds: TimeInterval = 15)
    
    // Queue management
    func loadQueue(_ items: [URL])
    func playNext()
    func playPrevious()
    
    // State management
    @Published var state: SwiftAudioPlayerState
    @Published var currentTime: TimeInterval
    @Published var duration: TimeInterval
    @Published var rate: Float
}
```

### 3.2 UnifiedAudioPlayer
```swift
class UnifiedAudioPlayer: ObservableObject {
    private let ttsGenerator: TTSGeneratorService
    private let audioPlayer: SwiftAudioExService
    private let queueManager: QueueManager
    
    // High-level playback
    func play(article: Article) async throws
    func play(rssEpisode: RSSEpisode) async throws
    func play(queueItem: EnhancedQueueItem) async throws
    
    // Pre-generation
    func prepareNextItems() async
    
    // Now Playing
    func updateNowPlayingInfo()
    func setupRemoteCommands()
}
```

## Phase 4: Integration (Day 5)
**Goal**: Wire everything together

### 4.1 Update ViewModels
```swift
class AudioPlayerViewModel: ObservableObject {
    // Replace AudioService with UnifiedAudioPlayer
    private let audioPlayer = UnifiedAudioPlayer()
    
    // Maintain same public API for UI
    @Published var isPlaying: Bool
    @Published var currentTitle: String
    @Published var progress: Double
    @Published var playbackSpeed: Float
}
```

### 4.2 Queue Integration
```swift
extension QueueServiceV2 {
    func prepareAudioForQueue() async {
        // Trigger pre-generation for current queue
        // Monitor queue changes
        // Clean up old generated files
    }
}
```

## Phase 5: UI Updates (Day 6)
**Goal**: Update UI for new capabilities

### 5.1 Speed Control UI
```swift
// Update SpeedPicker for 0.5x - 20x range
// Add preset buttons: 1x, 2x, 4x, 8x, 16x
// Smooth slider for fine control
```

### 5.2 Progress Indicators
```swift
// Show TTS generation progress
// Cache status indicators
// Pre-generation status in queue
```

## Phase 6: Testing & Cleanup (Day 7)
**Goal**: Ensure all tests pass and remove old code

### 6.1 Make Tests Pass
- Run each test file individually
- Fix implementation until green
- No test modifications allowed (TDD rule)

### 6.2 Remove Old Audio System
Files to delete (after full testing):
- AudioService.swift
- AudioService+RSS.swift
- AudioServiceAdapter.swift
- AudioServiceV2.swift
- QueueService.swift (old version)
- QueueService+RSS.swift
- FeatureFlagManager.swift
- Old audio-related ViewModels

## 🔑 Key Technical Decisions

### Audio Format
- **Primary**: MP3 (best compatibility)
- **Fallback**: M4A (iOS native)
- **Sample Rate**: 24kHz (Gemini default)
- **Bitrate**: 64kbps (good for speech)

### Caching Strategy
- **Key**: SHA256(text + voice)
- **Location**: ~/Library/Caches/tts_audio/
- **Naming**: {hash_prefix}_{voice}.mp3
- **Metadata**: Core Data for fast lookup

### Performance Optimization
- **Pre-generation**: Task.detached { priority: .background }
- **Streaming**: Don't load entire file into memory
- **Cleanup**: Run during app backgrounding
- **Queue**: Max 3 concurrent TTS generations

### Error Handling
- **API Failures**: Exponential backoff with jitter
- **Network Issues**: Queue for retry when connected
- **Cache Misses**: Regenerate transparently
- **Corrupted Files**: Delete and regenerate

## 📊 Success Metrics

1. **All 27 tests passing** ✅
2. **Audio plays at 20x speed** ✅
3. **Seek works smoothly** ✅
4. **Cache stays under 500MB** ✅
5. **Pre-generation doesn't block UI** ✅
6. **Fallback works seamlessly** ✅
7. **Old audio system removed** ✅

## 🚀 Next Immediate Steps

1. **Add SwiftAudioEx package** (30 min)
2. **Create AudioCacheManager** (2 hours)
3. **Add Core Data models** (1 hour)
4. **Start TTSGeneratorService** (3 hours)
5. **Run first test** (verify setup)

## 💡 Implementation Tips

1. **Start Small**: Get one test passing at a time
2. **Use Breakpoints**: Debug audio file generation
3. **Log Everything**: Track cache hits/misses
4. **Test on Device**: Simulator audio can be quirky
5. **Monitor Memory**: Watch for leaks with Instruments
6. **Check Background**: Ensure audio continues when backgrounded

## 🎯 Definition of Done

- [ ] All TDD tests pass without modification
- [ ] 20x playback speed works smoothly
- [ ] TTS generation doesn't block UI
- [ ] Cache management works automatically
- [ ] Gemini → AVSpeech fallback is seamless
- [ ] Old audio system completely removed
- [ ] No memory leaks or performance issues
- [ ] Background audio works perfectly
- [ ] Remote control commands work

---

This plan provides a clear, methodical approach to implementing SwiftAudioEx with TTS generation while maintaining the existing app functionality during the transition.