# Queue System Audit - Briefeed iOS App

**Date:** December 16, 2025
**Auditor:** AI Code Analysis
**Status:** CRITICAL - Multiple architectural issues identified

---

## Executive Summary

The Briefeed iOS app's queue management system is **critically fragmented** with **at least 4 different queue representations** operating simultaneously without proper synchronization. This creates a high risk of state inconsistency, lost items, duplicates, and user-facing bugs.

### Critical Findings:
1. **4 Independent Queue Representations** with unclear synchronization
2. **Dual persistence systems** (legacy + enhanced) causing data duplication
3. **Race conditions** in queue state updates
4. **Broken conversion flow** between queue types
5. **Memory leaks** from incomplete cleanup of pre-generation tasks

---

## Architecture Overview

### The Four Queue Representations

```
┌─────────────────────────────────────────────────────────────────┐
│                        QUEUE FRAGMENTATION                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────┐        ┌─────────────────────────┐   │
│  │  QueueServiceV2      │        │  UnifiedAudioPlayer     │   │
│  ├──────────────────────┤        ├─────────────────────────┤   │
│  │ - queuedItems[]      │        │ - queue[]               │   │
│  │ - enhancedQueue[]    │        │   (UnifiedQueueItem[])  │   │
│  │                      │        │ - currentIndex          │   │
│  │ TWO QUEUES!          │        │                         │   │
│  └──────────────────────┘        └─────────────────────────┘   │
│           ↓                                    ↓                 │
│           ↓                                    ↓                 │
│  ┌──────────────────────┐        ┌─────────────────────────┐   │
│  │  AudioPlayerVM V2    │        │  BriefViewModel         │   │
│  ├──────────────────────┤        ├─────────────────────────┤   │
│  │ - queueItems[]       │        │ - queuedArticles[]      │   │
│  │   (UnifiedQueueItem) │        │   (Article[])           │   │
│  │ - currentQueueIndex  │        │                         │   │
│  └──────────────────────┘        └─────────────────────────┘   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Queue Type 1: QueueServiceV2.queuedItems
**Location:** `Core/Services/QueueServiceV2.swift:27-31`
**Type:** `[QueuedItem]` (legacy structure)
**Purpose:** Originally for article-only queue
**Persistence:** UserDefaults key "AudioQueueItems"

```swift
struct QueuedItem: Codable {
    let articleID: UUID
    let addedDate: Date
}
```

**Issues:**
- Only supports articles (no RSS episodes)
- Maintained in parallel with enhancedQueue
- Updated on every add/remove operation even though not used
- Lines 123-127: Unsafe index-based synchronization with enhancedQueue

### Queue Type 2: QueueServiceV2.enhancedQueue
**Location:** `Core/Services/QueueServiceV2.swift:33-37`
**Type:** `[EnhancedQueueItem]`
**Purpose:** Mixed queue (articles + RSS episodes)
**Persistence:** UserDefaults key "EnhancedAudioQueueItems"

```swift
struct EnhancedQueueItem: Codable {
    let id: UUID
    let title: String
    let source: QueueItemSource
    let articleID: UUID?
    let audioUrl: URL?
    // ... more fields
}
```

**Issues:**
- Duplicate state with queuedItems
- No atomic updates with queuedItems
- Audio URL updates require full item recreation (lines 260-275)
- Background generation modifies queue without synchronization

### Queue Type 3: UnifiedAudioPlayer.queue
**Location:** `Core/Services/Audio/UnifiedAudioPlayer.swift:97`
**Type:** `[UnifiedQueueItem]` (MainActor-bound ObservableObject)
**Purpose:** Active playback queue with generation state
**Persistence:** None (transient)

```swift
@MainActor
class UnifiedQueueItem: ObservableObject {
    let id: String
    let type: QueueItemType
    @Published var generationState: GenerationState
    @Published var cachedAudioURL: URL?
    let article: Article?
    let episode: RSSEpisode?
}
```

**Issues:**
- No persistence mechanism
- Lost on app restart
- MainActor isolation prevents background updates
- Holds strong references to Core Data objects (Article/RSSEpisode)

### Queue Type 4: AudioPlayerViewModelV2.queueItems
**Location:** `Core/ViewModels/AudioPlayerViewModelV2.swift:37`
**Type:** `[UnifiedQueueItem]` (bound from UnifiedAudioPlayer)
**Purpose:** UI binding layer
**Persistence:** Attempted via saveQueueState() but incomplete

```swift
@Published private(set) var queueItems: [UnifiedQueueItem] = []
```

**Issues:**
- Lines 373-393: Incomplete saveQueueState() implementation
- Only saves metadata, not full queue state
- No restoration logic for UnifiedQueueItems
- Duplicate method definition (lines 373 and 466)

---

## Data Flow Analysis

### How Articles Are Queued

```
User Action (Save Article)
    ↓
BriefViewModel.queuedArticles (Core Data fetch)
    ↓
BriefView+Filtering.swift:89-94 (onAppear)
    ↓
AudioPlayerViewModelV2.playQueue(articles:)
    ↓
UnifiedAudioPlayer.loadQueue(from: [Article])
    ↓
Create UnifiedQueueItems, trigger pre-generation
    ⚠️ QueueServiceV2 is NOT updated!
```

**Critical Gap:** When articles are played from BriefView, QueueServiceV2 is bypassed entirely!

### How RSS Episodes Are Queued

```
User Action (Play Live News)
    ↓
AudioPlayerViewModelV2.playLiveNews(from: [RSSFeed])
    ↓
Fetch latest unlistened episodes per feed
    ↓
AudioPlayerViewModelV2.playQueue(episodes:)
    ↓
UnifiedAudioPlayer.loadQueue(from: [RSSEpisode])
    ↓
Mark episodes as ready (audioURL pre-exists)
    ⚠️ QueueServiceV2.enhancedQueue is NOT updated!
```

**Critical Gap:** RSS episodes bypass QueueServiceV2 entirely!

### How Items Are Added to Queue

**Path 1: Via UnifiedAudioPlayer.addToQueue()**
```swift
// Line 188-205
func addToQueue(_ item: Any) async {
    if let article = item as? Article {
        let queueItem = UnifiedQueueItem(article: article)
        queue.append(queueItem)
        // Pre-generate if within first 3 items
    } else if let episode = item as? RSSEpisode {
        let queueItem = UnifiedQueueItem(episode: episode)
        queueItem.generationState = .ready
        queue.append(queueItem)
    }
}
```

**Issue:** Doesn't update QueueServiceV2 at all!

**Path 2: Via QueueServiceV2.addToQueue()**
```swift
// Article: Lines 73-98
func addToQueue(article: Article) async {
    let item = QueuedItem(articleID: ...)
    queuedItems.insert(item, at: 0)
    await saveQueue()

    let enhancedItem = EnhancedQueueItem(...)
    enhancedQueue.insert(enhancedItem, at: 0)
    await saveEnhancedQueue()
}

// Episode: Lines 100-115
func addToQueue(episode: RSSEpisode) async {
    let enhancedItem = EnhancedQueueItem(...)
    enhancedQueue.insert(enhancedItem, at: 0)
    await saveEnhancedQueue()
    // Note: queuedItems is NOT updated for episodes!
}
```

**Issue:** QueueServiceV2 is updated but UnifiedAudioPlayer's queue is NOT updated!

---

## Queue Persistence Analysis

### Persistence Layer 1: QueueServiceV2
**Keys:**
- `AudioQueueItems` → legacy article queue
- `EnhancedAudioQueueItems` → mixed queue

**Save Points:**
- Line 198: `saveQueue()` - legacy queue
- Line 204: `saveEnhancedQueue()` - enhanced queue
- BriefeedApp.swift:84 - on app resign active

**Load Points:**
- Line 184-195: `loadQueue()` - loads both queues
- QueueServiceV2.swift:62-68: `initialize()` async

**Issues:**
- Saves two queues separately (can get out of sync)
- No atomic transaction between saves
- Legacy queue overwritten by enhanced operations

### Persistence Layer 2: AudioPlayerViewModelV2
**Key:** `audioQueueState` (attempted)

**Save Points:**
- Line 391: UserDefaults.set (but incomplete implementation)

**Load Points:**
- None! No restoration logic exists

**Issues:**
- saveQueueState() defined twice (lines 372-393, 466-470)
- Only saves minimal metadata ([String: Any] dictionary)
- Cannot reconstruct UnifiedQueueItems from metadata
- No tie to QueueServiceV2 persistence

### Persistence Layer 3: BriefViewModel
**Storage:** Core Data (Article.isSaved)

**Load Points:**
- Line 50-60: Fetches saved articles as queue

**Issues:**
- Separate from audio queue persistence
- Lines 89-94 in BriefView+Filtering: Loads to audio player but no bidirectional sync
- Clear queue (line 98-101) doesn't sync with audio player

---

## Queue Ordering and Prioritization

### Insertion Strategy: NEWEST FIRST (Lines 79, 96, 113)

```swift
// All queues insert at position 0
queuedItems.insert(item, at: 0)
enhancedQueue.insert(enhancedItem, at: 0)
```

**Rationale:** "Funnel concept" - newest items at top (comments on lines 79, 95, 112)

### Sort Order in BriefViewModel
```swift
// Line 53
fetchRequest.sortDescriptors = [
    NSSortDescriptor(keyPath: \Article.savedAt, ascending: false)
]
```

**Alignment:** ✅ Consistent - newest first

### Reordering Support
- QueueServiceV2.reorderQueue(): Lines 130-137
- AudioPlayerViewModelV2.reorderQueue(): Lines 407-429
- BriefView moveItems(): Line 284-286 (TODO comment!)

**Critical Issue:** Reordering in view model creates new queue but doesn't update QueueServiceV2!

```swift
// Line 426-428 - This discards state!
await unifiedPlayer.loadMixedQueue(items: newQueue.compactMap { item in
    item.article ?? item.episode
})
```

---

## Queue Synchronization Issues

### Issue 1: Add Article - Path Divergence

**Scenario:** User saves article in Feed view

```
Article.isSaved = true
    ↓
BriefView detects change (line 37-43)
    ↓
loadQueuedArticles() updates BriefViewModel.queuedArticles
    ↓
⚠️ AudioPlayerViewModelV2.queueItems NOT updated
⚠️ QueueServiceV2 NOT updated
```

**Result:** Article appears in Brief tab but not in audio queue!

### Issue 2: Play Queue - State Overwrite

**Scenario:** User taps "Play All" in Brief tab

```
BriefView+Filtering.swift:56
    ↓
AudioPlayerViewModelV2.playQueue(articles: viewModel.queuedArticles)
    ↓
UnifiedAudioPlayer.loadQueue(from: articles) [Line 150]
    ↓
queue = articles.map { UnifiedQueueItem(article: $0) }
    ↓
⚠️ COMPLETELY REPLACES existing queue
⚠️ Loses any RSS episodes that were in queue
⚠️ QueueServiceV2.enhancedQueue NOT updated
```

**Result:** Mixed queue items lost!

### Issue 3: Remove from Queue - Dual State

**Scenario:** User swipes to delete item from Brief

```
BriefView+Filtering.swift:288-304
    ↓
Finds item in audioPlayerViewModel.queueItems by ID matching
    ↓
audioPlayerViewModel.removeFromQueue(at: index)
    ↓
UnifiedAudioPlayer.removeFromQueue(at: index) [Line 208-220]
    ↓
⚠️ QueueServiceV2 NOT updated!
    ↓
viewModel.removeFromQueue(article) [Line 301-304]
    ↓
BriefViewModel toggles isSaved [Line 84]
    ↓
⚠️ Two separate removals with no transaction
```

**Result:** Queue state fragmented across systems!

### Issue 4: Background Audio Generation - Race Condition

**Scenario:** QueueServiceV2 generates audio in background

```
QueueServiceV2.processNextItemForAudioGeneration() [Line 227]
    ↓
Background Task (Line 215-224)
    ↓
Iterates enhancedQueue [Line 228]
    ↓
generateAudioForArticle() [Line 245-280]
    ↓
Updates enhancedQueue[index] with new audioUrl [Line 273]
    ↓
⚠️ NOT on MainActor
⚠️ UnifiedAudioPlayer.queue NOT updated
⚠️ UI shows stale generation state
```

**Result:** Generated audio not reflected in player!

### Issue 5: App Launch - Partial Restoration

**Scenario:** App launched after termination

```
BriefeedApp.init():40-50
    ↓
Task { await QueueServiceV2.shared.initialize() }
    ↓
Loads queuedItems and enhancedQueue from UserDefaults
    ↓
⚠️ UnifiedAudioPlayer.queue remains empty
⚠️ AudioPlayerViewModelV2 has no restoration logic
    ↓
User sees empty queue in UI
    ↓
BriefView.onAppear:86-95
    ↓
Loads queuedArticles from Core Data
    ↓
IF queue empty: playQueue(articles) then pause
    ↓
⚠️ Creates NEW queue, doesn't restore persisted state
⚠️ Loses queue position
⚠️ Loses RSS episodes
```

**Result:** Queue state lost on restart!

---

## Mixed Queue Handling

### Design Intent
EnhancedQueueItem is designed to handle both articles and RSS episodes:

```swift
enum QueueItemSource {
    case article(source: String)
    case rss(feedId: String, feedName: String)
}
```

### Implementation Reality

**Article Path:**
1. Article saved → Core Data
2. BriefView loads saved articles
3. PlayQueue creates UnifiedQueueItems
4. ❌ Never touches QueueServiceV2.enhancedQueue

**RSS Episode Path:**
1. User plays Live News
2. Fetches episodes from Core Data
3. Creates UnifiedQueueItems with audioURL
4. ❌ Never touches QueueServiceV2.enhancedQueue

**Mixed Queue Path (BROKEN):**
```swift
// UnifiedAudioPlayer.swift:173-185
func loadMixedQueue(items: [Any]) async {
    queue = items.compactMap { item in
        if let article = item as? Article {
            return UnifiedQueueItem(article: article)
        } else if let episode = item as? RSSEpisode {
            return UnifiedQueueItem(episode: episode)
        }
        return nil
    }
    currentIndex = -1
    await preGenerateNextItems()
}
```

**Critical Flaw:** No persistence! Mixed queue lost on app termination.

### Conversion Between Formats

**UnifiedQueueItem → EnhancedQueueItem:**
```swift
// EnhancedQueueItem+Extensions.swift:15-46
func toEnhancedQueueItem() -> EnhancedQueueItem {
    // Creates NEW item with new Date()
    // ⚠️ Loses original addedDate
    // ⚠️ No expiration preserved
    // ⚠️ isListened/lastPosition always reset
}
```

**EnhancedQueueItem → UnifiedQueueItem:**
❌ NO CONVERSION EXISTS!

**Result:** One-way conversion that loses data!

---

## Pre-Generation System

### Implementation: UnifiedAudioPlayer

**Strategy:** Generate audio for current + next 2 items (lines 567-588)

```swift
private func preGenerateNextItems() async {
    preGenerationTask?.cancel()

    preGenerationTask = Task {
        let indicesToGenerate = [
            currentIndex,
            currentIndex + 1,
            currentIndex + 2
        ].filter { $0 >= 0 && $0 < queue.count }

        for index in indicesToGenerate {
            guard !Task.isCancelled else { break }
            let item = queue[index]
            if item.generationState == .pending {
                await generateAudioForItem(item)
            }
        }
    }
}
```

**Trigger Points:**
- Line 155: After loading article queue
- Line 256: After starting playback
- Called from play(at:) method

**Issues:**
1. preGenerationTask never cleaned up on queue change
2. Task reference held in UnifiedAudioPlayer (line 115)
3. Cancellation on line 569 but task could be mid-generation
4. No cleanup on removeFromQueue (line 208-220)

### Implementation: QueueServiceV2 (Duplicate!)

**Strategy:** Background task generates for ALL items (lines 212-243)

```swift
private func startBackgroundAudioGeneration() {
    audioGenerationTask?.cancel()

    audioGenerationTask = Task.detached(priority: .background) {
        while !Task.isCancelled {
            await self.processNextItemForAudioGeneration()
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 sec
        }
    }
}
```

**Critical Issues:**

1. **DUPLICATE GENERATION:** Two systems generate audio independently!
2. **Race Condition:** QueueServiceV2 updates enhancedQueue, UnifiedAudioPlayer unaware
3. **Infinite Loop:** Line 218 never exits (while !Task.isCancelled)
4. **Memory Leak:** Task not stored properly, deinit on line 290 may not cancel
5. **fetchArticle() returns nil** (line 282-286): Placeholder implementation!

```swift
private func fetchArticle(with id: UUID) async -> Article? {
    // Fetch article from Core Data
    // This would need to be implemented with proper Core Data context
    return nil // Placeholder
}
```

**Result:** QueueServiceV2 audio generation NEVER WORKS!

---

## Critical Bugs Identified

### Bug 1: Queue State Lost on App Restart
**Severity:** HIGH
**Location:** UnifiedAudioPlayer has no persistence

**Reproduction:**
1. Add 5 articles to queue
2. Add 2 RSS episodes
3. Play 2 items
4. Force quit app
5. Relaunch app

**Expected:** Queue restored with 5 items remaining at position 2
**Actual:** Queue empty or only articles restored (episodes lost)

**Root Cause:** UnifiedAudioPlayer.queue is transient, QueueServiceV2 not synced

### Bug 2: Mixed Queue Items Duplicated
**Severity:** MEDIUM
**Location:** Multiple code paths add to queue

**Reproduction:**
1. Save article (adds to Brief)
2. BriefView.onAppear loads queue
3. Add same article via play button

**Expected:** Single instance in queue
**Actual:** Article appears twice

**Root Cause:** No deduplication check in addToQueue

### Bug 3: Reordering Destroys Queue State
**Severity:** HIGH
**Location:** AudioPlayerViewModelV2.reorderQueue (line 407-429)

**Reproduction:**
1. Queue 3 articles + 2 RSS episodes
2. Article 1 generating audio
3. Drag item to reorder
4. Check generation state

**Expected:** Generation continues, state preserved
**Actual:** Generation reset, all items back to pending

**Root Cause:** loadMixedQueue creates fresh UnifiedQueueItems, loses state

```swift
// Line 426-428
await unifiedPlayer.loadMixedQueue(items: newQueue.compactMap { item in
    item.article ?? item.episode
})
```

### Bug 4: Remove from Queue Leaves Orphans
**Severity:** MEDIUM
**Location:** BriefView+Filtering.swift:288-304

**Reproduction:**
1. Queue article via Brief tab
2. Remove from queue via swipe
3. Check QueueServiceV2.enhancedQueue
4. Check UserDefaults persistence

**Expected:** Item removed from all queues
**Actual:** Item removed from UnifiedAudioPlayer but remains in QueueServiceV2.enhancedQueue

**Root Cause:** removeItem() only updates audioPlayerViewModel, not QueueServiceV2

### Bug 5: Background Generation Never Completes
**Severity:** HIGH
**Location:** QueueServiceV2.processNextItemForAudioGeneration

**Reproduction:**
1. Add article to queue
2. Wait for background generation
3. Check QueueServiceV2.enhancedQueue[0].audioUrl

**Expected:** audioUrl populated after generation
**Actual:** audioUrl remains nil forever

**Root Cause:** fetchArticle() returns nil (line 285), generation never runs

### Bug 6: Clear Queue Partial Failure
**Severity:** MEDIUM
**Location:** BriefView+Filtering.swift:320-324

**Reproduction:**
1. Queue 3 articles + 2 episodes
2. Tap "Clear Queue" in Brief tab
3. Check all queue representations

**Expected:** All queues cleared
**Actual:**
- UnifiedAudioPlayer.queue: ✅ Cleared
- BriefViewModel.queuedArticles: ✅ Cleared
- QueueServiceV2.queuedItems: ❓ Unknown
- QueueServiceV2.enhancedQueue: ❓ Unknown

**Root Cause:** clearQueue() doesn't coordinate with QueueServiceV2

### Bug 7: Play Live News Overwrites Article Queue
**Severity:** HIGH
**Location:** AudioPlayerViewModelV2.playLiveNews (line 482-521)

**Reproduction:**
1. Queue 5 articles
2. Articles 1-2 generated, playing article 1
3. Tap "Play Live News"
4. Check queue

**Expected:** Episodes added to queue OR prompt user
**Actual:** Entire queue replaced with episodes, articles lost

**Root Cause:** playQueue(episodes:) calls loadQueue which replaces queue (line 150-156)

---

## Synchronization Gaps

### Gap 1: QueueServiceV2 ↔ UnifiedAudioPlayer
**Status:** ❌ NO SYNCHRONIZATION

- QueueServiceV2 maintains enhancedQueue
- UnifiedAudioPlayer maintains separate queue
- No delegate or notification system
- QueueServiceDelegate protocol exists (line 296-300) but never implemented
- Delegate weak reference on line 48 never set

### Gap 2: UnifiedAudioPlayer ↔ AudioPlayerViewModelV2
**Status:** ✅ ONE-WAY BINDING (Player → ViewModel)

```swift
// AudioPlayerViewModelV2.swift:68-90
unifiedPlayer.$queue.assign(to: &$queueItems)
```

- ViewModel mirrors player state
- ViewModel methods delegate to player
- ✅ Works correctly

### Gap 3: AudioPlayerViewModelV2 ↔ BriefViewModel
**Status:** ❌ NO SYNCHRONIZATION

- BriefViewModel loads queuedArticles from Core Data
- AudioPlayerViewModel has separate queue
- One-way load on line 89-94 in BriefView+Filtering
- Remove operations don't sync (lines 288-304)

### Gap 4: QueueServiceV2 ↔ BriefViewModel
**Status:** ❌ NO SYNCHRONIZATION

- Completely independent state
- No coordination mechanism
- Intended to be separate but causes confusion

### Gap 5: Persistence Layers
**Status:** ❌ CONFLICTING

- QueueServiceV2 saves to "AudioQueueItems" + "EnhancedAudioQueueItems"
- AudioPlayerViewModelV2 attempts to save to "audioQueueState"
- BriefViewModel uses Core Data (Article.isSaved)
- No master persistence coordinator

---

## Recommendations

### Priority 1: IMMEDIATE (Critical Fixes)

#### 1.1 Remove QueueServiceV2 Entirely
**Rationale:** It's unused and creates confusion

- QueueServiceV2 not integrated with actual playback
- Background generation broken (fetchArticle returns nil)
- Delegate never connected
- Creates false sense of persistence

**Action:**
- Delete QueueServiceV2.swift
- Remove from BriefeedApp initialization (lines 42, 78, 84)
- Consolidate to single queue in UnifiedAudioPlayer

#### 1.2 Implement Proper Queue Persistence
**Location:** UnifiedAudioPlayer

**Strategy:**
```swift
// Add to UnifiedAudioPlayer
func saveQueueState() async {
    let persistableItems = queue.map { item -> PersistableQueueItem in
        PersistableQueueItem(
            id: item.id,
            type: item.type,
            articleID: item.article?.objectID.uriRepresentation(),
            episodeID: item.episode?.id,
            cachedAudioURL: item.cachedAudioURL,
            generationState: item.generationState
        )
    }
    // Save to UserDefaults or Core Data
    let data = try? JSONEncoder().encode(persistableItems)
    UserDefaults.standard.set(data, forKey: "unified_queue_state")
    UserDefaults.standard.set(currentIndex, forKey: "unified_queue_index")
}

func restoreQueueState() async {
    guard let data = UserDefaults.standard.data(forKey: "unified_queue_state"),
          let persistableItems = try? JSONDecoder().decode([PersistableQueueItem].self, from: data) else {
        return
    }

    // Reconstruct UnifiedQueueItems from Core Data
    let context = PersistenceController.shared.container.viewContext
    var restoredQueue: [UnifiedQueueItem] = []

    for pItem in persistableItems {
        switch pItem.type {
        case .article:
            if let uri = pItem.articleID,
               let objectID = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri),
               let article = try? context.existingObject(with: objectID) as? Article {
                let qItem = UnifiedQueueItem(article: article)
                qItem.cachedAudioURL = pItem.cachedAudioURL
                qItem.generationState = pItem.generationState
                restoredQueue.append(qItem)
            }
        case .rssEpisode:
            // Restore episode
        }
    }

    queue = restoredQueue
    currentIndex = UserDefaults.standard.integer(forKey: "unified_queue_index")
}
```

#### 1.3 Fix Reordering to Preserve State
**Location:** AudioPlayerViewModelV2.reorderQueue (line 407-429)

**Current Issue:** Creates new queue items, loses generation state

**Fix:**
```swift
func reorderQueue(from source: IndexSet, to destination: Int) async {
    // Reorder existing UnifiedQueueItems (preserves state)
    await MainActor.run {
        var newQueue = unifiedPlayer.queue
        newQueue.move(fromOffsets: source, toOffset: destination)
        unifiedPlayer.queue = newQueue  // Direct assignment
    }

    // Persist
    await unifiedPlayer.saveQueueState()
}
```

#### 1.4 Fix Race Condition in Pre-Generation
**Location:** UnifiedAudioPlayer.preGenerateNextItems

**Issue:** Multiple tasks can run simultaneously

**Fix:**
```swift
private var preGenerationTask: Task<Void, Never>?

private func preGenerateNextItems() async {
    // Cancel existing task
    preGenerationTask?.cancel()

    // Create new task
    preGenerationTask = Task { @MainActor in
        let indicesToGenerate = [
            currentIndex,
            currentIndex + 1,
            currentIndex + 2
        ].filter { $0 >= 0 && $0 < self.queue.count }

        for index in indicesToGenerate {
            guard !Task.isCancelled else { break }

            let item = self.queue[index]
            if item.generationState == .pending {
                await self.generateAudioForItem(item)
            }
        }
    }
}

// Add cleanup
func removeFromQueue(at index: Int) {
    guard index >= 0 && index < queue.count else { return }

    queue.remove(at: index)

    // Cancel generation if we removed upcoming items
    if index <= currentIndex + 2 {
        preGenerationTask?.cancel()
        Task { await preGenerateNextItems() }
    }

    // ... rest of logic
}
```

### Priority 2: HIGH (Architecture Improvements)

#### 2.1 Unify Queue Operations
**Create:** QueueCoordinator service

```swift
@MainActor
final class QueueCoordinator: ObservableObject {
    static let shared = QueueCoordinator()

    private let audioPlayer = UnifiedAudioPlayer.shared
    private let context = PersistenceController.shared.container.viewContext

    @Published private(set) var queue: [UnifiedQueueItem] = []

    // SINGLE SOURCE OF TRUTH
    func addToQueue(_ item: Any) async {
        switch item {
        case let article as Article:
            let qItem = UnifiedQueueItem(article: article)
            queue.append(qItem)
            article.isSaved = true
            try? context.save()

        case let episode as RSSEpisode:
            let qItem = UnifiedQueueItem(episode: episode)
            queue.append(qItem)
        }

        await audioPlayer.loadMixedQueue(items: queue.map { $0.article ?? $0.episode })
        await persist()
    }

    func removeFromQueue(at index: Int) async {
        let item = queue[index]
        queue.remove(at: index)

        // Update Core Data if article
        if let article = item.article {
            article.isSaved = false
            try? context.save()
        }

        await audioPlayer.loadMixedQueue(items: queue.map { $0.article ?? $0.episode })
        await persist()
    }

    private func persist() async {
        await audioPlayer.saveQueueState()
    }
}
```

#### 2.2 Add Deduplication
**Location:** Before adding to queue

```swift
func addToQueue(_ item: Any) async {
    // Check for duplicates
    let isDuplicate: Bool
    if let article = item as? Article {
        isDuplicate = queue.contains { $0.article?.id == article.id }
    } else if let episode = item as? RSSEpisode {
        isDuplicate = queue.contains { $0.episode?.id == episode.id }
    } else {
        return
    }

    guard !isDuplicate else {
        print("Item already in queue")
        return
    }

    // ... add logic
}
```

#### 2.3 Fix Mixed Queue Persistence
**Strategy:** Store mixed queue in Core Data

Create new entity:
```swift
@objc(QueueItem)
class QueueItem: NSManagedObject {
    @NSManaged var position: Int16
    @NSManaged var itemType: String  // "article" or "episode"
    @NSManaged var article: Article?
    @NSManaged var episode: RSSEpisode?
    @NSManaged var cachedAudioPath: String?
    @NSManaged var generationState: String
    @NSManaged var addedDate: Date
}
```

Benefits:
- Atomic persistence with Core Data transactions
- Relationships to articles/episodes maintained
- Queue survives app termination
- No JSON encoding issues

### Priority 3: MEDIUM (Code Quality)

#### 3.1 Remove Duplicate Code
- AudioPlayerViewModelV2 has two saveQueueState() definitions (lines 372, 466)
- Consolidate to single implementation

#### 3.2 Implement QueueServiceDelegate
**Current State:** Protocol defined but never used (line 296-300)

**Options:**
1. Delete protocol if QueueServiceV2 is removed
2. Implement delegate in UnifiedAudioPlayer if keeping service

#### 3.3 Fix Unsafe Index Synchronization
**Location:** QueueServiceV2.swift:123-127

```swift
func removeFromQueue(at index: Int) async {
    guard index < enhancedQueue.count else { return }
    enhancedQueue.remove(at: index)
    await saveEnhancedQueue()

    // ⚠️ UNSAFE: Assumes same index in both queues!
    if index < queuedItems.count {
        queuedItems.remove(at: index)
        await saveQueue()
    }
}
```

**Issue:** Episodes don't exist in queuedItems, indexes misaligned

#### 3.4 Add Comprehensive Logging
**Purpose:** Debug queue state issues

```swift
func logQueueState() {
    print("=== QUEUE STATE ===")
    print("UnifiedAudioPlayer.queue: \(queue.count) items")
    queue.enumerated().forEach { index, item in
        print("  [\(index)] \(item.title) - \(item.generationState)")
    }
    print("Current index: \(currentIndex)")
    print("===================")
}
```

### Priority 4: LOW (Future Enhancements)

#### 4.1 Add Queue Analytics
- Track queue usage patterns
- Monitor generation success rates
- Identify bottlenecks

#### 4.2 Smart Pre-Generation
- Adjust window size based on playback speed
- Prioritize articles vs episodes differently
- Cancel generation if user skips ahead

#### 4.3 Queue Limits
- Maximum queue size (prevent memory issues)
- Auto-archive old items
- Warning when queue exceeds limit

---

## Testing Recommendations

### Unit Tests Needed

1. **Queue Persistence Test**
```swift
func testQueuePersistence() async {
    // Given
    let article = createTestArticle()
    await coordinator.addToQueue(article)

    // When
    await coordinator.persist()
    let newCoordinator = QueueCoordinator()
    await newCoordinator.restore()

    // Then
    XCTAssertEqual(newCoordinator.queue.count, 1)
    XCTAssertEqual(newCoordinator.queue[0].title, article.title)
}
```

2. **Mixed Queue Test**
```swift
func testMixedQueueOrdering() async {
    // Given
    let article = createTestArticle()
    let episode = createTestEpisode()

    // When
    await coordinator.addToQueue(article)
    await coordinator.addToQueue(episode)

    // Then
    XCTAssertEqual(coordinator.queue.count, 2)
    XCTAssertEqual(coordinator.queue[0].type, .article)
    XCTAssertEqual(coordinator.queue[1].type, .rssEpisode)
}
```

3. **Deduplication Test**
```swift
func testDeduplication() async {
    // Given
    let article = createTestArticle()

    // When
    await coordinator.addToQueue(article)
    await coordinator.addToQueue(article)

    // Then
    XCTAssertEqual(coordinator.queue.count, 1)
}
```

4. **Reordering Preserves State Test**
```swift
func testReorderingPreservesGenerationState() async {
    // Given
    let articles = createTestArticles(count: 3)
    for article in articles {
        await coordinator.addToQueue(article)
    }
    coordinator.queue[0].generationState = .ready
    coordinator.queue[1].generationState = .generating

    // When
    await coordinator.reorder(from: IndexSet(integer: 2), to: 0)

    // Then
    XCTAssertEqual(coordinator.queue[1].generationState, .ready)
    XCTAssertEqual(coordinator.queue[2].generationState, .generating)
}
```

### Integration Tests Needed

1. **End-to-End Queue Flow**
2. **App Restart Restoration**
3. **Concurrent Modification Handling**
4. **Memory Leak Detection**

---

## Conclusion

The Briefeed queue system is **critically fragmented** with multiple independent queue representations causing:

1. **Data Loss:** Queue state lost on app restart
2. **Duplicates:** Items appear multiple times
3. **Inconsistency:** UI shows different state than backend
4. **Broken Features:** Background generation never works
5. **Race Conditions:** Concurrent updates corrupt state

**Recommended Action Plan:**

**Week 1:**
- Remove QueueServiceV2
- Implement proper persistence in UnifiedAudioPlayer
- Fix reordering to preserve state

**Week 2:**
- Create QueueCoordinator
- Add deduplication
- Implement Core Data queue persistence

**Week 3:**
- Add comprehensive tests
- Performance optimization
- Documentation

**Estimated Effort:** 3 weeks for complete refactor

**Risk Level:** HIGH - Core functionality affected

**Impact:** CRITICAL - Affects all audio playback features

---

## Appendix A: File Reference

| File | Purpose | Issues |
|------|---------|--------|
| QueueServiceV2.swift | Legacy queue service | Unused, broken generation |
| UnifiedAudioPlayer.swift | Active playback queue | No persistence |
| AudioPlayerViewModelV2.swift | UI binding layer | Duplicate methods |
| BriefViewModel.swift | Brief tab queue | No sync with audio |
| QueueModels.swift | Data structures | Good design |
| EnhancedQueueItem+Extensions.swift | Conversion helpers | One-way, lossy |
| BriefView+Filtering.swift | Queue UI | Inconsistent updates |

## Appendix B: Data Structure Comparison

| Field | QueuedItem | EnhancedQueueItem | UnifiedQueueItem |
|-------|-----------|-------------------|------------------|
| ID | articleID (UUID) | id (UUID) | id (String) |
| Title | ❌ | ✅ | ✅ |
| Type | Articles only | Mixed | Mixed |
| Audio URL | ❌ | ✅ | ✅ (as cachedAudioURL) |
| Generation State | ❌ | ❌ | ✅ (@Published) |
| Core Data Ref | ❌ | ❌ | ✅ (Article/Episode) |
| Added Date | ✅ | ✅ | ❌ |
| Expiration | ❌ | ✅ | ❌ |
| Position | ❌ | ❌ | ✅ (in array) |
| Persistence | UserDefaults | UserDefaults | None |

## Appendix C: Queue Operation Matrix

| Operation | QueueServiceV2 | UnifiedAudioPlayer | BriefViewModel | Synced? |
|-----------|---------------|-------------------|----------------|---------|
| Add Article | ❌ Not called | ✅ Via loadQueue | ✅ Core Data | ❌ |
| Add Episode | ❌ Not called | ✅ Via loadQueue | N/A | ❌ |
| Remove | ✅ But unused | ✅ | ✅ | ❌ |
| Reorder | ✅ But unused | ✅ (broken) | ✅ | ❌ |
| Clear | ✅ But unused | ✅ | ✅ | ❌ |
| Persist | ✅ 2 keys | ❌ | ✅ Core Data | ❌ |
| Restore | ✅ But unused | ❌ | ✅ | ❌ |

---

**End of Audit**
