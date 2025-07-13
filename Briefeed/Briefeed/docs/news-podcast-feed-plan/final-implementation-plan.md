# RSS Audio News - Final Implementation Plan

## Overview
Add a "Live News" tab that acts like a news radio station - tap the tab and fresh news episodes start playing automatically. Users can also add individual episodes to their Brief queue for mixed playback with article summaries.

## Core Architecture Decisions

### 1. Unified Audio System
- **Extend existing AudioService** with RSS capabilities
- RSS episodes and article summaries share the same audio pipeline
- Seamless switching between RSS audio files and TTS
- Single mini player at bottom controls all audio

### 2. Dual Queue System
- **Live News Queue**: Auto-generated playlist on RSS tab (newest first)
- **Brief Queue**: User-curated mix of articles and RSS episodes
- Episodes can be moved from Live News to Brief via swipe gestures

### 3. Smart Caching
- Use existing download logic from article summaries
- Cache current playing + next episode
- Progressive download while playing
- Automatic cleanup of old cached files

## Implementation Phases

### Phase 1: Data Layer (2 days)

#### Core Data Entities

**RSSFeed**
```swift
- id: String (unique identifier)
- url: String
- displayName: String  
- updateFrequency: String ("hourly", "daily")
- priority: Int16 (for ordering)
- isEnabled: Bool
- lastFetchDate: Date?
- episodes: [RSSEpisode] (relationship)
```

**RSSEpisode**
```swift
- id: String (guid or computed hash)
- feedId: String
- title: String
- audioUrl: String
- pubDate: Date
- duration: Int32? (seconds)
- description: String?
- isListened: Bool
- lastPosition: Float (0.0-1.0)
- cachedFilePath: String?
- feed: RSSFeed (relationship)
```

#### UserDefaults Keys
```swift
- rssAutoPlayOnOpen: Bool
- rssPlaybackSpeed: Float  
- rssFeedOrder: [String] // Feed IDs in priority order
- rssLastPlayedEpisodeId: String?
```

### Phase 2: RSS Service (2 days)

#### RSSAudioService
```swift
@MainActor
class RSSAudioService: ObservableObject {
    // Singleton instance
    static let shared = RSSAudioService()
    
    // Published properties for UI
    @Published var feeds: [RSSFeed] = []
    @Published var currentEpisodes: [RSSEpisode] = []
    @Published var isRefreshing = false
    
    // Core functionality
    func loadDefaultFeeds()
    func refreshAllFeeds() async
    func parsePlayerFMUrl(_ url: String) async -> String?
    func getOrderedEpisodes() -> [RSSEpisode]
    func markEpisodeListened(_ episode: RSSEpisode)
    func cleanupOldEpisodes() // 24h for hourly, 7d for daily
}
```

#### Default Feeds Configuration
```swift
struct RSSFeedConfig {
    static let defaultFeeds = [
        (id: "npr-news-now", url: "https://feeds.npr.org/500005/podcast.xml", 
         name: "NPR News Now", frequency: "hourly", priority: 1),
        (id: "bbc-global-news", url: "https://podcasts.files.bbci.co.uk/p02nq0gn.rss",
         name: "BBC Global News", frequency: "daily", priority: 2),
        // ... rest of feeds
    ]
}
```

### Phase 3: Audio Integration (2 days)

#### Extend AudioService
```swift
extension AudioService {
    // RSS Mode
    private var rssQueue: [RSSEpisode] = []
    private var isPlayingRSS = false
    
    // New methods
    func playRSSEpisode(_ episode: RSSEpisode)
    func playLiveNewsQueue() // Auto-play fresh episodes
    func addRSSToMainQueue(_ episode: RSSEpisode)
    func getRSSAudioUrl(_ episode: RSSEpisode) async -> URL?
}
```

#### Audio Source Protocol
```swift
protocol AudioSource {
    var id: String { get }
    var title: String { get }
    var audioUrl: URL? { get }
    var sourceType: AudioSourceType { get }
}

enum AudioSourceType {
    case articleTTS
    case rssEpisode
}
```

### Phase 4: UI Implementation (3 days)

#### Live News Tab
```swift
struct LiveNewsView: View {
    @StateObject private var rssService = RSSAudioService.shared
    @StateObject private var audioService = AudioService.shared
    @State private var selectedEpisode: RSSEpisode?
    
    var body: some View {
        NavigationView {
            VStack {
                // Now Playing Section (if RSS episode)
                if audioService.isPlayingRSS {
                    NowPlayingCard()
                }
                
                // Episode List
                List {
                    ForEach(rssService.currentEpisodes) { episode in
                        RSSEpisodeRow(episode: episode)
                            .swipeActions { swipeButtons }
                    }
                }
                .refreshable {
                    await rssService.refreshAllFeeds()
                }
            }
            .navigationTitle("Live News")
            .onAppear {
                handleAutoPlay()
            }
        }
    }
    
    private func handleAutoPlay() {
        guard UserDefaultsManager.shared.rssAutoPlayOnOpen else { return }
        audioService.playLiveNewsQueue()
    }
}
```

#### Episode Row States
```swift
struct RSSEpisodeRow: View {
    let episode: RSSEpisode
    @StateObject private var audioService = AudioService.shared
    
    private var indicator: some View {
        if audioService.currentRSSEpisode?.id == episode.id {
            // NOW PLAYING - animated waveform
        } else if episode.isListened {
            // Checkmark with 50% opacity
        } else if episode.isFresh {
            // Red LIVE badge
        } else {
            // Blue unplayed dot
        }
    }
}
```

#### Swipe Actions (Reuse Pattern)
- Default right swipe → Add to Brief queue
- Show action buttons: Play Now, Play Next, Add to Queue
- Left swipe → Mark as Listened

### Phase 5: Settings Integration (1 day)

#### RSS Settings Section
```swift
struct RSSSettingsView: View {
    // Playback
    - Auto-play on tab open: Toggle
    - Playback speed: Slider (separate from TTS)
    
    // Feed Management  
    - Feed priority list (drag to reorder)
    - Toggle feeds on/off
    - Add custom feed button (Phase 2)
    
    // Storage
    - Clear RSS cache
    - Cache size display
}
```

#### Feed Priority List
```swift
struct FeedPriorityList: View {
    @State private var feeds: [RSSFeed]
    
    List {
        ForEach(feeds) { feed in
            HStack {
                Image(systemName: "line.3.horizontal")
                VStack(alignment: .leading) {
                    Text(feed.displayName)
                    Text(feed.updateFrequency)
                        .font(.caption)
                }
                Spacer()
                Toggle("", isOn: $feed.isEnabled)
            }
        }
        .onMove(perform: reorderFeeds)
    }
    .environment(\.editMode, .constant(.active))
}
```

### Phase 6: Mini Player Updates (1 day)

#### Show Context
- Display "Live News" instead of "Brief" for RSS episodes
- Show feed name as subtitle
- Same controls and gestures
- Plus button to add current RSS episode to Brief queue

### Phase 7: Player FM Integration (1 day)

#### URL Parser
```swift
extension RSSAudioService {
    func extractFeedFromPlayerFM(_ url: String) async -> String? {
        // Fetch HTML
        // Parse for RSS feed link
        // Return clean RSS URL
    }
    
    func addCustomFeed(urlString: String) async {
        var feedUrl = urlString
        
        // Check if Player FM URL
        if urlString.contains("player.fm") {
            feedUrl = await extractFeedFromPlayerFM(urlString) ?? urlString
        }
        
        // Validate and add feed
        // Save to Core Data
    }
}
```

## Key Implementation Notes

### Auto-Play Logic
```swift
func playLiveNewsQueue() {
    let episodes = getOrderedEpisodes()
        .filter { !$0.isListened && $0.isFresh }
        .prefix(20) // Reasonable queue size
    
    rssQueue = Array(episodes)
    if let first = rssQueue.first {
        playRSSEpisode(first)
    }
}
```

### Episode Ordering
1. Fresh hourly (< 2 hours old, unplayed)
2. Today's daily episodes (unplayed)
3. Partially played (newest first)
4. Older unplayed (up to retention limit)

### Progress Tracking
- Save position on: pause, skip, background, every 30 seconds
- Store as percentage (0.0-1.0) for consistency
- Clear progress when episode marked as listened

### Error Handling
- Skip failed feeds (grey out in UI)
- Show refresh button for manual retry
- Continue with next episode on playback error
- "No internet connection" message if all feeds fail

## Testing Checkpoints

### Phase 1-2: Data & Service
- [ ] RSS feeds parse correctly
- [ ] Episodes ordered by freshness
- [ ] Core Data saves/loads properly

### Phase 3-4: Audio & UI  
- [ ] Auto-play works on tab open
- [ ] Seamless audio switching
- [ ] Swipe gestures work correctly

### Phase 5-7: Polish
- [ ] Settings persist correctly
- [ ] Feed reordering saves
- [ ] Player FM URLs extract properly

## Future Enhancements
1. Custom feed addition UI
2. Episode search
3. Download management 
4. CarPlay support
5. Widgets

## Success Criteria
- Tap "Live News" tab → news starts playing (if enabled)
- Natural queue mixing between RSS and articles
- Consistent UI patterns with existing app
- Smooth audio transitions
- Easy to add new feeds in code