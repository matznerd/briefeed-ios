# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Briefeed is an iOS app built with SwiftUI that provides an RSS feed reader with unique audio playback capabilities. The app allows users to manage RSS feeds, queue articles for reading, and listen to AI-generated summaries of articles using text-to-speech.

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
- **Navigation**: `ContentView.swift` - Tab-based navigation with Feed, Brief (queue), and Settings tabs
- **Persistence**: `Persistence.swift` - Core Data stack management
- **Audio Player**: Always-visible mini player at bottom of screen

### Key Services

1. **QueueService** (`Core/Services/QueueService.swift`): 
   - Manages persistent audio queue across app launches
   - Syncs with AudioService for playback
   - Handles background audio generation for queued articles

2. **AudioService** (`Core/Services/AudioService.swift`):
   - Handles audio playback using AVSpeechSynthesizer
   - Manages playback state, speed, and queue
   - Provides UI state updates via @Published properties

3. **GeminiService** (`Core/Services/GeminiService.swift`):
   - Integrates with Google's Gemini API for article summarization
   - Handles API communication and error handling

4. **FirecrawlService** (`Core/Services/FirecrawlService.swift`):
   - Scrapes article content from URLs
   - Provides clean text extraction for summarization

5. **StorageService** (`Core/Services/StorageService.swift`):
   - Manages article storage and archiving
   - Handles article state management

### Feature Organization

Features are organized by domain:
- **Article/**: Article list, reader, and summary views
- **Audio/**: Audio player UI components
- **Brief/**: Queue management and playlist views
- **Feed/**: RSS feed management and article fetching
- **Settings/**: App preferences and configuration

### State Management

- **UserDefaultsManager**: Singleton for app settings (theme, playback speed, etc.)
- **Core Data**: For persistent storage of feeds and articles
- **@StateObject/@ObservedObject**: For reactive UI updates
- **Combine**: For reactive programming patterns

### Key Models

- **Article**: Core Data entity for RSS articles
- **Feed**: Core Data entity for RSS feeds
- **ArticleSummary**: Struct for AI-generated summaries
- **QueuedItem**: Persistent queue item structure

## Important Implementation Details

1. **Audio Session**: Configured for spoken audio with mix-with-others capability
2. **Theme Management**: Dark/light mode preference applied at window level
3. **Queue Persistence**: Queue state saved to UserDefaults and restored on app launch
4. **Background Processing**: Articles in queue have summaries generated in background
5. **Error Handling**: Services use async/await with proper error propagation

## UI Components

- **MarqueeText**: Scrolling text for long titles
- **WaveformView**: Audio visualization during playback
- **LoadingButton**: Button with loading state
- **SpeedPicker**: Playback speed selection

## Testing

The project includes both unit tests (`BriefeedTests/`) and UI tests (`BriefeedUITests/`). Run tests through Xcode or using xcodebuild commands above.