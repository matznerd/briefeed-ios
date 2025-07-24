# Unified Queue Design - Live News Integration

## Core Concept
**One Queue to Rule Them All** - Everything flows through the Brief queue, but with smart filtering and auto-expiration.

## How It Works

### 1. Auto-Play Live News
When the app opens (with setting enabled):
- Automatically adds fresh RSS episodes to the Brief queue
- Starts playing the first one
- Continues adding new episodes as they play
- Episodes auto-expire based on type (hourly: 24h, daily: 7d)

### 2. Single Queue, Multiple Views
The Brief queue contains everything:
- Live News (RSS episodes)
- Reddit articles (TTS summaries)
- User-added content

But can be filtered to show:
- **All** (default mix)
- **Live News** (RSS only)
- **Articles** (Reddit/other sources)
- **By Source** (NPR, BBC, Reddit, etc.)

### 3. Auto-Expiration
RSS episodes automatically remove themselves:
- Hourly feeds: Remove after 24 hours if unplayed
- Daily feeds: Remove after 7 days if unplayed
- Played episodes: Remove immediately after completion (unless user saves)

## Visual Design

### Brief Tab with Filter
```
┌─────────────────────────┐
│ Brief     [All ▼]       │  <- Dropdown filter
├─────────────────────────┤
│ ▶️ NPR News Now         │
│    Live • 5 min         │
├─────────────────────────┤
│ 🔵 Reddit: Tech News    │
│    r/technology • 2 min │
├─────────────────────────┤
│ 🔵 BBC Global News      │
│    Live • 12 min        │
├─────────────────────────┤
│ 🔵 Reddit: World News   │
│    r/worldnews • 3 min  │
└─────────────────────────┘
```

### Filter Options
```
[All ▼]
├── All (Mixed)
├── Live News
├── Articles  
└── By Source
    ├── NPR
    ├── BBC
    ├── Reddit
    └── Others...
```

### Mini Player Enhancement
```
Standard:
[▶️ NPR News Now - 2:34/5:00] 

With Quick Filter:
[▶️ NPR News Now - 2:34/5:00] [📻]
                                ↑
                        Tap to filter to Live News only
```

## Implementation Details

### Queue Item Structure
```swift
struct QueueItem {
    let id: String
    let title: String
    let source: QueueItemSource
    let duration: Int?
    let addedDate: Date
    let expiresAt: Date?
    let audioUrl: URL?
    let audioData: Data? // For TTS
    
    enum QueueItemSource {
        case rss(feedName: String)
        case reddit(subreddit: String)
        case custom
    }
}
```

### Auto-Population Logic
```swift
func autoPlayLiveNews() {
    // Get fresh episodes
    let freshEpisodes = rssService.getFreshEpisodes()
        .prefix(10) // Reasonable limit
    
    // Add to queue with expiration
    for episode in freshEpisodes {
        let queueItem = QueueItem(
            source: .rss(episode.feedName),
            expiresAt: calculateExpiration(episode)
        )
        queueService.addToQueue(queueItem)
    }
    
    // Start playing if nothing active
    if !audioService.isPlaying {
        audioService.playNext()
    }
}
```

### Smart Expiration
```swift
// Runs periodically
func cleanupExpiredItems() {
    let now = Date()
    queueItems.removeAll { item in
        guard let expiresAt = item.expiresAt else { return false }
        return now > expiresAt && !item.isPlaying && !item.isSaved
    }
}
```

### Filter Implementation
```swift
enum QueueFilter {
    case all
    case liveNews
    case articles
    case source(String)
}

var filteredQueue: [QueueItem] {
    switch currentFilter {
    case .all:
        return queueItems
    case .liveNews:
        return queueItems.filter { $0.source.isRSS }
    case .articles:
        return queueItems.filter { $0.source.isArticle }
    case .source(let name):
        return queueItems.filter { $0.source.name == name }
    }
}
```

## Settings

### New UserDefaults Keys
```swift
- autoPlayLiveNewsOnOpen: Bool
- briefQueueDefaultFilter: String ("all", "liveNews", "articles")
- mixLiveNewsWithArticles: Bool
- liveNewsExpirationHours: Int
```

### Settings UI
```
Live News Settings:
- [x] Auto-play live news on app open
- [x] Mix live news with articles
- Default filter: [All ▼]
- Keep unplayed episodes: [24 hours ▼]
```

## User Flows

### Flow 1: Morning News Briefing
1. User opens app → Live news starts playing
2. Fresh RSS episodes auto-populate Brief queue
3. User can add Reddit articles as they browse
4. Everything plays in order added
5. Old episodes auto-expire later

### Flow 2: Curated Session
1. User manually adds specific episodes/articles
2. No auto-population (setting disabled)
3. Full control over queue content
4. Items only expire if RSS-based

### Flow 3: Live News Only
1. User filters Brief to "Live News"
2. Sees only RSS episodes
3. Can still add articles (appear when filter removed)
4. Clean, focused news experience

## Advantages

1. **Simple Mental Model**: One queue for everything
2. **No Context Switching**: Everything in Brief tab
3. **Smart Defaults**: Auto-play and auto-cleanup
4. **User Control**: Filters let users focus
5. **Natural Integration**: RSS episodes are just queue items
6. **Familiar UX**: Same swipe gestures everywhere

## Edge Cases Handled

1. **Queue Overflow**: Max 50 items, oldest expire first
2. **Duplicate Episodes**: Check by ID before adding
3. **Network Failures**: Skip to next item
4. **Mixed Playback**: Seamless switch between RSS/TTS
5. **App Restart**: Restore queue minus expired items

This design treats RSS episodes as first-class queue items that happen to have expiration dates and auto-populate when enabled. Much cleaner than separate contexts!