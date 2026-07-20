# Briefeed Live Radio MVP Design

**Date:** 2026-07-19  
**Status:** Proposed for implementation planning  
**Product focus:** Reliable, quick, lean-back news radio from RSS podcast audio  
**Relationship to existing PRD:** This specification governs the Live Radio vertical slice. It does not delete or redesign the Brief, Feed, Reddit, article summarization, or TTS systems. Where `PRD-REFACTOR-V2.md` describes Live News as a temporary non-persisted playback list, this specification supersedes that behavior for Radio playback.

## Product Intent

Briefeed should open into a useful audio experience even while Reddit ingestion and the future shared content backend remain unfinished. The primary launch experience is a Radio tab that plays current podcast news from configured sources such as NPR and BBC.

The experience is designed for short, repeated visits:

- With autoplay enabled, a cold launch begins or resumes Radio with minimal delay.
- Reopening the app during the same listening window does not restart completed episodes.
- A partially played episode resumes from its saved position.
- A user can press Next to defer that episode and continue immediately.
- Refresh adds new episodes without replacing the current session or duplicating entries.
- The player remains understandable and controllable in the app, on the Lock Screen, and in Control Center.

The MVP should be independently useful without depending on Reddit discovery, article summarization, Gemini TTS, PocketTTS, Supabase, Render, or another server-side content pipeline.

## Approved Experience

The approved visual direction is stored at:

![Approved Live Radio navigation and mini-player](assets/live-radio-approved-navigation.png)

The required interaction hierarchy is:

1. Radio is the first and default app destination.
2. The bottom navigation is one compact, centered, icon-only glass rail with Radio, Brief, and Feed.
3. Settings is removed from the bottom navigation and opened from a top-right gear button.
4. A persistent black mini-player sits below the navigation rail when a Radio or Brief session exists.
5. Mini-player metadata, speed, and sleep controls occupy the left zone.
6. Back 10 seconds, play or pause, forward 10 seconds, and Next occupy an elevated right-aligned action zone.
7. The scrubber is thin, secondary, and draggable, with a larger invisible interaction area.
8. The mini-player has no waveform.
9. Tapping the upward chevron opens the expanded player.

The rendered chrome may be visually compact, but every interactive control must retain a minimum 44 by 44 point hit target.

## Scope

### In Scope

- Radio as the first tab and the primary launch surface.
- Opt-in cold-launch autoplay, disabled by default.
- A persisted Radio session independent of the Brief queue.
- Deterministic source ordering using the user's saved feed priority.
- Partial playback resume and completion tracking.
- Refresh and queue replenishment without duplicates.
- Manual Next behavior that does not lose partial progress.
- Playback speed from 0.5x through 3.0x, persisted as the last-used speed.
- Back and forward 10-second controls in the app and remote-command configuration.
- Next Episode in the mini-player and remote commands where iOS exposes it.
- A sleep timer with End of Episode, presets, and an exact custom duration.
- Background audio, interruptions, route changes, Now Playing metadata, Lock Screen, and Control Center behavior.
- Explicit empty, offline, stale, feed-failure, and playback-failure states.
- Unit, integration, UI, simulator, and physical-device verification.
- A thin Briefeed adapter over the shared simulator-fleet engine.
- A verified archive suitable for the next iOS distribution step.

### Preserved but Not Repaired by This Slice

- Brief queue and article playback.
- Feed browsing and article interactions.
- Existing RSS feed add, enable, delete, detail, and reorder operations.
- Article summarization and TTS code.
- Existing settings unrelated to Radio.

### Out of Scope

- Fixing Reddit ingestion.
- Supabase or Render content services.
- Mixing Radio episodes into the Brief queue automatically.
- User-authored episode playlists or arbitrary per-episode drag ordering.
- Guaranteed offline episode downloads.
- Background fetch while the app is suspended.
- CarPlay, widgets, and watchOS.
- On-device transcription, ad classification, smart ad skipping, or automatic ad skipping. That research remains isolated in GitHub issue #10.
- Irreversible TestFlight or App Store publication.

## Current-State Findings

The existing code contains useful foundations but does not satisfy the product behavior:

- `UnifiedAudioPlayer.liveNewsStreamQueue` is explicitly temporary and non-persisted.
- Live News marks an episode listened when playback starts rather than when playback completes.
- Live News progress is excluded from `QueueCoordinator` and is not saved to `RSSEpisode`.
- `RSSEpisode.lastPosition` is defined as a normalized 0 through 1 fraction, while Brief queue position is stored in seconds.
- `SwiftAudioExService` owns a second private URL queue and can auto-advance after notifying `UnifiedAudioPlayer`, creating double-advance risk.
- Cold-launch autoplay rebuilds one latest unlistened episode per feed instead of restoring a prior Radio session.
- Feed refresh is already persisted and deduplicated by `(guid, feedId)`, but multiple queue builders disagree about ordering.
- Two foreground refresh timers are registered.
- Background audio capability, spoken-audio session configuration, remote commands, Now Playing metadata, and interruption handling already exist.
- No sleep-timer domain state exists.
- The deployment target is iOS 18.2, while native Liquid Glass view APIs require an availability-gated iOS 26 path.

## Architecture Alternatives

### Option A: Separate Persisted Radio Session Coordinator - Recommended

Create a `RadioSessionCoordinator` as the single source of truth for Radio order, current episode, progress, autoplay, refresh reconciliation, error disposition, and sleep state. Store a lightweight Codable snapshot in UserDefaults and continue using Core Data for RSS feed and episode records. `UnifiedAudioPlayer` derives its Radio presentation from this coordinator and plays one URL at a time.

**Advantages**

- Keeps Radio independent of the broken article pipeline.
- Reuses existing RSS and audio foundations.
- Avoids a Core Data model migration for the first release.
- Makes restart restoration and deterministic reconciliation explicit.
- Closely mirrors the successful single-source pattern already used for Brief.

**Costs**

- Adds a second coordinator, intentionally scoped to a different playback product.
- Requires removing direct mutations of the temporary Live News queue.
- Requires a small event seam between the coordinator and `UnifiedAudioPlayer`.

### Option B: Extend QueueCoordinator to Own Radio and Brief

Add a second persisted queue or playback mode to `QueueCoordinator` and route Radio through it.

**Advantages**

- Fewer coordinator types.
- Some persistence helpers could be shared.

**Costs**

- Re-couples Radio to article and Brief queue semantics.
- Makes expiration, completion, retry, and navigation rules conditional throughout a foundational service.
- Increases regression risk in the already-complex article path.
- Conflicts with the goal that Radio remain independently shippable.

### Option C: Persist RadioSession and RadioQueueEntry as Core Data Entities

Create Core Data entities for sessions, ordered entries, seconds-based progress, failure state, and completion.

**Advantages**

- Strong relational persistence and queryability.
- Better long-term foundation for multiple playlists and history.

**Costs**

- Requires a model migration and migration tests before product behavior can be validated.
- The current persistence fallback can delete the store after selected migration failures.
- Adds complexity that the single-session MVP does not need.

### Decision

Use Option A. Add only small pure-value shared primitives where they reduce duplication. Do not move Radio into `QueueCoordinator`, and do not add new Core Data entities in this slice.

## Component Boundaries

### RadioSessionCoordinator

`RadioSessionCoordinator` is an `@MainActor` observable service and the only writer of Radio session state.

Responsibilities:

- Restore and validate the persisted Radio snapshot.
- Build the initial queue from Core Data episodes.
- Reconcile queue state after feed refresh.
- Persist current episode, order, per-entry position, and disposition.
- Decide which episode is next.
- Apply autoplay policy once per cold launch.
- Route play, pause, seek, skip, Next, completion, failure, and connectivity events.
- Own sleep-timer state and expiration behavior.
- Expose a stable read-only presentation state to view models.

It does not fetch or parse RSS itself, synthesize audio, own the Brief queue, or render UI.

### RadioQueueBuilder

`RadioQueueBuilder` is a pure type with no singleton or UI dependency.

Inputs:

- Enabled feeds and their priorities.
- Episodes grouped by feed.
- The validated prior snapshot.
- Current time.
- Freshness and retention policy.

Output:

- A deterministic ordered list of `RadioQueueEntry` values.
- A reconciliation report describing retained, appended, completed, expired, missing, disabled, and duplicate entries.

### RadioSessionStore

`RadioSessionStore` encodes and decodes `PersistedRadioSession` under a versioned UserDefaults key. Writes are debounced during progress updates and forced on pause, Next, completion, background transition, and termination notification.

Corrupt or unsupported state fails closed by discarding only the Radio snapshot. It must never delete RSS Core Data or the Brief queue.

### RSSAudioService

`RSSAudioService` remains the RSS fetch, parse, Core Data save, and source-management service.

Changes are limited to:

- One authoritative active-app refresh schedule.
- Stable episode identity and duplicate protection.
- A structured per-source refresh result instead of one overwritten `lastError`.
- A refresh completion event consumed by `RadioSessionCoordinator`.

### UnifiedAudioPlayer

`UnifiedAudioPlayer` remains the app-wide playback facade and the projection layer for Brief and Radio presentation.

For Radio:

- Its queue and index are read-only projections derived from `RadioSessionCoordinator`.
- It plays the coordinator-selected episode and seeks to the supplied seconds position.
- It forwards progress, completion, and playback errors to the coordinator.
- It never marks an episode listened at playback start.
- It never directly appends, removes, reorders, or resets Radio entries.

Brief behavior remains delegated to `QueueCoordinator`.

### SwiftAudioExService

`SwiftAudioExService` becomes a single-item transport adapter:

- Load and play exactly one URL.
- Pause, resume, stop, seek, and set rate.
- Publish player state, progress, completion, interruption, route, and remote-command events.
- Publish Now Playing metadata.

Its private URL queue, index, `loadQueue`, `playNext`, `playPrevious`, and completion-time auto-advance are removed or made unreachable. High-level coordinators alone decide navigation.

### RadioPresentationModel

`AudioPlayerViewModelV2` may continue to expose the app-wide player API, but its Radio properties derive from `RadioSessionCoordinator`. Views never read Core Data directly to decide current Radio order.

## Persisted Data Model

The stored schema is versioned from its first release:

```swift
struct RadioEpisodeKey: Codable, Hashable {
    let feedID: String
    let episodeID: String
}

enum RadioEntryDisposition: String, Codable {
    case pending
    case playing
    case deferred
    case failedThisSession
}

struct RadioQueueEntry: Codable, Identifiable, Equatable {
    var id: RadioEpisodeKey { key }
    let key: RadioEpisodeKey
    var positionSeconds: TimeInterval
    var disposition: RadioEntryDisposition
    var playbackFailureCount: Int
    var lastPlaybackError: String?
}

struct PersistedRadioSession: Codable, Equatable {
    let schemaVersion: Int
    var entries: [RadioQueueEntry]
    var currentKey: RadioEpisodeKey?
    var savedAt: Date
}
```

UserDefaults key:

```text
briefeed_radio_session_v1
```

Core Data remains authoritative for:

- Feed identity, enablement, priority, and refresh metadata.
- Episode title, enclosure URL, publication date, duration, and source relation.
- `isListened` and `listenedDate` completion history.
- Existing normalized `lastPosition`, updated only when duration is known.

The snapshot remains authoritative for seconds-based resume position and Radio order. The implementation must not reinterpret legacy fractional `lastPosition` values as seconds.

## Stable Identity and Deduplication

The durable episode key is `(feedID, episodeID)`, not `episodeID` alone.

Within one refresh:

1. Prefer a non-empty RSS GUID as `episodeID`.
2. If GUID is absent, derive a deterministic ID from normalized enclosure URL plus publication timestamp.
3. Never derive an ID from `Date()`.

Within the active Radio session:

- Reject duplicate `RadioEpisodeKey` values.
- Reject a second entry with the same normalized enclosure URL, even if syndicated by another enabled feed.
- Preserve the first occurrence according to source priority.

## Queue Ordering and Reconciliation

### Source Order

Enabled feeds are sorted by:

1. `RSSFeed.priority`, ascending.
2. Stable `RSSFeed.id`, ascending, as the deterministic tie-breaker.

The existing drag-to-reorder feed UI remains the user's MVP queue-order control.

### Initial Queue

When no valid snapshot exists:

1. For each enabled feed in source order, inspect its single newest published episode.
2. Hourly-source freshness is 2 hours.
3. Daily-source freshness is 24 hours.
4. Append that episode only when it is fresh, incomplete, and not a duplicate enclosure.
5. Do not backfill an older episode merely because the newest one was already completed.
6. Append at most one episode per source in the first pass.

If the snapshot is missing but a selected Core Data episode has a valid normalized `lastPosition` and known duration, initialize `positionSeconds` as `lastPosition * duration`. Never apply this conversion when duration is unknown.

This produces a short, source-balanced radio brief instead of allowing one feed to dominate.

### Restored Queue

When a snapshot exists:

1. Resolve each entry by exact `(feedID, episodeID)`.
2. Drop entries whose feed or episode no longer exists.
3. Drop entries from disabled feeds.
4. Drop completed entries.
5. Drop entries beyond retention.
6. Preserve the remaining entry order and seconds position.
7. Preserve `currentKey` when its entry remains eligible.
8. Append newly eligible episodes after the restored entries.

The queue is never rebuilt from the beginning merely because a refresh returns no new items.

### Replenishment

After a successful or partially successful refresh:

- Keep the current entry and all still-eligible existing entries in their persisted order.
- Append new candidates in source priority order.
- Append no more than one new latest episode per source per reconciliation pass.
- Never insert a new episode ahead of the currently playing or paused episode.
- Never replay an entry already completed.

### Source Reordering

Changing feed priority does not interrupt the current episode. It reorders only pending, never-started entries after the current entry. Deferred partial entries retain their relative position so a user pressing Next is not immediately returned to the same episode.

## Playback Semantics

### Partial Episode

- Save position in seconds at least every 5 seconds while playing.
- Force a save on pause, seek completion, Next, background transition, route loss, interruption, and termination notification.
- On a cold launch with autoplay enabled, resume the current partial episode if it remains within retention.
- On a cold launch with autoplay disabled, restore it in a paused ready state.

### Manual Next

Manual Next means "defer this episode and continue," not "mark complete."

- Save the current seconds position.
- Change its disposition to `deferred`.
- Move it behind all currently pending entries.
- Select and play the next eligible entry.
- If the session later cycles back to the deferred entry, resume it from the saved position.

### Completion

Mark an episode completed when either condition is true:

- The transport reports a successful natural end.
- The user leaves or advances after reaching at least 95 percent of a known duration.

Completion writes `isListened = true`, `listenedDate = now`, and normalized `lastPosition = 1.0`, then removes the entry from the Radio snapshot. A completed episode is never selected again during its retention lifetime.

### Previous Behavior

The mini-player does not include Previous. Back 10 seconds is the fast correction action. The expanded player may expose previous-session navigation only after the Radio coordinator can provide deterministic semantics; it is not required for the first usable build.

### Seeking

- Back and forward actions use exactly 10 seconds.
- Clamp seeks to `0...duration` when duration is known.
- The scrubber accepts taps and drags across a 44-point interaction lane even though the visible rail is thin.
- VoiceOver exposes the scrubber as adjustable, announces elapsed and remaining time, and changes in useful increments.

### Playback Speed

- Supported values are `0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0`.
- Persist the last-used value for both Radio and Brief playback.
- Clamp a legacy saved value above 3.0 to 3.0 on load.
- Remote-command supported rates match the same list.

## Autoplay and Lifecycle State Machine

### States

```text
idle
restoring
readyPaused
loading
playing
pausedByUser
waitingForNetwork
exhausted
failed
```

Sleep state is orthogonal:

```text
off
deadline(Date)
endOfEpisode
```

### Cold Launch

1. Load user settings and Core Data.
2. Restore and reconcile the Radio snapshot using local data only.
3. If autoplay is enabled and an eligible entry exists, start or resume it immediately.
4. Begin `refreshIfStale` without blocking playback from local episode metadata.
5. Reconcile and append after refresh returns.
6. If no local entry exists, show an updating state while refresh runs.
7. If refresh produces an entry and autoplay is enabled, start it.
8. If no entry exists, transition to `exhausted`.

Autoplay is off by default and is exposed as a clear Radio setting. It runs once per process cold launch, not every time the scene becomes active or the Radio tab appears.

### Foreground Return

- If audio is playing, continue playing.
- If the user paused, remain paused.
- Do not invoke autoplay again.
- Refresh only when source data is stale, and reconcile without replacing the session.

### Background Transition

- Persist the snapshot immediately.
- Continue active audio under the existing background-audio mode.
- Do not start a new feed refresh solely because the app entered background.
- Continue evaluating an armed sleep deadline while audio remains active.

### Interruption and Route Change

- Pause on interruption start.
- Resume after interruption only when iOS supplies `shouldResume` and the user had not paused first.
- Pause when headphones or an external route are removed.
- Persist position before changing playback state.

## Refresh, Failure, Offline, and Empty Behavior

### Feed Refresh Failure

- Each source produces an independent success or failure result.
- Failure of one source does not fail the whole refresh.
- Existing queued entries from that source remain playable.
- The Radio screen shows a source-level retry affordance and last-success context.
- Successful sources can still replenish the queue.

### Episode Playback Failure

- If online, retry opening the current stream once after a short delay.
- After the retry fails, preserve its position, mark it `failedThisSession`, and advance.
- Do not mark it completed.
- Do not retry the same failed entry again during the same uninterrupted queue pass.
- A manual source refresh or later cold launch normalizes `failedThisSession` back to `pending`, clears its transient error count, and allows one new bounded attempt.
- If every remaining entry fails, stop in `failed` with a clear Retry action.

### Offline

- Do not run a feed refresh while offline.
- Allow currently buffered playback to continue.
- Prefer `downloadedFilePath` when it exists and points to a readable file.
- If the selected episode requires the network, save position and transition to `waitingForNetwork` without advancing or marking complete.
- When connectivity returns, retry the same selected episode once, then resume normal failure handling.
- Guaranteed episode downloading is not part of this MVP.

### Stale and Missed Episodes

- A newly built session considers only fresh candidates: 2 hours for hourly sources and 24 hours for daily sources.
- A persisted, already-selected episode remains eligible through retention: 24 hours for hourly sources and 7 days for daily sources.
- A partial episode beyond retention is removed from the Radio session and is not auto-resumed.
- Older unplayed episodes that were never in the persisted session are not backfilled automatically.

### Empty Queue

When no eligible entry remains:

- Stop automatic advancement.
- Show `You're caught up` in the player.
- Keep Refresh available.
- Keep autoplay preference unchanged.
- Do not loop completed episodes or rebuild from the first source.

## Sleep Timer

The moon control opens a compact menu containing:

- Off
- End of Episode
- 10 minutes
- 20 minutes
- 30 minutes
- 45 minutes
- 60 minutes
- Custom

Custom duration uses an exact minute stepper from 1 through 180 minutes, initialized to 20 minutes. A slider is not used for the final exact value because it makes single-minute selection unnecessarily imprecise.

Behavior:

- Setting a duration replaces any existing timer atomically.
- The mini-player shows remaining time in the sleep control's accessibility value and compact visible state.
- At a deadline, pause playback once, persist position, and clear the timer.
- Deadline expiration never marks the episode complete.
- End of Episode allows the current episode to finish, suppresses auto-advance, persists the next cursor, and pauses.
- Canceling the timer has no playback side effect.
- The timer survives ordinary foreground/background transitions by storing an in-memory deadline and checking it on progress and lifecycle events.
- The timer does not survive process termination or a new cold launch.

## Navigation and Player UI

### Root Navigation

Introduce:

```swift
enum AppTab: Hashable {
    case radio
    case brief
    case feed
}
```

`ContentView` owns the selected `AppTab`, defaulting to `.radio`. Keep a `TabView` to preserve each section's state, hide its native tab bar, and place custom lower chrome through `safeAreaInset(edge: .bottom)` rather than a fixed 49-point offset.

The lower chrome order is:

```text
RadioTabRail
MiniAudioPlayerV4
system safe area / home indicator
```

### RadioTabRail

- One centered glass capsule.
- Three icon-only controls: Radio, Brief, Feed.
- Selected Radio uses the app's restrained red accent and a soft inner selection lozenge.
- No visible text labels.
- VoiceOver labels are `Radio`, `Brief`, and `Feed`.
- The selected item has the selected accessibility trait.
- The rail remains stable across active and inactive player states.

### Glass Availability

- iOS 26 and later: use `GlassEffectContainer` and native glass effects where they preserve the approved proportions.
- iOS 18.2 through 25: use a smoky adaptive material, fine highlight, and restrained shadow.
- Reduce Transparency: use an opaque high-contrast semantic surface.
- Increase Contrast: strengthen symbol and boundary contrast.
- Reduce Motion: use a short cross-fade for selection rather than a spring translation.

Glass is reserved for navigation and the Settings button, not used throughout feed content.

### Settings

Remove Settings as a tab. A top-right gear presents the existing `SettingsView` as a full-height sheet from Radio, Brief, and Feed. Radio-specific settings are grouped at the top of its Audio section:

- Autoplay Radio on cold launch, default Off.
- Playback speed, reflecting the shared last-used value.
- Feed order and enablement link.

### Mini Player

The mini-player remains compact and uses the approved asymmetric layout:

- Left: episode artwork, one-line title, source, speed, sleep state.
- Right: Back 10, dominant Play or Pause, Forward 10, Next.
- Bottom: elapsed time, thin draggable scrubber, remaining time.
- Secondary upward chevron opens the expanded player.

It appears whenever Radio or Brief has a current or resumable session. On the Radio tab with an exhausted session, it remains in a compact stopped state with `You're caught up` and Refresh available.

### Expanded Player

The expanded player continues as a sheet. For this slice it must:

- Use 10-second back and forward intervals.
- Use the same 0.5x through 3.0x speed source.
- Expose the same sleep timer.
- Display the Radio source and current session position.
- Avoid presenting the Brief queue as though it were the active Radio queue.

## Accessibility and Layout

- Use semantic text styles and Dynamic Type instead of fixed point sizes for user-facing text.
- Use `@ScaledMetric` for icon and spacing adjustments that must scale.
- Maintain 44 by 44 point hit areas for all controls.
- Give the scrubber an adjustable accessibility role, value, and increment/decrement behavior.
- Announce play/pause, speed, sleep, and queue-exhausted state changes without excessive live-region chatter.
- Keep the right transport cluster stable when titles, times, or speed values change.
- Truncate metadata before compressing transport controls.
- Validate small iPhone, large iPhone, iPad landscape, default Dynamic Type, XXXL, and accessibility sizes.
- Respect safe areas, keyboard presentation, Reduce Motion, Reduce Transparency, Increase Contrast, and Dark Mode.

## Simulator Fleet and Test Runbook

Briefeed must use the shared simulator-fleet engine at `/Users/me/ericode/skills/app-testing` through a thin repo-owned adapter. It must not copy or reimplement the fleet.

Create:

```text
Briefeed/skills/app-testing/
  SKILL.md
  config.sh
  scripts/build-install.sh
  scripts/radio-fixtures.sh
  scripts/radio-smoke.sh
```

Adapter rules:

- `AGENT_SIM_PREFIX=Briefeed-Codex`.
- Bundle ID is `Matznerd.Briefeed`.
- Every lane receives a distinct key such as `radio-unit`, `radio-ui`, or `radio-manual`.
- All automated lanes remain headless.
- Never select the first available iPhone.
- Never use the protected human simulator.
- Never shut down or erase a simulator the lane did not create.
- Use recorded UUIDs, per-device locks, bounded waits, and fixed DerivedData paths.
- Exit 75 means capacity or routing failure, not a product test failure.
- Run simulator-free compile and analysis gates before claiming a simulator.
- Release the simulator promptly after a lane finishes.

### Deterministic Fixtures

Radio tests must not depend on live publisher feeds. The fixture service provides:

- Three feeds with deterministic priorities.
- Fresh, partial, completed, stale, malformed, duplicate-GUID, and duplicate-enclosure episodes.
- Small local audio files long enough to verify time advancement, seeking, completion, and transition latency.
- Success, delayed response, HTTP failure, invalid media, and offline conditions.
- Launch arguments that disable automatic production startup and select an isolated test store.

## Verification Strategy

### Pure Unit Tests

- Initial queue order and stable tie-breaking.
- Restore and reconciliation without reordering existing entries.
- Freshness and retention boundaries.
- Partial resume and manual-Next deferral.
- Completion removal and same-hour no-replay behavior.
- Disabled and deleted feed removal.
- Duplicate GUID and duplicate enclosure handling.
- Refresh append without duplicate or current-item replacement.
- Bounded playback failure and offline transitions.
- Autoplay cold-launch-only policy.
- Sleep schedule, replacement, cancellation, deadline, and End of Episode.
- Speed clamping and persistence.

### Hosted Integration Tests

- Core Data episode round-trip with exact `(feedID, episodeID)` lookup.
- Persisted Radio snapshot restoration across a new coordinator instance.
- Progress saved in seconds without corrupting normalized Core Data progress.
- One low-level completion event produces exactly one coordinator advance.
- Natural completion versus manual Next semantics.
- Brief queue and position remain unchanged during Radio playback.
- Refresh during active playback preserves the current item.

### XCUITests

- App launches into Radio.
- Icon-only rail switches Radio, Brief, and Feed while preserving state.
- Settings opens and dismisses from each primary section.
- Autoplay Off remains silent; autoplay On begins fixture audio on cold relaunch.
- Mini-player play, pause, back 10, forward 10, Next, speed, sleep, scrubber, and expanded-player presentation.
- Empty, refreshing, offline, source-failure, and caught-up states.
- Relaunch restores partial progress and does not replay completed content.
- Accessibility labels and selected traits for icon-only navigation.

### Headless Simulator Smoke

- Build and install into an owned clone.
- Seed deterministic feeds and local audio.
- Launch Radio, start playback, and prove time advances.
- Exercise Back 10, Forward 10, Next, pause, and resume.
- Relaunch and prove restored item and position.
- Capture bounded logs, UI hierarchy, screenshots, and the `.xcresult` path.

### Physical Device Gate

Simulator success is insufficient for:

- Audible playback quality.
- Screen-lock background continuation.
- Lock Screen and Control Center command layout.
- Bluetooth, AirPlay, headphone removal, and route changes.
- Phone-call and Siri interruptions.
- Network loss and recovery while streaming.
- Sleep timer expiration while locked.
- Real power, thermal, and buffering behavior.

These checks are mandatory before release-candidate signoff.

## Shortest Sequence to a Usable Build

1. Add deterministic Radio unit fixtures and the repo-owned simulator adapter.
2. Add the persisted Radio snapshot, store, pure queue builder, and coordinator tests.
3. Route existing Live News playback through the coordinator and remove low-level queue auto-navigation.
4. Correct seconds progress, partial resume, completion, Next deferral, and refresh reconciliation.
5. Add cold-launch autoplay, lifecycle persistence, offline state, and bounded failure handling.
6. Implement the approved Radio-first navigation and mini-player layout with accessibility and iOS 18.2 fallback.
7. Add speed normalization, remote 10-second commands, and the sleep timer.
8. Run unit, integration, XCUITest, headless simulator, and physical-device gates.
9. Produce and validate a fresh signed archive.

Each step must leave a testable app and must preserve Brief and Feed behavior.

## Distribution Boundary

Deployment means producing a verified build suitable for the next distribution action. It does not mean automatically publishing the app.

Automation may:

- Resolve packages.
- Build, analyze, test, archive, and export when signing is available.
- Inspect bundle identity, version, entitlements, packaged resources, and archive validity.
- Prepare release notes and a TestFlight checklist.

The release audit must treat API values substituted into the application `Info.plist` as extractable public client configuration. Shipping credentials must be removed, restricted to the bundle and allowed APIs where the provider supports it, or explicitly accepted as non-secret client keys before archive approval.

Human-only actions include:

- Creating the missing App Store Connect record for `Matznerd.Briefeed`.
- Confirming agreements, roles, certificates, profiles, privacy answers, and export compliance.
- Approving the final signed archive and version/build numbers.
- Explicitly initiating upload.
- Selecting tester groups and submitting external beta review or App Review.

GitHub issue #7 remains the current App Store Connect blocker. Historical `/tmp` IPA and archive paths are not release evidence for this build and must be regenerated.

## Acceptance Criteria

The Live Radio MVP is ready for a distribution candidate when all of the following are true:

- A fresh install opens to Radio.
- Autoplay is disabled by default and can be enabled in Settings.
- Enabled autoplay runs on cold launch only.
- A partial episode resumes at the saved position after process recreation.
- A completed episode is not replayed after reopening in the same hour.
- Manual Next preserves partial progress and advances to the next eligible episode.
- Feed priority deterministically controls source order.
- Refresh retains current and queued entries, appends new eligible entries, and creates no duplicates.
- Failed sources do not block successful sources.
- Offline state preserves session and position without falsely completing or skipping an episode.
- Exhaustion shows `You're caught up` and does not loop.
- Mini and expanded players use Back 10 and Forward 10.
- Playback speed remains within 0.5x through 3.0x and persists across launch.
- Sleep presets, exact custom duration, cancel, deadline, and End of Episode work while foregrounded and while locked on device.
- Brief queue items, Brief index, and Brief position are unchanged by Radio playback.
- Lock Screen and Control Center show accurate metadata and working play/pause, 10-second skip controls where iOS exposes them, and Next.
- The custom navigation is accessible, safe-area correct, and usable with Dynamic Type and reduced-transparency settings.
- All focused automated gates pass using deterministic fixtures and owned simulator lanes.
- The physical-device checklist passes.
- A fresh archive is validated and the remaining human-only App Store Connect actions are identified.

## Evidence Map

Key current implementation surfaces:

- `Briefeed/Briefeed/ContentView.swift`
- `Briefeed/Briefeed/BriefeedApp.swift`
- `Briefeed/Briefeed/BriefeedApp+RSSV2.swift`
- `Briefeed/Briefeed/Core/Services/RSS/RSSAudioService.swift`
- `Briefeed/Briefeed/Core/Models/RSS/RSSEpisode+CoreDataClass.swift`
- `Briefeed/Briefeed/Core/Models/RSS/RSSEpisode+CoreDataProperties.swift`
- `Briefeed/Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift`
- `Briefeed/Briefeed/Core/Services/Audio/SwiftAudioExService.swift`
- `Briefeed/Briefeed/Core/ViewModels/AudioPlayerViewModelV2.swift`
- `Briefeed/Briefeed/Features/LiveNews/LiveNewsViewV2.swift`
- `Briefeed/Briefeed/Features/Audio/MiniAudioPlayerV4.swift`
- `Briefeed/Briefeed/Features/Audio/ExpandedAudioPlayerV2.swift`
- `Briefeed/Briefeed/Features/Settings/SettingsView.swift`
- `Briefeed/Briefeed/Info.plist`
- `Briefeed/docs/PRD-REFACTOR-V2.md`
- `Briefeed/docs/handoff/pockettts-testflight-handoff.md`
