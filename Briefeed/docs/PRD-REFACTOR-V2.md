# Briefeed iOS App - Refactoring PRD v2.0

> **Live Radio MVP focus (updated July 20, 2026):** The independently shippable Live Radio experience specified in [`docs/superpowers/specs/2026-07-19-live-radio-mvp-design.md`](superpowers/specs/2026-07-19-live-radio-mvp-design.md) and sequenced in [`docs/superpowers/plans/2026-07-19-live-radio-mvp.md`](superpowers/plans/2026-07-19-live-radio-mvp.md) is implemented. It supersedes this PRD's temporary, non-persisted Live News behavior and broader phase ordering for the Radio slice. Focused deterministic Radio units, a prior focused Brief regression baseline, and the complete 15-test Radio UI suite pass on the owned iPhone 15 Pro / iOS 18.6 simulator; Analyze, signed archive, and App Store export also pass. This is not a claim that the broad legacy test target is green. The exported artifact is approved only for an explicitly authorized local physical-device test: audible playback, Lock Screen/Control Center, routes, interruptions, and sleep-under-lock remain `NOT RUN`, and its packaged `Info.plist` contains nonempty Firecrawl and Gemini values. Public sharing, TestFlight, and App Store upload are blocked until GitHub issue #16 removes/rotates the embedded credentials and moves privileged Firecrawl access off device. See [`docs/release/LIVE-RADIO-DISTRIBUTION-RECEIPT.md`](release/LIVE-RADIO-DISTRIBUTION-RECEIPT.md).

> **Physical-device hardening amendment (July 20, 2026):** The first iPhone run exposed presentation and cold-launch gaps not represented by the fixture suite. Radio Home first preserves the coordinator's persisted episode order, including the current partially played item, then supplements it with each source's newest out-of-brief episode so listened and latest state remain visible; source administration lives in Settings except for no-source recovery. The mini-player is a compact bottom-docked surface that continues through the home-indicator area, with transport on the right and speed, sleep, and scrubbing in one lower row. Production Radio restoration starts only after the first active scene so a transient launch `.inactive` phase cannot consume autoplay. Focused lifecycle and presentation suites, the expanded 16-test Radio UI suite, and a directly inspected final headless screenshot pass; the exact hardening build is installed and launched on the approved iPhone. Audible autoplay, resume, Lock Screen/Control Center, and sleep-under-lock remain owner-observed physical gates. Podcast ad detection remains separate future research in [`docs/research/2026-07-20-podcast-ad-skip-spike.md`](research/2026-07-20-podcast-ad-skip-spike.md).

**Date:** December 17, 2025
**Version:** 2.1 - All Requirements Finalized
**Status:** Live Radio MVP implemented; focused simulator verification complete; physical-device and credential-remediation gates open

---

## Executive Summary

This PRD synthesizes findings from a comprehensive audit of the Briefeed iOS app, with clarified requirements from the product owner. The app has solid architectural foundations but requires refactoring to fix **fragmented state management**, **incomplete feature implementations**, and **critical integration gaps**.

### Scope

**In Scope:**

*   Queue system consolidation and persistence
*   Gemini 2.5 Flash TTS integration
*   Summarization pipeline fixes
*   Swipe gesture implementation
*   Live News expiration system
*   Settings for API keys and expiration times
*   **Voice rotation system** (newscaster-style transitions)
*   **Autoplay on app open** (with configurable source)
*   **"Add all latest to Brief"** button for Live News
*   **Download queue for offline** playback
*   **Graceful error handling** (continue to next item on failure)

**Out of Scope (Future):**

*   Multi-speaker TTS for dialogue content
*   OpenAI TTS integration (Gemini is primary)
*   Advanced analytics/telemetry

---

## Clarified Requirements

### Content Types and Expiration

| Content Type | Source | Processing | Expiration |
| --- | --- | --- | --- |
| **Articles** | Reddit/RSS feeds | Summarized by Gemini → TTS by Gemini | Never expires |
| **Live News Episodes** | RSS podcast feeds | Streams existing audio URL | Expires after N hours (default 48h) |

**Key Insight:** Articles need summarization + TTS generation. Live News episodes already have audio URLs and just stream directly.

### Queue Behavior

1.  **Queue Order:** FIFO (oldest first) - listen to older stories first to clear backlog
2.  **Persistence:** Queue state persists across app restarts including position
3.  **Adding to Queue:**
    *   Swipe right on article → adds to bottom of queue
    *   After swipe, overlay shows "Play Now" / "Play Next" options
4.  **Live News Playback:**
    *   "Play Live News" starts streaming immediately using a **temporary, non-persisted** playback list (doesn't queue to Brief)
    *   While streaming Live News, next/previous controls navigate within the temporary stream list
    *   Live News streaming must **not** modify/persist the Brief queue or Brief playback position
    *   Mini player must be visible during Live News streaming (even if Brief queue is empty) with pause/next/previous controls
    *   Per-episode "Play Now" actions in Live News also stream immediately (doesn't queue)
    *   Separate "Add latest episodes to Brief" feature queues episodes into Brief
5.  **Expiration:**
    *   Only Live News episodes expire (from when added to queue)
    *   Expiration time configurable in Settings (default: 48 hours)
    *   Articles never expire

### TTS Configuration

**Primary TTS Engine:** Gemini 2.5 Flash TTS

*   Model: `gemini-2.5-flash-preview-tts`
*   No quota limitations (out of beta)
*   Audio: 24kHz sample rate, 16-bit mono PCM → WAV
*   30 available voices with controllable style

**Voice Rotation (Default Behavior):**

*   Rotate between voices for each article like different newscasters
*   Creates natural segment transitions - user knows the story switched
*   Voices should sound like professional public radio newscasters
*   Clear pronunciation optimized for fast playback speeds (1.5x-2x)
*   User can optionally select a single preferred voice instead

**Available Voices (30 total):**
```
Zephyr, Puck, Charon, Kore, Fenrir, Leda, Orus, Aoede, Callirrhoe, Autonoe,
Enceladus, Iapetus, Umbriel, Algieba, Despina, Erinome, Algenib, Rasalgethi,
Laomedeia, Achernar, Alnilam, Schedar, Gacrux, Pulcherrima, Achird,
Zubenelgenubi, Vindemiatrix, Sadachbia, Sadaltager, Sulafat
```

**Settings Required:**

*   Gemini/Google API Key input
*   Voice mode: "Rotate" (default) or single voice selection
*   Voice preview/sample functionality
*   All 30 voices shown when selecting single voice

**No Fallback Needed:** Gemini TTS is reliable and primary. OpenAI TTS code will be removed.

### Swipe Gestures

| Gesture | Location | Action |
| --- | --- | --- |
| Swipe Right (small) | Feed article | Add to queue (bottom), show "Play Now"/"Play Next" overlay |
| Swipe Left | Feed article | Archive/remove from feed |
| Swipe Left | Brief queue item | Remove from queue |
| Swipe to Keep | Brief Live News item | Prevent expiration |

### Brief View

*   Always shows all queued content (articles + Live News episodes)
*   Filter tabs: All / Articles / Live News
*   "Play All" should respect current filter
*   Queue reordering is important (implement drag handles)

### Autoplay on App Open

**Purpose:** Quick access to news - open app and immediately start getting stories.

**Settings Submenu:**

| Option | Behavior |
| --- | --- |
| **Off** (default) | No autoplay |
| **Mixed Brief** | Start playing from Brief queue (articles + episodes) |
| **Articles Only** | Start playing only articles from Brief |
| **Live News** | Start streaming from Live News tab (like "Play Live News" button) |

**UX Considerations:**

*   Once autoplay starts, provide clear quick way to pause/stop
*   Many users open app quickly to catch up, then move on
*   Mini player should be visible immediately with pause button

### Live News "Add to Brief"

**"Add All Latest to Brief" Button:**

*   Located prominently on Live News page
*   Queues latest unlistened episodes from all configured feeds
*   Episodes added to bottom of Brief queue (FIFO)
*   Expiration timer starts when added to Brief

**Per-Episode Actions:**

*   Individual "Add to Brief" action available on each episode row
*   Swipe gesture or action button

### Error Handling

**Graceful Failure Principle:** Never stop the news feed from progressing.

| Scenario | Behavior |
| --- | --- |
| Summarization fails | Show error, offer retry, skip to next item |
| TTS generation fails | Show error, offer retry, skip to next item |
| Network error | Retry automatically 3 times, then show error and skip |
| Audio stream fails | Skip to next item with notification |

**Error Display:**

*   Surface what went wrong (not generic "error occurred")
*   Show retry button on failed items
*   Failed items remain in queue with error indicator
*   User can retry manually or remove from queue

### Offline Support

**Download Queue Feature:**

*   "Download Queue" button to pre-cache all audio
*   Parallel downloads (respectful of bandwidth - 2-3 concurrent)
*   Shows download progress indicator
*   Downloaded items marked with offline indicator

**Offline Behavior:**

*   Queue keeps processing - downloads next item in line
*   Cached audio/summaries play without network
*   If item needs network and unavailable, skip to next cached item
*   When connectivity returns, resume background processing

---

## Architecture Decisions

### Unified Queue System

**Decision:** Create new `QueueCoordinator` service as single source of truth.

**Rationale:**

*   Current 4-queue fragmentation causes state loss and sync issues
*   QueueServiceV2 is unused and broken - remove it
*   UnifiedAudioPlayer handles playback but shouldn't own queue state

**QueueCoordinator Responsibilities:**

1.  Single queue state for both articles and episodes
2.  Persistence to UserDefaults/Core Data
3.  Expiration management for Live News
4.  FIFO ordering
5.  Add/remove/reorder operations
6.  Provide derived playback projections for UnifiedAudioPlayer (without owning queue state)

### Playback Modes

Briefeed has two playback modes with different persistence rules:

1.  **Brief Queue Mode (Persisted):**
    *   Uses `QueueCoordinator` as the single source of truth (items + current index + position)
    *   Persists across app restarts (resume playback where the user left off)
    *   Live News expiration applies only to episodes that have been added to the Brief queue

2.  **Live News Streaming Mode (Not Persisted):**
    *   "Play Live News" plays a temporary list of episodes immediately
    *   Does **not** enqueue episodes into Brief
    *   Does **not** write to/persist `QueueCoordinator` queue/index/position while streaming
    *   Exiting streaming returns the player to Brief queue mode

### Data Model

```swift
struct QueueItem: Codable, Identifiable {
    let id: UUID
    let type: QueueItemType  // .article or .liveNews
    let title: String
    let source: String
    let addedAt: Date
    let expiresAt: Date?  // Only for Live News

	// Article-specific
	/// `Article.id` (Core Data) is a UUID in this project; ensure it is non-nil and persisted before enqueue
	let articleID: UUID?
	var summaryState: SummaryState  // .pending, .generating, .ready, .failed
	var cachedAudioURL: URL?

    // Live News-specific
    /// `RSSEpisode.id` (Core Data) is a String in this project
    let episodeID: String?
    let streamURL: URL?

    // Playback state (Phase 1)
    var lastPosition: TimeInterval = 0
    var isListened: Bool = false

    // Error handling
    var errorMessage: String?  // Specific error description
    var retryCount: Int = 0

    // Offline support
    var isDownloaded: Bool { cachedAudioURL != nil || streamURL != nil }
    var downloadState: DownloadState = .notStarted

    // Voice assignment (for rotation)
    var assignedVoice: String?  // Assigned when queued, used for TTS

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() > expiresAt
    }

    var hasFailed: Bool { summaryState == .failed }
    var canRetry: Bool { hasFailed && retryCount < 3 }
}

enum QueueItemType: String, Codable {
    case article
    case liveNews
}

enum SummaryState: String, Codable {
    case pending
    case generating
    case ready
    case failed
}

enum DownloadState: String, Codable {
    case notStarted
    case downloading
    case downloaded
    case failed
}
```

### Summarization Flow

```
Article queued
    → Check if summary exists
    → If not: Fetch content (Firecrawl if needed)
    → Send to Gemini 2.5 Flash for summarization
    → Use structured output mode (JSON schema)
    → Store summary in Core Data
    → Generate TTS audio with Gemini 2.5 Flash TTS
    → Cache audio file
    → Mark ready for playback
```

**Key Changes:**

1.  Remove double truncation (keep single 50k char limit)
2.  Use Gemini structured output mode for consistent JSON
3.  Increase maxOutputTokens to 4000+ to handle thinking tokens
4.  Surface errors to user instead of silent fallbacks

### TTS Flow

```
Summary ready
    → Format text for TTS (title + summary)
    → Determine voice:
        → If voice rotation enabled (default): Use item.assignedVoice
        → If single voice selected: Use user preference
    → Check audio cache (key = SHA256(text + voice))
    → If not cached: Call Gemini 2.5 Flash TTS
        → Model: gemini-2.5-flash-preview-tts
        → Voice: Assigned or selected voice
        → Output: Base64 PCM → WAV conversion
        → On failure: Retry 3 times, then mark failed and skip
    → Cache audio file
    → Return audio URL for playback
```

**Voice Rotation Logic:**

```swift
// VoiceRotationManager.swift
class VoiceRotationManager {
    static let shared = VoiceRotationManager()

    private let allVoices = [
        "Zephyr", "Puck", "Charon", "Kore", "Fenrir", "Leda",
        "Orus", "Aoede", "Callirrhoe", "Autonoe", "Enceladus", "Iapetus",
        "Umbriel", "Algieba", "Despina", "Erinome", "Algenib", "Rasalgethi",
        "Laomedeia", "Achernar", "Alnilam", "Schedar", "Gacrux", "Pulcherrima",
        "Achird", "Zubenelgenubi", "Vindemiatrix", "Sadachbia", "Sadaltager", "Sulafat"
    ]

    private var currentIndex = 0

    /// Assign voice when item is added to queue
    func assignVoice() -> String {
        let voice = allVoices[currentIndex]
        currentIndex = (currentIndex + 1) % allVoices.count
        return voice
    }

    /// Get voice for item (uses assigned or rotates)
    func getVoice(for item: QueueItem) -> String {
        if UserDefaultsManager.shared.voiceRotationEnabled {
            return item.assignedVoice ?? assignVoice()
        } else {
            return UserDefaultsManager.shared.selectedTTSVoice
        }
    }
}
```

**Gemini TTS API Configuration:**

```swift
// Request structure
let config = GenerateContentConfig(
    responseModalities: ["AUDIO"],
    speechConfig: SpeechConfig(
        voiceConfig: VoiceConfig(
            prebuiltVoiceConfig: PrebuiltVoiceConfig(
                voiceName: voice  // From rotation or user selection
            )
        )
    )
)
```

---

## Implementation Phases

### Phase 1: Core Queue System (Priority: CRITICAL)

**Goal:** Single source of truth for queue with persistence

| Task | Est. Hours | Files |
| --- | --- | --- |
| Create QueueCoordinator service | 6 | New: QueueCoordinator.swift |
| Add queue persistence (UserDefaults) | 4 | QueueCoordinator.swift |
| Implement expiration for Live News | 3 | QueueCoordinator.swift |
| Remove QueueServiceV2 | 2 | Delete file, update BriefeedApp.swift |
| Update UnifiedAudioPlayer to use QueueCoordinator | 4 | UnifiedAudioPlayer.swift |
| Update AudioPlayerViewModelV2 bindings | 3 | AudioPlayerViewModelV2.swift |
| Implement queue reordering | 2 | QueueCoordinator.swift |
| **Phase 1 Total** | **24 hours** |   |

**Phase 1 Notes:**

*   `QueueCoordinator` is the only source of truth for the Brief queue (items + current index + persisted position).
*   `UnifiedAudioPlayer` may maintain a derived, UI-friendly view of the Brief queue, but must rebuild it from `QueueCoordinator` and be able to hydrate required Core Data objects after app restart.
*   Live News playback uses a separate, temporary streaming list and must not mutate/persist Brief queue state.
*   Queue items reference Core Data IDs; enqueue must ensure `Article.id` / `RSSEpisode.id` are stable (generate + persist if missing) to support hydration after restart.

### Phase 2: Summarization Fixes (Priority: HIGH)

**Goal:** Reliable article summarization without silent failures

| Task | Est. Hours | Files |
| --- | --- | --- |
| Remove double truncation | 1 | GeminiService.swift |
| Increase maxOutputTokens to 4000 | 0.5 | GeminiService.swift |
| Implement structured output mode | 4 | GeminiService.swift |
| Add proper error handling (no silent fallbacks) | 3 | UnifiedAudioPlayer.swift |
| Surface errors to UI | 2 | MiniAudioPlayerV4.swift, views |
| Refactor formatArticleForTTS | 3 | UnifiedAudioPlayer.swift |
| **Phase 2 Total** | **13.5 hours** |   |

### Phase 3: TTS Simplification (Priority: HIGH)

**Goal:** Clean Gemini-only TTS with proper caching

| Task | Est. Hours | Files |
| --- | --- | --- |
| Remove TTSQuotaManager (no quota) | 1 | Delete file, update references |
| Remove OpenAI TTS fallback code | 2 | UnifiedAudioPlayer.swift |
| Clean up TTSGeneratorService | 2 | TTSGeneratorService.swift |
| Remove invalid OpenAI model enum | 0.5 | OpenAITTSServiceSimple.swift |
| Remove device TTS fallback (broken anyway) | 1 | GeminiTTSService.swift |
| Add retry logic for network failures | 3 | GeminiTTSService.swift |
| Use SHA256 for cache keys | 1 | GeminiTTSService.swift, AudioCacheManager.swift |
| **Phase 3 Total** | **10.5 hours** |   |

### Phase 4: Swipe Gestures & UI (Priority: MEDIUM)

**Goal:** Complete swipe interactions as designed

| Task | Est. Hours | Files |
| --- | --- | --- |
| Re-enable "Play Now"/"Play Next" overlay | 3 | ArticleRowView.swift |
| Implement swipe-right = queue behavior | 2 | ArticleRowView.swift |
| Fix Play All to respect filter | 2 | BriefView+Filtering.swift |
| Connect episode swipe actions | 1 | LiveNewsViewV2.swift |
| Implement queue reordering in Brief | 2 | BriefView+Filtering.swift |
| Add queue position indicators to episodes | 1 | EpisodeRowV2.swift |
| Standardize haptic feedback | 1 | Multiple files |
| **Phase 4 Total** | **12 hours** |   |

### Phase 5: Settings & Polish (Priority: MEDIUM)

**Goal:** User configuration and cleanup

| Task | Est. Hours | Files |
| --- | --- | --- |
| Add Gemini API key setting | 2 | Settings view, UserDefaultsManager |
| Add Live News expiration setting | 2 | Settings view, UserDefaultsManager |
| Add voice mode setting (rotate/single) | 3 | Settings view, UserDefaultsManager |
| Add voice selection with preview | 4 | Settings view, VoiceRotationManager |
| Add autoplay on app open setting | 3 | Settings view, UserDefaultsManager |
| Remove dead code (cleanup) | 2 | Multiple files |
| Extract magic numbers to constants | 1 | New Constants.swift |
| Store API keys in Keychain | 3 | New KeychainHelper.swift |
| **Phase 5 Total** | **20 hours** |   |

### Phase 6: Advanced Features (Priority: MEDIUM)

**Goal:** Download queue, autoplay implementation, Live News enhancements

| Task | Est. Hours | Files |
| --- | --- | --- |
| Implement VoiceRotationManager | 2 | New: VoiceRotationManager.swift |
| Integrate voice rotation with TTS flow | 2 | GeminiTTSService.swift, QueueCoordinator |
| Add "Add All Latest to Brief" button | 3 | LiveNewsViewV2.swift, QueueCoordinator |
| Implement autoplay on app open | 4 | BriefeedApp.swift, QueueCoordinator |
| Add "Download Queue" button | 2 | BriefView, QueueCoordinator |
| Implement parallel download manager | 4 | New: DownloadManager.swift |
| Add download progress UI | 3 | BriefView, MiniAudioPlayerV4 |
| Offline playback logic (skip unavailable) | 3 | UnifiedAudioPlayer.swift |
| Network connectivity monitoring | 2 | New: NetworkMonitor.swift |
| **Phase 6 Total** | **25 hours** |   |

### Total Estimated Effort

| Phase | Hours | Priority |
| --- | --- | --- |
| Phase 1: Queue System | 24 | CRITICAL |
| Phase 2: Summarization | 13.5 | HIGH |
| Phase 3: TTS Simplification | 10.5 | HIGH |
| Phase 4: UI/Gestures | 12 | MEDIUM |
| Phase 5: Settings | 20 | MEDIUM |
| Phase 6: Advanced Features | 25 | MEDIUM |
| **Total** | **105 hours** |   |

---

## Technical Specifications

### Queue Persistence Format

```
// Saved to UserDefaults
struct PersistedQueueState: Codable {
    let items: [QueueItem]
    let currentIndex: Int
    let currentPosition: TimeInterval  // Playback position
    let savedAt: Date
}

// Keys
let queueStateKey = "briefeed_queue_state_v2"
```

**Important:** `PersistedQueueState` applies to **Brief Queue Mode only**. Live News streaming mode must not persist or overwrite Brief queue position/state.

### Live News Expiration Logic

```
// In QueueCoordinator
func cleanExpiredItems() {
    queue = queue.filter { !$0.isExpired }
}

func startExpirationTimer() {
    Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
        cleanExpiredItems()
    }
}

// Default expiration
let defaultExpirationHours: Int = 48

// Setting
UserDefaults.standard.integer(forKey: "liveNewsExpirationHours") // Default 48
```

### Gemini TTS Integration

```
// GeminiTTSService.swift updates
func generateSpeech(text: String, voice: String = "Autonoe") async throws -> URL {
    let apiKey = KeychainHelper.shared.get("gemini_api_key")
        ?? UserDefaultsManager.shared.geminiAPIKey

    guard let apiKey, !apiKey.isEmpty else {
        throw TTSError.noAPIKey
    }

    // Check cache first
    let cacheKey = SHA256.hash(text + voice)
    if let cached = AudioCacheManager.shared.getCachedAudio(key: cacheKey) {
        return cached
    }

    // Generate with retry
    return try await withRetry(maxAttempts: 3) {
        let response = try await callGeminiTTS(text: text, voice: voice, apiKey: apiKey)
        let audioURL = try convertPCMToWAV(pcmData: response.audioData)
        AudioCacheManager.shared.cache(url: audioURL, key: cacheKey)
        return audioURL
    }
}
```

### Settings Configuration

```swift
// New settings to add
extension UserDefaultsManager {
    // Gemini API Key (should migrate to Keychain)
    var geminiAPIKey: String? {
        get { UserDefaults.standard.string(forKey: "gemini_api_key") }
        set { UserDefaults.standard.set(newValue, forKey: "gemini_api_key") }
    }

    // Live News expiration (hours)
    var liveNewsExpirationHours: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: "liveNewsExpirationHours")
            return value > 0 ? value : 48
        }
        set { UserDefaults.standard.set(newValue, forKey: "liveNewsExpirationHours") }
    }

    // Voice rotation enabled (default: true)
    var voiceRotationEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "voice_rotation_enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "voice_rotation_enabled") }
    }

    // Selected TTS voice (when rotation disabled)
    var selectedTTSVoice: String {
        get { UserDefaults.standard.string(forKey: "selected_tts_voice") ?? "Autonoe" }
        set { UserDefaults.standard.set(newValue, forKey: "selected_tts_voice") }
    }

    // Autoplay on app open
    var autoplayOnOpen: AutoplayMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "autoplay_on_open") else { return .off }
            return AutoplayMode(rawValue: raw) ?? .off
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "autoplay_on_open") }
    }
}

enum AutoplayMode: String, CaseIterable {
    case off = "off"
    case mixedBrief = "mixed_brief"     // All content from Brief queue
    case articlesOnly = "articles_only"  // Only articles from Brief
    case liveNews = "live_news"          // Start streaming Live News tab

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .mixedBrief: return "Mixed Brief (All)"
        case .articlesOnly: return "Articles Only"
        case .liveNews: return "Live News"
        }
    }
}
```

---

## Files to Create

| File | Purpose |
| --- | --- |
| `Core/Services/QueueCoordinator.swift` | Unified queue management |
| `Core/Services/Audio/VoiceRotationManager.swift` | Voice rotation for TTS |
| `Core/Services/DownloadManager.swift` | Parallel queue download for offline |
| `Core/Utilities/KeychainHelper.swift` | Secure API key storage |
| `Core/Utilities/NetworkMonitor.swift` | Connectivity monitoring |
| `Core/Constants.swift` | Magic numbers extracted |

## Files to Delete

| File | Reason |
| --- | --- |
| `Core/Services/QueueServiceV2.swift` | Unused, broken |
| `Core/Services/Audio/TTSQuotaManager.swift` | No quota in production |

## Files to Significantly Modify

| File | Changes |
| --- | --- |
| `UnifiedAudioPlayer.swift` | Use QueueCoordinator, remove dual queue logic, offline skip logic |
| `AudioPlayerViewModelV2.swift` | Bind to QueueCoordinator |
| `GeminiService.swift` | Structured output, remove double truncation |
| `GeminiTTSService.swift` | Remove fallbacks, add retry, integrate VoiceRotationManager |
| `ArticleRowView.swift` | Enable action overlay |
| `BriefView+Filtering.swift` | Fix Play All, implement reordering, add Download Queue button |
| `LiveNewsViewV2.swift` | Add "Add All Latest to Brief" button |
| `BriefeedApp.swift` | Remove QueueServiceV2 init, implement autoplay on open |
| `MiniAudioPlayerV4.swift` | Error display, download progress indicator |
| Settings view | Add new settings (API key, voices, autoplay, expiration) |

---

## Questions Resolved

All questions have been answered and incorporated into this PRD:

| Question | Resolution |
| --- | --- |
| **Voice Selection UI** | Show all 30 voices with preview. Default: voice rotation (like different newscasters). |
| **Voice Style** | Professional public radio style, clear pronunciation for fast playback. |
| **Live News Add to Brief** | "Add All Latest to Brief" button on Live News page. |
| **Autoplay on Open** | Settings submenu: Off / Mixed Brief / Articles Only / Live News. |
| **Error Display** | Surface specific errors, offer retry, continue to next item gracefully. |
| **Offline Behavior** | "Download Queue" feature, skip unavailable items, auto-retry when connectivity returns. |

---

## Success Criteria

### Phase 1 Complete When:

*   Queue state persists across app restarts
*   Queue position preserved
*   Persisted Brief queue can resume playback after restart (no reliance on in-memory caches)
*   Live News episodes expire after configured time
*   Articles never expire
*   Single QueueCoordinator is source of truth
*   Queue reordering works
*   "Play Live News" streams without queuing and does not overwrite Brief position/state
*   Mini player is visible during Live News streaming (even with empty Brief queue) and next/previous controls work within the stream

### Phase 2 Complete When:

*   Articles consistently get summaries (no silent failures)
*   Failed summaries show error to user
*   Retry option available for failed summaries
*   No double truncation

### Phase 3 Complete When:

*   Gemini TTS is sole TTS provider
*   Network failures retry automatically (3 attempts)
*   Audio caching works with SHA256 keys
*   Dead TTS code removed

### Phase 4 Complete When:

*   Swipe right shows "Play Now"/"Play Next" overlay
*   Swipe left archives article
*   Play All respects current filter
*   Episode swipe actions work
*   Queue reordering via drag works

### Phase 5 Complete When:

*   Gemini API key can be set in Settings
*   Live News expiration time configurable
*   Voice mode setting works (rotate/single)
*   Voice selection with preview available
*   Autoplay on app open setting works
*   API keys stored in Keychain
*   All dead code removed

### Phase 6 Complete When:

*   Voice rotation works - different voice per article
*   "Add All Latest to Brief" button works on Live News page
*   Autoplay on app open works for all modes
*   "Download Queue" button pre-caches audio
*   Download progress indicator shows in UI
*   Offline playback skips unavailable items
*   Network connectivity monitoring works
*   Auto-retry when connectivity returns

---

## Next Steps

1.  **Validate Phase 1** - Verify Phase 1 success criteria end-to-end (including restart + Live News streaming)
2.  **Begin Phase 2** - Summarization reliability and error surfacing
3.  **Iterate** - Each phase builds on previous, avoid scope creep

---

**End of PRD v2.1**
