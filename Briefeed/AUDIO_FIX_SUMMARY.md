# Audio Pipeline Fix Summary

## Changes Made

### 1. Fixed JSON Summary Parsing
**File**: `UnifiedAudioPlayer.swift`
- Added JSON parsing to extract `theStory` field from Gemini's JSON response
- Now properly extracts plain text summary instead of raw JSON
- Added extensive logging to track summary generation

### 2. Updated Gemini Models
**Files**: `GeminiService.swift`, `GeminiTTSService.swift`
- Unified to use `gemini-2.5-flash` for both summarization and audio generation
- Previously was using incorrect model names

### 3. Enhanced Logging
Added comprehensive logging throughout the pipeline:
- `[GeminiService]` - Tracks API calls and responses
- `[UnifiedPlayer]` - Shows content fetching and summary generation
- `[GeminiTTS]` - Monitors audio generation process

## Current Audio Pipeline

1. **Article saved** → Queue updated
2. **Content fetching**: 
   - Try article.content first
   - If empty, fetch from URL via Firecrawl
3. **Summary generation**:
   - Send content to `gemini-2.5-flash`
   - Receive JSON response with `theStory` field
   - Parse and extract plain text summary
4. **Audio generation**:
   - Format text (title + summary)
   - Send to `gemini-2.5-flash` for TTS
   - Receive base64 audio data
   - Convert to WAV and cache
5. **Playback**:
   - SwiftAudioEx plays WAV file using file path (not file:// URL)

## Key Fix
The main issue was that summaries were being stored as raw JSON instead of extracted text. The JSON response from Gemini includes:
```json
{
  "quickFacts": { ... },
  "theStory": "Actual summary text here..."
}
```

Now we properly parse this JSON and extract the `theStory` field for TTS generation.

## Testing Instructions
1. Save an article to queue
2. Watch logs for:
   - `[UnifiedPlayer] Generating summary from X characters`
   - `[UnifiedPlayer] Extracted summary text: X characters`
   - `[GeminiTTS] Starting audio generation`
   - `[SwiftAudioEx] File is playable, duration: X seconds`

## Next Steps
- Monitor if articles are properly fetching content from RSS feeds
- Verify Gemini API key is configured correctly
- Test with different article types