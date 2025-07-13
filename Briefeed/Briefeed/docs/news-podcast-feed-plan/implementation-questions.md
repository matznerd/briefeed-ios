# RSS Audio News Feature - Implementation Questions

## Audio Playback Architecture

### 1\. Audio Service Integration

*   **Should RSS audio playback share the same AudioService instance or have its own dedicated service?**
    *   Option A: Extend existing AudioService with RSS mode (simpler, but mixing concerns)  
        It should share the audio service so that if it's open, it's basically now overriding, it's playing from that list. If there's a setting for auto-play on load on, it could start playing that when the app opens, the first unplayed news feed.

Because sometimes you're looking at it and then if they're scrolling the regular feed, they can add things from the RSS feed to Play Next or add to Playlist. So it needs to integrate into the brief feed. The brief should somehow integrate the added stuff from the feed and also from the live news feed as well. 

*   Option B: Create separate RSSAudioService that coordinates with main AudioService
*   Consideration: How do we handle switching between article TTS and RSS audio? They're all audio, aren't they? So it doesn't really matter. They should be able to be interspersed. It's better if they're designed to work seamlessly with the same tooling.   
      
     

### 2\. Queue Management

*   **When user adds RSS episode to Brief queue, how should it behave?**
    *   Should it pause current RSS playback and switch to Brief tab?  
        It should have the same options they have when they swipe in the feed:
*   Default swipe adds to queue
*   Play now
*   Play next  
    But there needs to be a setting that says "autoplay live stories on load" that just starts that page. 
    *   Should it continue RSS playback and add silently to queue?
    *   Should RSS episodes in Brief queue show different UI/indicators?

### 3\. Audio File Handling

*   **Should we download/cache RSS audio files or stream directly?**
    *   Streaming: Less storage, but requires constant connection  
        Caching: Better offline experience, but storage management needed
    *   Caching the last episodes with local storage when one's playing, you can start downloading the next one just like we do in the Briefeed. It can use the same exact logic we have.   
        Hybrid: Cache current + next episode only?

## Data Persistence

### 4\. Core Data vs UserDefaults

*   **Which data should go in Core Data vs UserDefaults?**
    *   Use your judgment on these data questions.   
        Feed configurations (priority, enabled state)?
    *   Episode listen history and progress?  
         
    *   Currently considering: Core Data for episodes, UserDefaults for settings

### 5\. Episode Retention

*   **How strictly should we enforce retention rules?**
    *   Delete immediately at 24h/7d mark?
    *   Grace period for partially listened?
    *   What about downloaded/cached audio files?  
        There should be some storage. 

## User Experience

### 6\. Tab Switching Behavior

*   **What happens to RSS playback when switching tabs?**
    *   Continue playing in background?  
        Yeah, there's the player should still play it's a persistent audio player supposed to stay on the bottom of the app open the whole time like it's a news player. 
    *   Pause and resume when returning?
    *   Show mini-player in other tabs? Yes, the mini player in the bottom should always be visible, even if nothing's playing. That way, we have a clear way to play - just hit the play button.   
         

### 7\. Feed Priority UI

*   **How should the draggable priority list work?**
    *   Drag handle on each row?  
        Drag to reorder is good. 
    *   Edit mode like iOS native apps?
    *   Group by update frequency with sections?

### 8\. Error Handling

*   **How to handle RSS feed failures?**
    *   Retry automatically? How many times?  
        Just the normal one-time or whatever is normal. 
    *   Show error in feed list or hide failed feeds?  
        Just skip ones or grey them out when they don't have a story. Maybe have a refresh button. 
    *   Fallback behavior when all feeds fail?  
        Maybe just say "like we can't detect internet connection" if that's what it is. 

## Technical Implementation

### 9\. RSS Parsing

*   **Which RSS elements are critical vs optional?**
    *   Required: title, audio URL, pubDate
    *   Optional: duration, description, author?
    *   How to handle non-standard RSS formats?  
          
        I don't think anything is required aside from what we've provided. Come up with the way to handle it so that the audio plays just like one after the other without the user needing to get involved. And anything special. 

### 10\. Playback State

*   **How granular should progress tracking be?**
    *   Save position every X seconds?
    *   Only on pause/app background?
    *   Sync across app launches?  
        Whatever is standard here, it should be. If you know the option, if they switch between tracks or feeds, it should at least store the state of where it was with whatever is a reasonable pull, nothing too much. For example, 

### 11\. Performance

*   **How many episodes should we keep in memory?**
    *   Load all on tab open?
    *   Paginate with lazy loading?
    *   Pre-fetch next N episodes?  
          
         

## Integration Points

### 12\. Mini Player

*   **Should MiniPlayer show different UI for RSS episodes?**
    *   Show feed name instead of "Brief"?
    *   Different progress indicators?
    *   Quick action to jump to RSS tab?  
        Same UI. The feed is live news instead of brief, but then we can also add them to the brief with the plus button.  

### 13\. Notifications

*   **Should we notify users of new episodes?**
    *   Background fetch for new episodes?
    *   Local notifications for breaking news?
    *   Requires notification permissions?  
          
        No notifications needed for new episodes that are hourly and whatever. 

##   
Settings & Configuration

### 14\. Default Behavior

*   **What should be the default settings?**
    *   Auto-play on tab open: ON or OFF?
    *   Which feeds enabled by default?
    *   Default playback speed for RSS?  
          
        Autoplay live news should be an option because the user just wants to get the hourly news from all the different top ones when they come in, they should be able to do that. Give feeds a toggle, but if they're on the list, they should be pulling the feed. They should be at the playback speed last used. 

### 15\. Migration

*   **How do we handle adding this feature to existing users?**
    *   Show onboarding/introduction?
    *   Enable all feeds by default or start with subset?
    *   Import any existing podcast app settings?  
          
        Just add the tab, don't worry. It's just me for right now. 

## Content & Licensing

### 16\. Feed Selection

*   **Are the proposed RSS feeds confirmed to be:**
    *   Publicly available without authentication?
    *   Properly licensed for redistribution?
    *   Stable URLs that won't change frequently?  
          
        There are stable URLs, and I'll be adding new ones, so we need to make it easy to be adaptable.   
        Can you make it so that if I provide a player FM URL, it finds the feed link and loads it, so I could just add from that list? Here's an example: 
    *   [https://player.fm/series/on-point-podcast-1324359](https://player.fm/series/on-point-podcast-1324359)
    *   feed link goes to https://rss.wbur.org/onpoint/podcast

### 17\. Attribution

*   **How should we handle attribution?**
    *   Show source/copyright in player?
    *   Link to original podcast/website?
    *   Terms of use compliance?  
        Don't worry about this. These feeds are public for a reason. They include their own attribution. 

## Future Considerations

### 18\. Expandability

*   **Should the architecture support:**
    *   User-added custom RSS feeds?
    *   Video podcasts in the future?
    *   Podcast subscriptions with authentication?  
          
        Yes, above I noted how I want to be able to add ones from Player FM website. 

### 19\. Analytics

*   **What metrics should we track?**
    *   Episode completion rates?
    *   Most popular feeds?
    *   Skip/replay patterns?  
          
        Contract the completion rate

### 20\. Offline Support

*   **How important is offline playback?**
    *   Download episodes on WiFi only?
    *   Automatic download of next N episodes?
    *   Storage limit management?  
          
        You can allow downloading if it makes sense   
          
        Proposed Answers (To Be Confirmed)

Based on the existing codebase patterns, here are my recommendations:

1.  **Extend existing AudioService** - Add RSS mode to maintain single audio source
2.  **Silent queue addition** - Don't interrupt current playback
3.  **Stream with smart caching** - Cache current + next episode
4.  **Core Data for all RSS data** - Consistent with article storage
5.  **24h hard limit, 48h for partial** - Balance storage and UX
6.  **Continue playing** - Similar to music apps
7.  **iOS-style edit mode** - Familiar to users
8.  **Retry 3x with backoff** - Show errors after that
9.  **Parse defensively** - Handle missing optional fields
10.  **Save every 10 seconds** - Balance battery and accuracy

Please confirm or modify these recommendations based on your vision for the feature.