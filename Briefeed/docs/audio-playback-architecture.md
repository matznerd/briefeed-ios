# Audio Playback Architecture Analysis

## Overview
The Briefeed app has a complex audio system that handles two distinct types of content:
1. **TTS Articles**: Reddit/RSS articles converted to audio using Gemini TTS or device TTS
2. **RSS Episodes**: Actual podcast episodes with audio URLs from RSS feeds

## Current System Components

### 1. AudioService (Core/Services/AudioService.swift)
- **Primary Role**: Manages audio playback state and controls
- **Handles**: 
  - AVSpeechSynthesizer for device TTS
  - AVAudioPlayer for Gemini TTS audio files
  - AVPlayer for RSS episode streaming (via extension)
- **Issues**:
  - Has its own internal `queue` array separate from QueueService
  - Mixing different audio types causes state management issues
  - `currentArticle` property used for both articles and RSS episodes

### 2. QueueService (Core/Services/QueueService.swift)
- **Primary Role**: Manages persistent queue across app launches
- **Features**:
  - `queuedItems`: Legacy queue for articles only
  - `enhancedQueue`: New unified queue supporting both articles and RSS episodes
  - Saves queue to UserDefaults
- **Issues**:
  - Two queue systems running in parallel (legacy and enhanced)
  - Synchronization issues between QueueService and AudioService queues

### 3. RSSAudioService (Core/Services/RSS/RSSAudioService.swift)
- **Primary Role**: Manages RSS podcast feeds and episodes
- **Features**:
  - Fetches and parses RSS feeds
  - Tracks episode listen status
  - Provides latest unlistened episodes

## Playback Contexts and Issues

### Context 1: Live News (Radio Mode)
**Expected Behavior**:
- "Play Live News" button should start streaming immediately
- Should play latest unlistened episodes from each feed
- Next/Previous should navigate through Live News list only
- Should NOT add to Brief queue

**Current Issues**:
- First play button on individual feed rows not working
- Items not showing in universal player
- Context lost when navigating

### Context 2: Brief Queue (Playlist Mode)
**Expected Behavior**:
- Mixed queue of TTS articles and RSS episodes
- Items explicitly added by user
- Next/Previous navigates through Brief queue
- Persistent across app launches

**Current Issues**:
- Queue synchronization between services
- Context switching when playing from different sources

### Context 3: Direct Play
**Expected Behavior**:
- Play button on any item plays immediately
- Replaces current playback
- Maintains source context for navigation

**Current Issues**:
- Source context not preserved
- Navigation defaults to wrong queue

## Root Causes

### 1. Multiple Queue Systems
```
AudioService.queue (Article[])
QueueService.queuedItems (QueuedItem[])  
QueueService.enhancedQueue (EnhancedQueueItem[])
```
Three separate queues trying to stay in sync

### 2. Context Loss
No tracking of playback source:
- Was it started from Live News?
- Was it started from Brief?
- Was it a direct play action?

### 3. Article Model Misuse
Using Article entity for RSS episodes causes:
- Type confusion
- Missing RSS-specific properties
- Incorrect state management

## Proposed Solution Architecture

### 1. Unified Playback Context
```swift
enum PlaybackContext {
    case liveNews           // Playing from Live News list
    case brief             // Playing from Brief queue
    case direct            // Single item play
}

class AudioService {
    @Published var playbackContext: PlaybackContext = .direct
    @Published var contextQueue: [EnhancedQueueItem] = []
}
```

### 2. Single Queue System
- Remove AudioService.queue entirely
- Use only QueueService.enhancedQueue
- AudioService references queue items by ID

### 3. Context-Aware Navigation
```swift
func playNext() {
    switch playbackContext {
    case .liveNews:
        // Get next from RSSAudioService latest episodes
    case .brief:
        // Get next from QueueService.enhancedQueue
    case .direct:
        // No next available
    }
}
```

### 4. Proper Current Item Tracking
```swift
class AudioService {
    @Published var currentItemId: UUID?
    @Published var currentItem: PlayableItem? // Protocol for both types
}
```

## Implementation Plan

### Phase 1: Add Playback Context
1. Add PlaybackContext enum
2. Track context when playback starts
3. Update navigation to respect context

### Phase 2: Unify Queue System  
1. Remove AudioService.queue
2. Update all references to use QueueService
3. Fix queue synchronization

### Phase 3: Fix Live News
1. Implement context-aware Live News playback
2. Fix individual play buttons
3. Ensure proper mini player updates

### Phase 4: Harmonize Item Types
1. Create unified playable item protocol
2. Update UI to handle both types properly
3. Fix state management

## Expected User Flows

### Flow 1: Live News Radio
1. User taps "Play Live News"
2. System sets context = .liveNews
3. Loads latest episodes into contextQueue
4. Starts playing first item
5. Next button plays next episode in Live News
6. Mini player shows RSS episode info

### Flow 2: Brief Playlist
1. User adds items to Brief
2. User plays from Brief
3. System sets context = .brief  
4. Loads QueueService.enhancedQueue
5. Next button plays next in Brief queue
6. Mini player shows current item

### Flow 3: Individual Play
1. User taps play on specific item
2. System sets context = .direct
3. Plays single item
4. Next/Previous disabled
5. Can still add to Brief queue

## Testing Scenarios

1. **Live News Flow**
   - Play Live News → Next → Next → Should stay in Live News
   - Individual feed play → Should play that episode only
   
2. **Brief Flow**
   - Add items → Play from Brief → Next → Should follow Brief order
   
3. **Context Switching**
   - Playing from Live News → Play from Brief → Context should switch
   - Navigation should follow new context

4. **Mini Player**
   - Should always show current item
   - Should reflect correct source
   - Controls should work for current context