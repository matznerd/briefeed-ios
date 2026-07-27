# Briefeed iOS App - Refactoring PRD

> ⚠️ **SUPERSEDED** - This document is obsolete.
>
> **See [PRD-REFACTOR-V2.md](PRD-REFACTOR-V2.md) for current requirements.**
>
> Key differences in V2:
> - No TTS quota (Gemini is out of beta)
> - Model: `gemini-2.5-flash-preview-tts` (preview)
> - TTSQuotaManager removed
> - Additional features: voice rotation, autoplay, offline download

**Date:** December 16, 2025
**Version:** 1.0
**Status:** ~~Draft~~ **SUPERSEDED by V2**

---

## Executive Summary

This PRD synthesizes findings from a comprehensive audit of the Briefeed iOS app, identifying **47 issues** across 5 core areas. The app has solid architectural foundations but suffers from **fragmented state management**, **incomplete feature implementations**, and **critical integration gaps** that prevent core functionality from working as intended.

### Critical Statistics

| Area | Critical | High | Medium | Low |
| --- | --- | --- | --- | --- |
| TTS/Audio Pipeline | 3 | 4 | 5 | 4 |
| Summarization | 4 | 3 | 3 | 3 |
| Queue System | 7 | 4 | 3 | 3 |
| Views/UI | 3 | 4 | 5 | 3 |
| Interactions | 2 | 2 | 1 | 0 |
| **Total** | **19** | **17** | **17** | **13** |

### Root Cause Summary

The majority of issues stem from **three fundamental architectural problems**:

1.  **Fragmented Queue System** - 4 independent queue representations with no synchronization
2.  **Incomplete Integrations** - Components exist but aren't connected (TTSQuotaManager, episode swipe actions)
3.  **Silent Failure Modes** - Errors fall back to degraded states without user notification

---

## Table of Contents

1.  [TTS and Audio Pipeline Issues](#1-tts-and-audio-pipeline-issues)
2.  [Summarization Pipeline Issues](#2-summarization-pipeline-issues)
3.  [Queue Management Issues](#3-queue-management-issues)
4.  [Views and UI Issues](#4-views-and-ui-issues)
5.  [User Interaction Issues](#5-user-interaction-issues)
6.  [Gemini TTS API Update](#6-gemini-tts-api-update)
7.  [Prioritized Fix Roadmap](#7-prioritized-fix-roadmap)
8.  [Questions for Clarification](#8-questions-for-clarification)
9.  [Technical Debt Summary](#9-technical-debt-summary)

---

## 1\. TTS and Audio Pipeline Issues

### 1.1 CRITICAL: TTSQuotaManager Not Integrated

**Files Affected:**

*   `TTSGeneratorService.swift`
*   `GeminiTTSService.swift`
*   `UnifiedAudioPlayer.swift`

**Problem:**  
TTSQuotaManager exists and tracks Gemini's 100/day limit, but it's **never consulted** before making API calls. Services hit the quota at the API level instead of gracefully handling it beforehand.

**Current Behavior:**

```
User plays article → Gemini TTS called → API returns quota error → Falls back to AVSpeech
```

**Expected Behavior:**

```
User plays article → Check TTSQuotaManager → If quota low, warn user → Proactively use fallback
```

**Recommendation:**

```
// In TTSGeneratorService.generateWithGemini():
guard TTSQuotaManager.shared.remainingGeminiGenerations > 0 else {
    throw TTSError.quotaExceeded
}
let audioURL = try await geminiService.generateSpeech(...)
await MainActor.run {
    TTSQuotaManager.shared.recordGeminiGeneration()
}
```

---

### 1.2 CRITICAL: Device TTS Fallback Returns Empty Audio

**File:** `GeminiTTSService.swift:400-418`

**Problem:**

```
return TTSResult(
    success: true,    // Claims success...
    audioData: nil,   // ...but no audio data
    audioURL: nil,    // ...and no URL
    usedFallback: true
)
```

When Gemini fails and device TTS is triggered, it returns "success" with no actual audio. Playback silently fails.

**Recommendation:**  
Either implement actual AVSpeechSynthesizer recording or remove this function and rely on `TTSGeneratorService.generateWithAVSpeech()`.

---

### 1.3 CRITICAL: Invalid OpenAI TTS Model

**File:** `OpenAITTSServiceSimple.swift:16`

**Problem:**

```
case gpt4oMiniTTS = "gpt-4o-mini-tts"  // This model doesn't exist!
```

Using this model causes API errors. The code comments acknowledge this but the enum case remains.

**Recommendation:**  
Remove the invalid enum case or mark it as unavailable:

```
@available(*, unavailable, message: "Model not yet released by OpenAI")
case gpt4oMiniTTS = "gpt-4o-mini-tts"
```

---

### 1.4 HIGH: OpenAI Streaming Not Implemented

**File:** `OpenAITTSServiceSimple.swift:212-228`

**Problem:**  
`useStreaming` parameter is accepted but completely ignored. No streaming implementation exists.

**Impact:** Users cannot get progressive audio playback for long articles.

**Recommendation:**  
Either:

1.  Remove the parameter (breaking change)
2.  Implement streaming with URLSession delegate
3.  Document clearly that streaming is not supported

---

### 1.5 HIGH: Hardcoded Sample Rate

**File:** `GeminiTTSService.swift:354`

**Problem:**

```
let wavData = pcmToWav(pcmData: decodedData, sampleRate: 24000)  // Hardcoded
```

If Gemini changes the sample rate, audio will play at wrong speed.

**Recommendation:**  
Parse sample rate from API response metadata or document the assumption clearly.

---

### 1.6 HIGH: No Retry Logic for Network Failures

**Files:** All TTS services

**Problem:** Network failures cause immediate errors with no retry attempts.

**Recommendation:**

```
func generateWithRetry<T>(maxAttempts: Int = 3, operation: () async throws -> T) async throws -> T {
    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            if attempt == maxAttempts { throw error }
            try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
        }
    }
}
```

---

### 1.7 MEDIUM: Dead Code - generatePlaceholderAudio()

**File:** `TTSGeneratorService.swift:298-329`

**Problem:** Function exists but is never called. Generates silent audio.

**Recommendation:** Remove dead code.

---

### 1.8 MEDIUM: Cache Key Uses Base64 Instead of Hash

**Files:** `GeminiTTSService.swift:176-179`, `AudioCacheManager.swift:56-73`

**Problem:** Base64 encoding entire text is wasteful. Duplicated logic in two files.

**Recommendation:**

```
import CryptoKit

func cacheKey(for text: String, voice: String?) -> String {
    let combined = text + (voice ?? "default")
    let hash = SHA256.hash(data: Data(combined.utf8))
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}
```

---

## 2\. Summarization Pipeline Issues

### 2.1 CRITICAL: Gemini 2.5 Flash Token Limit Bug

**File:** `GeminiService.swift:201-207`

**Problem:**  
Gemini 2.5 Flash includes "thinking tokens" in output count but doesn't return them. This causes MAX\_TOKENS errors with empty responses.

**Impact:** Articles fail to summarize with no visible error, falling back to excerpts.

**Recommendation:**  
Consider switching to `gemini-1.5-flash` which doesn't have this issue, or significantly increase `maxOutputTokens` (currently 2000).

*   you can update this  to be even larger but lets ask the AI to make the text output text of the summary to be somewhat limited.

---

### 2.2 CRITICAL: Double Content Truncation

**Problem:** Content is truncated TWICE:

1.  UnifiedAudioPlayer: 20,000 chars (line 408)
2.  GeminiService: 10,000 chars (line 488)

The second truncation is more aggressive and unnecessary.

**Recommendation:** Remove truncation in GeminiService. Gemini 2.5 Flash supports 32k tokens (~128k chars).

---

### 2.3 CRITICAL: Silent Fallback to Title-Only Playback

**File:** `UnifiedAudioPlayer.swift:433-446`

**Problem:**  
When summarization fails, code silently falls back to a 100-word excerpt:

```
catch {
    let words = processedContent.split(separator: " ").prefix(100).joined(separator: " ")
    summaryText = "Article excerpt: \(words)..."
}
```

Users never know their article wasn't properly summarized.

**Recommendation:**

*   Surface errors to users
*   Mark articles with failed summaries
*   Allow retry option

---

### 2.4 CRITICAL: Error Messages Saved as Summary

**File:** `UnifiedAudioPlayer.swift:448-463`

**Problem:**

```
article.summary = "Unable to generate summary..."  // Saved to Core Data!
```

This error message persists and is later filtered out in `formatArticleForTTS`, resulting in "Article content not available" being spoken.

**Recommendation:**  
Use a separate `article.summaryError` field, or set summary to nil and check a separate error state.

---

### 2.5 HIGH: Fragile JSON Parsing

**File:** `GeminiService.swift:338-384`

**Problem:** Extensive character-by-character cleanup needed for Gemini JSON responses:

*   Strips markdown code fences
*   Manually escapes newlines
*   Fixes malformed JSON

**Recommendation:**

*   Use proper JSON schema in prompt
*   Consider Gemini's structured output mode
*   Add `response_schema` parameter

yes lets move to structured output mode

---

### 2.6 HIGH: formatArticleForTTS Complexity

**File:** `UnifiedAudioPlayer.swift:591-720`

**Problem:** 130-line method with 3 levels of nested conditionals, multiple JSON/text detection strategies, and scattered fallback paths.

**Recommendation:**  
Refactor into smaller methods:

```
func formatArticleForTTS(_ article: Article) -> String {
    if let text = formatFromSummary(article) { return text }
    if let text = formatFromContent(article) { return text }
    return "Article content not available for text-to-speech."
}
```

---

### 2.7 MEDIUM: Short Content Warning But No Action

**File:** `UnifiedAudioPlayer.swift:392-395`

**Problem:** Warns about content \< 100 chars but continues anyway, likely producing poor summaries.

**Recommendation:** Reject very short content with specific error.

---

## 3\. Queue Management Issues

### 3.1 CRITICAL: Four Independent Queue Representations

**Problem:**  
The app maintains 4 separate queue structures that don't synchronize:

| Queue | Location | Type | Persistence |
| --- | --- | --- | --- |
| QueueServiceV2.queuedItems | QueueServiceV2 | QueuedItem\[\] | UserDefaults |
| QueueServiceV2.enhancedQueue | QueueServiceV2 | EnhancedQueueItem\[\] | UserDefaults |
| UnifiedAudioPlayer.queue | UnifiedAudioPlayer | UnifiedQueueItem\[\] | None |
| AudioPlayerViewModelV2.queueItems | ViewModel | UnifiedQueueItem\[\] | Attempted |

**Impact:**

*   Queue state lost on app restart
*   Items can appear in one queue but not others
*   Reordering in one place doesn't update others

**Recommendation:**  
Remove QueueServiceV2 entirely and implement proper persistence in UnifiedAudioPlayer.

---

### 3.2 CRITICAL: Queue State Lost on App Restart

**Problem:** UnifiedAudioPlayer.queue has no persistence mechanism.

**Recommendation:**

```
// Add to UnifiedAudioPlayer
func saveQueueState() async {
    let persistableItems = queue.map { PersistableQueueItem(from: $0) }
    let data = try? JSONEncoder().encode(persistableItems)
    UserDefaults.standard.set(data, forKey: "unified_queue_state")
}

func restoreQueueState() async {
    guard let data = UserDefaults.standard.data(forKey: "unified_queue_state") else { return }
    // Reconstruct from Core Data references
}
```

---

### 3.3 CRITICAL: QueueServiceV2 Background Generation Never Works

**File:** `QueueServiceV2.swift:282-286`

**Problem:**

```
private func fetchArticle(with id: UUID) async -> Article? {
    return nil  // Placeholder - never implemented!
}
```

Background audio generation never actually runs.

**Recommendation:** Remove QueueServiceV2 or implement properly.

---

### 3.4 CRITICAL: Play Live News Overwrites Article Queue

**File:** `AudioPlayerViewModelV2.swift:482-521`

**Problem:** Tapping "Play Live News" replaces entire queue with episodes, losing any queued articles.

**Recommendation:**

*   Prompt user before replacing queue
*   Or append to existing queue
*   Or provide separate Live News queue

---

### 3.5 HIGH: Reordering Destroys Generation State

**File:** `AudioPlayerViewModelV2.swift:407-429`

**Problem:**

```
await unifiedPlayer.loadMixedQueue(items: newQueue.compactMap { item in
    item.article ?? item.episode
})
```

Creates new UnifiedQueueItems, losing all generation state (generating items reset to pending).

**Recommendation:**  
Reorder existing items instead of creating new ones:

```
func reorderQueue(from source: IndexSet, to destination: Int) async {
    await MainActor.run {
        var newQueue = unifiedPlayer.queue
        newQueue.move(fromOffsets: source, toOffset: destination)
        unifiedPlayer.queue = newQueue  // Direct assignment preserves state
    }
}
```

---

### 3.6 HIGH: Remove from Queue Doesn't Sync

**File:** `BriefView+Filtering.swift:288-304`

**Problem:** Removing item from UnifiedAudioPlayer doesn't update QueueServiceV2.

**Impact:** Orphaned items remain in persisted queue.

---

### 3.7 HIGH: Pre-Generation Race Condition

**File:** `UnifiedAudioPlayer.swift:567-588`

**Problem:** Multiple pre-generation tasks can run simultaneously without proper coordination.

---

### 3.8 MEDIUM: Duplicate saveQueueState() Methods

**File:** `AudioPlayerViewModelV2.swift:372-393, 466-470`

**Problem:** Two identical method definitions.

---

### 3.9 MEDIUM: Unsafe Index Synchronization

**File:** `QueueServiceV2.swift:123-127`

**Problem:** Assumes same index in queuedItems and enhancedQueue (they can differ for episodes).

---

## 4\. Views and UI Issues

### 4.1 CRITICAL: Play All Button Ignores Filter

**File:** `BriefView+Filtering.swift:54-71`

**Problem:**

```
Button {
    let articles = viewModel.queuedArticles  // Always plays articles!
}
```

Filtering to "Live News" and clicking "Play All" plays articles instead of filtered episodes.

**Recommendation:**

```
Button {
    switch currentFilter {
    case .articles:
        await audioPlayerViewModel.playQueue(articles: filteredArticles)
    case .liveNews:
        await audioPlayerViewModel.playQueue(episodes: filteredEpisodes)
    case .all:
        await audioPlayerViewModel.playMixedQueue(items: filteredQueue)
    }
}
```

---

### 4.2 CRITICAL: Episode Swipe Actions Defined But Never Used

**File:** `LiveNewsViewV2.swift:155-178`

**Problem:**

```
private func episodeSwipeActions(for episode: RSSEpisode) -> some View {
    // Full implementation exists but never attached to any view!
}
```

**Impact:** Users cannot queue episodes from Live News view - must tap to play only.

**Recommendation:**

```
// In EpisodeRowV2:
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    episodeSwipeActions(for: episode)
}
```

---

### 4.3 CRITICAL: Queue Reordering Not Implemented

**File:** `BriefView+Filtering.swift:284-286`

**Problem:**

```
private func moveItems(from source: IndexSet, to destination: Int) {
    // TODO: Implement reordering in enhanced queue
}
```

Edit mode shows move handles but nothing happens.

**Recommendation:** Implement or remove the feature.

---

### 4.4 HIGH: Auto-Queue on Brief View Appear

**File:** `BriefView+Filtering.swift:85-95`

**Problem:** Navigating to Brief tab auto-loads saved articles to queue, potentially replacing user's existing queue.

**Recommendation:** Only auto-load if queue is empty AND no active playback.

---

### 4.5 HIGH: Redundant Action Buttons Overlay Code

**File:** `ArticleRowView.swift:434-501`

**Problem:** 67 lines of unused code for "Play Now"/"Play Next" overlay. `showActionButtons` never set to true.

**Recommendation:** Remove dead code or implement the feature.

---

### 4.6 MEDIUM: No Queue Position Indicators for Episodes

**Problem:** Articles show queue position badge, but episodes don't.

---

### 4.7 MEDIUM: Incomplete "Save" Feature for Live News

**File:** `BriefView+Filtering.swift:307-318`

**Problem:** "Keep" swipe action exists but implementation is incomplete.

---

## 5\. User Interaction Issues

### 5.1 CRITICAL: Missing "Swipe to Play" Gesture

**File:** `ArticleRowView.swift:408-409`

**Problem:**

```
// Don't show action buttons - swipe should just add to queue
// showActionButtons = true  // COMMENTED OUT!
```

Users cannot swipe an article to immediately play it. Current workflow requires:

1.  Swipe to save (adds to queue)
2.  Navigate to Brief
3.  Tap to play

**Expected:** Single swipe gesture to play immediately.

**Recommendation:**  
Re-enable action buttons overlay OR implement dedicated "swipe left = play now" gesture.

---

### 5.2 HIGH: Inconsistent Haptic Feedback

**Problem:**

*   ArticleRowView: Uses `HapticManager.shared`
*   LiveNewsViewV2: Uses `UIImpactFeedbackGenerator` directly

**Recommendation:** Standardize on HapticManager for consistency.

---

## 6\. Gemini TTS API Update

Based on the provided Gemini 2.5 Flash TTS documentation, the current implementation needs updates:

### 6.1 Current vs. Recommended Configuration

| Aspect | Current | Recommended |
| --- | --- | --- |
| Model | `gemini-2.5-flash-preview-tts` | Correct |
| Sample Rate | Hardcoded 24kHz | Parse from response |
| Voice Selection | Sequential rotation | Random or user preference |
| Multi-speaker | Not implemented | Optional enhancement |
| Streaming | Not implemented | Consider for long content |

### 6.2 Voice Options Available

The current implementation correctly includes all 30 voices:

```
Autonoe, Zephyr, Puck, Charon, Kore, Fenrir, Leda, Orus, Aoede,
Callirhoe, Enceladus, Iapetus, Umbriel, Algieba, Despina, Erinome,
Alatheia, Tethys, Helike, Vindemiatrix, Sadachbia, Sadatoni,
Sulafat, Lesath, Gacrux, Pulcherrima, Achird, Zubeneschamali,
Elara, Alnilam
```

### 6.3 Recommendations

1.  **Consider Native Multi-Modal Output**: For dialogue/multi-speaker content
2.  **Implement Streaming**: For better UX on long articles
3.  **Voice Affinity**: Let users pick preferred voices, remember across sessions
4.  **Verify Sample Rate**: Ensure 24kHz is correct for current API version

---

## 7\. Prioritized Fix Roadmap

### Phase 1: Critical Fixes (Immediate)

| # | Issue | Est. Hours | Files |
| --- | --- | --- | --- |
| 1 | Remove/fix QueueServiceV2 | 4 | QueueServiceV2.swift, BriefeedApp.swift |
| 2 | Add UnifiedAudioPlayer persistence | 8 | UnifiedAudioPlayer.swift |
| 3 | Fix double truncation | 1 | GeminiService.swift |
| 4 | Integrate TTSQuotaManager | 2 | TTSGeneratorService.swift, GeminiTTSService.swift |
| 5 | Fix Play All filter bug | 2 | BriefView+Filtering.swift |
| 6 | Connect episode swipe actions | 1 | LiveNewsViewV2.swift |
| 7 | Implement queue reordering | 2 | BriefView+Filtering.swift, AudioPlayerViewModelV2.swift |
| **Total** |   | **20 hours** |   |

### Phase 2: High Priority (Week 1-2)

| # | Issue | Est. Hours | Files |
| --- | --- | --- | --- |
| 8 | Fix reordering state preservation | 3 | AudioPlayerViewModelV2.swift |
| 9 | Remove invalid OpenAI model | 1 | OpenAITTSServiceSimple.swift |
| 10 | Fix device TTS fallback | 4 | GeminiTTSService.swift OR TTSGeneratorService.swift |
| 11 | Add retry logic for TTS | 4 | TTSGeneratorService.swift |
| 12 | Surface summarization errors to UI | 4 | UnifiedAudioPlayer.swift, MiniAudioPlayerV4.swift |
| 13 | Fix error message saved as summary | 2 | UnifiedAudioPlayer.swift |
| 14 | Consider Gemini 1.5 Flash | 2 | GeminiService.swift |
| **Total** |   | **20 hours** |   |

### Phase 3: Medium Priority (Week 2-3)

| # | Issue | Est. Hours | Files |
| --- | --- | --- | --- |
| 15 | Implement swipe-to-play | 4 | ArticleRowView.swift |
| 16 | Refactor formatArticleForTTS | 4 | UnifiedAudioPlayer.swift |
| 17 | Fix JSON parsing robustness | 4 | GeminiService.swift |
| 18 | Remove dead code | 2 | Multiple files |
| 19 | Standardize haptic feedback | 1 | LiveNewsViewV2.swift |
| 20 | Add queue position to episodes | 2 | EpisodeRowV2.swift |
| **Total** |   | **17 hours** |   |

### Phase 4: Polish (Week 3+)

| # | Issue | Est. Hours |
| --- | --- | --- |
| 21 | Use SHA256 for cache keys | 2 |
| 22 | Add comprehensive tests | 16 |
| 23 | Add analytics/telemetry | 8 |
| 24 | Implement OpenAI streaming | 8 |
| 25 | Extract magic numbers to constants | 2 |
| **Total** |   | **36 hours** |

---

## 8\. Questions for Clarification

Before proceeding with implementation, I need clarification on the following:

### Queue Behavior

**Q1:** When user plays Live News, should it:

*   (a) Replace the existing queue with episodes
*   (b) Append episodes to existing queue
*   (c) Maintain separate article and episode queues
*   (d) Ask user what to do  
      
    when they play from the live news page, it just starts playing without builduing the live news. there can maybe be an add latest episodes to brief. and then the brief can have it in the live news. and for news (not articles) maybe we expire them after some time which is in the settings, maybe 2-3 days of being in the queue as the news gets stale and i can gointo the news and ad individual episodes if i want to listne backwards, but those get stale, where as the reddit and other articles shouldn't expire. 

**Q2:** Should queue state persist across app restarts?

*   (a) Yes, restore exact queue with position
*   (b) Yes, but start from beginning
*   (c) No, start fresh each launch

 yes, the queue state should persist across app restarts, and there should be an expiration only on the live news because that becomes stale. It's from when they're added, and that should be able to be set in the settings. The default should be maybe 48 hours or something. the idea with the feed and the way we had it before was that we listen to the older stories first to kind of clear them out as we add new stories in the top because those also need to be processed and whatnot as they're in the queue. So that was kind of the way to limit the amount of tokens and expenses was to not process every story if we're never going to listen to the audio or if we're just reading the summary etc 

**Q3:** Should RSS episodes expire from queue?

*   Currently they have optional expiration
*   Should "Keep" feature actually work?  
      
     I believe I've addressed this above. The feature for the RSS feed adds things, they stay. The audio stream, streams coming from a live news, those are the ones that expire  
     

### TTS Behavior

**Q4:** Preferred TTS fallback chain:

*   (a) OpenAI TTS → Gemini TTS → Device TTS (current)
*   (b) Gemini TTS → OpenAI TTS → Device TTS
*   (c) User configurable
*   (d) Remove device TTS entirely (requires API key)  
      
      
     the main TTS we're going to use is the Gemini 2.5 flash  "gemini-2.5-flash-preview-tts" which is a cheap, fast model that is able to generate high-quality voices and is the main one we'll be relying on and should stay up, and of which you should allow me in the settings to put and save a Gemini Google API key   
     

**Q5:** When approaching Gemini daily quota (100 generations):

*   (a) Warn user and continue with Gemini
*   (b) Automatically switch to OpenAI/device
*   (c) Block generation and prompt user
*   (d) Show banner but let user choose  
      
     that is out of beta now and I don't have a quota

### UI/UX

**Q6:** What should "swipe article" do in feed view?

*   (a) Swipe right = save + queue, Swipe left = archive (current)
*   (b) Swipe right = play now, Swipe left = queue for later
*   (c) Show action overlay with Play Now / Play Later options
*   (d) Other: \_\_\_\_\_\_\_\_\_\_\_

 I think a small swipe right was to add to the queue, and there's supposed to be a button that appears that says "Play Now" or "Play Next". Otherwise, it just goes to the bottom of the queue   
 Swipe left can be removed from the feed / archive  
  
**Q7:** Should Brief view auto-load saved articles to queue on appear?

*   (a) Yes, always
*   (b) Only if queue is completely empty
*   (c) Never (let user explicitly tap Play All)  
      
     the brief you should always show the  articles and news saved from the sources in the queue.

**Q8:** Priority of features to remove vs. implement:  
Several features have partial implementations (action buttons overlay, queue reordering, episode save). Should we:

*   (a) Remove all partial features for cleaner codebase
*   (b) Complete all partial features
*   (c) Prioritize specific features: \_\_\_\_\_\_\_\_\_\_\_  
      
    Those features such as queue reordering are important, and saves are also important. So they should be put into the PRD for the future. And I don't know the action buttons, I'm not sure what that is, but that is important. But more importantly is getting the audio playing properly, getting the summarization work, getting the core features working, and then making sure we know what we need to work on next or what needs to be refactored next. 

### Architecture

**Q9:** Should we consolidate to a single QueueCoordinator service?

*   (a) Yes, create new unified service
*   (b) No, enhance existing UnifiedAudioPlayer
*   (c) Keep separate services but add synchronization  
      
     I think a new unified service could be good, especially since you're architecting it from scratch, but you need to understand the nuances of the decision-making that went into the articles from the feed that are being summarized, and then the live news, which is constantly updating but for the same sources that those are basically available as well. They could be in the same briefing (all) together.

**Q10:** Model preference for summarization:

*   (a) Stay with Gemini 2.5 Flash 
*    use the new Gemini Flash TTS model I provided above 

---

## 9\. Technical Debt Summary

### Dead Code to Remove

| File | Lines | Description |
| --- | --- | --- |
| TTSGeneratorService.swift | 298-329 | generatePlaceholderAudio() |
| ArticleRowView.swift | 434-501 | Action buttons overlay |
| QueueServiceV2.swift | Entire file | Unused service |
| AudioPlayerViewModelV2.swift | 466-470 | Duplicate saveQueueState() |

### Duplicate Logic to Consolidate

1.  **Cache key generation** - GeminiTTSService + AudioCacheManager
2.  **Title deduplication** - UnifiedAudioPlayer (2 places)
3.  **Queue item matching** - BriefView+Filtering (3 places)
4.  **Content truncation** - UnifiedAudioPlayer + GeminiService

### TODOs in Code

| File | Line | TODO |
| --- | --- | --- |
| BriefView+Filtering.swift | 285 | Implement queue reordering |
| BriefView+Filtering.swift | 315 | Implement item save |
| QueueServiceV2.swift | 285 | Implement fetchArticle |

### Security Considerations

1.  **API Keys in UserDefaults** - Should use Keychain
2.  **API Keys in Logs** - Some logging may expose keys
3.  **Temp File Cleanup** - Some error paths may leave temp files

---

## Appendix A: File Reference

### Core Services

*   `Core/Services/Audio/TTSGeneratorService.swift` - TTS orchestrator
*   `Core/Services/Audio/UnifiedAudioPlayer.swift` - Playback + queue
*   `Core/Services/Audio/SwiftAudioExService.swift` - Audio player wrapper
*   `Core/Services/Audio/OpenAITTSServiceSimple.swift` - OpenAI TTS
*   `Core/Services/GeminiTTSService.swift` - Gemini TTS
*   `Core/Services/GeminiService.swift` - Summarization
*   `Core/Services/QueueServiceV2.swift` - Legacy queue (unused)

### ViewModels

*   `Core/ViewModels/AudioPlayerViewModelV2.swift` - Audio state
*   `Core/ViewModels/AppViewModel.swift` - App facade
*   `Core/ViewModels/BriefViewModel.swift` - Brief tab state

### Views

*   `Features/Brief/BriefView+Filtering.swift` - Queue UI
*   `Features/LiveNews/LiveNewsViewV2.swift` - RSS feed UI
*   `Features/Feed/CombinedFeedView.swift` - Article feed UI
*   `Features/Article/ArticleRowView.swift` - Article display
*   `Features/Audio/MiniAudioPlayerV4.swift` - Mini player
*   `Features/Audio/ExpandedAudioPlayerV2.swift` - Full player

---

## Appendix B: Test Coverage Gaps

### Unit Tests Needed

*   Queue persistence round-trip
*   TTS quota management
*   Summarization error handling
*   Queue item conversion
*   Content truncation

### Integration Tests Needed

*   End-to-end article → summary → TTS → playback
*   Queue operations across app lifecycle
*   Mixed content playback
*   Network failure recovery

### UI Tests Needed

*   Swipe gestures
*   Queue filter changes
*   Play All behavior
*   Edit mode operations

---

**End of PRD**

_This document will be updated based on answers to clarification questions._
