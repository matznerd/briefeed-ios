# Full Cutover Migration Plan

## Status: IN PROGRESS

### ✅ Completed
1. **BriefeedApp.swift**
   - Removed `@StateObject private var queueService = QueueService.shared` (ANTI-PATTERN!)
   - Added `@StateObject private var audioPlayerViewModel = AudioPlayerViewModel()`
   - Initialize V2 services in Task (async, no UI freeze)
   - Pass audioPlayerViewModel as environmentObject

2. **ContentView.swift**
   - Replaced `@ObservedObject private var audioService = AudioService.shared`
   - Added `@EnvironmentObject var audioPlayerViewModel: AudioPlayerViewModel`
   - Updated MiniAudioPlayer to MiniAudioPlayerV3

3. **MiniAudioPlayerV3.swift** (NEW)
   - Uses AudioPlayerViewModel from environment
   - No direct service access
   - Proper architecture

### 🔄 In Progress

4. **ArticleRowView.swift** - Needs update
   - Replace AudioService.shared references
   - Replace QueueService.shared references
   - Use AudioPlayerViewModel for playback

5. **BriefView.swift** - Needs update
   - Replace all service references
   - Use AudioPlayerViewModel

6. **LiveNewsView.swift** - Needs update
   - Heavy service usage, needs complete refactor

### 📝 TODO

7. **ExpandedAudioPlayer.swift**
   - Create ExpandedAudioPlayerV2 using AudioPlayerViewModel

8. **CombinedFeedView.swift**
   - Update to use new architecture

9. **BriefViewModel.swift**
   - Update to use V2 services

10. **ArticleViewModel.swift**
    - Update to use V2 services

### Migration Pattern

#### OLD (CAUSES FREEZE):
```swift
@ObservedObject private var audioService = AudioService.shared
@ObservedObject private var queueService = QueueService.shared
```

#### NEW (NO FREEZE):
```swift
@EnvironmentObject var audioPlayerViewModel: AudioPlayerViewModel
```

### Service Access Pattern

#### OLD:
```swift
// Direct service access
AudioService.shared.play(article: article)
QueueService.shared.addToQueue(article: article)
```

#### NEW:
```swift
// Through ViewModel
await audioPlayerViewModel.play(article: article)
await audioPlayerViewModel.queueArticle(article)
```

### Key Files to Update

| File | Old Service | New Approach | Status |
|------|------------|--------------|--------|
| BriefeedApp.swift | QueueService.shared | AudioPlayerViewModel | ✅ |
| ContentView.swift | AudioService.shared | AudioPlayerViewModel | ✅ |
| MiniAudioPlayer.swift | Both services | MiniAudioPlayerV3 | ✅ |
| ArticleRowView.swift | Both services | AudioPlayerViewModel | 🔄 |
| BriefView.swift | Both services | AudioPlayerViewModel | 📝 |
| LiveNewsView.swift | All services | AudioPlayerViewModel | 📝 |
| ExpandedAudioPlayer.swift | AudioService.shared | ExpandedAudioPlayerV2 | 📝 |

### Testing Checklist

- [ ] App launches without freeze
- [ ] Audio playback works
- [ ] Queue management works
- [ ] Mini player shows correct state
- [ ] Expanded player works
- [ ] Article interactions work
- [ ] RSS playback works
- [ ] Live News mode works

### Final Steps

1. Remove old service files:
   - AudioService.swift
   - QueueService.swift
   - ArticleStateManager.swift

2. Remove old UI files:
   - MiniAudioPlayer.swift (replaced by V3)
   - ExpandedAudioPlayer.swift (replaced by V2)

3. Run full test suite

4. Verify no 11.5-second freeze!