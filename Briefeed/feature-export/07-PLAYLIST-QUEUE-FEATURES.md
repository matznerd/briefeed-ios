# Playlist & Queue Features

## Overview
The queue system supports mixed content (articles + RSS episodes), automatic playback, persistence across app launches, and smart queue management.

## Queue Types

### Unified Queue
- **Articles**: Text articles converted to speech
- **RSS Episodes**: Direct audio playback
- **Mixed Playback**: Seamless transition between types

## Queue Features

### 1. Add to Queue

#### Quick Add Methods
```swift
// From article row - swipe or long press
"Play Now" → Add to queue and play immediately
"Play Next" → Insert after current item

// From article detail view
Button("Add to Queue") {
    queueService.addArticle(article)
}

// Batch add from feed
Button("Queue All Unread") {
    for article in unreadArticles {
        await queueService.addArticle(article)
    }
}
```

### 2. Queue Persistence

#### Automatic Save/Restore
```swift
// Saved to UserDefaults on every change
Queue items → JSON encoded → UserDefaults
Current index → Integer → UserDefaults

// Restored on app launch
func loadQueue() {
    let data = userDefaults.data(forKey: "EnhancedAudioQueueV2")
    queue = JSONDecoder().decode([EnhancedQueueItem].self, from: data)
    currentIndex = userDefaults.integer(forKey: "EnhancedAudioQueueIndexV2")
}
```

### 3. Smart Queue Management

#### Duplicate Prevention
```swift
// Articles checked by ID
if queue.contains(where: { $0.articleID == article.id }) {
    return // Skip duplicate
}

// RSS episodes checked by URL
if queue.contains(where: { $0.audioUrl == episode.audioUrl }) {
    return // Skip duplicate
}
```

#### Auto-remove Listened
```swift
// RSS episodes marked as listened
if item.source.isLiveNews && playbackProgress > 0.95 {
    item.isListened = true
    // Optionally remove from queue
}
```

### 4. Queue Reordering

#### Drag & Drop
```swift
List {
    ForEach(queue) { item in
        QueueRowView(item: item)
    }
    .onMove { source, destination in
        queueService.moveItem(from: source, to: destination)
    }
}
```

#### Priority Insertion
```swift
// "Play Next" inserts after current
if playNext && currentIndex >= 0 {
    queue.insert(item, at: currentIndex + 1)
}
```

### 5. Queue Filtering

#### Filter Options
```swift
enum QueueFilter {
    case all        // Everything
    case liveNews   // RSS episodes only  
    case articles   // Articles only
}

// Applied in UI
Picker("Filter", selection: $filter) {
    Text("All").tag(QueueFilter.all)
    Text("Live News").tag(QueueFilter.liveNews)
    Text("Articles").tag(QueueFilter.articles)
}
```

### 6. Background Processing

#### Pre-generation Pipeline
```swift
// When article added to queue:
1. Fetch content (if needed)
2. Generate summary (if missing)
3. Generate TTS audio
4. Cache for instant playback

// Happens in background
Task {
    await fetchArticleContent(article)
    await generateSummary(article)
    await generateTTSAudio(article)
}
```

## Playback Features

### 1. Continuous Playback

#### Auto-advance
```swift
// When item finishes
audioService.onPlaybackFinished = {
    if await queueService.playNext() {
        // Playing next item
    } else {
        // Queue finished
    }
}
```

### 2. Resume Position

#### Track Progress
```swift
struct EnhancedQueueItem {
    var lastPosition: Double // 0.0 to 1.0
    
    // Save position periodically
    func updatePosition(_ progress: Double) {
        lastPosition = progress
        saveQueue()
    }
}
```

### 3. Playback Speed

#### Global Setting
```swift
// Applies to all TTS content
UserDefaultsManager.shared.playbackSpeed // 0.5x to 2.0x

// RSS episodes use native speed control
audioPlayer.rate = playbackSpeed
```

## Queue UI

### Brief View (Queue Tab)

#### Layout
```swift
VStack {
    // Now Playing section
    if let currentItem = currentItem {
        NowPlayingCard(item: currentItem)
    }
    
    // Queue list
    List {
        Section("Up Next") {
            ForEach(upcomingItems) { item in
                QueueRowView(item: item)
                    .swipeActions {
                        Button("Remove") {
                            removeItem(item)
                        }
                    }
            }
        }
        
        Section("History") {
            ForEach(playedItems) { item in
                QueueRowView(item: item)
                    .opacity(0.6)
            }
        }
    }
}
```

#### Queue Row
```swift
HStack {
    // Icon based on type
    Image(systemName: item.source.iconName)
    
    VStack(alignment: .leading) {
        Text(item.title)
            .lineLimit(2)
        
        HStack {
            Text(item.source.displayName)
                .font(.caption)
            
            if let duration = item.formattedDuration {
                Text(duration)
                    .font(.caption)
            }
        }
    }
    
    // Playing indicator
    if isCurrentlyPlaying {
        WaveformMiniView()
    }
}
```

## Queue Actions

### Bulk Operations

```swift
// Clear all
Button("Clear Queue") {
    queueService.clearQueue()
}

// Remove listened
Button("Remove Played") {
    queueService.removePlayedItems()
}

// Shuffle
Button("Shuffle") {
    queueService.shuffleQueue()
}
```

### Context Menu

```swift
.contextMenu {
    Button("Play Now") {
        queueService.playFromIndex(index)
    }
    
    Button("Move to Top") {
        queueService.moveToTop(index)
    }
    
    Button("Remove") {
        queueService.removeItem(at: index)
    }
    
    if item.source.isArticle {
        Button("View Article") {
            navigateToArticle(item.articleID)
        }
    }
}
```

## Smart Features

### 1. Expiring Content
```swift
struct EnhancedQueueItem {
    let expiresAt: Date? // For time-sensitive content
    
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() > expiresAt
    }
}
```

### 2. Queue Limits
```swift
// Prevent excessive memory usage
let maxQueueSize = 100

func addToQueue(_ item: EnhancedQueueItem) {
    if queue.count >= maxQueueSize {
        queue.removeFirst() // FIFO
    }
    queue.append(item)
}
```

### 3. Smart Ordering
```swift
// Priority scoring for auto-queue
func priorityScore(for article: Article) -> Int {
    var score = 0
    
    // Newer articles higher priority
    if article.age < 1.hour { score += 10 }
    
    // User's preferred sources
    if preferredSources.contains(article.source) { score += 5 }
    
    // Popular articles
    if article.score > 100 { score += 3 }
    
    return score
}
```

## Performance Optimizations

### Lazy Loading
```swift
// Don't load all queue items at once
LazyVStack {
    ForEach(visibleQueueItems) { item in
        QueueRowView(item: item)
    }
}
```

### Batch Updates
```swift
// Defer sync to avoid UI freezes
private func scheduleDeferredSync() {
    deferredSyncTimer?.invalidate()
    deferredSyncTimer = Timer.scheduledTimer(
        withTimeInterval: 0.5,
        repeats: false
    ) { _ in
        performSync()
    }
}
```

## Known Issues

1. **Queue sync freezes UI** during large updates
2. **Memory usage** grows with queue size
3. **TTS generation** can timeout for long articles
4. **Reordering animation** stutters with many items