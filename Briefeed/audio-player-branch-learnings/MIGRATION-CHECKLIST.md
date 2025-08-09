# AudioStreaming Migration Checklist

## Pre-Migration Verification

### ✅ Confirm Current State
- [ ] Current branch is clean (no uncommitted changes)
- [ ] All tests pass on current branch
- [ ] App runs without crashes (even if frozen)
- [ ] Create new branch: `feature/audiostreaming-migration`

### ✅ Document Current Issues
- [ ] List all known UI freezes
- [ ] Note performance metrics (launch time, etc.)
- [ ] Screenshot current audio player UI
- [ ] Save current build size

## Phase 1: Architecture Audit (Day 1)

### ✅ Service Audit
Check each service for anti-patterns:

#### ArticleStateManager
- [ ] Is it @MainActor? (Remove if yes)
- [ ] Is it ObservableObject? (Remove if yes)
- [ ] Heavy work in init()? (Move to initialize())
- [ ] Has @Published properties? (Move to ViewModel)

#### ProcessingStatusService
- [ ] Is it @MainActor? (Remove if yes)
- [ ] Is it ObservableObject? (Remove if yes)
- [ ] Heavy work in init()? (Move to initialize())
- [ ] Has @Published properties? (Move to ViewModel)

#### RSSAudioService
- [ ] Is it @MainActor? (Remove if yes)
- [ ] Is it ObservableObject? (Remove if yes)
- [ ] Heavy work in init()? (Move to initialize())
- [ ] Has @Published properties? (Move to ViewModel)

#### QueueServiceV2
- [ ] Is it @MainActor? (Remove if yes)
- [ ] Is it ObservableObject? (Remove if yes)
- [ ] Heavy work in init()? (Move to initialize())
- [ ] Has @Published properties? (Move to ViewModel)

### ✅ View Audit
Check each view for anti-patterns:

#### ContentView
- [ ] Remove @StateObject with .shared references
- [ ] Add @StateObject for new ViewModel
- [ ] Add .task for initialization
- [ ] Remove service access from init()

#### MiniAudioPlayer
- [ ] Remove @StateObject with .shared references
- [ ] Change to @EnvironmentObject
- [ ] Remove direct service calls
- [ ] Use ViewModel methods instead

#### ExpandedAudioPlayer
- [ ] Remove @StateObject with .shared references
- [ ] Change to @EnvironmentObject
- [ ] Remove direct service calls
- [ ] Use ViewModel methods instead

## Phase 2: Remove SwiftAudioEx (Day 2)

### ✅ Package Removal
- [ ] Remove SwiftAudioEx from Package.swift
- [ ] Run `xcodebuild -resolvePackageDependencies`
- [ ] Clean build folder
- [ ] Delete DerivedData

### ✅ Code Cleanup
- [ ] Remove all `import SwiftAudioEx` statements
- [ ] Comment out BriefeedAudioService temporarily
- [ ] Comment out audio UI temporarily
- [ ] Ensure app builds (even without audio)

### ✅ Add AudioStreaming
```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/dimitris-c/AudioStreaming.git", from: "2.0.0")
]
```
- [ ] Add dependency
- [ ] Run `xcodebuild -resolvePackageDependencies`
- [ ] Verify package downloaded

## Phase 3: Implement Core Service (Day 3)

### ✅ Create AudioStreamingService.swift
```swift
import AudioStreaming

final class AudioStreamingService {
    static let shared = AudioStreamingService()
    
    private let audioPlayer: AudioPlayer
    
    private init() {
        self.audioPlayer = AudioPlayer()
    }
    
    func initialize() async {
        // TODO: Add initialization
    }
}
```
- [ ] Create file
- [ ] Add basic structure
- [ ] Verify builds

### ✅ Add Core Methods
- [ ] play(url:)
- [ ] pause()
- [ ] resume()
- [ ] stop()
- [ ] seek(to:)
- [ ] queue(url:)

### ✅ Add Audio Session Configuration
- [ ] Configure AVAudioSession
- [ ] Set category to .playback
- [ ] Enable background audio
- [ ] Handle interruptions

## Phase 4: Implement ViewModel (Day 4)

### ✅ Create AudioPlayerViewModel.swift
```swift
@MainActor
final class AudioPlayerViewModel: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    
    private var audioService: AudioStreamingService?
    
    init() {
        // Lightweight
    }
    
    func connect() async {
        self.audioService = AudioStreamingService.shared
        await audioService?.initialize()
    }
}
```
- [ ] Create file
- [ ] Add @Published properties
- [ ] Add connect() method
- [ ] Add playback control methods

### ✅ Implement AudioPlayerDelegate
- [ ] Add delegate conformance
- [ ] Handle state changes
- [ ] Update @Published properties
- [ ] Use Task { @MainActor in }

### ✅ Add Update Timer
- [ ] Create Timer for progress updates
- [ ] Update every 0.5 seconds
- [ ] Only update if values changed
- [ ] Clean up timer on deinit

## Phase 5: Update AppViewModel (Day 5)

### ✅ Remove Anti-Patterns
- [ ] Remove @MainActor from class
- [ ] Remove service singletons from properties
- [ ] Remove @Published for audio state
- [ ] Remove heavy init work

### ✅ Add ViewModel Integration
- [ ] Add audioViewModel property
- [ ] Connect in .task, not init
- [ ] Proxy audio methods to ViewModel
- [ ] Remove direct service access

### ✅ Fix Service Connections
```swift
func connectToServices() async {
    // Essential services only
    await connectEssentialServices()
    
    // Defer non-essential
    Task {
        await connectDeferredServices()
    }
}
```
- [ ] Split essential vs deferred
- [ ] Remove .value awaits
- [ ] Add proper error handling
- [ ] Add timing logs

## Phase 6: Update Views (Day 6)

### ✅ Update BriefeedApp
```swift
@main
struct BriefeedApp: App {
    @StateObject private var audioViewModel = AudioPlayerViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioViewModel)
        }
    }
}
```
- [ ] Add @StateObject audioViewModel
- [ ] Add .environmentObject
- [ ] Remove old audio references

### ✅ Update ContentView
- [ ] Remove audio service @StateObject
- [ ] Add @EnvironmentObject audioViewModel
- [ ] Add .task { await audioViewModel.connect() }
- [ ] Update audio UI bindings

### ✅ Update MiniAudioPlayer
- [ ] Change to @EnvironmentObject
- [ ] Update all bindings
- [ ] Use ViewModel methods
- [ ] Test play/pause

### ✅ Update ExpandedAudioPlayer
- [ ] Change to @EnvironmentObject
- [ ] Update all bindings
- [ ] Use ViewModel methods
- [ ] Test all controls

## Phase 7: Queue Integration (Day 7)

### ✅ Update QueueServiceV2
- [ ] Remove ObservableObject
- [ ] Remove @Published
- [ ] Update to use AudioStreaming
- [ ] Fix queue persistence

### ✅ Create QueueViewModel
- [ ] Add @Published queue properties
- [ ] Connect to QueueService
- [ ] Handle queue updates
- [ ] Sync with AudioPlayerViewModel

### ✅ Update Queue UI
- [ ] Update BriefView
- [ ] Fix queue item views
- [ ] Test add/remove/reorder
- [ ] Verify persistence

## Phase 8: Feature Integration (Day 8)

### ✅ TTS Integration
- [ ] Update TTSGenerator for AudioStreaming
- [ ] Test article audio generation
- [ ] Verify caching works
- [ ] Test queue integration

### ✅ RSS Integration
- [ ] Update for streaming URLs
- [ ] Test episode playback
- [ ] Verify metadata parsing
- [ ] Test Live News feature

### ✅ Remote Commands
- [ ] Setup MPRemoteCommandCenter
- [ ] Handle play/pause
- [ ] Handle next/previous
- [ ] Update Now Playing info

## Phase 9: Testing (Day 9)

### ✅ Performance Tests
```swift
func testServiceInitTime() {
    measure {
        _ = AudioStreamingService.shared
    }
    // Should be <10ms
}
```
- [ ] Service init time <10ms
- [ ] ViewModel init time <1ms
- [ ] No main thread blocks
- [ ] 60fps scrolling

### ✅ UI Tests
- [ ] App launches <1 second
- [ ] Tabs respond immediately
- [ ] Audio controls work
- [ ] No freezes during playback

### ✅ Integration Tests
- [ ] Queue persistence
- [ ] Background playback
- [ ] Interruption handling
- [ ] Remote commands

### ✅ Regression Tests
- [ ] All existing features work
- [ ] No new crashes
- [ ] Memory usage acceptable
- [ ] Battery usage reasonable

## Phase 10: Cleanup (Day 10)

### ✅ Remove Old Code
- [ ] Delete old BriefeedAudioService
- [ ] Remove SwiftAudioEx remnants
- [ ] Clean up commented code
- [ ] Remove debug logs

### ✅ Documentation
- [ ] Update CLAUDE.md
- [ ] Document new architecture
- [ ] Add inline comments
- [ ] Update README if needed

### ✅ Final Verification
- [ ] Run all tests
- [ ] Check for warnings
- [ ] Run SwiftLint
- [ ] Profile with Instruments

## Post-Migration Monitoring

### ✅ Week 1 Metrics
- [ ] Crash rate (should be 0%)
- [ ] UI freeze reports (should be 0)
- [ ] Performance metrics
- [ ] User feedback

### ✅ Week 2 Stability
- [ ] Memory leaks check
- [ ] Battery usage analysis
- [ ] Network usage review
- [ ] Error rate tracking

### ✅ Week 3 Optimization
- [ ] Identify bottlenecks
- [ ] Optimize slow paths
- [ ] Reduce memory usage
- [ ] Improve error handling

## Success Criteria

### Must Have ✅
- [ ] **NO UI FREEZES**
- [ ] App launches <1 second
- [ ] Service init <10ms
- [ ] Playback works reliably
- [ ] Queue persistence works

### Should Have 🎯
- [ ] Smooth animations
- [ ] Background playback
- [ ] Remote commands
- [ ] Error recovery
- [ ] Progress tracking

### Nice to Have 🌟
- [ ] Gapless playback
- [ ] Advanced caching
- [ ] Offline support
- [ ] Analytics
- [ ] A/B testing ready

## Emergency Rollback Plan

If critical issues found:

1. **Hour 1**: Assess impact
   - [ ] Check crash reports
   - [ ] Monitor user complaints
   - [ ] Test core features

2. **Hour 2**: Decision point
   - [ ] If >5% users affected → rollback
   - [ ] If core feature broken → rollback
   - [ ] If data loss risk → rollback

3. **Rollback Steps**:
   ```bash
   git checkout main
   git revert --no-commit HEAD~10..HEAD
   git commit -m "Revert AudioStreaming migration"
   git push
   ```

4. **Post-Rollback**:
   - [ ] Document issues found
   - [ ] Plan fixes
   - [ ] Schedule retry
   - [ ] Communicate with team

## Notes Section

### Lessons from Previous Attempt:
1. **Never mix Singleton + ObservableObject**
2. **Never do heavy work in init()**
3. **Always initialize services after view construction**
4. **Keep Services and ViewModels separate**
5. **Test on slowest device early**

### Key Contacts:
- Architecture questions: Team Lead
- AudioStreaming issues: GitHub Issues
- Performance concerns: iOS Team
- User feedback: Support Team

### Resources:
- [AudioStreaming Documentation](https://github.com/dimitris-c/AudioStreaming)
- [SwiftUI Best Practices](https://developer.apple.com/documentation/swiftui)
- [AVAudioEngine Guide](https://developer.apple.com/documentation/avfaudio/avaudioengine)

---

**Remember: Take it slow, test each phase thoroughly, and don't skip steps!**