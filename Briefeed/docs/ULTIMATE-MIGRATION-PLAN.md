# 🎯 ULTIMATE AUDIO SYSTEM MIGRATION PLAN - V2.0

## Executive Summary

We are replacing the broken AudioService (AVAudioSession error -50) with BriefeedAudioService built on SwiftAudioEx. This document provides a comprehensive, deeply thought-through plan for completing this migration with **zero regressions** and **improved architecture**.

---

## 📚 Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [Architecture Design](#architecture-design)
3. [SwiftAudioEx Integration](#swiftaudioex-integration)
4. [Data Models & Flow](#data-models--flow)
5. [Component Migration Strategy](#component-migration-strategy)
6. [Feature Preservation](#feature-preservation)
7. [Implementation Phases](#implementation-phases)
8. [Testing Strategy](#testing-strategy)
9. [Risk Analysis & Mitigation](#risk-analysis--mitigation)
10. [Success Metrics](#success-metrics)

---

## 🔍 Current State Analysis

### What We Have

1. **Old System (BROKEN)**
   - `AudioService.swift` - Main service with AVAudioSession error -50
   - `AudioService+RSS.swift` - RSS episode handling
   - Direct Article manipulation in queue
   - Synchronous API design
   - Tightly coupled with UI components

2. **New System (70% COMPLETE)**
   - `BriefeedAudioService.swift` - SwiftAudioEx-based
   - `BriefeedAudioItem.swift` - Unified audio item wrapper
   - `TTSGenerator.swift` - TTS generation
   - `AudioCacheManager.swift` - Cache management
   - `PlaybackHistoryManager.swift` - History tracking

3. **Queue System (FRAGMENTED)**
   - `QueueService.swift` - Old queue management
   - `QueueService+RSS.swift` - RSS additions
   - `EnhancedQueueItem` - Unified queue model
   - `QueueServiceV2.swift` - Our new proposal

### Problems to Solve

1. **Type Mismatch**: Old uses `Article`, new uses `BriefeedAudioItem`
2. **API Incompatibility**: Sync vs Async, different method signatures
3. **Queue Fragmentation**: Multiple queue representations
4. **UI Coupling**: Components directly manipulate audio service
5. **State Management**: Inconsistent state observation patterns

---

## 🏗️ Architecture Design

### Proposed Clean Architecture

```
┌──────────────────────────────────────────────┐
│                 UI Layer                      │
│  MiniPlayer, ExpandedPlayer, LiveNewsView     │
└─────────────────┬────────────────────────────┘
                  │ Observes
┌─────────────────▼────────────────────────────┐
│             ViewModel Layer                   │
│  BriefViewModel, ArticleViewModel, etc        │
└─────────────────┬────────────────────────────┘
                  │ Coordinates
┌─────────────────▼────────────────────────────┐
│             Service Layer                     │
│  ┌─────────────────┐  ┌──────────────────┐  │
│  │ QueueServiceV2  │◄─►│BriefeedAudioSvc │  │
│  └─────────────────┘  └──────────────────┘  │
│         Queue              Playback          │
└──────────────────────────────────────────────┘
                  │ Uses
┌─────────────────▼────────────────────────────┐
│              Data Layer                       │
│  CoreData, UserDefaults, FileSystem          │
└──────────────────────────────────────────────┘
```

### Service Responsibilities

#### QueueServiceV2 (Queue Authority)
- **Owns**: Queue state, order, persistence
- **Manages**: EnhancedQueueItem instances
- **Provides**: Queue operations (add, remove, reorder)
- **Handles**: TTS pre-generation for articles
- **Syncs**: With BriefeedAudioService for playback

#### BriefeedAudioService (Playback Engine)
- **Owns**: Audio playback state
- **Manages**: SwiftAudioEx player
- **Provides**: Play, pause, seek, skip controls
- **Handles**: Background audio, remote commands
- **Reports**: Playback events to QueueService

### Key Design Decisions

1. **Separation of Concerns**: Queue logic separate from playback
2. **Single Source of Truth**: QueueServiceV2 for queue, BriefeedAudioService for playback
3. **Async-First**: All potentially blocking operations are async
4. **Type Safety**: EnhancedQueueItem unifies Articles and RSS Episodes
5. **Observable State**: Both services expose @Published properties

---

## 🎵 SwiftAudioEx Integration

### Library Capabilities (from GitHub)

```swift
// Core Features We Use
- QueuedAudioPlayer: Manages audio queue
- AudioItem protocol: Custom audio items
- RemoteCommands: Lock screen controls
- NowPlayingInfo: Control Center integration
- Event system: State changes, progress updates
- AVAudioSession management
```

### Our Implementation

```swift
class BriefeedAudioService {
    private let audioPlayer = QueuedAudioPlayer()
    
    func setupAudioPlayer() {
        // Configuration
        audioPlayer.bufferDuration = 2.0
        audioPlayer.automaticallyWaitsToMinimizeStalling = true
        audioPlayer.automaticallyUpdateNowPlayingInfo = true
        
        // Remote Commands
        audioPlayer.remoteCommands = [
            .play, .pause,
            .skipForward(intervals: [15]),  // Articles
            .skipBackward(intervals: [15]), // Articles
            .changePlaybackPosition,
            .next, .previous
        ]
        
        // Event Listeners
        audioPlayer.event.stateChange.addListener(self, handleStateChange)
        audioPlayer.event.secondElapse.addListener(self, handleProgress)
        audioPlayer.event.updateDuration.addListener(self, handleDuration)
        audioPlayer.event.currentItem.addListener(self, handleItemChange)
        audioPlayer.event.playbackEnd.addListener(self, handlePlaybackEnd)
    }
}
```

### BriefeedAudioItem Implementation

```swift
class BriefeedAudioItem: AudioItem {
    // SwiftAudioEx Protocol Requirements
    func getSourceUrl() -> String { audioURL?.absoluteString ?? "" }
    func getArtist() -> String? { content.author }
    func getTitle() -> String? { content.title }
    func getAlbumTitle() -> String? { content.feedTitle ?? "Briefeed" }
    func getSourceType() -> SourceType { audioURL?.isFileURL ? .file : .stream }
    
    // InitialTiming Support (resume playback)
    func getInitialTime() -> TimeInterval? {
        content.lastPlaybackPosition > 0 ? content.lastPlaybackPosition : nil
    }
}
```

---

## 📊 Data Models & Flow

### EnhancedQueueItem Structure

```swift
struct EnhancedQueueItem {
    // Identity
    let id: UUID
    let type: ItemType  // .article or .rssEpisode
    
    // Content
    let title: String?
    let author: String?
    let dateAdded: Date
    
    // References
    let articleID: UUID?      // For articles
    let audioUrl: URL?        // For RSS episodes
    let feedTitle: String?    // Feed name
    
    // Playback
    var duration: TimeInterval?
    var lastPosition: TimeInterval
}
```

### Data Flow

```
1. User Action (Play Article)
       ↓
2. ViewModel Coordination
   - QueueService.addArticle()
   - AudioService.playArticle()
       ↓
3. QueueService Updates
   - Add to queue array
   - Start TTS generation
   - Save to UserDefaults
       ↓
4. AudioService Playback
   - Generate/load audio
   - Create BriefeedAudioItem
   - Load into SwiftAudioEx
       ↓
5. State Updates
   - Queue state changes
   - Playback state changes
   - UI observes and updates
```

### Initialization Helpers

```swift
extension EnhancedQueueItem {
    // From Article
    init(from article: Article) {
        self.id = UUID()
        self.type = .article
        self.title = article.title
        self.author = article.author
        self.dateAdded = Date()
        self.articleID = article.id
        self.audioUrl = nil
        self.feedTitle = article.feed?.name
        self.duration = nil
        self.lastPosition = 0
    }
    
    // From RSS Episode
    init(from episode: RSSEpisode) {
        self.id = UUID()
        self.type = .rssEpisode
        self.title = episode.title
        self.author = episode.feed?.displayName
        self.dateAdded = Date()
        self.articleID = nil
        self.audioUrl = URL(string: episode.audioUrl)
        self.feedTitle = episode.feed?.displayName
        self.duration = TimeInterval(episode.duration)
        self.lastPosition = TimeInterval(episode.lastPosition)
    }
}
```

---

## 🔄 Component Migration Strategy

### Phase 1: Service Layer Updates

#### 1.1 Complete BriefeedAudioService APIs

```swift
extension BriefeedAudioService {
    // UI Compatibility Layer
    @Published var currentArticle: Article? // Backward compat
    let state = CurrentValueSubject<AudioPlayerState, Never>(.idle)
    let progress = CurrentValueSubject<Float, Never>(0.0)
    
    // Missing Methods
    func playNow(_ article: Article) async {
        clearQueue()
        await playArticle(article)
    }
    
    func playAfterCurrent(_ article: Article) async {
        await queueService.addArticle(article, playNext: true)
        if !isPlaying { await playNext() }
    }
    
    func skipBackward() {
        let interval = currentItem?.content.contentType == .article ? 15 : 30
        seek(to: max(0, currentTime - interval))
    }
    
    // RSS URL Support
    func playRSSEpisode(url: URL, title: String, episode: RSSEpisode?) async {
        if let episode = episode {
            await playRSSEpisode(episode)
        } else {
            // Direct URL playback
            let tempItem = createTemporaryRSSItem(url: url, title: title)
            await playAudioItem(tempItem)
        }
    }
}
```

#### 1.2 Implement QueueServiceV2

Already created in previous response - handles:
- Queue state management
- Persistence
- TTS pre-generation
- Sync with audio service

### Phase 2: ViewModel Updates

#### 2.1 BriefViewModel

```swift
class BriefViewModel: ObservableObject {
    private let queueService = QueueServiceV2.shared
    private let audioService = BriefeedAudioService.shared
    
    @Published var queue: [EnhancedQueueItem] = []
    
    init() {
        // Observe queue changes
        queueService.$queue
            .assign(to: &$queue)
        
        // No more direct queue manipulation
        // Use QueueService methods
    }
    
    func playArticle(_ article: Article) async {
        await audioService.playArticle(article)
    }
    
    func addToQueue(_ article: Article) async {
        await queueService.addArticle(article)
    }
    
    func removeFromQueue(at index: Int) {
        queueService.removeItem(at: index)
    }
    
    func reorderQueue(from: IndexSet, to: Int) {
        queueService.moveItem(from: from, to: to)
    }
}
```

#### 2.2 ArticleViewModel

```swift
class ArticleViewModel: ObservableObject {
    private let audioService = BriefeedAudioService.shared
    private let queueService = QueueServiceV2.shared
    
    @Published var isPlaying = false
    @Published var isInQueue = false
    
    init(article: Article) {
        // Observe playback state
        audioService.$currentArticle
            .map { $0?.id == article.id }
            .assign(to: &$isPlaying)
        
        // Observe queue state
        queueService.$queue
            .map { items in
                items.contains { $0.articleID == article.id }
            }
            .assign(to: &$isInQueue)
    }
    
    func playArticle() async {
        await audioService.playArticle(article)
    }
    
    func toggleQueue() async {
        if isInQueue {
            // Find and remove
            if let index = queueService.queue.firstIndex(where: { $0.articleID == article.id }) {
                queueService.removeItem(at: index)
            }
        } else {
            await queueService.addArticle(article)
        }
    }
}
```

### Phase 3: UI Component Updates

#### 3.1 MiniAudioPlayer

```swift
struct MiniAudioPlayer: View {
    @ObservedObject private var audioService = BriefeedAudioService.shared
    @ObservedObject private var queueService = QueueServiceV2.shared
    
    var currentItem: EnhancedQueueItem? {
        queueService.currentItem
    }
    
    var body: some View {
        if let item = currentItem {
            HStack {
                // Play/Pause
                Button(action: { audioService.togglePlayPause() }) {
                    Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                }
                
                // Title
                VStack(alignment: .leading) {
                    Text(item.title ?? "Unknown")
                    Text(item.author ?? "")
                        .font(.caption)
                }
                
                // Skip
                Button(action: { Task { await queueService.playNext() } }) {
                    Image(systemName: "forward.end.fill")
                }
                .disabled(!queueService.hasNext)
            }
        }
    }
}
```

#### 3.2 ExpandedAudioPlayer

```swift
struct ExpandedAudioPlayer: View {
    @ObservedObject private var audioService = BriefeedAudioService.shared
    @ObservedObject private var queueService = QueueServiceV2.shared
    @State private var isDraggingSlider = false
    @State private var draggedTime: TimeInterval = 0
    
    var body: some View {
        VStack {
            // Queue List
            List {
                ForEach(Array(queueService.queue.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        if index == queueService.currentIndex {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        
                        VStack(alignment: .leading) {
                            Text(item.title ?? "Unknown")
                            Text(item.author ?? "")
                                .font(.caption)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await queueService.playItem(at: index) }
                    }
                }
                .onMove { source, destination in
                    queueService.moveItem(from: source, to: destination)
                }
                .onDelete { indexSet in
                    indexSet.forEach { queueService.removeItem(at: $0) }
                }
            }
            
            // Playback Controls
            HStack {
                Button(action: { audioService.skipBackward() }) {
                    Image(systemName: "gobackward.15")
                }
                
                Button(action: { audioService.togglePlayPause() }) {
                    Image(systemName: audioService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }
                
                Button(action: { audioService.skipForward() }) {
                    Image(systemName: "goforward.15")
                }
            }
            
            // Progress Slider
            Slider(
                value: Binding(
                    get: { isDraggingSlider ? draggedTime : audioService.currentTime },
                    set: { draggedTime = $0 }
                ),
                in: 0...max(1, audioService.duration),
                onEditingChanged: { dragging in
                    isDraggingSlider = dragging
                    if !dragging {
                        audioService.seek(to: draggedTime)
                    }
                }
            )
            
            // Speed Control
            Picker("Speed", selection: $audioService.playbackRate) {
                Text("0.5x").tag(Float(0.5))
                Text("0.75x").tag(Float(0.75))
                Text("1x").tag(Float(1.0))
                Text("1.25x").tag(Float(1.25))
                Text("1.5x").tag(Float(1.5))
                Text("2x").tag(Float(2.0))
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }
}
```

#### 3.3 LiveNewsView Updates

```swift
struct LiveNewsView: View {
    @StateObject private var rssService = RSSAudioService.shared
    @StateObject private var queueService = QueueServiceV2.shared
    @StateObject private var audioService = BriefeedAudioService.shared
    
    private func playAllLiveNews() async {
        print("🎙️ Starting Live News Radio Mode")
        
        // Clear current queue
        queueService.clearQueue()
        
        // Find latest unlistened episode from each feed
        var episodes: [RSSEpisode] = []
        for feed in feeds where feed.isEnabled {
            if let latestEpisode = feed.episodes?
                .sorted { $0.pubDate > $1.pubDate }
                .first(where: { !$0.isListened }) {
                episodes.append(latestEpisode)
            }
        }
        
        // Add all to queue
        for episode in episodes {
            queueService.addRSSEpisode(episode)
        }
        
        // Start playing first
        if !episodes.isEmpty {
            await queueService.playItem(at: 0)
        }
    }
}
```

---

## ✅ Feature Preservation

### Critical Features to Maintain

1. **Live News Radio Mode** ✅
   - Auto-play latest episodes from each feed
   - Skip listened episodes
   - Continuous playback

2. **Mixed Queue** ✅
   - Articles with TTS
   - RSS episodes
   - Seamless transitions

3. **Queue Persistence** ✅
   - Survives app restarts
   - Maintains playback position
   - Restores on launch

4. **Background Audio** ✅
   - Lock screen controls
   - Control Center integration
   - Interruption handling

5. **TTS Generation** ✅
   - Gemini API primary
   - Device fallback
   - Background pre-generation

6. **Playback Contexts** ✅
   - Track source (Live News, Brief, Direct)
   - Different skip intervals
   - Context-aware UI

### Feature Testing Checklist

```swift
// Test Cases
□ Play article with TTS
□ Play RSS episode
□ Mixed queue playback
□ Queue persistence across restart
□ Background audio continues
□ Lock screen controls work
□ Skip forward/backward (15s articles, 30s RSS)
□ Speed control (0.5x - 2x)
□ Sleep timer
□ History tracking
□ Auto-play next
□ Handle interruptions (phone call)
□ Handle route changes (headphones)
□ Live News radio mode
□ Queue reordering
□ Remove from queue
□ Play specific queue item
□ Resume from history
```

---

## 📋 Implementation Phases

### Phase 1: Complete Core Services (4 hours)
- [ ] Add missing APIs to BriefeedAudioService
- [ ] Fix background audio configuration
- [ ] Add state management publishers
- [ ] Implement RSS URL support
- [ ] Add convenience methods
- [ ] Complete QueueServiceV2 implementation

### Phase 2: Update ViewModels (2 hours)
- [ ] Update BriefViewModel
- [ ] Update ArticleViewModel
- [ ] Update other ViewModels
- [ ] Remove direct AudioService references
- [ ] Add proper state observations

### Phase 3: Update UI Components (3 hours)
- [ ] Update MiniAudioPlayer
- [ ] Update ExpandedAudioPlayer
- [ ] Update LiveNewsView
- [ ] Update BriefView
- [ ] Update ArticleRowView
- [ ] Update all other UI references

### Phase 4: Testing & Validation (2 hours)
- [ ] Run unit tests
- [ ] Run integration tests
- [ ] Manual testing checklist
- [ ] Performance profiling
- [ ] Memory leak detection

### Phase 5: Cleanup (1 hour)
- [ ] Remove AudioService.swift
- [ ] Remove AudioService+RSS.swift
- [ ] Remove AudioServiceAdapter.swift
- [ ] Remove old QueueService
- [ ] Remove feature flags
- [ ] Update documentation

---

## 🧪 Testing Strategy

### Unit Tests

```swift
class BriefeedAudioServiceTests: XCTestCase {
    func testPlayArticle() async throws {
        let service = BriefeedAudioService.shared
        let article = createMockArticle()
        
        await service.playArticle(article)
        
        XCTAssertNotNil(service.currentArticle)
        XCTAssertEqual(service.state.value, .playing)
    }
    
    func testQueueManagement() async throws {
        let queue = QueueServiceV2.shared
        let article = createMockArticle()
        
        await queue.addArticle(article)
        
        XCTAssertEqual(queue.queue.count, 1)
        XCTAssertEqual(queue.queue.first?.articleID, article.id)
    }
}
```

### Integration Tests

```swift
class AudioIntegrationTests: XCTestCase {
    func testEndToEndPlayback() async throws {
        // Setup
        let article = createArticleInCoreData()
        let queue = QueueServiceV2.shared
        let audio = BriefeedAudioService.shared
        
        // Add to queue and play
        await queue.addArticle(article)
        await queue.playItem(at: 0)
        
        // Verify
        XCTAssertEqual(audio.state.value, .playing)
        XCTAssertNotNil(audio.currentPlaybackItem)
        XCTAssertEqual(queue.currentIndex, 0)
    }
}
```

### Manual Testing Script

```
1. Launch app
2. Add article to queue
3. Play article
4. Verify TTS generation
5. Background app
6. Verify audio continues
7. Use lock screen controls
8. Skip forward/backward
9. Change playback speed
10. Add RSS episode
11. Verify mixed queue
12. Force quit app
13. Relaunch
14. Verify queue restored
15. Continue playback
```

---

## ⚠️ Risk Analysis & Mitigation

### High Risk Items

1. **Queue Data Loss**
   - Risk: Migration could lose user's queue
   - Mitigation: Backup queue before migration
   - Recovery: Restore from backup if needed

2. **TTS Generation Failure**
   - Risk: Gemini API issues
   - Mitigation: Device fallback
   - Recovery: Retry with exponential backoff

3. **Memory Leaks**
   - Risk: SwiftAudioEx retention cycles
   - Mitigation: Weak references, proper cleanup
   - Recovery: Memory profiling with Instruments

### Medium Risk Items

1. **UI State Inconsistency**
   - Risk: Race conditions in updates
   - Mitigation: MainActor, proper state management
   - Recovery: Force refresh UI

2. **Background Audio Issues**
   - Risk: iOS kills background tasks
   - Mitigation: Proper audio session config
   - Recovery: Resume on foreground

### Low Risk Items

1. **Performance Degradation**
   - Risk: Slower than old system
   - Mitigation: Profile and optimize
   - Recovery: Cache optimization

---

## 📈 Success Metrics

### Technical Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Build Success | 100% | Xcode build |
| Test Coverage | >80% | XCTest coverage |
| Crash Rate | <0.1% | Crashlytics |
| Memory Leaks | 0 | Instruments |
| Audio Start Time | <1s | Timer measurement |
| Queue Save Time | <100ms | Performance test |

### User Experience Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Playback Success | >99% | Analytics |
| Background Audio | 100% working | Manual test |
| Queue Persistence | 100% reliable | User reports |
| Live News Mode | Seamless | User feedback |
| Control Response | <100ms | UI testing |

### Code Quality Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| SwiftLint Warnings | 0 | SwiftLint |
| Deprecation Warnings | 0 | Xcode |
| Force Unwraps | <5 | Code review |
| TODO Comments | 0 | Grep search |
| Documentation | 100% public APIs | Jazzy |

---

## 🎯 Definition of Done

The migration is complete when:

1. **All UI components use new services** ✅
2. **No references to old AudioService** ✅
3. **All tests pass** ✅
4. **Feature parity confirmed** ✅
5. **No memory leaks** ✅
6. **Performance equal or better** ✅
7. **Documentation updated** ✅
8. **Feature flags removed** ✅
9. **Old files deleted** ✅
10. **Beta tested successfully** ✅

---

## 🚀 Go/No-Go Decision Criteria

### GO Criteria (All must be met)
- [ ] Build compiles without errors
- [ ] All critical features work
- [ ] No data loss during migration
- [ ] Performance acceptable
- [ ] Memory usage stable

### NO-GO Criteria (Any triggers stop)
- [ ] Crash rate >1%
- [ ] Queue persistence fails
- [ ] Background audio broken
- [ ] TTS generation fails >10%
- [ ] Memory leaks detected

---

## 📝 Post-Migration Checklist

1. **Immediate (Day 1)**
   - [ ] Monitor crash reports
   - [ ] Check analytics for playback success
   - [ ] Review user feedback
   - [ ] Hot fix any critical issues

2. **Short-term (Week 1)**
   - [ ] Performance optimization
   - [ ] Minor bug fixes
   - [ ] Documentation updates
   - [ ] Team knowledge transfer

3. **Long-term (Month 1)**
   - [ ] Feature enhancements
   - [ ] Code cleanup
   - [ ] Architecture documentation
   - [ ] Lessons learned document

---

## 🎉 Conclusion

This migration plan provides a comprehensive, risk-mitigated approach to replacing AudioService with BriefeedAudioService. The new architecture is:

1. **Cleaner**: Separation of concerns between queue and playback
2. **More Maintainable**: Clear service boundaries
3. **More Testable**: Isolated components
4. **More Reliable**: Built on proven SwiftAudioEx
5. **Future-Proof**: Extensible for new features

**Estimated Total Time**: 12-15 hours
**Recommended Approach**: Phase-by-phase with testing between phases
**Success Probability**: 95% with this plan

---

## 📎 Appendix

### A. File Mapping

| Old File | New File | Action |
|----------|----------|--------|
| AudioService.swift | BriefeedAudioService.swift | Delete old |
| AudioService+RSS.swift | (merged into BriefeedAudioService) | Delete |
| AudioServiceAdapter.swift | (not needed) | Delete |
| QueueService.swift | QueueServiceV2.swift | Replace |
| QueueService+RSS.swift | (merged into QueueServiceV2) | Delete |

### B. API Mapping

| Old API | New API | Notes |
|---------|---------|-------|
| AudioService.shared | BriefeedAudioService.shared | Singleton |
| audioService.queue | queueService.queue | Different service |
| audioService.playNow() | audioService.playNow() | Same name |
| audioService.addToQueue() | queueService.addArticle() | Different service |
| audioService.reorderQueue() | queueService.moveItem() | Different service |

### C. State Observation Mapping

| Old Pattern | New Pattern | Notes |
|-------------|-------------|-------|
| @ObservedObject audioService | @ObservedObject audioService + queueService | Two services |
| audioService.$queue | queueService.$queue | Different source |
| audioService.state | audioService.state.value | CurrentValueSubject |
| audioService.currentArticle | audioService.currentPlaybackItem | New property |

### D. Common Migration Patterns

```swift
// OLD: Direct queue manipulation
audioService.queue = articles
audioService.reorderQueue(from: source, to: dest)

// NEW: Use QueueService
await queueService.syncFromArticles(articles)
queueService.moveItem(from: source, to: dest)

// OLD: Sync playback
audioService.playNow(article)

// NEW: Async playback
await audioService.playNow(article)

// OLD: Single service observation
@ObservedObject var audioService = AudioService.shared

// NEW: Multiple service observation
@ObservedObject var audioService = BriefeedAudioService.shared
@ObservedObject var queueService = QueueServiceV2.shared
```

---

*Document Version: 2.0*
*Last Updated: Current Session*
*Author: Assistant with deep analysis*
*Status: Ready for Review and Approval*