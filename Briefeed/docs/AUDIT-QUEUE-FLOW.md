# Queue System Flow Audit

**Date:** 2025-12-30
**Status:** Complete

## Architecture Overview

The queue system uses a **single source of truth** pattern with `QueueCoordinator` at the center.

```
┌─────────────────────────────────────────────────────────────────┐
│                      QueueCoordinator                           │
│  (Single Source of Truth - Persisted to UserDefaults)          │
│                                                                  │
│  @Published queue: [QueueItem]                                  │
│  @Published currentIndex: Int                                   │
│  @Published currentPosition: TimeInterval                       │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Combine Subscriptions
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    UnifiedAudioPlayer                            │
│  (Playback Orchestration - Audio Generation + Playback)         │
│                                                                  │
│  - Subscribes to $queue, $currentIndex                          │
│  - Rebuilds local queue with Core Data hydration                │
│  - Manages SwiftAudioExService for actual playback              │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Combine Subscriptions
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                   AudioPlayerViewModelV2                         │
│  (UI Binding Layer - View Model for SwiftUI)                    │
│                                                                  │
│  - Subscribes to UnifiedAudioPlayer state                       │
│  - Provides formatted values for UI                             │
│  - Handles user interactions                                    │
└─────────────────────────────────────────────────────────────────┘
```

## Key Data Types

### QueueItem (QueueCoordinator.swift)
- **id**: `UUID` - Unique identifier
- **type**: `article` | `liveNews`
- **articleID**: `UUID?` - Reference to Core Data Article
- **episodeID**: `String?` - Reference to Core Data RSSEpisode
- **summaryState**: `pending` | `generating` | `ready` | `failed`
- **cachedAudioURL**: `URL?` - Generated audio file location
- **lastPosition**: `TimeInterval` - Resume position
- **errorMessage/retryCount**: Error tracking for Phase 2

### UnifiedQueueItem (UnifiedAudioPlayer.swift)
- **id**: `String` (from UUID.uuidString)
- **article/episode**: Hydrated Core Data objects
- **generationState**: In-memory generation tracking
- **cachedAudioURL**: Audio file URL

### EnhancedQueueItem (QueueModels.swift)
- UI display model with error state bridged from QueueCoordinator

## Flow 1: Queue Initialization (App Launch)

```
1. QueueCoordinator.init()
   └── loadPersistedState()
       ├── Decode PersistedQueueState from UserDefaults
       ├── Filter expired items
       └── Restore currentIndex, currentPosition

2. UnifiedAudioPlayer.init()
   └── setupQueueCoordinatorBindings()
       ├── Subscribe to $currentIndex
       └── Subscribe to $queue
           └── rebuildQueueFromCoordinator()
               ├── For each QueueItem:
               │   ├── Check articleCache/episodeCache
               │   └── If not cached: fetchArticle()/fetchEpisode() from Core Data
               └── Create UnifiedQueueItem with hydrated objects

3. AudioPlayerViewModelV2.init()
   └── setupBindings()
       └── Subscribe to UnifiedAudioPlayer state
```

## Flow 2: Playing an Item

```
1. User taps item in BriefView
   └── EnhancedQueueRow.playItem()
       └── audioPlayerViewModel.play(article:)

2. AudioPlayerViewModelV2.play(article:)
   ├── Check if already in queue (by article.id)
   │   ├── YES: play(at: existingIndex)
   │   └── NO: addToQueue(article, playNow: true)
   └── unifiedPlayer.play(at: index)

3. UnifiedAudioPlayer.play(at: index)
   ├── Exit Live News streaming mode if active
   ├── Set currentIndex locally
   ├── Sync to QueueCoordinator: setCurrentIndex(index)
   ├── Set pendingSeekTime from QueueCoordinator.currentPosition
   ├── Check generationState
   │   └── If not .ready: generateAudioForItem()
   ├── Play audio via SwiftAudioExService
   ├── Mark article/episode as listened
   └── Start pre-generation for next items
```

## Flow 3: Auto-Advance (Item Finished)

```
1. SwiftAudioExService finishes playback
   └── Delegate: audioDidFinishPlaying(successfully: true)
       └── Task { await playNext() }

2. UnifiedAudioPlayer.playNext()
   ├── Check isStreamingLiveNews
   │   ├── YES: playNextLiveNewsStreamItem()
   │   └── NO: play(at: currentIndex + 1)
   └── (same as Flow 2, step 3)
```

## Flow 4: Position Resumption

```
1. On play(at: index):
   └── pendingSeekTime = queueCoordinator.currentPosition

2. SwiftAudioExService starts playing
   └── Delegate: audioStateChanged(to: .playing)
       └── If pendingSeekTime > 0:
           ├── audioPlayer.seek(to: pendingSeekTime)
           ├── currentTime = pendingSeekTime
           └── pendingSeekTime = nil
```

## Flow 5: Position Persistence

```
1. Progress timer fires every 0.1s
   └── updateProgress()
       └── Every 5 seconds:
           └── queueCoordinator.updateCurrentPosition(currentTime)

2. QueueCoordinator.updateCurrentPosition()
   ├── Update queue[currentIndex].lastPosition
   └── schedulePositionPersist() (debounced to 10s)

3. On app background/termination:
   └── QueueCoordinator.saveStateNow() (immediate persist)
```

## Potential Issues Identified

### 1. ID Type Mismatch (Low Risk)
- **Location:** UnifiedQueueItem.id is `String`, QueueCoordinator uses `UUID`
- **Impact:** Requires `UUID(uuidString:)` conversion in multiple places
- **Status:** Working but fragile

### 2. Position Sync Gap (Medium Risk)
- **Location:** UnifiedAudioPlayer:1075, QueueCoordinator:211
- **Issue:** Progress syncs every 5s, persistence debounces to 10s
- **Impact:** Could lose up to 10-15s of position on crash
- **Mitigation:** `saveStateNow()` called on lifecycle events

### 3. Cache Never Cleared (Low Risk)
- **Location:** UnifiedAudioPlayer.articleCache/episodeCache
- **Issue:** Caches grow indefinitely during session
- **Impact:** Memory usage increases, but items are small
- **Recommendation:** Clear caches when queue is cleared

### 4. No Retry on Playback Failure (Fixed in Phase 2)
- **Location:** UnifiedAudioPlayer.play(at:) catch block
- **Status:** Now marks items failed with error for UI retry

### 5. Dual State Management for Streaming
- **Location:** UnifiedAudioPlayer has separate `liveNewsStreamQueue`
- **Issue:** Two parallel queue systems (Brief + Live News)
- **Status:** By design - Live News is intentionally temporary

## Live News Stream Ordering

### Feed Priority System
- `RSSFeed.priority` (Int16) controls play order
- FetchRequest sorts by `priority` → `displayName`
- Lower priority = plays first

### Drag-to-Reorder (Added 2025-12-30)
- **Location:** `LiveNewsViewV2.swift:106-108, 269-286`
- **UI:** EditButton in toolbar, `.onMove` on List
- **Logic:** `moveFeeds()` updates priority values after reorder
- **Persistence:** Saved to Core Data immediately

### Stream Order Flow
```
1. User taps "Play Live News"
2. playAllLiveNews() iterates feeds (sorted by priority)
3. For each feed: get latest unlistened episode
4. episodesToPlay array maintains feed priority order
5. playLiveNewsStream() plays in that order
```

## Verification Checklist

- [x] Queue persists across app launches
- [x] Current index preserved on restart
- [x] Position resumes at saved point
- [x] Items removed adjust currentIndex correctly
- [x] Expired items cleaned on load
- [x] Error states flow to UI for retry
- [x] Feed reorder persists via priority field
- [ ] Pre-generation doesn't block UI (needs runtime test)
- [ ] Live News streaming exits cleanly (needs runtime test)
