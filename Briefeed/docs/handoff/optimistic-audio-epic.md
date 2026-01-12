# Epic 3: Optimistic Audio Pre-generation (Phase 3)

**Priority:** P2 (Medium)
**Type:** Epic
**Status:** Blocked by Epic 2
**Depends On:** [Epic 2: Non-Blocking Summary UI](./summary-ui-epic.md)

---

## Overview

Pre-generate TTS audio immediately when summary completes, before user taps Play. Most plays become instant from cache.

## Goal

Reduce perceived audio latency by generating TTS in background as soon as summary is ready.

## Current Flow (Problem)

```
Summary ready
    ↓
User reads article (30+ seconds)
    ↓
User taps Play
    ↓
TTS generation starts (2-5s wait)
    ↓
Audio plays
```

## Target Flow (Solution)

```
Summary ready
    ↓
Immediately: TTS generation starts in background
    ↓
User reads article (30+ seconds)
    ↓
TTS completes, cached (user doesn't notice)
    ↓
User taps Play
    ↓
Audio plays INSTANTLY (from cache)
```

---

## Audio Architecture

### Correct API: Gemini 2.5 Flash TTS

**Model:** `gemini-2.5-flash-preview-tts`

**NOT Gemini Live API** - that's for interactive conversations, not text recitation.

| Aspect | Gemini TTS | Gemini Live API |
|--------|-----------|-----------------|
| Purpose | Exact text recitation | Interactive conversations |
| Use case | Podcasts, audiobooks | Voice assistants, NPCs |
| Input | Text only | Audio/video streams |
| Output | Faithful reading | Dynamic responses |

### API Call Structure

```swift
// Endpoint
POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent

// Request body
{
    "contents": [{
        "parts": [{
            "text": "Read in a calm, informative tone: \(summaryText)"
        }]
    }],
    "generationConfig": {
        "responseModalities": ["AUDIO"],
        "speechConfig": {
            "voiceConfig": {
                "prebuiltVoiceConfig": {
                    "voiceName": "Kore"
                }
            }
        }
    }
}
```

### Style Control via Prompt

Natural language in the text prompt controls voice style:
- `"Say cheerfully: ..."`
- `"Read in a calm, informative tone: ..."`
- `"Speak at a brisk pace, like a news anchor: ..."`

### Available Voices (30 options)

| Voice | Style | Voice | Style |
|-------|-------|-------|-------|
| Kore | Firm | Puck | Upbeat |
| Zephyr | Bright | Charon | Informative |
| Aoede | Breezy | Fenrir | Excitable |
| Sulafat | Warm | Achird | Friendly |

---

## Implementation Tasks

### Task 3.1: Add Pre-generation Trigger

**File:** `Briefeed/Core/ViewModels/ArticleViewModel.swift`

**Changes:**
- When summary completes successfully, immediately trigger TTS generation
- Don't wait for user to tap Play

```swift
func generateStructuredSummary() async {
    // ... existing summary generation ...

    if let story = structuredResult.story {
        summary = story
        article.summary = story
        try await storageService.saveContext()

        // NEW: Pre-generate audio immediately
        Task {
            await preGenerateAudio(for: story)
        }
    }
}

private func preGenerateAudio(for text: String) async {
    do {
        let _ = try await TTSGeneratorService.shared.generateAudioFile(
            from: text,
            trackingIn: article.managedObjectContext,
            for: article
        )
        // Audio now cached - Play button will be instant
    } catch {
        // Silently fail - user can still generate on-demand
        print("[ArticleViewModel] Pre-generation failed: \(error)")
    }
}
```

**Acceptance Criteria:**
- [ ] TTS generation starts within 100ms of summary completion
- [ ] Generation runs in background Task (non-blocking)
- [ ] Failures are silent (user can still play manually)

### Task 3.2: Update Play Button State

**File:** `Briefeed/Features/Article/ArticleView.swift`

**Changes:**
- Check if audio is cached before showing loading state
- Show different states: ready (cached), loading (generating), or generate-on-tap

```swift
enum PlayButtonState {
    case ready          // Audio cached, instant play
    case preGenerating  // Background generation in progress
    case idle           // User must tap to generate
    case generating     // User tapped, waiting
    case playing
    case paused
}
```

**Acceptance Criteria:**
- [ ] Button shows "ready" state when audio cached
- [ ] Button shows subtle indicator during pre-generation
- [ ] Tap during pre-generation waits for completion, then plays

### Task 3.3: Add Cache Check to Play Flow

**File:** `Briefeed/Core/ViewModels/AudioPlayerViewModelV2.swift`

**Changes:**
- Check cache before starting generation
- If cached, play immediately
- If pre-generating, wait for completion

```swift
func play(article: Article) async {
    // Check if audio already cached
    if let cachedURL = checkCache(for: article) {
        await playFromCache(cachedURL)
        return
    }

    // Check if pre-generation in progress
    if let pendingTask = preGenerationTasks[article.id] {
        let url = try await pendingTask.value
        await playFromCache(url)
        return
    }

    // Fall back to on-demand generation
    await generateAndPlay(article)
}
```

**Acceptance Criteria:**
- [ ] Cached audio plays within 100ms
- [ ] Pre-generating audio waits and plays when ready
- [ ] On-demand generation still works as fallback

### Task 3.4: Track Pre-generation Progress

**File:** `Briefeed/Core/Services/Audio/TTSGeneratorService.swift`

**Changes:**
- Add method to check if generation is in progress for specific text
- Add callback/publisher for generation completion

```swift
// Track active pre-generations
private var activePreGenerations: [String: Task<URL, Error>] = [:]

func preGenerateAudio(for text: String, articleId: UUID) -> Task<URL, Error> {
    let cacheKey = cacheManager.cacheKey(for: text, voice: selectedVoice)

    // Return existing task if already generating
    if let existingTask = activePreGenerations[cacheKey] {
        return existingTask
    }

    // Create new generation task
    let task = Task {
        defer { activePreGenerations.removeValue(forKey: cacheKey) }
        return try await generateAudioFile(from: text)
    }

    activePreGenerations[cacheKey] = task
    return task
}
```

**Acceptance Criteria:**
- [ ] Duplicate pre-generation requests reuse existing task
- [ ] Tasks tracked by cache key (text + voice hash)
- [ ] Tasks cleaned up on completion/failure

---

## Files to Modify

| File | Change Type | Description |
|------|-------------|-------------|
| `ArticleViewModel.swift` | Moderate | Add pre-generation trigger |
| `ArticleView.swift` | Minor | Update play button states |
| `AudioPlayerViewModelV2.swift` | Minor | Add cache check |
| `TTSGeneratorService.swift` | Moderate | Track active generations |

---

## Timeline Optimization

### Before (Sequential)

```
0s   User opens article
5s   Summary ready
35s  User taps Play
37s  TTS generation starts
42s  Audio plays
```
**Time to audio: 7 seconds after tap**

### After (Parallel)

```
0s   User opens article
5s   Summary ready → TTS pre-generation starts
10s  TTS complete, cached
35s  User taps Play
35s  Audio plays INSTANTLY
```
**Time to audio: <100ms after tap**

---

## Test Plan

1. **Pre-generation Timing**
   - Open article
   - Wait for summary
   - Check logs: TTS should start within 100ms

2. **Cache Hit Test**
   - Open article, wait for summary + pre-generation
   - Wait 10 seconds
   - Tap Play → Should be instant

3. **Pre-generation In-Progress Test**
   - Open article
   - Tap Play immediately after summary appears
   - Should wait for pre-generation, then play (no double generation)

4. **Failure Handling**
   - Simulate TTS API failure
   - Verify user can still tap Play and retry

---

## Handoff Notes

**Completed:** [ ] Yes / [x] No
**Completion Date:** _________
**Prerequisites Verified:**
- [ ] Epic 1 completed
- [ ] Epic 2 completed
- [ ] Summary card slides in correctly
- [ ] Play button in card works

**Notes:**
```
(Add implementation notes here)
```

---

## References

- [Gemini 2.5 Flash TTS Documentation](../../docs/gemini-tts-docs/gemini-2.5-flash-tts.md)
- [Current TTS Implementation](../../Briefeed/Core/Services/Audio/TTSGeneratorService.swift)
- [Audio Cache Manager](../../Briefeed/Core/Services/Audio/AudioCacheManager.swift)
