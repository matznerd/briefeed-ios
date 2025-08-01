# Audio Playback System Fixes - Summary

## Fixed Issues

### 1. Play Button on Live News Feed Row ✅
- **Issue**: Nested button inside button causing gesture conflicts
- **Fix**: Restructured FeedRow to have separate tap areas for play button and feed details
- **Result**: Play button now works independently from row tap

### 2. Mini Player Shows RSS Episodes ✅
- **Issue**: RSS episodes created transient Article objects that weren't retained
- **Fix**: Added `CurrentPlaybackItem` system to properly track both articles and RSS episodes
- **Result**: Mini player now shows RSS episode info with radio icon

## Implemented Changes

### 1. New Playback Context System
```swift
// PlaybackContext.swift
enum PlaybackContext {
    case liveNews   // Radio mode
    case brief      // Playlist mode  
    case direct     // Single item
}

struct CurrentPlaybackItem {
    // Unified item for both articles and RSS
}
```

### 2. Updated AudioService
- Added `@Published var currentPlaybackItem: CurrentPlaybackItem?`
- Added `@Published var playbackContext: PlaybackContext`
- RSS episodes now create proper playback items instead of transient articles

### 3. Updated MiniAudioPlayer
- Uses `currentPlaybackItem` for display
- Shows appropriate icon (radio for RSS, text for articles)
- All controls enabled for both content types

## Remaining Issues to Address

### 1. Context-Aware Navigation (TODO #24)
Currently, next/previous buttons don't respect playback context:
- Live News should navigate through Live News list only
- Brief should navigate through Brief queue
- Need to track where playback was initiated

### 2. Live News Radio Mode (TODO #25)
When "Play Live News" is pressed:
- Should set context = .liveNews
- Next button should play next unlistened episode
- Should NOT mix with Brief queue

### 3. Queue Harmonization
Multiple queue systems still exist:
- AudioService.queue (legacy)
- QueueService.queuedItems (articles only)
- QueueService.enhancedQueue (unified)
Need to consolidate to single queue

## Next Steps

### Phase 1: Implement Playback Context
1. Set context when starting playback:
   - `playbackContext = .liveNews` when Play Live News pressed
   - `playbackContext = .brief` when playing from Brief
   - `playbackContext = .direct` for individual plays

2. Update navigation methods:
```swift
func playNext() {
    switch playbackContext {
    case .liveNews:
        // Get next from Live News episodes
    case .brief:
        // Get next from enhanced queue
    case .direct:
        // No next available
    }
}
```

### Phase 2: Live News Queue
1. Create separate tracking for Live News playback
2. Store ordered list of unlistened episodes
3. Auto-advance through list

### Phase 3: Remove Legacy Queue
1. Remove AudioService.queue entirely
2. Update all references to use QueueService
3. Ensure queue persistence works correctly

## Testing Checklist

- [ ] Play button on Live News feed row starts playback
- [ ] Mini player shows RSS episode info with radio icon
- [ ] Play Live News creates radio-style continuous playback
- [ ] Next button in Live News context plays next episode
- [ ] Playing from Brief maintains Brief queue context
- [ ] Context switches appropriately when starting new playback