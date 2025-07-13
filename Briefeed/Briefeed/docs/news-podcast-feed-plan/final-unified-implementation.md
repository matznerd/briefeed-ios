# Final Implementation Plan - Unified Queue with Live News

## Overview
Live News (RSS episodes) flows directly into the existing Brief queue. With auto-play enabled, fresh episodes populate the queue automatically and expire after a set time. Users can filter the Brief view to see just Live News, just articles, or a mix.

## Core Design Principles
1. **One Queue**: Everything goes through Brief - no separate contexts
2. **Auto-Population**: Fresh RSS episodes add themselves when auto-play is on
3. **Smart Expiration**: Hourly content expires after 24h, daily after 7d
4. **Flexible Filtering**: View all, Live News only, or by source
5. **Seamless Playback**: RSS audio and TTS articles play in sequence

## Implementation Phases

### Phase 1: Extend Queue Infrastructure (2 days)

#### Update Queue Models
```swift
// Extend existing queue item
extension QueuedItem {
    // New properties
    var source: QueueItemSource
    var expiresAt: Date?
    var audioUrl: URL? // For RSS episodes
    
    enum QueueItemSource {
        case rss(feedId: String, feedName: String)
        case article(source: String) // reddit, etc.
        
        var displayName: String {
            switch self {
            case .rss(_, let name): return name
            case .article(let source): return source
            }
        }
        
        var isLiveNews: Bool {
            switch self {
            case .rss: return true
            case .article: return false
            }
        }
    }
}
```

#### Update QueueService
```swift
extension QueueService {
    // New methods
    func addRSSEpisode(_ episode: RSSEpisode) {
        let queueItem = QueuedItem(
            articleID: UUID(), // Temporary ID for RSS
            source: .rss(feedId: episode.feedId, feedName: episode.feedName),
            expiresAt: calculateExpiration(episode),
            audioUrl: episode.audioUrl
        )
        addToQueue(queueItem)
    }
    
    func autoPopulateWithLiveNews() {
        guard UserDefaultsManager.shared.autoPlayLiveNewsOnOpen else { return }
        
        // Get fresh episodes
        let episodes = RSSAudioService.shared.getFreshEpisodes()
        for episode in episodes.prefix(10) {
            addRSSEpisode(episode)
        }
        
        // Start playing if idle
        if !AudioService.shared.isPlaying {
            AudioService.shared.playNext()
        }
    }
    
    func cleanupExpiredItems() {
        let now = Date()
        queuedItems.removeAll { item in
            guard let expires = item.expiresAt else { return false }
            return now > expires && !isCurrentlyPlaying(item)
        }
    }
}
```

### Phase 2: RSS Service Layer (2 days)

#### Create RSS Models in Core Data
```swift
// RSSFeed entity
- id: String
- url: String
- displayName: String
- updateFrequency: String
- priority: Int16
- isEnabled: Bool
- lastFetchDate: Date?

// RSSEpisode entity  
- id: String
- feedId: String
- title: String
- audioUrl: String
- pubDate: Date
- duration: Int32?
- hasBeenQueued: Bool // Prevent re-adding
```

#### RSSAudioService
```swift
@MainActor
class RSSAudioService: ObservableObject {
    static let shared = RSSAudioService()
    
    private let defaultFeeds = [
        ("npr-news-now", "https://feeds.npr.org/500005/podcast.xml", "NPR News Now", "hourly"),
        ("bbc-global-news", "https://podcasts.files.bbci.co.uk/p02nq0gn.rss", "BBC Global News", "daily"),
        // ... rest of feeds
    ]
    
    func initializeDefaultFeeds() {
        // Create Core Data entries for default feeds
    }
    
    func refreshAllFeeds() async {
        // Fetch and parse all enabled feeds
        // Mark fresh episodes for queue
    }
    
    func getFreshEpisodes() -> [RSSEpisode] {
        // Return unqueued episodes sorted by priority and date
    }
    
    private func calculateExpiration(for episode: RSSEpisode) -> Date {
        let hours = episode.updateFrequency == "hourly" ? 24 : 168
        return Date().addingTimeInterval(TimeInterval(hours * 3600))
    }
}
```

### Phase 3: Update Brief UI (2 days)

#### Add Filtering to BriefView
```swift
struct BriefView: View {
    @State private var currentFilter: QueueFilter = .all
    
    enum QueueFilter: String, CaseIterable {
        case all = "All"
        case liveNews = "Live News"
        case articles = "Articles"
        
        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .liveNews: return "dot.radiowaves.left.and.right"
            case .articles: return "doc.text"
            }
        }
    }
    
    var filteredQueue: [QueuedItem] {
        switch currentFilter {
        case .all:
            return queueService.queuedItems
        case .liveNews:
            return queueService.queuedItems.filter { $0.source.isLiveNews }
        case .articles:
            return queueService.queuedItems.filter { !$0.source.isLiveNews }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Filter Picker
                Picker("Filter", selection: $currentFilter) {
                    ForEach(QueueFilter.allCases, id: \.self) { filter in
                        Label(filter.rawValue, systemImage: filter.icon)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Queue List
                List {
                    ForEach(filteredQueue) { item in
                        QueuedItemRow(item: item)
                    }
                }
            }
            .navigationTitle("Brief")
        }
    }
}
```

#### Update QueuedArticleRow for RSS
```swift
struct QueuedItemRow: View {
    let item: QueuedItem
    
    var body: some View {
        HStack {
            // Source indicator
            if item.source.isLiveNews {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundColor(.red)
            }
            
            VStack(alignment: .leading) {
                Text(item.title)
                HStack {
                    Text(item.source.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let duration = item.duration {
                        Text("• \(formatDuration(duration))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Expiration indicator
            if let expires = item.expiresAt {
                TimeRemainingView(until: expires)
            }
        }
        .swipeActions { /* existing swipe actions */ }
    }
}
```

### Phase 4: Audio Service Updates (1 day)

#### Handle RSS Audio URLs
```swift
extension AudioService {
    func playQueueItem(_ item: QueuedItem) async {
        if let audioUrl = item.audioUrl {
            // Play RSS episode
            await playAudioFromURL(audioUrl)
        } else if let article = fetchArticle(item.articleID) {
            // Generate and play TTS
            await generateAndPlayTTS(article)
        }
    }
    
    private func playAudioFromURL(_ url: URL) async {
        // Download/stream and play
        // Reuse existing audio player infrastructure
    }
}
```

### Phase 5: Add Live News Tab (1 day)

#### Simple RSS Feed Management View
```swift
struct LiveNewsView: View {
    @StateObject private var rssService = RSSAudioService.shared
    @State private var isRefreshing = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Fresh Episodes") {
                    ForEach(rssService.getFreshEpisodes()) { episode in
                        RSSEpisodeRow(episode: episode)
                    }
                }
                
                Section("Feeds") {
                    ForEach(rssService.feeds) { feed in
                        RSSFeedRow(feed: feed)
                    }
                }
            }
            .navigationTitle("Live News")
            .refreshable {
                await rssService.refreshAllFeeds()
            }
        }
    }
}
```

### Phase 6: Settings Integration (1 day)

#### New Settings
```swift
// In UserDefaultsManager
@Published var autoPlayLiveNewsOnOpen: Bool = false
@Published var defaultBriefFilter: String = "all"
@Published var liveNewsRetentionHours: Int = 24

// In SettingsView
Section("Live News") {
    Toggle("Auto-play on app open", isOn: $userDefaults.autoPlayLiveNewsOnOpen)
    
    Picker("Default Brief filter", selection: $userDefaults.defaultBriefFilter) {
        Text("All").tag("all")
        Text("Live News").tag("liveNews")
        Text("Articles").tag("articles")
    }
    
    Picker("Keep unplayed episodes", selection: $userDefaults.liveNewsRetentionHours) {
        Text("24 hours").tag(24)
        Text("48 hours").tag(48)
        Text("7 days").tag(168)
    }
}
```

### Phase 7: App Launch Integration (1 day)

#### Update BriefeedApp
```swift
struct BriefeedApp: App {
    init() {
        // Existing initialization...
        
        // Initialize RSS feeds
        Task {
            await RSSAudioService.shared.initializeDefaultFeeds()
            
            // Auto-populate if enabled
            if UserDefaultsManager.shared.autoPlayLiveNewsOnOpen {
                await RSSAudioService.shared.refreshAllFeeds()
                QueueService.shared.autoPopulateWithLiveNews()
            }
        }
        
        // Schedule periodic cleanup
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            QueueService.shared.cleanupExpiredItems()
        }
    }
}
```

## Key Features Summary

1. **Unified Queue**: RSS episodes are just queue items with expiration
2. **Auto-Play**: Optional setting to start news on app open
3. **Smart Filtering**: View all, Live News, or articles
4. **Auto-Expiration**: Old episodes remove themselves
5. **Same UX**: Existing swipe gestures work everywhere
6. **Source Attribution**: Shows NPR, BBC, Reddit, etc.
7. **Mixed Playback**: Seamless audio switching

## Testing Milestones

- [ ] RSS feeds parse correctly
- [ ] Episodes add to Brief queue
- [ ] Auto-play starts on app open
- [ ] Filters work properly
- [ ] Episodes expire on schedule
- [ ] Audio transitions smoothly
- [ ] Swipe gestures consistent

## Future Enhancements
1. Add custom RSS feeds via Player.fm
2. Per-source volume normalization
3. Smart feed priorities based on usage
4. Episode search across all sources

This approach integrates Live News seamlessly into your existing Brief infrastructure while maintaining the simplicity users expect!