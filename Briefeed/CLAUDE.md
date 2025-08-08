# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ✅ Audio System Migration Complete

The audio system migration from the old AudioService to BriefeedAudioService has been successfully completed.

### Migration Summary
- ✅ Old AudioService removed (AVAudioSession error -50 fixed)
- ✅ New BriefeedAudioService fully integrated
- ✅ QueueServiceV2 managing queue operations
- ✅ All feature flags removed
- ✅ Build succeeds with new architecture

---

## Project Overview

Briefeed is an iOS app built with SwiftUI that provides an RSS feed reader with unique audio playback capabilities. The app allows users to manage RSS feeds, queue articles for reading, and listen to AI-generated summaries of articles using text-to-speech. 

The app now includes a Live News feature that works like a radio - automatically playing the latest RSS podcast episodes from your configured feeds with a single tap.

## Build and Development Commands

This is a native iOS project using Xcode. Common commands:

```bash
# Open project in Xcode
open Briefeed.xcodeproj

# Build from command line
xcodebuild -project Briefeed.xcodeproj -scheme Briefeed -configuration Debug build

# Run tests
xcodebuild test -project Briefeed.xcodeproj -scheme Briefeed -destination 'platform=iOS Simulator,name=iPhone 15'

# Clean build folder
xcodebuild clean -project Briefeed.xcodeproj -scheme Briefeed
```

## Architecture Overview

### Core Structure

The app follows a clean architecture pattern with clear separation of concerns:

- **App Entry**: `BriefeedApp.swift` - Main app entry point, handles app lifecycle, theme management, and Core Data initialization
- **Navigation**: `ContentView.swift` - Tab-based navigation with Feed, Brief (queue), Live News, and Settings tabs
- **Persistence**: `Persistence.swift` - Core Data stack management
- **Audio Player**: Always-visible mini player at bottom of screen

### Key Services

#### Audio Services
- **BriefeedAudioService** (`Core/Services/Audio/BriefeedAudioService.swift`):
  - Modern SwiftAudioEx-based audio service
  - Handles article TTS and RSS episode playback
  - Manages playback state and controls
  - Supports background audio with remote commands

#### Other Services

1. **QueueServiceV2** (`Core/Services/QueueServiceV2.swift`): 
   - Manages persistent audio queue across app launches
   - Syncs with BriefeedAudioService for playback
   - Handles background audio generation for queued articles
   - Unified queue management for articles and RSS episodes

2. **GeminiService** (`Core/Services/GeminiService.swift`):
   - Integrates with Google's Gemini API for article summarization
   - Handles API communication and error handling

4. **FirecrawlService** (`Core/Services/FirecrawlService.swift`):
   - Scrapes article content from URLs
   - Provides clean text extraction for summarization

5. **StorageService** (`Core/Services/StorageService.swift`):
   - Manages article storage and archiving
   - Handles article state management

6. **RSSAudioService** (`Core/Services/RSS/RSSAudioService.swift`):
   - Manages RSS podcast feeds and episodes
   - Handles feed parsing and updates
   - Tracks episode listen status

### Feature Organization

Features are organized by domain:
- **Article/**: Article list, reader, and summary views
- **Audio/**: Audio player UI components
- **Brief/**: Queue management and playlist views
- **Feed/**: RSS feed management and article fetching
- **LiveNews/**: RSS podcast feed management and radio-like playback
- **Settings/**: App preferences and configuration

### State Management

- **UserDefaultsManager**: Singleton for app settings (theme, playback speed, etc.)
- **Core Data**: For persistent storage of feeds and articles
- **@StateObject/@ObservedObject**: For reactive UI updates
- **Combine**: For reactive programming patterns

### Key Models

- **Article**: Core Data entity for RSS articles
- **Feed**: Core Data entity for RSS feeds
- **RSSFeed**: Core Data entity for RSS podcast feeds
- **RSSEpisode**: Core Data entity for RSS podcast episodes
- **ArticleSummary**: Struct for AI-generated summaries
- **QueuedItem**: Persistent queue item structure
- **EnhancedQueueItem**: Unified queue item supporting both articles and RSS episodes

## Important Implementation Details

1. **Audio Session**: Configured for spoken audio (being fixed in migration)
2. **Theme Management**: Dark/light mode preference applied at window level
3. **Queue Persistence**: Queue state saved to UserDefaults and restored on app launch
4. **Background Processing**: Articles in queue have summaries generated in background
5. **Error Handling**: Services use async/await with proper error propagation
6. **RSS Radio Mode**: "Play Live News" button queues only latest unlistened episodes from each feed
7. **Auto-play**: Optional auto-play on app launch for radio-like experience
8. **Episode Management**: Listened episodes are automatically removed from queue

## UI Components

- **MarqueeText**: Scrolling text for long titles
- **WaveformView**: Audio visualization during playback
- **LoadingButton**: Button with loading state
- **SpeedPicker**: Playback speed selection

## Testing

The project includes both unit tests (`BriefeedTests/`) and UI tests (`BriefeedUITests/`). Run tests through Xcode or using xcodebuild commands above.

## Known Issues

None currently. The audio system migration has been completed successfully.

## Important Instructions

- Do what has been asked; nothing more, nothing less.
- NEVER create files unless they're absolutely necessary for achieving your goal.
- ALWAYS prefer editing an existing file to creating a new one.
- NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.