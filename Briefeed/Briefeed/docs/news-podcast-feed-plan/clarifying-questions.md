# Clarifying Questions for RSS Implementation

Based on your answers, I want to confirm a few key points:

## 1. Auto-play Behavior
You mentioned "autoplay live stories on load" - should this:
- Start playing when opening the app (if RSS tab was last active)?
Yes, if the RSS tab/Audio tab/Live Audio tab was the last one open, then you should auto-play it. There should also be a setting that says "Always auto-play live news on open." Because the user journey is that they have 5 minutes to get the news, so they open it, hit them with the news from the live ones that don't need to render or be selected. They start getting the news, they start building the queue based on what they see either by playing, hitting play next, play next, play next which starts to load up the queue, or they just add the queue at the end. They can start playing now if they want, but there is no real news in the app until you click it otherwise, so good with the audio
- Start playing only when navigating to RSS tab?
- Have a separate setting from the existing "autoPlayAudio" for articles?

## 2. Feed Integration with Brief
When you say "The brief should somehow integrate the added stuff from the feed and also from the live news feed" - do you mean:
Yes, the RSS episodes added to the Brief cue do mix seamlessly. So it would just go from the Gemini-generated audio of a story to the RSS to the Gemini audio again, if that's the order that they were in. 
- RSS episodes added to Brief queue should mix seamlessly with article summaries?
- Should there be any visual distinction between RSS episodes and articles in the Brief queue? You don't need any specific distinction except from the source. So we know if it's from where things are from, if they're from Reddit, if they're from NPR, et cetera. 
- Should the "Live News" tab have its own separate playback queue, or always use the main Brief queue?

## 3. Player FM Integration
For the Player FM URL feature:
- Should this be in the initial release or added later?
- Would you want a simple "Add Feed" button that accepts either direct RSS URLs or Player FM URLs?
- Should we scrape the Player FM page to extract the RSS feed URL?
Yeah, we can add it as a feature that won't break the app if it doesn't work well. Yes, the idea of like the ad feed and that we can use the player.fm and then you can fetch that URL if you need to. You have Firecrawl specifically as well, but sounds like it could be its own feature to work on later, though it would be nice to have some way to import Because there's more stations there, I want to add. 

## 4. Live News Tab Behavior
When you said "it's basically now overriding, it's playing from that list" - to clarify:
- Opening the Live News tab starts playing from the RSS episode list (not the Brief queue)?
If your nothing is playing and you go to the live news tab, it should auto play. Also could be the universal setting, autoplay, live news on open. 
- But users can still add RSS episodes to the Brief queue for mixed playback?
I guess once the story is playing, it should be on the brief page. Then the user could start adding stories to the brief behind it or hit the plus button / swipe to add the other live news to the feed. If they would need to figure out a way to autoplay from the live news or to drop in to the existing feed. What do you think? 
- Is there a separate "RSS queue" that plays in order on the Live News tab?

## 5. Feed Storage & Management
For easy adaptability to add new feeds:
- Should feeds be hardcoded initially but with an easy way to add more in code?
- Or should we build the "Add Feed" UI from the start?
- How do you envision adding new feeds - through Settings or directly in the Live News tab?
I think you should take in all the feeds that I gave you because I have hunted those down. Make it possible to add new feeds later on. Find that later, more, and we can focus on just getting this live news in there working. 
## 6. Playback Priority
When mixing RSS episodes with article summaries in Brief queue:
- Should they play in the order they were added?
Just do the same plane at swipe that adds it to the queue play now or play next Like we're doing there. 
- Any special handling for "Play Next" vs "Add to Queue"?
- Should RSS episodes use the same TTS voice settings or actual podcast audio?
RSS episodes are real human red news. So they stay how they are, but they intermix with the TTS stuff, like in the queues. 
## 7. Progress & State
For the "reasonable polling" of playback position:
- Save position when: pause, skip, app background, every 30 seconds?
- Should we remember position across app restarts for partially played episodes?
- Clean up old progress data after episodes are deleted?
You can remember them while they're in the memory. Clean up old data as episodes are deleted or fall out of memory. 

## My Understanding So Far:

**Core Concept**: The Live News tab is like a radio station - tap it and news starts playing automatically (if enabled). It has its own playlist of fresh RSS episodes playing newest-first. Users can also selectively add episodes to their Brief queue to mix with article summaries.

**Key Features**:
1. Auto-play option for instant news when opening Live News tab
2. Seamless integration with existing audio infrastructure
3. Same swipe gestures (add to queue, play now, play next)
4. Persistent mini player showing current audio
5. Smart caching of current + next episode
6. Drag-to-reorder feed priorities
7. Future support for adding custom feeds via Player FM URLs

Is this understanding correct? Any adjustments needed?

Sounds pretty good. We just need to figure out how to integrate the live playing of the news feed with the actual feed we have or the brief that we have. How do we integrate when the news is running through the RSS? How do we integrate with the existing audio feed backlog so that it plays? What are your ideas? Do you have anything? Any other designs in mind you want to propose? 
