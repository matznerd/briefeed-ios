# Briefeed iOS Refactor Plan (PRD v2.1)

Source of truth: `docs/PRD-REFACTOR-V2.md`

## Phase 1 (Core Queue System) — Implemented (needs validation)

**Goal:** One persisted Brief queue, reliable after restart, with isolated Live News streaming.

Done:

- `QueueCoordinator` is the persisted source of truth (items + currentIndex + per-item lastPosition/currentPosition).
- `UnifiedAudioPlayer` derives its Brief queue from `QueueCoordinator` and hydrates `Article`/`RSSEpisode` from Core Data by stored IDs after restart.
- Live News playback is a temporary streaming list (not persisted, does not mutate Brief position/state).
- Per-episode Live News “Play Now” streams immediately (no queuing to Brief).
- Queue reorder delegates to `QueueCoordinator` (no duplicate queue mutations).
- Mini player shows during Live News streaming (even if Brief is empty); next/prev works in both modes.
- Playback position is persisted (debounced) and saved on lifecycle events; Brief playback resumes from last position.

Key files:

- `Briefeed/Core/Services/QueueCoordinator.swift`
- `Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift`
- `Briefeed/Core/ViewModels/AudioPlayerViewModelV2.swift`
- `Briefeed/Features/LiveNews/LiveNewsViewV2.swift`
- `Briefeed/Features/Audio/MiniAudioPlayerV4.swift`

### Phase 1 validation checklist (manual)

1. Brief queue persists across restart:
   - Add 2–3 articles to Brief, start playing item 1, scrub to ~10–20s, force close, relaunch.
   - Confirm Brief queue items are present and playback resumes at the saved position on the current item.
2. Hydration after restart:
   - Confirm playback works after restart even if the in-memory caches are empty.
3. Live News streaming is isolated:
   - From Live News tab, tap “Play Live News” and confirm it plays immediately without adding episodes to Brief.
   - While streaming, use next/prev and confirm it navigates within the stream list.
   - Stop playback/relaunch and confirm Brief queue index/position was not overwritten by streaming.
4. Per-episode streaming:
   - In Live News feed details, tap an episode or use “Play Now” swipe → should stream (not queue).
5. Reorder:
   - Reorder Brief queue and confirm no duplicates and playback index stays sane.

## Phase 2 (Summarization Fixes) — In Progress

Primary goal: make summarization reliable, structured, and user-visible on failure (no silent fallbacks).

### Completed:

- [x] Removed double truncation (consolidated to 20k in UnifiedAudioPlayer, removed 10k in GeminiService)
- [x] Increased token budget to 4096 (PRD calls for 4000+)
- [x] Added `errorMessage: String?` and `retryCount: Int` to QueueItem (backward-compatible decoding)
- [x] Added error tracking methods to QueueCoordinator: `markItemFailed`, `resetItemForRetry`, `retryableItems`, `permanentlyFailedItems`
- [x] Added computed properties: `hasFailed`, `canRetry` (max 3 attempts)

### Remaining tasks:

- [ ] Improve prompt-based JSON + parsing reliability (before response_schema)
- [ ] Add retry logic with exponential backoff (3 attempts, transient errors only)
- [ ] Wire up error tracking in UnifiedAudioPlayer summarization flow
- [ ] Improve error surfacing in UI (queue item shows failure + retry, skip to next)

## Notes / Ground Truth

- Gemini TTS model id remains: `gemini-2.5-flash-preview-tts` (see `docs/gemini-tts-docs/gemini-2.5-flash-tts.md`).

