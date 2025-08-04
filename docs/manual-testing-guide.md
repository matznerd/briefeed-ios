# Manual Testing Guide - Audio System Migration

## Prerequisites

1. Open Xcode: `open Briefeed.xcodeproj`
2. Select iPhone 16 Pro simulator
3. Build and run the app (Cmd+R)

## Test Scenarios

### 1. Feature Flag Toggle Test
- [ ] Launch app
- [ ] Go to Settings tab
- [ ] Look for "Developer Settings" or audio feature toggle
- [ ] Toggle between old and new audio system
- [ ] Verify app doesn't crash

### 2. Basic Article Audio Playback
- [ ] Go to Feed tab
- [ ] Select any article
- [ ] Tap "Play" button
- [ ] Verify audio starts playing
- [ ] Check mini player appears at bottom
- [ ] Verify play/pause works
- [ ] Test skip forward/backward (15 seconds)

### 3. Live News/RSS Audio Test
- [ ] Go to Live News tab
- [ ] Add an RSS podcast feed if needed
- [ ] Tap "Play Live News" button
- [ ] Verify RSS episode starts playing
- [ ] Check if AVAudioSession error -50 is resolved
- [ ] Test skip intervals (30 seconds for RSS)

### 4. TTS Generation Test
- [ ] Select an article without audio
- [ ] Tap play
- [ ] Verify TTS generates audio (Gemini or device)
- [ ] Check audio cache is created

### 5. Queue Management Test
- [ ] Add multiple articles to queue
- [ ] Play through queue
- [ ] Close app completely
- [ ] Reopen app
- [ ] Verify queue persists
- [ ] Continue playback from where left off

### 6. Expanded Player Test
- [ ] While audio is playing, tap mini player
- [ ] Verify expanded player opens
- [ ] Test all controls:
  - Play/pause
  - Skip forward/backward
  - Next/previous track
  - Speed control
  - Sleep timer
  - Volume slider

### 7. Background Audio Test
- [ ] Start playing audio
- [ ] Press home button (Cmd+Shift+H)
- [ ] Verify audio continues playing
- [ ] Use control center to pause/play
- [ ] Return to app
- [ ] Verify state is synchronized

### 8. Sleep Timer Test
- [ ] Start playing audio
- [ ] Set sleep timer (5 minutes)
- [ ] Verify timer countdown
- [ ] Wait for timer to expire
- [ ] Verify audio stops/fades out

### 9. Mixed Queue Test
- [ ] Add articles to queue
- [ ] Add RSS episodes to Live News
- [ ] Play mixed content
- [ ] Verify smooth transitions
- [ ] Check correct skip intervals per content type

### 10. Error Recovery Test
- [ ] Try playing invalid content
- [ ] Disconnect network while streaming
- [ ] Verify graceful error handling
- [ ] Check fallback to device TTS works

## Expected Results

✅ **Success Indicators:**
- No crashes
- Audio plays smoothly
- Queue persists across restarts
- Background audio works
- Live News plays without error -50
- Feature flag toggles correctly

❌ **Known Issues:**
- Tests don't compile (to be fixed later)
- Some UI components may need adjustments
- Feature flag UI may not be visible yet

## Debug Tips

If audio doesn't play:
1. Check Xcode console for errors
2. Verify Gemini API key is set in Settings
3. Check network connection
4. Try toggling feature flag
5. Clear app data and retry

## Logging

Enable verbose logging:
1. Look for audio-related logs in console
2. Filter by "Audio", "TTS", "Briefeed"
3. Note any error messages or stack traces

---

**Priority Tests:**
1. Live News playback (original issue)
2. Basic article playback
3. Queue persistence
4. Background audio

Start with these core features before testing advanced features.