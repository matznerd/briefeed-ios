# Architecture Fix Implementation Plan

## Overview
Fix the UI freeze by separating the audio service (plain singleton) from UI state management (ObservableObject ViewModel).

## Phase 1: Create AudioPlayerViewModel ✅ START HERE

### Step 1.1: Create the ViewModel
Create `Core/ViewModels/AudioPlayerViewModel.swift`:

```swift
import Foundation
import Combine
import SwiftAudioEx

final class AudioPlayerViewModel: ObservableObject {
    // MARK: - Published UI State
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var playbackRate: Float = 1.0
    @Published var volume: Float = 1.0
    
    // Current item info
    @Published private(set) var currentTitle: String?
    @Published private(set) var currentArtist: String?
    @Published private(set) var currentArtwork: Data?
    
    // Queue info
    @Published private(set) var queueCount: Int = 0
    @Published private(set) var hasNext: Bool = false
    @Published private(set) var hasPrevious: Bool = false
    
    // For compatibility
    @Published var currentArticle: Article?
    
    // MARK: - Private Properties
    private let audioService = BriefeedAudioService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        // Will bind to audio service events once it's converted
        // For now, use a timer to poll state
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)
    }
    
    private func updateState() {
        // Poll audio service state
        // This is temporary until we convert the service
    }
    
    // MARK: - Public Methods
    func play() {
        audioService.play()
    }
    
    func pause() {
        audioService.pause()
    }
    
    func togglePlayPause() {
        audioService.togglePlayPause()
    }
    
    func next() {
        audioService.skipToNext()
    }
    
    func previous() {
        audioService.skipToPrevious()
    }
    
    func seek(to time: TimeInterval) {
        audioService.seek(to: time)
    }
}
```

### Step 1.2: Test with One View First
Update `MiniAudioPlayer.swift` to use the ViewModel:

```swift
struct MiniAudioPlayer: View {
    @StateObject private var viewModel = AudioPlayerViewModel()  // Changed from audioService
    // Rest of the view implementation
}
```

## Phase 2: Convert BriefeedAudioService to Plain Singleton

### Step 2.1: Create New Non-Observable Service
Create `Core/Services/Audio/BriefeedAudioCore.swift`:

```swift
import Foundation
import SwiftAudioEx
import Combine

final class BriefeedAudioCore {
    // MARK: - Singleton
    static let shared = BriefeedAudioCore()
    
    // MARK: - Properties
    private let audioPlayer: QueuedAudioPlayer
    private let ttsGenerator = TTSGenerator.shared
    private let cacheManager = AudioCacheManager.shared
    
    // Event publishers for ViewModel to subscribe to
    let playbackStatePublisher = PassthroughSubject<AudioPlayerState, Never>()
    let currentTimePublisher = PassthroughSubject<TimeInterval, Never>()
    let currentItemPublisher = PassthroughSubject<BriefeedAudioItem?, Never>()
    
    // MARK: - Initialization
    private init() {
        // Initialize immediately, no lazy loading
        let remoteCommandController = RemoteCommandController()
        self.audioPlayer = QueuedAudioPlayer(remoteCommandController: remoteCommandController)
        
        setupAudioSession()
        setupAudioPlayer()
        setupRemoteCommands()
    }
    
    // Rest of implementation without @Published properties
}
```

### Step 2.2: Migrate Functionality
- Move all audio logic from BriefeedAudioService to BriefeedAudioCore
- Remove all @Published properties
- Replace with event publishers that ViewModel can subscribe to

## Phase 3: Update All Views

### Step 3.1: Create Migration Map
Views that need updating:
- `ContentView.swift` - Remove audioService StateObject
- `MiniAudioPlayer.swift` - Use AudioPlayerViewModel
- `ExpandedAudioPlayer.swift` - Use AudioPlayerViewModel  
- `BriefView.swift` - Use AudioPlayerViewModel
- `ArticleRowView.swift` - Use AudioPlayerViewModel
- `LiveNewsView.swift` - Use AudioPlayerViewModel

### Step 3.2: Update Each View
Replace:
```swift
@StateObject private var audioService = BriefeedAudioService.shared
```

With:
```swift
@StateObject private var audioViewModel = AudioPlayerViewModel()
```

## Phase 4: Fix Service Dependencies

### Step 4.1: Update QueueServiceV2
- Change from accessing BriefeedAudioService.shared
- To accessing BriefeedAudioCore.shared
- Remove any @Published property dependencies

### Step 4.2: Update ArticleStateManager
- Same pattern: use the core service, not the observable one

## Phase 5: Testing Strategy

### Step 5.1: Incremental Testing
1. Start app - should not freeze on launch ✓
2. Play audio - should work without UI freeze ✓
3. Navigate tabs - should remain responsive ✓
4. Background/foreground - should maintain state ✓

### Step 5.2: Verification Checklist
- [ ] No "Publishing changes from within view updates" errors
- [ ] No UI freezes
- [ ] Audio controls work
- [ ] Queue management works
- [ ] Background audio works
- [ ] Remote commands work

## Implementation Order

1. **Create AudioPlayerViewModel first** (can coexist with current code)
2. **Test with MiniAudioPlayer only** (lowest risk)
3. **If successful, create BriefeedAudioCore**
4. **Migrate one view at a time**
5. **Remove old BriefeedAudioService last**

## Rollback Plan

Each phase can be rolled back independently:
- Phase 1: Delete ViewModel, revert MiniAudioPlayer
- Phase 2: Keep using BriefeedAudioService
- Phase 3: Revert views one by one
- Phase 4: Revert service changes
- Phase 5: If tests fail, identify which phase broke

## Success Criteria

1. App launches without freezing
2. All audio functionality works
3. No SwiftUI state management warnings
4. Clean architecture: Service → ViewModel → View

## Timeline Estimate

- Phase 1: 30 minutes (low risk, can test immediately)
- Phase 2: 1 hour (core refactoring)
- Phase 3: 45 minutes (mechanical changes)
- Phase 4: 30 minutes (update dependencies)
- Phase 5: 30 minutes (testing)

Total: ~3 hours for complete fix

## Start Command

Begin with Phase 1, Step 1.1:
```bash
# Create the ViewModel
touch Briefeed/Core/ViewModels/AudioPlayerViewModel.swift
```

Then implement the basic ViewModel and test with MiniAudioPlayer only. This is the safest first step.