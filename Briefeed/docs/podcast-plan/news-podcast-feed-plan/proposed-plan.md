# RSS Audio News Feature Implementation Plan

## Overview
Add a dedicated RSS News tab that auto-plays audio news updates in chronological order. The tab should start playing immediately when selected, similar to dedicated news apps. Users can customize feed priority and add individual episodes to the main Brief queue.

## Core Features

### 1. Auto-Play News Mode
When you tap the RSS News tab:
- Immediately starts playing the freshest unplayed episode
- Shows a "news player" interface optimized for quick updates
- Continues through episodes chronologically (newest → oldest)

### 2. Two Playback Modes

#### "Live News" Mode (Default)
- Plays within the RSS tab itself
- Sequential playback through fresh episodes
- Separate from the main article queue
- Perfect for "morning news briefing" use case

#### "Add to Queue" Mode
- Long-press or swipe to add individual episodes to Brief queue
- Mix RSS audio with article summaries
- For curated listening sessions

### 3. Smart Ordering Logic

Priority Order:
1. 🔴 Fresh hourly updates (< 2 hours old, unplayed)
2. 🟠 Recent daily updates (today, unplayed) 
3. 🟡 Partially listened episodes (resume where left off)
4. ⚪ Older unplayed (auto-cleanup after 24-48 hours)

### 4. Visual Design

```
┌─────────────────────────┐
│ Feed │ Brief │ 📻 News  │
└─────────────────────────┘

📻 News Tab (Auto-playing):
┌─────────────────────────┐
│ ▶️ NOW PLAYING          │
│ NPR News Now           │
│ 2:00 PM Update • 5 min │
│ ████████░░░░ 3:21/5:00 │
├─────────────────────────┤
│ 🔵 UP NEXT             │
│ BBC Global News        │
│ Latest • 12 min        │
├─────────────────────────┤
│ 🔵 ABC News Update     │
│ 1:30 PM • 2 min       │
├─────────────────────────┤
│ ✓ CBS On The Hour      │
│ 1:00 PM • Listened     │
└─────────────────────────┘
```

## RSS Feed List

```swift
let DEFAULT_RSS_FEEDS = [
    RSSAudioFeed(
        id: "npr-news-now",
        url: "https://feeds.npr.org/500005/podcast.xml",
        displayName: "NPR News Now",
        updateFrequency: .hourly,
        priority: 1
    ),
    RSSAudioFeed(
        id: "bbc-global-news",
        url: "https://podcasts.files.bbci.co.uk/p02nq0gn.rss",
        displayName: "BBC Global News Podcast",
        updateFrequency: .daily, // Actually twice daily
        priority: 2
    ),
    RSSAudioFeed(
        id: "abc-news-update",
        url: "https://feeds.megaphone.fm/ESP9792844572",
        displayName: "ABC News Update",
        updateFrequency: .hourly, // Twice hourly
        priority: 3
    ),
    RSSAudioFeed(
        id: "cbs-on-the-hour",
        url: "https://rss.cbsradionewsfeed.com/254f5d63-d75a-44a2-b727-1ed9b51f03d4/90259cbd-993c-4ca1-afb4-aa23294369ac?feedFormat=all&itemFormat=latest",
        displayName: "CBS News: On The Hour",
        updateFrequency: .hourly,
        priority: 4
    ),
    RSSAudioFeed(
        id: "marketplace-morning",
        url: "https://feeds.publicradio.org/public_feeds/marketplace-morning-report/rss/rss",
        displayName: "Marketplace Morning Report",
        updateFrequency: .daily,
        priority: 5
    ),
    RSSAudioFeed(
        id: "marketplace-tech",
        url: "https://feeds.publicradio.org/public_feeds/marketplace-tech",
        displayName: "Marketplace Tech Report",
        updateFrequency: .daily,
        priority: 6
    ),
    RSSAudioFeed(
        id: "nyt-the-daily",
        url: "https://feeds.simplecast.com/Sl5CSM3S",
        displayName: "The New York Times - The Daily",
        updateFrequency: .daily,
        priority: 7
    ),
    RSSAudioFeed(
        id: "wsj-minute-briefing",
        url: "https://video-api.wsj.com/podcast/rss/wsj/minute-briefing",
        displayName: "WSJ Minute Briefing",
        updateFrequency: .daily, // Three times daily
        priority: 8
    ),
    RSSAudioFeed(
        id: "cbc-world-this-hour",
        url: "https://www.cbc.ca/podcasting/includes/hourlynews.xml",
        displayName: "CBC World This Hour",
        updateFrequency: .hourly,
        priority: 9
    )
]
```

## Implementation Steps

### Phase 1: Core Data Models
Create new Core Data entities and models:
- `RSSFeed` entity with priority, update frequency, and enabled status
- `RSSEpisode` entity with playback tracking
- Add relationships and migration

### Phase 2: RSS Service
Create `RSSAudioService` following existing service patterns:
- Parse RSS feeds using XMLParser
- Track episode listen status and progress
- Implement freshness logic and auto-cleanup
- Handle feed priority ordering

### Phase 3: Audio Integration
Extend `AudioService`:
- Add RSS playback mode separate from main queue
- Track RSS playlist and current episode
- Add methods for RSS-specific playback control
- Handle auto-play next functionality

### Phase 4: UI Components
Create RSS News tab:
- `RSSNewsView` as third tab
- Episode list with visual states (NOW PLAYING, UP NEXT, etc.)
- Swipe gestures matching existing `QueuedArticleRow` patterns
- Auto-play on tab selection

### Phase 5: Settings Integration
Add RSS configuration:
- Draggable feed priority list (especially for hourly feeds)
- Auto-play and refresh settings
- Retention period configuration
- Separate playback speed for RSS

### Phase 6: Queue Integration
- Allow adding RSS episodes to Brief queue
- Show RSS episodes with special indicator in queue
- Handle mixed playback (RSS + article summaries)

## Key Features

### Instant Playback
- Tab selection triggers immediate playback
- No need to tap play - news just starts
- Visual indicator shows "LIVE" or "AUTO-PLAYING"

### Smart Resume
- Remember position in longer podcasts
- Skip fully-listened episodes automatically
- Option to "Mark all as listened" to reset

### Freshness Indicators
- 🔴 "LIVE" badge for updates < 1 hour old
- Time-based fading (older = lower opacity)
- Auto-remove stale content based on feed type

### Quick Actions
- Swipe right → Add to Brief queue
- Swipe left → Mark as listened/skip
- Tap → Expand for description/controls

## Technical Notes

### Episode Identification
- Use RSS guid if available
- Fallback to hash of: feedId + pubDate + title
- Ensures uniqueness even with repeated titles

### Freshness Logic
```swift
func isEpisodeFresh(_ episode: RSSEpisode) -> Bool {
    let age = Date().timeIntervalSince(episode.pubDate)
    
    switch episode.updateFrequency {
    case .hourly:
        return age < 2 * 60 * 60 // 2 hours
    case .daily:
        return age < 24 * 60 * 60 // 24 hours
    default:
        return true
    }
}
```

### Auto-cleanup Rules
- Hourly episodes: Remove after 24 hours
- Daily episodes: Remove after 7 days
- Keep partially listened episodes regardless of age

### Background Refresh
- Check for new episodes when app becomes active
- Pull-to-refresh gesture support
- Configurable auto-refresh interval
- Only fetch if last refresh > 5 minutes ago