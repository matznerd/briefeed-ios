# Briefeed iOS App - Swipe Gestures and User Interactions Audit

**Date:** 2025-12-16
**Auditor:** Claude Code
**Status:** Complete

## Executive Summary

This audit examines all swipe gestures, context menus, and user interactions across the Briefeed iOS app. The audit reveals a **mixed implementation state** with some gestures working correctly while others are incomplete or missing expected functionality.

### Key Findings

- ✅ **Working:** Article swipe gestures in feed view (save/archive)
- ✅ **Working:** Brief queue swipe actions (remove/keep)
- ✅ **Working:** Live News feed swipe actions (delete/toggle)
- ❌ **Missing:** Swipe to play immediately in feed view
- ❌ **Missing:** Swipe to add to queue in feed view
- ⚠️ **Partial:** Audio player gestures (drag to expand/dismiss)
- ⚠️ **Limited:** Context menus only on feed management

---

## 1. ArticleRowView - Feed Article Gestures

**File:** `/Users/me/ericode/briefeed-app/briefeed-ios/Briefeed/Briefeed/Features/Article/ArticleRowView.swift`

### Implemented Gestures

#### 1.1 Swipe Right → Save & Add to Queue
**Lines:** 317-410

```swift
private var swipeGesture: some Gesture {
    DragGesture(minimumDistance: 30, coordinateSpace: .local)
        .onChanged { value in
            // Detects horizontal swipe
            if abs(horizontalAmount) > abs(verticalAmount) * 1.5 && abs(horizontalAmount) > 30 {
                // Updates offset with elastic resistance
                // Triggers haptic at threshold (100pt)
            }
        }
        .onEnded { value in
            if shouldTriggerAction {
                if offset > 0 {
                    performSaveAction()  // Swipe right
                } else {
                    performArchiveAction()  // Swipe left
                }
            }
        }
}
```

**Visual Feedback:**
- Green background with bookmark icon (swipe right)
- Red background with archive icon (swipe left)
- Icon scales and text appears at threshold
- Haptic feedback when reaching 100pt threshold

**Actions:**
- **Swipe Right (100pt+):**
  - Toggles article save state
  - **Automatically adds to audio queue** if being saved (line 402-405)
  - Haptic feedback
  - Does NOT show play options overlay (intentionally disabled, line 408-409)

- **Swipe Left (100pt+):**
  - Archives/unarchives article
  - Haptic feedback

#### 1.2 Tap Gesture
**Lines:** 103-107

```swift
Button(action: {
    if !isDragging && offset == 0 && !justCompletedSwipe {
        onTap()  // Opens article detail view
    }
})
```

**Protection:** Prevents tap-through during/after swipe gestures

### Missing Features

❌ **No dedicated "Play Now" swipe gesture**
- User expectation: Swipe to immediately play article
- Current behavior: Must swipe to save (adds to queue), then manually play
- Workaround: Swipe saves AND queues, but doesn't auto-play

❌ **Action buttons overlay disabled**
- Lines 408-409 comment: "Don't show action buttons - swipe should just add to queue"
- Code exists (lines 432-500) but never triggered
- Would provide "Play Now" and "Play Next" options after swipe

### Visual States

**Indicators shown:**
- 🔴 Playing (with waveform animation)
- 🔴 Unread
- 🟢 Saved (bookmark)
- 🟠 Queued (with position number)
- ⚪ Archived

---

## 2. BriefView+Filtering - Queue Management

**File:** `/Users/me/ericode/briefeed-app/briefeed-ios/Briefeed/Briefeed/Features/Brief/BriefView+Filtering.swift`

### Implemented Swipe Actions

#### 2.1 Queue Item Swipe Actions
**Lines:** 131-133, 240-257

```swift
.swipeActions(edge: .trailing, allowsFullSwipe: true) {
    swipeActions(for: item)
}

private func swipeActions(for item: EnhancedQueueItem) -> some View {
    Group {
        Button(role: .destructive) {
            removeItem(item)
        } label: {
            Label("Remove", systemImage: "trash")
        }

        // Only for Live News items with expiration
        if item.source.isLiveNews && item.remainingTime != nil {
            Button {
                saveItem(item)
            } label: {
                Label("Keep", systemImage: "bookmark")
            }
            .tint(.blue)
        }
    }
}
```

**Status:** ✅ **Working**

**Actions:**
- **Trailing swipe:** Remove from queue (destructive)
- **Conditional:** "Keep" button for expiring Live News episodes

#### 2.2 List Editing
**Lines:** 135-140

```swift
.onDelete { indexSet in
    deleteItems(at: indexSet)
}
.onMove { source, destination in
    moveItems(from: source, to: destination)  // TODO: Not implemented
}
```

**Status:** ⚠️ **Partial**
- Delete works via Edit mode
- **Move/reorder NOT implemented** (line 285-286 TODO comment)

#### 2.3 Play Button
**Lines:** 352-441

```swift
Button(action: playItem) {
    HStack {
        Button(action: playItem) {
            Image(systemName: isCurrentlyPlaying && audioPlayerViewModel.isPlaying ?
                "pause.circle.fill" : "play.circle.fill")
        }
        // ... content
    }
}

private func playItem() {
    if isCurrentlyPlaying && audioPlayerViewModel.isPlaying {
        audioPlayerViewModel.pause()
    } else if let audioUrl = item.audioUrl {
        // Play RSS episode
    } else if let articleID = item.articleID {
        // Play article
    }
}
```

**Status:** ✅ **Working**
- Tap entire row to play
- Dedicated play/pause button
- Correctly handles both articles and RSS episodes

---

## 3. CombinedFeedView - Feed Display

**File:** `/Users/me/ericode/briefeed-app/briefeed-ios/Briefeed/Briefeed/Features/Feed/CombinedFeedView.swift`

### Article Row Implementation

**Lines:** 104-115

```swift
ArticleRowView(article: article) {
    selectedArticle = article  // onTap
} onSave: {
    Task {
        await viewModel.toggleArticleSaved(article)
    }
} onDelete: {
    Task {
        await viewModel.archiveArticle(article)
    }
}
```

**Status:** ✅ **Delegates to ArticleRowView**
- All gestures handled by ArticleRowView component
- See section 1 for full gesture details

### No Feed-Level Swipe Actions
- Articles use ArticleRowView gestures
- No special feed-specific interactions

---

## 4. LiveNewsViewV2 - RSS Podcast Management

**File:** `/Users/me/ericode/briefeed-app/briefeed-ios/Briefeed/Briefeed/Features/LiveNews/LiveNewsViewV2.swift`

### Implemented Swipe Actions

#### 4.1 Feed Row Swipe Actions
**Lines:** 98-100, 181-195

```swift
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    feedSwipeActions(for: feed)
}

private func feedSwipeActions(for feed: RSSFeed) -> some View {
    Button(role: .destructive) {
        deleteFeed(feed)
    } label: {
        Label("Delete", systemImage: "trash")
    }

    Button {
        toggleEnabled(feed)
    } label: {
        Label(feed.isEnabled ? "Disable" : "Enable",
              systemImage: feed.isEnabled ? "pause.circle" : "play.circle")
    }
    .tint(feed.isEnabled ? .orange : .green)
}
```

**Status:** ✅ **Working**

**Actions:**
- **Trailing swipe:** Delete feed (destructive red)
- **Trailing swipe:** Toggle enabled/disabled (orange/green)
- **allowsFullSwipe: false** - prevents accidental deletions

#### 4.2 Episode Swipe Actions (Defined but Not Used)
**Lines:** 155-178

```swift
private func episodeSwipeActions(for episode: RSSEpisode) -> some View {
    Button {
        Task {
            await appViewModel.queueEpisode(episode)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    } label: {
        Label("Play Later", systemImage: "plus.circle")
    }
    .tint(.blue)

    Button {
        Task {
            await appViewModel.play(episode: episode)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    } label: {
        Label("Play Now", systemImage: "play.circle")
    }
    .tint(.orange)
}
```

**Status:** ⚠️ **Defined but NOT attached to any view**
- Function exists but never called
- Would provide "Play Now" and "Play Later" swipes for episodes
- **Missing implementation in FeedDetailsViewV2**

---

## 5. Audio Player Gestures

### 5.1 MiniAudioPlayerV4 - Mini Player

**File:** `/Users/me/ericode/briefeed-app/briefeed-ios/Briefeed/Briefeed/Features/Audio/MiniAudioPlayerV4.swift`

**Lines:** 211-236

```swift
.gesture(
    DragGesture()
        .onChanged { value in
            isDragging = true
            dragOffset = value.translation.height

            if dragOffset < expandThreshold {  // -50pt
                HapticManager.shared.lightImpact()
                isExpanded = true
            }
        }
        .onEnded { value in
            if dragOffset < expandThreshold {
                isExpanded = true  // Expand to full player
            } else if dragOffset > dismissThreshold {  // +100pt
                viewModel.stop()  // Dismiss/stop playback
            }
            dragOffset = 0
        }
)
```

**Status:** ✅ **Working**

**Gestures:**
- **Swipe up (-50pt):** Expands to full player sheet
- **Swipe down (+100pt):** Dismisses and stops playback
- Haptic feedback on threshold
- Visual offset during drag

### 5.2 ExpandedAudioPlayerV2 - Full Player

**File:** `/Users/me/ericode/briefeed-app/briefeed-ios/Briefeed/Briefeed/Features/Audio/ExpandedAudioPlayerV2.swift`

**Lines:** 170-181

```swift
.gesture(
    DragGesture(minimumDistance: 0)
        .onChanged { value in
            isDraggingSlider = true
            let progress = Float(value.location.x / UIScreen.main.bounds.width - 48)
            dragProgress = max(0, min(1, progress))
        }
        .onEnded { _ in
            viewModel.seek(to: dragProgress)
            isDraggingSlider = false
        }
)
```

**Status:** ✅ **Working**

**Gestures:**
- **Horizontal drag on progress bar:** Scrub through audio
- Custom slider implementation
- Smooth seeking with visual feedback

#### Queue View Swipe Actions
**Lines:** 460-471

```swift
.onDelete { indexSet in
    Task {
        for index in indexSet {
            await viewModel.removeFromQueue(at: index)
        }
    }
}
.onMove { source, destination in
    Task {
        await viewModel.reorderQueue(from: source, to: destination)
    }
}
```

**Status:** ✅ **Working**
- Delete queue items in edit mode
- Reorder queue items via drag

---

## 6. FeedRowView - Feed Management

**File:** `/Users/me/ericode/briefeed-app/briefeed-ios/Briefeed/Briefeed/Features/Feed/FeedRowView.swift`

### Context Menu Implementation

**Lines:** 44-61

```swift
.contextMenu {
    Button {
        Task {
            await viewModel.toggleFeedActive(feed)
        }
    } label: {
        Label(feed.isActive ? "Deactivate" : "Activate",
              systemImage: feed.isActive ? "pause.circle" : "play.circle")
    }

    Button(role: .destructive) {
        Task {
            await viewModel.deleteFeed(feed)
        }
    } label: {
        Label("Delete", systemImage: "trash")
    }
}
```

**Status:** ✅ **Working**

**Actions:**
- **Long press:** Shows context menu
- Toggle feed active/inactive
- Delete feed

**Note:** This is for RSS source feeds, not the Live News podcast feeds

---

## Summary of Issues and Recommendations

### Critical Missing Features

#### 1. No "Swipe to Play" in Feed View
**Problem:** Users cannot swipe an article to immediately play it
**Current Workaround:** Swipe right saves AND adds to queue, but doesn't auto-play
**Expected Behavior:** Swipe left = play now, swipe right = add to queue

**Recommendation:**
```swift
// In ArticleRowView, modify performSaveAction():
private func performSaveAction() {
    if isSwipingLeft {
        // Play immediately
        Task { @MainActor in
            await audioPlayerViewModel.play(article: article)
        }
    } else if isSwipingRight {
        // Add to queue
        onSave()
        if !article.isSaved {
            Task { @MainActor in
                await audioPlayerViewModel.addToQueue(article)
            }
        }
    }
}
```

Or re-enable the action buttons overlay (currently disabled at lines 408-409):

```swift
// Remove the comment and re-enable:
showActionButtons = true
timeRemaining = 5
actionButtonsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    timeRemaining -= 1
    if timeRemaining <= 0 {
        showActionButtons = false
        actionButtonsTimer?.invalidate()
    }
}
```

#### 2. Episode Swipe Actions Not Implemented
**Problem:** `episodeSwipeActions()` function exists but never used
**File:** LiveNewsViewV2.swift, lines 155-178
**Location:** Should be in FeedDetailsViewV2 episode list

**Recommendation:**
```swift
// In FeedDetailsViewV2, line 353:
ForEach(episodes) { episode in
    EpisodeRowV2(episode: episode)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Add the episode swipe actions here
            episodeSwipeActions(for: episode)
        }
}
```

#### 3. Queue Reordering Not Implemented
**Problem:** Move function is TODO in BriefView+Filtering.swift
**Lines:** 285-286

**Recommendation:**
```swift
private func moveItems(from source: IndexSet, to destination: Int) {
    var items = Array(filteredQueue)
    items.move(fromOffsets: source, toOffset: destination)

    // Update queue order in audio player
    Task {
        await audioPlayerViewModel.reorderQueue(
            from: source,
            to: destination
        )
    }
}
```

### Working Features to Preserve

✅ **ArticleRowView gestures** - Smooth implementation with elastic resistance
✅ **Brief queue swipe actions** - Clean remove/keep pattern
✅ **Audio player gestures** - Drag to expand/dismiss works well
✅ **Live News feed management** - Delete/toggle swipes functional
✅ **Context menus** - Feed management accessible via long-press

### Design Considerations

#### Gesture Conflicts
- **Horizontal swipe vs. vertical scroll:** ArticleRowView correctly requires 1.5x horizontal movement (line 325)
- **Tap vs. swipe:** Properly handled with `isDragging` and `justCompletedSwipe` flags
- **allowsFullSwipe setting:** Correctly disabled for destructive actions (feeds), enabled for queue removal

#### Haptic Feedback
✅ ArticleRowView uses HapticManager.shared for:
- Swipe threshold reached (line 342)
- Save action (line 393)
- Archive action (line 414)

⚠️ LiveNewsViewV2 uses UIImpactFeedbackGenerator directly (lines 162, 172)
- **Recommendation:** Standardize on HapticManager for consistency

#### Visual Feedback Quality
✅ Excellent:
- ArticleRowView background colors and icons
- Waveform animations for playing state
- Progress bars and sliders

⚠️ Could improve:
- Queue position indicator (exists but could be more prominent)
- Loading states during swipe actions
- Swipe gesture hints for first-time users

---

## Code Reference Map

### Primary Gesture Files
1. **ArticleRowView.swift** (530 lines)
   - Main feed article gestures
   - Lines 317-383: Swipe gesture implementation
   - Lines 251-313: Visual feedback views
   - Lines 391-422: Action handlers

2. **BriefView+Filtering.swift** (450 lines)
   - Queue management swipes
   - Lines 131-133: Swipe actions attachment
   - Lines 240-257: Swipe action definitions
   - Lines 288-305: Item removal logic

3. **LiveNewsViewV2.swift** (483 lines)
   - RSS feed management
   - Lines 98-100: Feed swipe actions attachment
   - Lines 181-195: Feed swipe action definitions
   - Lines 155-178: **Unused** episode swipe actions

4. **MiniAudioPlayerV4.swift** (280 lines)
   - Mini player gestures
   - Lines 211-236: Drag to expand/dismiss

5. **ExpandedAudioPlayerV2.swift** (497 lines)
   - Full player gestures
   - Lines 170-181: Progress scrubbing
   - Lines 460-471: Queue reordering

### Supporting Files
- **FeedRowView.swift** - Context menu only
- **CombinedFeedView.swift** - Delegates to ArticleRowView
- **AppViewModel.swift** - Audio playback coordination
- **AudioPlayerViewModelV2.swift** - Queue management

---

## Testing Recommendations

### Manual Testing Checklist

#### Feed View (ArticleRowView)
- [ ] Swipe right 50pt: See green background with bookmark icon
- [ ] Swipe right 100pt+: Triggers save + queue add
- [ ] Swipe left 50pt: See red background with archive icon
- [ ] Swipe left 100pt+: Triggers archive
- [ ] Verify haptic feedback at 100pt threshold
- [ ] Tap article while swiping: Should not open detail
- [ ] Swipe then tap: Should not open detail for 0.3s
- [ ] Normal tap: Opens article detail view

#### Brief View (Queue)
- [ ] Swipe queue item left: Shows Remove button (red)
- [ ] Swipe Live News item: Shows Remove + Keep buttons
- [ ] Tap Remove: Item removed from queue
- [ ] Tap Keep: Expiration removed (Live News only)
- [ ] Enter Edit mode: Can delete items
- [ ] Enter Edit mode: Can reorder items (EXPECTED TO FAIL - not implemented)

#### Live News View
- [ ] Swipe feed left: Shows Delete + Enable/Disable buttons
- [ ] Swipe with allowsFullSwipe false: Prevents accidental full swipe
- [ ] Tap Delete: Feed removed
- [ ] Tap Enable/Disable: Feed state toggles
- [ ] Open feed details: Episode list shown
- [ ] Try swiping episode: Nothing happens (EXPECTED - not implemented)

#### Audio Player
- [ ] Mini player: Swipe up 50pt: Expands to full player
- [ ] Mini player: Swipe down 100pt: Stops and dismisses
- [ ] Mini player: Tap play/pause: Works
- [ ] Full player: Drag progress bar: Seeks audio
- [ ] Full player: Open queue: Shows queue list
- [ ] Full player queue: Swipe to delete: Removes item
- [ ] Full player queue: Drag to reorder: Changes order

### Automated Testing Gaps
- No UI tests for swipe gestures found
- Could add XCTest UI tests for gesture interactions
- Recommendation: Add SwiftUI preview interactions for faster testing

---

## Conclusion

The Briefeed app has a **solid foundation** for gesture-based interactions, with most core functionality working correctly. However, there are **three critical gaps**:

1. **Missing "swipe to play"** - Users expect to play articles directly from feed
2. **Unused episode swipe actions** - Code exists but not connected
3. **Incomplete queue reordering** - TODO comment in production code

The existing implementations demonstrate good practices:
- Proper gesture conflict resolution
- Smooth animations with elastic resistance
- Comprehensive haptic feedback
- Clear visual indicators

**Priority Recommendations:**
1. **High:** Enable article play gestures (either via overlay or direct swipe)
2. **Medium:** Connect episode swipe actions to episode list
3. **Medium:** Implement queue reordering
4. **Low:** Standardize haptic feedback on HapticManager

**Overall Assessment:** 7/10 - Good implementation with key features missing

---

## Appendix: Gesture Patterns

### Standard Swipe Patterns in App

#### ArticleRowView
```
Swipe Right → Save + Queue
Swipe Left  → Archive
```

#### BriefView Queue
```
Swipe Left → Remove (always)
Swipe Left → Keep (Live News with expiration)
```

#### LiveNewsViewV2 Feeds
```
Swipe Left → Delete
Swipe Left → Toggle Enable/Disable
```

#### Audio Players
```
Mini Player:
  Swipe Up   → Expand
  Swipe Down → Dismiss/Stop

Full Player:
  Horizontal Drag → Seek

Queue:
  Swipe Left → Delete
  Drag       → Reorder
```

### Missing Patterns

#### Feed Episode List (Should have)
```
Swipe Left  → Play Now
Swipe Right → Play Later (add to queue)
```

#### Article Detail View (Could add)
```
Swipe Left/Right → Navigate between articles
```

---

**End of Audit**
