# Play Now Pipeline QA Report

**Date**: 2026-02-07
**Branch**: `feature/audiostreaming-with-tdd`
**Simulator**: iPhone 17 (iOS 26.0.1, UUID: CCCE8AC6-751D-4AA8-BD08-45FB55EE8EBC)

## Summary

End-to-end Play Now flow tested successfully. Audio plays through the full pipeline:
Firecrawl scrape -> Gemini summarize -> Gemini TTS -> SwiftAudioEx playback.

## Pipeline Timing (PipelineTimer instrumentation)

### First Run (cold - no TTS cache)

| Step | Duration | Notes |
|------|----------|-------|
| content_fetch | ~4s | Firecrawl scrape of the-independent.com (1758 words) |
| summarize | ~3s | Gemini 2.5 Flash structured summary (1129 chars) |
| tts_generate | **25.99s** | Gemini 2.5 Flash Preview TTS, voice: Autonoe |
| audio_load | 0.00s | WAV file, 2.7MB, 58.05s duration |
| **TOTAL** | **~33s** | From article tap to audio playback |

Note: `content_fetch` and `summarize` happened during ArticleView load (before Play tap).
The PipelineTimer only captured `tts_generate` and `audio_load` because the summary was
already cached when Play was tapped.

### Second Run (TTS cache hit)

| Step | Duration | Notes |
|------|----------|-------|
| tts_generate | 0.01s | Cache hit |
| audio_load | 0.00s | - |
| **TOTAL** | **0.03s** | Near-instant from cache |

## Issues Found

### 1. API Key Injection Method (FIXED during QA)

**Problem**: `defaults write <plist-path>` does not reliably inject keys into the simulator.
The in-memory UserDefaults cache doesn't pick up plist changes made externally.

**Fix**: Use `xcrun simctl spawn <UUID> defaults write <bundle-id> <key> -string <value>`.
This writes through the simulator's cfprefsd process, which properly synchronizes with
the app's UserDefaults.

### 2. Keychain Migration on Simulator (FIXED in Phase 0)

**Problem**: `KeychainHelper.set()` can fail silently on the simulator. The migration
code was deleting keys from UserDefaults even when Keychain write failed, losing keys.

**Fix**: Made `set()` return `Bool`, only remove from UserDefaults if Keychain succeeds.
Setter falls back to UserDefaults if Keychain write fails.

### 3. TTS is the Main Bottleneck (~26s)

**Problem**: Gemini 2.5 Flash Preview TTS takes ~26s to generate 58s of audio.
This is the dominant latency in the pipeline.

**Potential mitigations**:
- Pre-generate TTS when article summary is ready (background generation)
- Use streaming TTS if/when Gemini supports it
- Cache aggressively (already working - second play is 0.03s)
- Consider OpenAI TTS as alternative (if API key configured)
- Upgrade to `gemini-2.5-flash-tts` (GA) which may be faster than preview

### 4. No OpenAI API Key Configured

The app fell back to Gemini TTS because no OpenAI key was configured:
`[UnifiedPlayer] Using Gemini TTS (no OpenAI key configured)`

This is correct behavior - the app properly falls back to available TTS provider.

### 5. content_fetch and summarize Not Timed by PipelineTimer

The PipelineTimer instrumentation in `generateAudioForItem()` correctly instruments
`tts_generate` and `audio_load`, but the `content_fetch` and `summarize` steps happen
in ArticleViewModel (when the article view loads), not in the audio generation pipeline.

**Recommendation**: Consider adding PipelineTimer instrumentation to ArticleViewModel's
content loading path as well, or restructure so the full pipeline is measured when
triggered from the Feed list (Play Now without opening article first).

## Test Results

All 12 PlayNowPipelineTests pass GREEN:

- PipelineTimerTests (3): Records steps, measures duration, report includes TOTAL
- QueueOperationTests (3): Add increases count, playNow sets index, remove decreases count
- PipelineErrorHandlingTests (3): No API key error, format with summary, format no content
- GenerationStateTests (3): Initial state pending, RSS episode ready, coordinator adds article

## Files Created/Modified

### New Files
- `Briefeed/Core/Utilities/KeychainHelper.swift` - Secure API key storage
- `Briefeed/Core/Utilities/PipelineTimer.swift` - Pipeline timing instrumentation
- `BriefeedTests/TDD/PlayNowPipelineTests.swift` - TDD tests + mocks

### Modified Files
- `Briefeed/Core/Utilities/UserDefaultsManager.swift` - Keychain migration for API keys
- `Briefeed/Core/Services/Audio/OpenAITTSServiceSimple.swift` - Keychain for OpenAI key
- `Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift` - PipelineTimer instrumentation

## Verification Checklist

- [x] Build succeeds
- [x] All 12 TDD tests pass GREEN
- [x] API keys injected via `simctl spawn`
- [x] Firecrawl scrape works (HTTP 200, 1758 words)
- [x] Gemini summarize works (structured summary with Quick Facts)
- [x] Gemini TTS works (58s WAV audio generated)
- [x] SwiftAudioEx plays audio (confirmed visually + user heard audio)
- [x] Mini player shows with controls (play/pause, rewind, forward, next)
- [x] PipelineTimer logs captured with timing data
- [x] TTS cache works (second play: 0.03s)
- [ ] Queue: play second article while first plays (not tested yet)
- [ ] OpenAI TTS fallback (no OpenAI key configured)
