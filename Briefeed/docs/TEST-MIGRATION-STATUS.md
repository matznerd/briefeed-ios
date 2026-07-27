# Test Suite Migration Status

## Overview
The test suite needs to be updated to reflect the new audio architecture after migrating from the old Singleton + ObservableObject pattern to the new SwiftAudioEx-based system.

## Test Files Requiring Updates

### ✅ Partially Fixed
- **ArchitectureSafetyTests.swift**
  - Fixed: Changed `AudioPlayerViewModel` to `AudioPlayerViewModelV2` (lines 70, 154, 177)
  - Still tests for AudioServiceV2, QueueServiceV2, ArticleStateManagerV2 which exist

### ❌ Need Fixing - References to AudioPlayerViewModel
- **MixedQueueBriefTests.swift** (line 573)
- **PersistentMiniPlayerTests.swift** (lines 396, 426, 480)
- **RSSAudioPlaybackTests.swift** (line 442)
- **TextArticleInteractionTests.swift** (line 355)

### ❌ Need Fixing - References to non-existent services
- **ServiceArchitectureTests.swift**
  - References `BriefeedAudioService` (doesn't exist)
  - References `AudioStreamingService` (doesn't exist)
- **SpeedControlTests.swift**
  - References `AudioStreamingService` (doesn't exist)

### ❌ Need Fixing - API Changes
- **SwiftAudioExBasicTests.swift**
  - `TTSGeneratorService` has no member 'cacheSize'
  - `UnifiedAudioPlayer` initializer is private
- **SwiftAudioExIntegrationTests.swift**
  - `UnifiedAudioPlayer` initializer is private
  - Incorrect method signatures (play(article:) vs play(at:))
  - Missing properties: currentTitle, currentAudioURL, isStreaming

### ❌ Other Issues
- **TTSAudioTests.swift** - Duplicate TTSError declaration
- **TTSFileGenerationTests.swift** - Extension contains stored properties
- **NetworkServiceTests.swift** - Invalid override methods
- **RedditServiceTests.swift** - Invalid override methods, missing imports

## Components Removed in Migration

### Old Components (Deleted)
- AudioService.swift
- AudioService+RSS.swift
- QueueService.swift
- QueueService+RSS.swift
- AudioPlayerViewModel.swift
- BriefeedAudioService (never existed?)
- AudioStreamingService (never existed?)

### New Components (Current)
- AudioPlayerViewModelV2.swift
- UnifiedAudioPlayer.swift (private init)
- AudioServiceV2.swift (plain singleton)
- QueueServiceV2.swift (plain singleton)
- SwiftAudioExService.swift
- TTSGeneratorService.swift

## Test Strategy

### Option 1: Minimal Fix (Recommended)
1. Comment out or delete tests for non-existent services
2. Update references from AudioPlayerViewModel to AudioPlayerViewModelV2
3. Fix API changes in UnifiedAudioPlayer tests
4. Run basic smoke tests

### Option 2: Full Test Suite Update
1. Rewrite tests to match new architecture
2. Add new tests for SwiftAudioEx integration
3. Add tests for hybrid TTS (Gemini + AVSpeech)
4. Full regression testing

## Next Steps
1. Fix compilation errors in test files
2. Run test suite to identify runtime issues
3. Update tests to reflect new architecture patterns
4. Add tests for new features (20x speed, hybrid TTS)