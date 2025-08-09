# Current Issues & UI Freeze Problems

## Critical Issue: UI Freezes

### Symptoms
- **Complete UI lockup** for 1-5 seconds
- **Unresponsive taps** during freeze
- **Animation stuttering** before/after freeze
- **Beach ball cursor** (Mac Catalyst)

### Trigger Points
1. **Opening Brief tab** (queue view)
2. **Adding items to queue**
3. **Audio playback state changes**
4. **Tab switching** with active playback
5. **App launch** with saved queue

## Root Causes Identified

### 1. Main Thread Blocking

#### QueueServiceV2 Synchronization
```swift
// PROBLEM: Sync happens on main thread
func syncWithAudioService() {
    // This blocks UI
    let audioItems = queue.map { item in
        createAudioItem(from: item) // Heavy operation
    }
    audioService.updateQueue(audioItems) // Synchronous
}
```

#### Core Data Operations
```swift
// PROBLEM: Fetch on main thread
let fetchRequest = Article.fetchRequest()
let articles = try? viewContext.fetch(fetchRequest) // BLOCKS UI
```

### 2. Excessive View Re-renders

#### Published Property Cascade
```swift
// Every queue change triggers:
@Published var queue: [EnhancedQueueItem] = []
// → Updates BriefView
// → Updates ContentView
// → Updates MiniAudioPlayer
// → Updates ExpandedPlayer
// ALL SIMULTANEOUSLY
```

#### SwiftUI Diffing Issues
```swift
// Large list diffing is expensive
List(queue) { item in // 100+ items
    ComplexRowView(item: item) // Heavy view
}
// SwiftUI compares ALL items on EVERY change
```

### 3. Audio Service Architecture

#### SwiftAudioEx Integration
```swift
// PROBLEM: Not fully async
class BriefeedAudioService {
    func updateQueue(_ items: [AudioItem]) {
        // Synchronous operations
        audioController.clear() // Blocks
        for item in items {
            audioController.addItem(item) // Blocks each
        }
    }
}
```

### 4. Memory Pressure

#### Queue Item Bloat
```swift
struct EnhancedQueueItem: Codable {
    // Large objects in memory
    let articleContent: String? // Can be 50KB+
    let audioData: Data? // Can be 5MB+
    // × 100 items = 500MB+ RAM
}
```

## Attempted Fixes (Failed)

### 1. Deferred Sync Timer
```swift
// Attempted: Delay sync operations
private var deferredSyncTimer: Timer?

func scheduleDeferredSync() {
    deferredSyncTimer = Timer.scheduledTimer(
        withTimeInterval: 0.5,
        repeats: false
    ) { _ in
        self.performSync() // STILL BLOCKS
    }
}
// Result: Just delays the freeze
```

### 2. Background Queue
```swift
// Attempted: Move to background
DispatchQueue.global(qos: .userInitiated).async {
    self.loadQueue()
    DispatchQueue.main.async {
        self.updateUI() // CAUSES RACE CONDITIONS
    }
}
// Result: Crashes from thread conflicts
```

### 3. Async/Await Migration
```swift
// Attempted: Make everything async
func addArticle(_ article: Article) async {
    await MainActor.run {
        queue.append(item) // STILL ON MAIN THREAD
    }
}
// Result: No improvement, same freezes
```

## Other Known Issues

### 1. Audio Playback
- **AVAudioSession error -50**: Fixed by migration to BriefeedAudioService
- **Background audio stops**: iOS suspends app incorrectly
- **Remote commands broken**: Lock screen controls unresponsive

### 2. Content Processing
- **Gemini API timeouts**: Long articles fail
- **TTS generation failures**: Rate limiting issues
- **Summary quality**: Generic responses for complex articles
- **Firecrawl failures**: Some sites block scraping

### 3. Feed Management
- **Reddit rate limiting**: 429 errors during heavy use
- **RSS parsing failures**: Non-standard XML formats
- **Duplicate articles**: No deduplication across feeds
- **Stale content**: Old articles not cleaned up

### 4. UI/UX Problems
- **Swipe gesture conflicts**: Competing with system gestures
- **Animation glitches**: During queue reordering
- **Dark mode issues**: Some text invisible
- **iPad layout**: Not optimized for larger screens

### 5. Performance
- **Memory leaks**: Queue items not released
- **Cache growth**: Audio files accumulate (100MB+)
- **Battery drain**: Continuous background processing
- **Startup time**: Slow with large queues

## Proposed Solutions

### 1. Complete Queue Rewrite
```swift
// Move to actor-based concurrency
actor QueueManager {
    private var items: [QueueItem] = []
    
    func add(_ item: QueueItem) async {
        // Thread-safe, off main thread
        items.append(item)
        await notifyObservers()
    }
}
```

### 2. Virtualized List
```swift
// Only render visible items
LazyVStack {
    ForEach(visibleRange) { index in
        if let item = queue[safe: index] {
            QueueRow(item: item)
        }
    }
}
```

### 3. Debounced Updates
```swift
// Batch UI updates
class BatchedPublisher {
    private var pendingUpdates: [Update] = []
    private var timer: Timer?
    
    func scheduleUpdate(_ update: Update) {
        pendingUpdates.append(update)
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: 0.1,
            repeats: false
        ) { _ in
            self.flushUpdates()
        }
    }
}
```

### 4. Background Core Data Context
```swift
// Separate context for heavy operations
let backgroundContext = persistentContainer.newBackgroundContext()
backgroundContext.perform {
    // Fetch and process off main thread
    let articles = try? backgroundContext.fetch(request)
    // Process...
}
```

## Debugging Tools Added

### FreezeDetector
```swift
class FreezeDetector {
    func startMonitoring() {
        // Detect main thread blocks > 100ms
        DispatchQueue.main.async {
            let start = CACurrentMediaTime()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let elapsed = CACurrentMediaTime() - start
                if elapsed > 0.15 {
                    print("⚠️ UI FREEZE: \(elapsed)s")
                }
            }
        }
    }
}
```

### Performance Logger
```swift
class PerformanceLogger {
    func logOperation(_ name: String) {
        let start = CACurrentMediaTime()
        defer {
            let elapsed = CACurrentMediaTime() - start
            if elapsed > 0.05 {
                print("🐌 Slow operation: \(name) took \(elapsed)s")
            }
        }
    }
}
```

## Current Status

### What Works
- Basic playback functionality
- Content fetching and summarization
- Queue persistence
- RSS feed updates

### What's Broken
- **UI responsiveness** (critical)
- **Queue synchronization** (causes freezes)
- **Memory management** (leaks and bloat)
- **Performance** (degrades over time)

### Priority Fixes Needed
1. **Eliminate UI freezes** - Complete architecture change
2. **Fix memory leaks** - Proper cleanup
3. **Optimize Core Data** - Background contexts
4. **Rewrite queue sync** - Fully async