# Queue System Architecture

## Overview
The queue system manages the playback order of articles and RSS episodes, with persistence, background processing, and synchronization with the audio service.

## Core Components

### Service: `QueueServiceV2.swift`
- **Singleton**: Shared instance across app
- **Published Properties**: Queue state for UI binding
- **Background Processing**: TTS generation for upcoming items
- **Persistence**: UserDefaults storage

### Model: `EnhancedQueueItem`
Unified queue item supporting both articles and RSS episodes:

```swift
struct EnhancedQueueItem {
    let id: UUID
    let title: String
    let source: QueueItemSource      // .article or .rss
    let addedDate: Date
    let expiresAt: Date?             // For time-limited content
    
    // Content references
    let articleID: UUID?             // For articles
    let audioUrl: URL?               // For RSS episodes
    let duration: Int?               // In seconds
    
    // Playback state
    var isListened: Bool
    var lastPosition: Double         // 0.0 to 1.0 progress
}
```

## Queue Operations

### Adding Items

#### Add Article
```swift
func addArticle(_ article: Article, playNext: Bool = false) async {
    // 1. Check if already in queue
    if queue.contains(where: { $0.articleID == article.id }) {
        return
    }
    
    // 2. Create EnhancedQueueItem
    let item = EnhancedQueueItem(from: article)
    
    // 3. Insert at appropriate position
    if playNext && currentIndex >= 0 {
        queue.insert(item, at: currentIndex + 1)
    } else {
        queue.append(item)
    }
    
    // 4. Save to persistence
    saveQueue()
    
    // 5. Start background TTS generation
    startTTSGeneration(for: article)
    
    // 6. Schedule deferred sync (avoid UI freeze)
    scheduleDeferredSync()
}
```

#### Add RSS Episode
```swift
func addRSSEpisode(_ episode: RSSEpisode, playNext: Bool = false) {
    // Similar flow but no TTS generation needed
    // RSS episodes have direct audio URLs
}
```

### Queue Management

#### Remove Item
```swift
func removeItem(at index: Int) {
    // 1. Cancel any TTS generation in progress
    if let task = ttsGenerationTasks[item.id] {
        task.cancel()
    }
    
    // 2. Remove from queue
    queue.remove(at: index)
    
    // 3. Adjust current index
    if index < currentIndex {
        currentIndex -= 1
    } else if index == currentIndex {
        currentIndex = min(currentIndex, queue.count - 1)
    }
    
    // 4. Save and sync
    saveQueue()
    scheduleDeferredSync()
}
```

#### Reorder Items
```swift
func moveItem(from source: IndexSet, to destination: Int) {
    queue.move(fromOffsets: source, toOffset: destination)
    
    // Adjust current index based on move
    for index in source {
        if index == currentIndex {
            currentIndex = destination > index ? destination - 1 : destination
        }
    }
    
    saveQueue()
}
```

## Persistence

### Storage Format
```swift
// UserDefaults keys
private let queueKey = "EnhancedAudioQueueV2"
private let indexKey = "EnhancedAudioQueueIndexV2"

// Save queue
func saveQueue() {
    let encoder = JSONEncoder()
    if let data = try? encoder.encode(queue) {
        userDefaults.set(data, forKey: queueKey)
    }
    userDefaults.set(currentIndex, forKey: indexKey)
}

// Load queue
func loadQueue() {
    if let data = userDefaults.data(forKey: queueKey),
       let items = try? JSONDecoder().decode([EnhancedQueueItem].self, from: data) {
        self.queue = items
    }
    self.currentIndex = userDefaults.integer(forKey: indexKey)
}
```

## Background TTS Generation

### Pre-generation Strategy
```swift
private func startTTSGeneration(for article: Article) {
    let task = Task { @MainActor in
        // 1. Fetch article content if needed
        if article.content == nil {
            await fetchArticleContent(article)
        }
        
        // 2. Generate summary if missing
        if article.summary == nil {
            let summary = await geminiService.generateSummary(from: article.url)
            article.summary = summary
        }
        
        // 3. Generate TTS audio
        let speechText = GeminiTTSService.shared.formatStoryForSpeech(article)
        let ttsResult = await GeminiTTSService.shared.generateSpeech(
            text: speechText,
            useRandomVoice: true
        )
        
        // Audio is now cached for instant playback
    }
    
    ttsGenerationTasks[article.id] = task
}
```

## Audio Service Synchronization

### Deferred Sync Pattern
```swift
// Avoid UI freezes by deferring sync
private var deferredSyncTimer: Timer?
private var needsSync = false

private func scheduleDeferredSync() {
    needsSync = true
    
    // Cancel existing timer
    deferredSyncTimer?.invalidate()
    
    // Schedule sync after 0.5 seconds of inactivity
    deferredSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
        Task { @MainActor in
            self.performDeferredSync()
        }
    }
}

private func performDeferredSync() {
    guard needsSync else { return }
    needsSync = false
    
    // Sync with audio service
    audioService.updateQueue(queue, startingAt: currentIndex)
}
```

## Playback Control

### Play Queue
```swift
func playFromIndex(_ index: Int) async {
    guard index >= 0 && index < queue.count else { return }
    
    currentIndex = index
    let item = queue[index]
    
    if let articleID = item.articleID {
        // Play article with TTS
        await playArticle(withID: articleID)
    } else if let audioUrl = item.audioUrl {
        // Play RSS episode
        await audioService.playRSSEpisode(url: audioUrl, title: item.title)
    }
}
```

### Auto-advance
```swift
func playNext() async -> Bool {
    guard currentIndex < queue.count - 1 else { return false }
    
    currentIndex += 1
    await playFromIndex(currentIndex)
    return true
}
```

## Queue Filtering

### Filter Types
```swift
enum QueueFilter {
    case all        // Show everything
    case liveNews   // RSS episodes only
    case articles   // Articles only
}
```

### Applied in UI
```swift
var filteredQueue: [EnhancedQueueItem] {
    queue.filter { item in
        switch currentFilter {
        case .all:
            return true
        case .liveNews:
            return item.source.isLiveNews
        case .articles:
            return !item.source.isLiveNews
        }
    }
}
```

## Performance Issues

### Current Problems
1. **UI Freezes**: Sync operations block main thread
2. **Memory Usage**: Large queues consume significant memory
3. **TTS Generation**: Can timeout for long articles
4. **State Updates**: Excessive re-renders from queue changes

### Attempted Solutions
- Deferred sync with timers
- Background queue for operations
- Async/await for non-blocking code
- Published property optimization

### Remaining Issues
- Core Data fetches still synchronous
- Audio service sync still causes freezes
- SwiftUI diffing inefficient for large queues