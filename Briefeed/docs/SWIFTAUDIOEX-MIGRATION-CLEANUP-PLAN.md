# SwiftAudioEx Migration & Cleanup Plan

## Current State Analysis

### Active Audio Systems (Multiple!)
1. **OLD AudioService** (`AudioService.swift`) - Still being used by ArticleViewModel
2. **AudioServiceV2** (`AudioServiceV2.swift`) - Part of freeze fix, uses AVSpeechSynthesizer
3. **BriefeedAudioService** (`BriefeedAudioService.swift`) - Another service
4. **AudioStreamingService.swift.disabled** - Disabled SwiftAudioEx implementation
5. **NEW SwiftAudioExService** (`SwiftAudioExService.swift`) - Just created, not active

### This is a mess! We have 5 different audio systems!

## Migration Phases

### Phase 1: Preparation (Current)
✅ Write tests for SwiftAudioEx
✅ Create SwiftAudioExService skeleton
⬜ Create feature flag for gradual rollout

### Phase 2: Parallel Implementation
1. Enable SwiftAudioEx in SwiftAudioExService
2. Make all tests pass
3. Add feature flag to switch between old and new

```swift
// In UserDefaultsManager
var useSwiftAudioEx: Bool {
    get { UserDefaults.standard.bool(forKey: "useSwiftAudioEx") }
    set { UserDefaults.standard.set(newValue, forKey: "useSwiftAudioEx") }
}
```

### Phase 3: Integration
1. Update AudioPlayerViewModel to use SwiftAudioExService when flag is ON
2. Update AppViewModel to check feature flag
3. Test with flag ON in development

### Phase 4: Migration
1. Enable flag by default for new installs
2. Gradually enable for existing users
3. Monitor for issues

### Phase 5: Cleanup (CRITICAL!)

## Files to Remove

### Immediate Removal List (After SwiftAudioEx is working)

```bash
# Old Services (5 different audio systems!)
Briefeed/Core/Services/AudioService.swift                    # Old singleton
Briefeed/Core/Services/AudioService+RSS.swift               # Old RSS extension
Briefeed/Core/Services/Audio/AudioServiceV2.swift           # Freeze fix version
Briefeed/Core/Services/Audio/BriefeedAudioService.swift     # Another variant
Briefeed/Core/Services/Audio/AudioServiceAdapter.swift      # Adapter pattern
Briefeed/Core/Services/Audio/AudioStreamingService.swift.disabled  # Can remove or update

# Old Queue Services
Briefeed/Core/Services/QueueService.swift                   # Old queue
Briefeed/Core/Services/QueueService+RSS.swift              # Old RSS queue

# Old State Managers
Briefeed/Core/Models/ArticleStateManager.swift             # Old state manager

# Old Audio Players
Briefeed/Features/Audio/MiniAudioPlayer.swift              # V1
Briefeed/Features/Audio/MiniAudioPlayerV2.swift            # V2
Briefeed/Features/Audio/ExpandedAudioPlayer.swift          # V1

# Old ViewModels (that use old services)
Briefeed/Core/ViewModels/ArticleViewModel.swift            # Uses old AudioService!
Briefeed/Core/ViewModels/BriefViewModel.swift             # May use old services
```

### Keep These (Updated Versions)
```bash
# New Services
Briefeed/Core/Services/Audio/SwiftAudioExService.swift     # NEW - SwiftAudioEx
Briefeed/Core/Services/QueueServiceV2.swift                # Keep V2

# New State Manager
Briefeed/Core/Models/ArticleStateManagerV2.swift           # Keep V2

# New Audio Players
Briefeed/Features/Audio/MiniAudioPlayerV3.swift            # Keep V3
Briefeed/Features/Audio/ExpandedAudioPlayerV2.swift        # Keep V2

# ViewModels
Briefeed/Core/ViewModels/AudioPlayerViewModel.swift        # Update to use SwiftAudioEx
Briefeed/Core/ViewModels/AppViewModel.swift                # Update to use SwiftAudioEx
```

## Cleanup Script

```bash
#!/bin/bash
# cleanup-old-audio.sh

echo "🧹 Cleaning up old audio implementation..."

# Create backup
BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

# Files to remove
OLD_FILES=(
    "Briefeed/Core/Services/AudioService.swift"
    "Briefeed/Core/Services/AudioService+RSS.swift"
    "Briefeed/Core/Services/Audio/AudioServiceV2.swift"
    "Briefeed/Core/Services/Audio/BriefeedAudioService.swift"
    "Briefeed/Core/Services/Audio/AudioServiceAdapter.swift"
    "Briefeed/Core/Services/QueueService.swift"
    "Briefeed/Core/Services/QueueService+RSS.swift"
    "Briefeed/Core/Models/ArticleStateManager.swift"
    "Briefeed/Features/Audio/MiniAudioPlayer.swift"
    "Briefeed/Features/Audio/MiniAudioPlayerV2.swift"
    "Briefeed/Features/Audio/ExpandedAudioPlayer.swift"
)

# Backup files
echo "📦 Creating backup..."
for file in "${OLD_FILES[@]}"; do
    if [ -f "$file" ]; then
        cp "$file" "$BACKUP_DIR/"
        echo "  Backed up: $file"
    fi
done

# Remove files
echo "🗑️ Removing old files..."
for file in "${OLD_FILES[@]}"; do
    if [ -f "$file" ]; then
        rm "$file"
        echo "  Removed: $file"
    fi
done

echo "✅ Cleanup complete! Backup saved to: $BACKUP_DIR"
```

## Dependency Check

Before removing files, check for dependencies:

```bash
# Check what's using AudioService
grep -r "AudioService.shared" --include="*.swift" .
grep -r "import.*AudioService" --include="*.swift" .

# Check what's using old ViewModels
grep -r "ArticleViewModel" --include="*.swift" .
```

## Update References

### ArticleView.swift
- Already updated to use AppViewModel ✅

### Other Views
Need to check and update:
- LiveNewsView
- CombinedFeedView
- Any other views using old services

## Testing Checklist Before Cleanup

- [ ] SwiftAudioEx tests all pass
- [ ] App launches without crashes
- [ ] Article playback works
- [ ] RSS playback works
- [ ] Queue management works
- [ ] Background playback works
- [ ] Speed control up to 20x works
- [ ] Seeking works
- [ ] Mini player updates properly
- [ ] Expanded player shows correct info
- [ ] No memory leaks
- [ ] State persistence works

## Rollback Plan

If issues occur after cleanup:
1. Restore from backup directory
2. Re-add files to Xcode project
3. Clean and rebuild
4. Revert git commit if needed

## Timeline

- **Week 1**: Implement SwiftAudioEx, make tests pass
- **Week 2**: Feature flag testing
- **Week 3**: Gradual rollout
- **Week 4**: **CLEANUP** - Remove all old code

## Success Metrics

Before cleanup:
- 5 different audio systems
- ~10,000 lines of redundant code
- Confusing architecture

After cleanup:
- 1 unified audio system (SwiftAudioEx)
- ~2,000 lines of clean code
- Clear architecture

## Important Notes

1. **DO NOT** remove files until SwiftAudioEx is fully working
2. **DO NOT** remove without backup
3. **DO NOT** remove without testing
4. **DO** use feature flags for safe rollout
5. **DO** remove ALL old implementations - don't leave any behind

## Final Architecture

```
SwiftAudioExService (Audio playback)
    ↓
UnifiedAudioPlayer (Orchestration)
    ↓
AudioPlayerViewModel (UI State)
    ↓
AppViewModel (App-wide state)
    ↓
Views (MiniPlayerV3, ExpandedPlayerV2)
```

## Verification Command

After cleanup, this should return 0:
```bash
find . -name "AudioService.swift" -o -name "AudioServiceV2.swift" -o -name "BriefeedAudioService.swift" | wc -l
```

## Git Commit Structure

```bash
# Separate commits for traceability
git add SwiftAudioExService.swift
git commit -m "feat: Add SwiftAudioEx implementation"

git add [test files]
git commit -m "test: Add SwiftAudioEx integration tests"

git rm [old files]
git commit -m "cleanup: Remove old audio implementation (5 systems -> 1)"
```