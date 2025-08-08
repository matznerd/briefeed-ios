# Migration Guide: AudioService → BriefeedAudioService

## Architecture Overview

The new architecture separates concerns properly:

```
QueueServiceV2 (Queue Management)
    ↓
BriefeedAudioService (Audio Playback)
```

## Component Migration Guide

### 1. QueueService
**Status**: ✅ Rewritten as QueueServiceV2
- Now the single source of truth for queue state
- Manages EnhancedQueueItems (articles + RSS)
- Coordinates with BriefeedAudioService for playback
- Handles persistence and TTS generation

### 2. ViewModels

#### BriefViewModel
**Before:**
```swift
private let audioService = AudioService.shared
audioService.queue = articles  // Direct manipulation
try await audioService.playNow(article)
```

**After:**
```swift
private let queueService = QueueServiceV2.shared
private let audioService = BriefeedAudioService.shared

// Use QueueService for queue operations
await queueService.addArticle(article)
await queueService.playItem(at: index)

// Observe both services
queueService.$queue  // For queue state
audioService.$isPlaying  // For playback state
```

#### ArticleViewModel
**Before:**
```swift
self.audioService = audioService ?? AudioService.shared
```

**After:**
```swift
private let audioService = BriefeedAudioService.shared
private let queueService = QueueServiceV2.shared

// Play article
await audioService.playArticle(article)

// Add to queue
await queueService.addArticle(article)
```

### 3. UI Components

#### MiniAudioPlayer
**Before:**
```swift
@ObservedObject private var audioService = AudioService.shared
if audioService.currentArticle != nil { ... }
```

**After:**
```swift
@ObservedObject private var audioService = BriefeedAudioService.shared
@ObservedObject private var queueService = QueueServiceV2.shared

if audioService.currentPlaybackItem != nil { ... }
// Or use queueService.currentItem for queue info
```

#### ExpandedAudioPlayer
**Before:**
```swift
audioService.queue  // Direct queue access
audioService.skipBackward(seconds: 15)
```

**After:**
```swift
queueService.queue  // Queue from QueueService
audioService.skipBackward()  // No parameter needed
```

#### LiveNewsView
**Before:**
```swift
audioService.playRSSEpisode(url: url, title: title, episode: episode)
```

**After:**
```swift
// For immediate playback:
await audioService.playRSSEpisode(episode)

// For adding to queue:
queueService.addRSSEpisode(episode)
```

### 4. Common Patterns

#### Playing Content
```swift
// Play article immediately
await audioService.playArticle(article)

// Play RSS episode immediately  
await audioService.playRSSEpisode(episode)

// Play from queue
await queueService.playItem(at: index)
```

#### Queue Management
```swift
// Add to queue
await queueService.addArticle(article)
queueService.addRSSEpisode(episode)

// Remove from queue
queueService.removeItem(at: index)

// Reorder queue
queueService.moveItem(from: source, to: destination)

// Clear queue
queueService.clearQueue()
```

#### State Observation
```swift
// Playback state
audioService.$isPlaying
audioService.$currentPlaybackItem
audioService.state  // CurrentValueSubject

// Queue state
queueService.$queue
queueService.$currentIndex
queueService.currentItem
```

## Migration Steps

1. **Update imports and service references**
   - Replace `AudioService.shared` with `BriefeedAudioService.shared`
   - Add `QueueServiceV2.shared` where queue operations are needed

2. **Update state observations**
   - Use `audioService` for playback state
   - Use `queueService` for queue state

3. **Update method calls**
   - Queue operations → QueueServiceV2
   - Playback control → BriefeedAudioService
   - Make functions async where needed

4. **Remove direct queue manipulation**
   - No more `audioService.queue = articles`
   - Use QueueService methods instead

5. **Update UI bindings**
   - Observe both services as needed
   - Use correct properties for state

## Benefits of New Architecture

1. **Separation of Concerns**: Queue logic separate from playback
2. **Better Type Safety**: EnhancedQueueItem handles mixed content
3. **Cleaner API**: Each service has focused responsibilities
4. **Easier Testing**: Services can be tested independently
5. **Better Performance**: Background TTS generation managed properly

## Features Preserved

✅ Live News radio mode
✅ Mixed queue (articles + RSS)
✅ Queue persistence
✅ Background TTS generation
✅ Playback contexts
✅ All playback controls