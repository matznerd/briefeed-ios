# Live News (RSS Podcast) Feature

## Overview
Live News provides radio-style playback of RSS podcast feeds, automatically queuing the latest episodes from news sources with a single tap.

## Service: `RSSAudioService.swift`

### Core Functionality
- **RSS Feed Management**: Add/remove podcast feeds
- **Episode Fetching**: Parse RSS XML for episodes
- **Auto-refresh**: Periodic updates (hourly/daily)
- **Smart Queuing**: Latest unlistened episodes only
- **Listen Tracking**: Mark episodes as played

## Default News Feeds

### Pre-configured Sources
```swift
defaultFeedsConfig = [
    ("npr-news-now", "NPR News Now", "hourly"),
    ("bbc-global-news", "BBC Global News Podcast", "daily"),
    ("abc-news-update", "ABC News Update", "hourly"),
    ("cbs-on-the-hour", "CBS News: On The Hour", "hourly"),
    ("marketplace-morning", "Marketplace Morning Report", "daily"),
    ("marketplace-tech", "Marketplace Tech", "daily"),
    ("nyt-the-daily", "The Daily", "daily"),
    ("wsj-minute-briefing", "WSJ Minute Briefing", "daily"),
    ("cbc-world-this-hour", "CBC World This Hour", "hourly")
]
```

### Update Frequencies
- **Hourly**: NPR, ABC, CBS, CBC
- **Daily**: BBC, Marketplace, NYT, WSJ

## Data Models

### RSSFeed (Core Data)
```swift
entity RSSFeed {
    id: String           // Unique identifier
    url: String          // RSS feed URL
    displayName: String  // User-friendly name
    updateFrequency: String // "hourly" or "daily"
    priority: Int16      // Sort order (1 = highest)
    isEnabled: Bool      // User toggle
    lastFetchDate: Date? // Last refresh time
    episodes: Set<RSSEpisode> // Related episodes
}
```

### RSSEpisode (Core Data)
```swift
entity RSSEpisode {
    guid: String         // Unique episode ID
    title: String
    audioUrl: String     // Direct MP3 URL
    duration: Int32      // Seconds
    publishDate: Date
    isListened: Bool     // Playback tracking
    feed: RSSFeed        // Parent feed
}
```

## RSS Parsing

### XML Structure Handling
```swift
class RSSParser: NSObject, XMLParserDelegate {
    // Parse RSS 2.0 format
    func parse(data: Data) -> [Episode] {
        // Extract from XML:
        // <item>
        //   <title>Episode Title</title>
        //   <enclosure url="audio.mp3" type="audio/mpeg" />
        //   <pubDate>Wed, 01 Jan 2025 12:00:00 GMT</pubDate>
        //   <guid>unique-id</guid>
        //   <itunes:duration>5:30</itunes:duration>
        // </item>
    }
}
```

## Live News Playback

### "Play Live News" Button Logic
```swift
func playLiveNews() async {
    // 1. Clear existing queue
    queueService.clearQueue()
    
    // 2. Get fresh episodes
    let episodes = getFreshEpisodes()
    
    // 3. Smart selection
    var selectedEpisodes: [RSSEpisode] = []
    var seenFeeds = Set<String>()
    
    for episode in episodes {
        // One episode per feed
        if !seenFeeds.contains(episode.feed.id) {
            // Skip if already listened
            if !episode.isListened {
                selectedEpisodes.append(episode)
                seenFeeds.insert(episode.feed.id)
            }
        }
    }
    
    // 4. Add to queue
    for episode in selectedEpisodes {
        queueService.addRSSEpisode(episode)
    }
    
    // 5. Start playback
    if !selectedEpisodes.isEmpty {
        await audioService.playFromStart()
    }
}
```

### Fresh Episode Selection
```swift
func getFreshEpisodes() -> [RSSEpisode] {
    // Sorted by feed priority, then date
    return feeds
        .filter { $0.isEnabled }
        .sorted { $0.priority < $1.priority }
        .flatMap { feed in
            feed.episodes
                .filter { !$0.isListened }
                .filter { $0.isFresh } // < 24 hours old
                .sorted { $0.publishDate > $1.publishDate }
                .prefix(1) // Latest per feed
        }
}
```

## Auto-refresh System

### Timer-based Updates
```swift
private func setupAutoRefresh() {
    // Check every 30 minutes
    refreshTimer = Timer.scheduledTimer(
        withTimeInterval: 1800, // 30 minutes
        repeats: true
    ) { _ in
        Task {
            await self.checkAndRefreshFeeds()
        }
    }
}

func checkAndRefreshFeeds() async {
    for feed in feeds.filter({ $0.isEnabled }) {
        let shouldRefresh: Bool
        
        switch feed.updateFrequency {
        case "hourly":
            // Refresh if > 1 hour since last fetch
            shouldRefresh = Date().timeIntervalSince(feed.lastFetchDate) > 3600
        case "daily":
            // Refresh if > 24 hours since last fetch
            shouldRefresh = Date().timeIntervalSince(feed.lastFetchDate) > 86400
        default:
            shouldRefresh = false
        }
        
        if shouldRefresh {
            await refreshFeed(feed)
        }
    }
}
```

## Listen Tracking

### Mark as Listened
```swift
// Automatic when playback > 95% complete
audioService.onPlaybackProgress = { progress in
    if progress > 0.95 {
        if let episode = currentEpisode {
            episode.isListened = true
            saveContext()
        }
    }
}

// Manual marking
func markAsListened(_ episode: RSSEpisode) {
    episode.isListened = true
    saveContext()
}
```

### Episode Cleanup
```swift
func cleanupOldEpisodes() {
    for feed in feeds {
        let oldEpisodes = feed.episodes.filter { episode in
            // Remove if > 7 days old AND listened
            let isOld = Date().timeIntervalSince(episode.publishDate) > 604800
            return isOld && episode.isListened
        }
        
        for episode in oldEpisodes {
            viewContext.delete(episode)
        }
    }
    
    try? viewContext.save()
}
```

## UI Components

### Live News View
```swift
struct LiveNewsViewV2: View {
    @StateObject var rssService = RSSAudioService.shared
    
    var body: some View {
        VStack {
            // Big play button
            Button(action: playLiveNews) {
                VStack {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 60))
                    Text("Play Live News")
                        .font(.headline)
                }
            }
            .buttonStyle(RadioButtonStyle())
            
            // Feed management
            List {
                Section("News Sources") {
                    ForEach(rssService.feeds) { feed in
                        FeedRow(feed: feed)
                    }
                }
            }
        }
    }
}
```

### Feed Row
```swift
struct FeedRow: View {
    let feed: RSSFeed
    
    var body: some View {
        HStack {
            // Enable/disable toggle
            Toggle(isOn: $feed.isEnabled) {
                VStack(alignment: .leading) {
                    Text(feed.displayName)
                    Text("\(feed.updateFrequency) updates")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Fresh episode count
            if feed.freshEpisodeCount > 0 {
                Badge(count: feed.freshEpisodeCount)
            }
        }
    }
}
```

## Settings Integration

### User Preferences
```swift
// Auto-play on app launch
UserDefaultsManager.shared.autoPlayLiveNews // Bool

// Episode retention
UserDefaultsManager.shared.episodeRetentionDays // Int (default: 7)

// Preferred news sources (priority override)
UserDefaultsManager.shared.preferredNewsSources // [String]
```

## Performance Optimizations

### Lazy Loading
```swift
// Don't fetch all episodes at once
func getEpisodesPage(offset: Int, limit: Int = 20) -> [RSSEpisode] {
    let request = NSFetchRequest<RSSEpisode>(entityName: "RSSEpisode")
    request.fetchOffset = offset
    request.fetchLimit = limit
    request.sortDescriptors = [
        NSSortDescriptor(keyPath: \RSSEpisode.publishDate, ascending: false)
    ]
    return try? viewContext.fetch(request) ?? []
}
```

### Background Fetching
```swift
// Refresh feeds in background
func backgroundRefresh() {
    Task.detached(priority: .background) {
        await self.refreshAllFeeds()
    }
}
```

## Known Issues

1. **XML parsing failures** with non-standard RSS formats
2. **Audio URL extraction** fails for some podcast providers
3. **Duration parsing** inconsistent (iTunes vs standard)
4. **Memory usage** with many episodes cached
5. **Refresh timing** not always reliable