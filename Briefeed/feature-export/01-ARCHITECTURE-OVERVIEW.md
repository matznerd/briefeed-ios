# Briefeed Architecture Overview

## Application Structure

Briefeed is a native iOS application built with SwiftUI that provides RSS feed reading with AI-powered summaries and text-to-speech capabilities.

### Core Architecture Pattern
- **MVVM (Model-View-ViewModel)** with SwiftUI
- **Singleton Services** for shared functionality
- **Core Data** for persistence
- **Combine** for reactive programming

## Key Components

### 1. Entry Points
- `BriefeedApp.swift` - Main app entry, lifecycle management, theme handling
- `ContentView.swift` - Tab-based navigation (Feed, Brief, Live News, Settings)

### 2. Data Layer
- **Core Data Stack** (`Persistence.swift`)
  - Article entity
  - Feed entity  
  - RSSFeed entity
  - RSSEpisode entity
  - UserPreferences entity

### 3. Service Layer
Services are organized as singletons:

#### Audio Services
- `BriefeedAudioService` - Modern SwiftAudioEx-based playback
- `GeminiTTSService` - Text-to-speech generation using Gemini API
- `RSSAudioService` - RSS podcast management

#### Content Services  
- `RedditService` - Reddit JSON API integration
- `FirecrawlService` - Web scraping for article content
- `GeminiService` - AI summarization
- `QueueServiceV2` - Queue management and persistence

#### Support Services
- `NetworkService` - Network requests wrapper
- `StorageService` - Article storage management
- `ProcessingStatusService` - UI status updates
- `DefaultDataService` - Content filtering

### 4. State Management
- `UserDefaultsManager` - Settings persistence
- `AppViewModel` - Main app state
- View-specific ViewModels for complex screens

## Data Flow

### Article Processing Pipeline
1. **Feed Source** → Reddit API or RSS feed
2. **Content Fetching** → FirecrawlService scrapes article
3. **Summarization** → GeminiService generates summary
4. **Audio Generation** → GeminiTTSService creates speech
5. **Queue Management** → QueueServiceV2 handles playback order
6. **Playback** → BriefeedAudioService plays audio

### State Synchronization
- Queue state persisted to UserDefaults
- Audio playback state shared via @Published properties
- Core Data for persistent article/feed storage

## Current Issues

### UI Freeze Problem
The app experiences UI freezes during:
- Queue operations
- Audio service synchronization
- View rendering with large datasets

### Root Causes Identified
1. Main thread blocking during sync operations
2. Excessive re-renders from state changes
3. Synchronous Core Data operations
4. Heavy computations in view body methods

## File Organization

```
Briefeed/
├── App/
│   ├── BriefeedApp.swift
│   └── ContentView.swift
├── Core/
│   ├── Services/
│   │   ├── Audio/
│   │   ├── RSS/
│   │   └── [Service files]
│   ├── ViewModels/
│   ├── Models/
│   └── Utils/
├── Features/
│   ├── Article/
│   ├── Audio/
│   ├── Brief/
│   ├── Feed/
│   ├── LiveNews/
│   └── Settings/
└── Resources/