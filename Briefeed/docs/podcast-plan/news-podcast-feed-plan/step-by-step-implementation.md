# RSS Audio News Feature - Step-by-Step Implementation Plan

## Overview
This document provides a detailed, sequential implementation plan for adding RSS audio news functionality to Briefeed. Each step includes specific files to modify, code patterns to follow, and testing checkpoints.

## Pre-Implementation Setup

### Step 0: Project Preparation
1. Create feature branch: `feature/rss-audio-news`
2. Create directory structure:
   ```
   Briefeed/Features/RSS/
   Briefeed/Core/Models/RSS/
   Briefeed/Core/Services/RSS/
   ```

## Phase 1: Data Models (Day 1)

### Step 1.1: Create Core Data Entities
**File:** `Briefeed.xcdatamodeld`

1. Add `RSSFeed` entity:
   - `id`: String (unique identifier)
   - `url`: String 
   - `displayName`: String
   - `updateFrequency`: String (hourly/daily)
   - `priority`: Int16
   - `isEnabled`: Boolean
   - `lastFetchDate`: Date?
   - `createdDate`: Date
   - Relationship: `episodes` (to many RSSEpisode)

2. Add `RSSEpisode` entity:
   - `id`: String (guid or computed)
   - `feedId`: String
   - `title`: String
   - `audioUrl`: String
   - `pubDate`: Date
   - `duration`: Int32 (seconds)
   - `description`: String?
   - `isListened`: Boolean
   - `listenedDate`: Date?
   - `lastPosition`: Double (0-1 progress)
   - `downloadedFilePath`: String?
   - Relationship: `feed` (to one RSSFeed)

3. Update `Persistence.swift`:
   - Add Core Data stack initialization for new entities
   - Create migration policy if needed

**Testing Checkpoint:** Build project, verify Core Data model compiles

### Step 1.2: Create Swift Models
**File:** `Briefeed/Core/Models/RSS/RSSModels.swift`

```swift
import Foundation

enum RSSUpdateFrequency: String, CaseIterable {
    case hourly = "hourly"
    case daily = "daily"
    
    var displayName: String {
        switch self {
        case .hourly: return "Hourly"
        case .daily: return "Daily"
        }
    }
    
    var retentionHours: Int {
        switch self {
        case .hourly: return 24
        case .daily: return 168 // 7 days
        }
    }
}

struct RSSFeedConfiguration {
    let id: String
    let url: String
    let displayName: String
    let updateFrequency: RSSUpdateFrequency
    let defaultPriority: Int
}

// Episode states for UI
enum RSSEpisodeState {
    case fresh       // < 2 hours old
    case recent      // < 24 hours
    case partial     // Started but not finished
    case listened    // Completed
    case stale       // Ready for cleanup
}
```

**Testing Checkpoint:** Compile and verify models

## Phase 2: RSS Service Layer (Day 2)

### Step 2.1: Create RSS Parser
**File:** `Briefeed/Core/Services/RSS/RSSParser.swift`

```swift
import Foundation

class RSSParser: NSObject {
    // Implement XMLParserDelegate
    // Parse RSS 2.0 and Atom feeds
    // Extract: title, enclosure URL, pubDate, duration
    // Handle errors gracefully
}
```

Key methods:
- `parse(data: Data) async throws -> [ParsedRSSItem]`
- `extractAudioURL(from item: XMLElement) -> String?`
- `parseDuration(_ duration: String?) -> Int?`

### Step 2.2: Create RSS Audio Service
**File:** `Briefeed/Core/Services/RSS/RSSAudioService.swift`

```swift
@MainActor
class RSSAudioService: ObservableObject {
    static let shared = RSSAudioService()
    
    @Published private(set) var feeds: [RSSFeed] = []
    @Published private(set) var episodes: [RSSEpisode] = []
    @Published private(set) var isRefreshing = false
    
    private let parser = RSSParser()
    private let networkService = NetworkService.shared
    private let viewContext = PersistenceController.shared.container.viewContext
    
    // Core methods
    func initializeDefaultFeeds() async
    func refreshAllFeeds() async
    func refreshFeed(_ feed: RSSFeed) async throws
    func markEpisodeListened(_ episode: RSSEpisode)
    func updateEpisodeProgress(_ episode: RSSEpisode, progress: Double)
    func cleanupOldEpisodes()
    func getOrderedEpisodes() -> [RSSEpisode]
}
```

### Step 2.3: Extend Audio Service
**File:** `Briefeed/Core/Services/AudioService.swift`

Add RSS-specific functionality:
```swift
// New properties
@Published private(set) var isRSSMode = false
@Published private(set) var rssQueue: [RSSEpisode] = []
@Published private(set) var currentRSSEpisode: RSSEpisode?

// New methods
func playRSSEpisode(_ episode: RSSEpisode) async
func enterRSSMode()
func exitRSSMode()
func playNextRSSEpisode()
func addRSSEpisodeToMainQueue(_ episode: RSSEpisode)
```

**Testing Checkpoint:** 
- Test RSS parser with sample feeds
- Verify feed refresh logic
- Test audio playback of RSS episodes

## Phase 3: UI Implementation (Day 3-4)

### Step 3.1: Create RSS News View
**File:** `Briefeed/Features/RSS/RSSNewsView.swift`

```swift
struct RSSNewsView: View {
    @StateObject private var viewModel = RSSNewsViewModel()
    @StateObject private var audioService = AudioService.shared
    
    var body: some View {
        // Main container
        // Pull-to-refresh
        // Episode list
        // Loading states
        // Error handling
    }
}
```

Components to implement:
- `RSSEpisodeRow` - Similar to `QueuedArticleRow`
- `RSSNowPlayingCard` - Expanded current episode
- `RSSQueueHeader` - Shows queue stats

### Step 3.2: Create Episode Row Component
**File:** `Briefeed/Features/RSS/RSSEpisodeRow.swift`

Features:
- Swipe gestures (reuse from `QueuedArticleRow`)
- Visual states (fresh, playing, listened)
- Progress indicator for partial episodes
- Tap to expand details

### Step 3.3: Update Main Navigation
**File:** `Briefeed/ContentView.swift`

```swift
// Add third tab
TabView(selection: $selectedTab) {
    // ... existing tabs ...
    
    RSSNewsView()
        .tabItem {
            Label("News", systemImage: "dot.radiowaves.left.and.right")
        }
        .tag(2)
}
```

### Step 3.4: Auto-play Implementation
**File:** `Briefeed/Features/RSS/RSSNewsViewModel.swift`

```swift
@MainActor
class RSSNewsViewModel: ObservableObject {
    func onAppear() {
        Task {
            await refreshFeeds()
            await autoPlayIfEnabled()
        }
    }
    
    private func autoPlayIfEnabled() async {
        guard UserDefaultsManager.shared.rssAutoPlay else { return }
        guard let firstUnplayed = getFirstUnplayedEpisode() else { return }
        await audioService.playRSSEpisode(firstUnplayed)
    }
}
```

**Testing Checkpoint:**
- Navigate between tabs
- Verify auto-play behavior
- Test swipe gestures
- Check visual states

## Phase 4: Settings Integration (Day 5)

### Step 4.1: Update UserDefaults Manager
**File:** `Briefeed/Core/Utilities/UserDefaultsManager.swift`

Add new keys:
```swift
enum UserDefaultsKey: String {
    // ... existing ...
    case rssAutoPlay = "rssAutoPlay"
    case rssRefreshInterval = "rssRefreshInterval"
    case rssPlaybackSpeed = "rssPlaybackSpeed"
    case rssFeedPriorities = "rssFeedPriorities"
    case rssRetentionDays = "rssRetentionDays"
}
```

### Step 4.2: Create RSS Settings View
**File:** `Briefeed/Features/Settings/RSSSettingsView.swift`

Sections:
1. Playback Settings
   - Auto-play toggle
   - Playback speed
   - Auto-play next

2. Feed Management
   - Draggable priority list
   - Enable/disable feeds
   - Add custom feed (future)

3. Data Management
   - Refresh interval
   - Retention period
   - Clear RSS cache

### Step 4.3: Implement Feed Priority Reordering
**File:** `Briefeed/Features/Settings/RSSFeedPriorityList.swift`

```swift
struct RSSFeedPriorityList: View {
    @State private var feeds: [RSSFeed] = []
    
    var body: some View {
        List {
            ForEach(feeds) { feed in
                RSSFeedRow(feed: feed)
            }
            .onMove(perform: moveFeed)
        }
        .environment(\.editMode, .constant(.active))
    }
}
```

**Testing Checkpoint:**
- Test all settings changes
- Verify feed reordering saves
- Check settings persistence

## Phase 5: Queue Integration (Day 6)

### Step 5.1: Update Queue Service
**File:** `Briefeed/Core/Services/QueueService.swift`

Add support for RSS episodes:
```swift
func addRSSEpisode(_ episode: RSSEpisode) {
    // Convert to queue item
    // Add to main queue
    // Update UI state
}
```

### Step 5.2: Update Brief View
**File:** `Briefeed/Features/Brief/BriefView.swift`

- Show RSS episodes with special indicator
- Handle mixed playback (RSS + articles)
- Update queue statistics

### Step 5.3: Update Mini Player
**File:** `Briefeed/Features/Audio/MiniAudioPlayer.swift`

- Display RSS episode info
- Show feed name instead of category
- Add RSS-specific controls

**Testing Checkpoint:**
- Add RSS episodes to queue
- Test mixed queue playback
- Verify UI updates correctly

## Phase 6: Polish & Optimization (Day 7)

### Step 6.1: Background Refresh
- Implement background task for feed updates
- Add refresh on app foreground
- Optimize network requests

### Step 6.2: Performance Optimization
- Implement lazy loading for episode list
- Add image caching for podcast artwork
- Optimize Core Data queries

### Step 6.3: Error Handling
- Network error recovery
- Feed parsing error handling
- Playback error fallbacks

### Step 6.4: Accessibility
- VoiceOver labels
- Dynamic Type support
- Haptic feedback

## Testing Plan

### Unit Tests
1. RSS Parser tests with various feed formats
2. Episode ordering logic tests
3. Freshness calculation tests
4. Progress tracking tests

### Integration Tests
1. Feed refresh flow
2. Audio playback transitions
3. Queue integration
4. Settings persistence

### UI Tests
1. Tab navigation
2. Swipe gestures
3. Settings changes
4. Error states

## Deployment Checklist

- [ ] All tests passing
- [ ] No memory leaks in Instruments
- [ ] Settings migration for existing users
- [ ] Default feeds properly configured
- [ ] API keys not exposed
- [ ] Performance acceptable on older devices
- [ ] Accessibility audit complete
- [ ] TestFlight build tested

## Future Enhancements (Post-Launch)

1. Custom RSS feed addition
2. Episode search
3. Playback history view
4. Download for offline
5. CarPlay support
6. Widget for latest episodes
7. Siri Shortcuts integration
8. Episode transcripts

---

## Implementation Timeline

**Week 1:**
- Day 1: Data models
- Day 2: RSS service layer
- Day 3-4: Core UI
- Day 5: Settings

**Week 2:**
- Day 6: Queue integration
- Day 7: Polish and testing
- Day 8-9: Bug fixes
- Day 10: TestFlight release

This plan provides a structured approach to implementing the RSS audio news feature while maintaining the existing app architecture and user experience patterns.