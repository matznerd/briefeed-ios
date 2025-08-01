# Audio Background Mode Setup Instructions

## Recent Fix: Audio Session Error -50 (January 2025)

### Issue
Live News feature was failing with audio session error -50 when trying to play RSS episodes:
```
AVAudioSessionClient_Common.mm:597   Failed to set properties, error: -50
❌ Failed to configure audio session: Error Domain=NSOSStatusErrorDomain Code=-50 "(null)"
```

### Root Cause
The audio session was being configured twice:
1. In `AppDelegate.configureAudioSession()` at app launch
2. In `AudioService.configureBackgroundAudio()` when trying to play audio

When the session was already active, trying to reconfigure it with different parameters caused the -50 error.

### Solution Applied
1. **Modified `AudioService.configureBackgroundAudio()`**:
   - Added checks to see if audio session is already properly configured
   - Only reconfigure if necessary
   - Handle deactivation/activation more carefully
   - Don't throw errors - let playback continue even if configuration partially fails

2. **Modified `AppDelegate.configureAudioSession()`**:
   - Only set category and mode at app launch
   - Don't activate the session - let AudioService handle activation when needed

3. **Updated RSS playback error handling**:
   - Use `try?` instead of `try` for audio session configuration
   - Continue with playback even if configuration fails

---

# Audio Background Mode Setup Instructions

## Adding Background Audio Capability in Xcode

Since your project uses modern Xcode (13+), you need to add the background audio capability through the Xcode interface:

### Method 1: Through Xcode UI (Recommended)

1. Open `Briefeed.xcodeproj` in Xcode
2. Select the Briefeed target in the project navigator
3. Go to the "Signing & Capabilities" tab
4. Click the "+ Capability" button
5. Search for "Background Modes"
6. Double-click "Background Modes" to add it
7. Check the box for "Audio, AirPlay, and Picture in Picture"

### Method 2: Manual Info.plist Entry

If you have a custom Info.plist file:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

### Method 3: Through Build Settings

1. In Xcode, select your target
2. Go to Build Settings
3. Search for "Info.plist Values"
4. Add a new entry with:
   - Key: `UIBackgroundModes`
   - Value: `audio`

## Changes Made to Your Code

### 1. Audio Session Configuration
Updated both `BriefeedApp.swift` and `AudioService.swift` to use:
- `.mixWithOthers` - Allows your audio to play alongside other apps
- `.allowBluetooth` - Enables Bluetooth headphone support
- `.allowBluetoothA2DP` - Enables high-quality Bluetooth audio
- `.allowAirPlay` - Enables AirPlay streaming

### 2. Lock Screen Controls
Your app already has proper MPRemoteCommandCenter setup with:
- Play/Pause buttons
- Skip Forward/Backward (15 seconds)
- Next/Previous track
- Playback rate control

## Testing Your Setup

1. **Test Audio Mixing**:
   - Play music in Apple Music or Spotify
   - Open Briefeed and play an article
   - Both should play simultaneously

2. **Test Lock Screen Controls**:
   - Play audio in Briefeed
   - Lock your device
   - Wake the screen (don't unlock)
   - You should see playback controls with skip buttons

3. **Test Background Playback**:
   - Play audio in Briefeed
   - Press Home button or switch apps
   - Audio should continue playing

4. **Test Bluetooth**:
   - Connect Bluetooth headphones
   - Play audio in Briefeed
   - Audio should route to headphones

## Important Notes

- The app will now mix with other audio instead of interrupting it
- Users can control playback from:
  - Lock screen
  - Control Center
  - Bluetooth headphone buttons
  - CarPlay (if connected)
- The 15-second skip intervals are standard for spoken content
- Background audio will drain battery faster - consider adding a sleep timer feature

## Troubleshooting

If background audio doesn't work:
1. Ensure you've added the background mode capability in Xcode
2. Clean and rebuild the project
3. Check that `AVAudioSession.sharedInstance().setActive(true)` is called
4. Verify the audio session category is `.playback` (not `.ambient`)

If controls don't appear on lock screen:
1. Ensure `MPNowPlayingInfoCenter` is being updated
2. Check that remote commands are enabled
3. Verify audio is actually playing (not just loaded)