# Debug Notes - Audio Playback Issue

## Current Status
- ✅ **Audio playback is working** - SwiftAudioEx successfully plays WAV files
- ⚠️ **Only playing article titles** - Articles lack summaries/content

## Key Fix Applied
Changed SwiftAudioEx file loading from:
```swift
audioUrl: url.absoluteString  // "file:///path/to/file.wav" - WRONG
```
To:
```swift
audioUrl: url.path  // "/path/to/file.wav" - CORRECT for .file sourceType
```

## What to Look for in Logs

### Success Indicators:
- `[SwiftAudioEx] File is playable, duration: X seconds` - File loaded
- `[UnifiedPlayer] Successfully started playback` - Audio playing

### Problem Indicators:
- `[UnifiedPlayer] Text for TTS (X chars):` - Shows how much content we have
  - If < 100 chars = only title
  - If > 500 chars = has summary/content
- `[UnifiedPlayer] Fetched X characters from article` - Content fetch status
- `[UnifiedPlayer] Failed to fetch article content:` - Network/API issues

## Next Steps
1. Check why articles don't have summaries
2. Verify Gemini API is working for summarization
3. Ensure RSS feed parsing includes article content/description
4. Consider fallback to article.content if summary generation fails

## Audio Flow
1. Article → UnifiedAudioPlayer
2. Check for summary → Generate if missing
3. Format text (title + summary/content)
4. Generate TTS audio (GeminiTTS → WAV file)
5. Play via SwiftAudioEx (using file path, not file:// URL)