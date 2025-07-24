# Briefeed App Feature Mapping

## Overview
Briefeed is a comprehensive iOS RSS reader app with audio playback capabilities, built using SwiftUI and following clean architecture principles.

## Core Features

### 1. RSS Feed Management
- **Add/Edit/Delete Feeds**: Users can manage traditional RSS feeds
- **Feed Categories**: Organize feeds by type
- **Feed Refresh**: Pull-to-refresh functionality
- **Combined Feed View**: View articles from all feeds in one place

### 2. Article Management
- **Article List**: Browse articles with filtering options
- **Article Reader**: In-app reader with web content
- **Save/Archive**: Save articles for later reading
- **Share**: Share articles via iOS share sheet

### 3. AI-Powered Summaries
- **Gemini Integration**: Generate article summaries using Google's Gemini API
- **Summary Caching**: Store summaries for offline access
- **Background Generation**: Queue items get summaries generated automatically

### 4. Audio Features
- **Text-to-Speech**: Convert articles and summaries to audio
- **Playback Controls**: Play/pause, skip, speed adjustment
- **Queue Management**: Persistent audio queue across app launches
- **Mini Player**: Always-visible audio controls
- **Expanded Player**: Full-screen player with waveform visualization

### 5. Brief (Queue) System
- **Add to Queue**: Queue articles for later reading/listening
- **Reorder Queue**: Drag and drop queue management
- **Filter Queue**: Filter by read/unread status
- **Persistent Queue**: Queue survives app restarts

### 6. Live News (RSS Podcasts)
- **RSS Audio Feeds**: Support for podcast RSS feeds
- **Radio Mode**: One-tap play of latest episodes
- **Episode Management**: Track listened/unlistened episodes
- **Auto-play**: Optional auto-play on app launch

### 7. Reddit Integration
- **Subreddit Feeds**: Import Reddit subreddits as feeds
- **Multireddit Support**: Import Reddit multireddits
- **Content Filtering**: Filter out non-article content (videos, images)
- **Custom User Agent**: Proper Reddit API compliance

### 8. Settings & Customization
- **Theme**: Dark/light mode support
- **Text Size**: Adjustable reading text size
- **Playback Speed**: Adjustable TTS speed
- **API Keys**: User-provided keys for Gemini and Firecrawl
- **Auto-play**: Configure auto-play behavior

## Architecture Components

### Services
1. **AudioService**: Audio playback management
2. **QueueService**: Queue persistence and management
3. **FeedService**: RSS feed parsing and updates
4. **GeminiService**: AI summary generation
5. **FirecrawlService**: Web content extraction
6. **StorageService**: Article storage and archiving
7. **RedditService**: Reddit API integration
8. **RSSAudioService**: Podcast feed management
9. **DefaultDataService**: Initial data setup

### Models
- **Article**: Core Data entity for articles
- **Feed**: Core Data entity for RSS feeds
- **RSSFeed**: Core Data entity for podcast feeds
- **RSSEpisode**: Core Data entity for podcast episodes
- **QueuedItem**: Queue item structure
- **EnhancedQueueItem**: Unified queue item for articles and episodes

### State Management
- **UserDefaultsManager**: Singleton for app settings
- **Core Data**: Persistent storage
- **@Published**: Reactive UI updates
- **Combine**: Reactive programming

## Current Issues

### 1. Reddit Import Not Working
- **Symptom**: Reddit feeds may not import correctly
- **Possible Causes**:
  - API changes
  - Authentication issues
  - Rate limiting
  - Network connectivity

### 2. Test Coverage Gaps
- **No unit tests** for services
- **No integration tests** for API calls
- **Minimal UI tests**
- **No test doubles/mocks**

### 3. Error Handling
- Error states not always visible to users
- No retry mechanisms for failed operations
- Limited error logging

## Testing Requirements

### Unit Tests Needed
1. **Service Tests**: All service classes
2. **Model Tests**: Data transformations and validations
3. **ViewModel Tests**: Business logic
4. **Utility Tests**: Helper functions

### Integration Tests Needed
1. **API Tests**: External service integration
2. **Core Data Tests**: Database operations
3. **Audio Tests**: Playback functionality

### UI Tests Needed
1. **Navigation Tests**: Tab switching, deep links
2. **Feed Management**: Add/edit/delete flows
3. **Queue Operations**: Add, reorder, remove
4. **Audio Controls**: Player interactions

## Next Steps
1. Implement comprehensive test suite
2. Debug Reddit import functionality
3. Add error recovery mechanisms
4. Improve error visibility to users
5. Add analytics for debugging production issues