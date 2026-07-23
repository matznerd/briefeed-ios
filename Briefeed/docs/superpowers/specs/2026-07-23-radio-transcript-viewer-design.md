# Briefeed Radio Transcript Viewer Design

**Date:** 2026-07-23  
**Status:** Proposed for product and engineering review  
**Tracking:** GitHub issue #23  
**Depends on:** Live Radio MVP and the completed on-device timed-transcript spike  
**Does not include:** Ad classification or automatic ad skipping (GitHub issue #10)

## Executive Decision

Briefeed will add an iOS 26 synchronized transcript viewer to Radio using
Apple's on-device `SpeechAnalyzer` and the word-level timing primitives already
in the app.

Playback always wins:

1. The selected Radio episode starts playing immediately.
2. If a matching transcript is cached, synchronized text appears immediately.
3. Otherwise, the viewer displays a quiet preparation state while Briefeed
   downloads and transcribes the episode without pausing playback.
4. As soon as the transcript is validated, the viewer begins following the
   player's current episode media time.
5. While Briefeed remains active, it prepares the next two eligible Radio
   episodes in order.
6. An explicit **Prepare All** command snapshots the remaining eligible Radio
   brief and starts a user-visible iOS 26 continued-processing task that may
   finish after Briefeed enters the background.

The automatic lookahead depth is two, not an unbounded feed crawl. On-device
inference has no per-request API charge, but it still consumes network data,
storage, battery, memory, and thermal budget. Prepare All widens that set only
after an explicit user action.

Background behavior is deliberately bounded:

- A background `URLSession` may finish audio downloads while Briefeed is
  suspended or system-terminated.
- Automatic transcript analysis is guaranteed only while the app is active.
- An explicit Prepare All operation may continue analysis in the background
  through `BGContinuedProcessingTask`; the system displays progress and lets the
  user cancel it.
- Returning to Briefeed resumes the highest-priority unfinished transcript.
- V1 does not promise silent automatic speech analysis after the app is
  suspended. Continued analysis requires the user's Prepare All action.

This is the smallest reliable contract that keeps playback smooth, avoids
misrepresenting iOS background guarantees, and makes the next one or two
episodes usually ready before playback reaches them.

## Evidence

The physical-device probe on an iPhone 13 Pro running iOS 26.5.2 cleared the
native engine:

| Input | Audio length | Processing | Throughput | Timing coverage |
| --- | ---: | ---: | ---: | ---: |
| Rights-cleared fixture | 68.23 s | 1.52 s | 44.76x real time | 100% |
| Marketplace excerpt | 90.00 s | 2.23 s | 40.30x real time | 100% |

Both outputs contained true word units with monotonic media-time ranges. The
rights-cleared fixture measured 6.55% word error rate.

The Marketplace excerpt contained two inserted sponsor reads. The last sponsor
word ended at **58.62 seconds**, and the first program word began at **59.40
seconds**. This proves that the timed transcript is precise enough to support a
future ad-boundary system. It does not prove that the app can classify ads
safely, and no skip behavior is included here.

Primary evidence:

- `docs/research/receipts/2026-07-21-apple-speech-transcript-probe.md`
- `docs/superpowers/specs/2026-07-21-on-device-timed-transcript-spike-design.md`
- `docs/superpowers/plans/2026-07-21-on-device-timed-transcript-spike.md`

## Product Intent

Briefeed Radio is for short, repeated listening sessions. The transcript should
make a live brief easier to follow at 1x through 3x without turning Radio into a
document reader.

The viewer must:

- reveal useful text without delaying audio;
- remain synchronized through pause, seek, +/-10 seconds, Next, rate changes,
  background/foreground transitions, and relaunch;
- preserve surrounding context instead of flashing an isolated word;
- keep the current spoken word visually obvious;
- avoid shifting the entire layout on every word;
- remain optional and never interfere with transport controls;
- work entirely on device after the podcast audio is downloaded;
- fail quietly when the device, locale, model asset, network, storage, or
  thermal state cannot support preparation.

The preparation controls must also let a user deliberately trade battery,
storage, and network use for a fully prepared current Radio brief without
making that work automatic or hidden.

## Proposed V1 Experience

### Radio Home Placement

When a Radio episode is selected, a transcript band appears near the top of
Radio, above "Your radio brief" and below the navigation chrome. It uses the
space previously spent on oversized playback artwork or empty hero treatment.
It is not embedded inside the mini-player.

The compact mini-player remains dedicated to:

- episode and source identity;
- back 10 seconds;
- play or pause;
- forward 10 seconds;
- Next;
- playback speed;
- sleep timer;
- scrubber.

Tapping the transcript band opens the expanded transcript experience. Tapping
the source row or episode disclosure continues to open episode history; these
interactions stay independent.

### Prepare All Command

A **Prepare All** command appears after the final item in "Your radio brief,"
inside the scroll content and above the safe-area inset reserved for the
floating navigation and mini-player. It is not added to the already dense
mini-player transport row.

The row shows:

- a familiar download/preparation icon;
- `Prepare all` as the command;
- the number of remaining eligible episodes;
- a short local-processing label;
- completed and total counts while work is active.

Examples:

- `Prepare all · 6 episodes`
- `Preparing 3 of 6`
- `All transcripts ready`

"All" is bounded to a snapshot of the deterministic Radio session at the time
of the tap:

- the current episode;
- pending latest-per-source Radio entries;
- manually queued Radio archive episodes;
- no duplicate `RadioEpisodeKey` values.

It does not include every historical episode in each source, retired hourly
bulletins, completed items no longer in the Radio session, Brief articles, or
episodes that arrive after the task begins. A later refresh may offer Prepare
All again for newly eligible work.

On iOS 26, tapping Prepare All:

1. Captures the immutable episode-key snapshot.
2. Registers and submits a `BGContinuedProcessingTaskRequest` using a unique
   identifier beneath a permitted wildcard prefix.
3. Shows Apple's system progress presentation with the title "Preparing Radio"
   and a useful completed/total subtitle.
4. Reuses the same serial transcript pipeline and persistent per-episode
   checkpoints.
5. Continues if the user backgrounds Briefeed, subject to system expiration,
   resource pressure, or user cancellation.

The user can stop the operation in Briefeed while it is foregrounded or through
the system's progress interface while it is backgrounded. Completed episode
artifacts remain valid; cancellation never rolls them back. Pending episodes
return to `queued` and can be resumed by a later Prepare All action.

Prepare All is hidden or replaced by a clear unavailable message on iOS 18
through 25. It is disabled when there is no eligible work or when required
speech support is unavailable.

### Default Flow View

V1 ships a compact three-line teleprompter:

- the prior line remains visible at reduced emphasis;
- the active line is high contrast;
- the active word receives the Radio accent treatment;
- the upcoming line remains visible at medium emphasis.

Lines are stable groups derived from word units. The projection does not rebuild
or slide all three lines for every word. It advances only when the active word
crosses a line boundary. This prevents visual jitter at 2x and 3x.

The grouping algorithm is deterministic and independent of playback rate:

- prefer punctuation boundaries;
- otherwise cap a line by measured width and a small word-count ceiling;
- retain each word's original timing;
- use the first word's start and last word's end as the line range;
- recompute only when transcript content, width class, Dynamic Type category,
  or display mode changes.

The underlying model remains word-level. A one-word RSVP projection can be
added later without retranscribing audio or changing persistence.

### Expanded View

The expanded player receives a transcript page for the current Radio episode.
It shows more surrounding lines and keeps the active line near the visual
center.

Behavior:

- Normal playback auto-follows media time.
- Manual scrolling temporarily suspends auto-follow.
- A compact "Resume Live" control returns to the active line.
- Tapping a transcript line seeks to its first word.
- The existing player controls remain reachable without dismissing the
  transcript.
- Closing the expanded view returns to the compact three-line projection at the
  same media time.

V1 does not include transcript editing, search, sharing, copying, translation,
or speaker labels.

### Preparation States

The transcript band has explicit states:

| State | Presentation | Playback effect |
| --- | --- | --- |
| `unavailableOS` | "Live transcript requires iOS 26" | None |
| `unsupportedDevice` | "Live transcript is not available on this iPhone" | None |
| `assetRequired` | "Preparing on-device speech model" | None |
| `queued` | "Transcript queued" | None |
| `downloading` | "Preparing transcript" with determinate progress when known | None |
| `transcribing` | "Transcribing on this iPhone" | None |
| `preparingAll` | "Preparing X of Y" with a Stop action | None |
| `ready` | Synchronized three-line text | None |
| `deferred` | "Transcript will continue when Briefeed is active" | None |
| `failed` | Short failure message and Retry action | None |

The preparation view does not use an indeterminate animation that continuously
reflows the layout. Its height is stable across queued, downloading,
transcribing, ready, and failed states.

### Playback Synchronization

`AudioPlayerViewModelV2.currentTime` is the only UI clock.

The viewer:

- never advances from a wall-clock timer;
- never multiplies elapsed time by playback rate;
- looks up the active word from episode media time using
  `TimedTranscriptIndex`;
- freezes on pause;
- updates immediately after seek, +/-10, or transcript-line selection;
- changes naturally at 0.5x through 3x because the player publishes media time;
- clears stale text immediately when the active episode identity changes;
- does not present a transcript belonging to a previous queue item while the
  next item loads.

UI update work should be coalesced to the display cadence and only publish when
the active word or line changes. It must not rebuild the full transcript tree on
every player progress event.

### Accessibility and Motion

- The compact changing words are hidden from VoiceOver to prevent continuous
  unsolicited announcements.
- The band exposes a stable accessibility label, current preparation state, and
  an action to open the full transcript.
- The expanded transcript exposes lines as seek actions with their starting
  timestamps.
- Dynamic Type is supported without clipping. At accessibility sizes, the
  compact projection may show two context lines rather than shrinking text.
- Reduce Motion disables positional transitions. Word emphasis changes without
  sliding or scaling.
- Color is never the only indication of the active word.
- The reader maintains at least WCAG AA contrast and 44 by 44 point interactive
  targets.

## Architecture Alternatives

### Option A: Prepare Only the Current Episode

Download and transcribe only after an episode starts.

**Advantages**

- Smallest implementation.
- Minimal storage and background coordination.
- Current playback determines all work.

**Costs**

- Every Next action repeats the preparation wait.
- Short hourly bulletins may finish before the viewer becomes useful on a slow
  connection.
- Wastes the measured 40x processing headroom.

### Option B: Bounded Current Plus Two Lookahead Pipeline - Recommended

Prioritize the current episode, then prepare the next two eligible Radio queue
entries. Run one speech analyzer at a time and a small number of background
downloads. Reconcile priorities whenever Radio order changes. Allow an explicit
Prepare All command to widen the desired set to a user-approved session
snapshot and continue it through an iOS 26 continued-processing task.

**Advantages**

- Current audio still starts immediately.
- Next is usually transcript-ready when playback advances.
- Bounded storage, CPU, and network use.
- Fits the existing deterministic Radio queue.
- Recovers cleanly after pause, Next, refresh, relaunch, or memory pressure.
- Lets a user explicitly prepare the full current brief in the background
  without turning autoplay into hidden background processing.

**Costs**

- Requires a production coordinator, cache index, download lifecycle, and
  explicit cancellation.
- Background downloads and foreground analysis have different execution
  guarantees.

### Option C: Pretranscribe the Entire Eligible Feed

Download and analyze all displayed Radio entries.

**Advantages**

- Most episodes eventually become ready.
- Browsing archive transcripts would be fast.

**Costs**

- Unbounded cellular, disk, battery, and publisher-audio retention.
- Work becomes stale as hourly bulletins are replaced.
- Higher thermal and memory risk with no launch-value benefit.
- Conflicts with the focused lean-back Radio product.

### Decision

Use Option B with a lookahead depth of two. Do not add a general offline podcast
download system or archive transcript browser in this slice.

## Component Design

### RadioTranscriptCoordinator

`RadioTranscriptCoordinator` is an `@MainActor` observable service and the
single writer of production transcript preparation state.

Responsibilities:

- Observe current Radio episode identity and the next eligible episode keys.
- Restore cached transcript records at launch.
- Maintain an ordered desired working set of current plus two.
- Promote the current episode above any lookahead work.
- Cancel obsolete analysis when Next, refresh, source order, or episode
  replacement changes the working set.
- Ask the asset service to acquire exact episode audio.
- Invoke one `TimedTranscriptEngine` at a time.
- Validate and persist successful transcripts.
- Expose read-only current-episode presentation state to
  `AudioPlayerViewModelV2`.
- Respond to foreground, background, memory-warning, low-power, thermal, and
  storage-pressure events.
- Coordinate explicit Prepare All snapshots and publish completed/total
  progress.

It does not own playback order, mutate `RadioSessionCoordinator`, parse RSS,
classify ads, or render SwiftUI.

### TranscriptPreparationPipeline

The pipeline is an actor so file I/O, hashing, and speech analysis never execute
on the main actor.

Scheduling rules:

1. Ready cache hit for the current episode.
2. Current episode missing or stale transcript.
3. First next eligible episode.
4. Second next eligible episode.
5. Remaining Prepare All snapshot entries in Radio order.

Limits:

- maximum one `SpeechAnalyzer` operation;
- maximum two active audio download tasks;
- maximum three desired episode assets;
- current episode preempts lookahead analysis;
- Prepare All expands the desired set but never outranks the current episode or
  the next-two interactive path;
- cancellation must reach the analyzer and downloader;
- a canceled result may never publish after a newer job generation wins.

Each job captures a generation and an immutable `RadioEpisodeKey`. Completion
must verify both before changing visible state.

### RadioTranscriptAssetService

The asset service acquires podcast audio without replacing or pausing current
remote playback.

It uses one background `URLSession` with a stable application identifier.
Downloads may continue if the app is suspended. Delegate events move completed
temporary files into `Library/Caches/Briefeed/RadioTranscriptAudio`.

An automatic current-plus-two session submits only its bounded transfers. A
Prepare All operation may submit the full user-approved snapshot together so
the system can schedule transfers efficiently instead of repeatedly waking the
app for one new download.

For every completed download it records:

- `RadioEpisodeKey`;
- original and final resolved URL;
- HTTP ETag and Last-Modified when supplied;
- response content length;
- local audio duration;
- SHA-256 content fingerprint;
- local file URL;
- completion and last-access dates.

Publisher audio is:

- local only;
- excluded from device backup;
- purgeable;
- never committed to the repository;
- never uploaded to Briefeed, Apple, Gemini, or another service by this feature.

### RadioTranscriptStore

Validated transcript JSON is stored under
`Library/Application Support/Briefeed/RadioTranscripts` and excluded from
backup. A versioned index maps episode identity and content fingerprint to the
transcript file.

Cache identity includes:

```swift
struct RadioTranscriptCacheKey: Codable, Hashable, Sendable {
    let episodeKey: RadioEpisodeKey
    let assetFingerprint: String
    let engineIdentifier: String
    let engineVersion: String
    let localeIdentifier: String
}
```

The persisted record includes:

```swift
struct RadioTranscriptRecord: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let key: RadioTranscriptCacheKey
    let sourceURLHash: String
    let audioDurationSeconds: TimeInterval
    let transcriptRelativePath: String
    let preparedAt: Date
    var lastAccessedAt: Date
}
```

Rules:

- A changed audio fingerprint invalidates the old transcript even if the RSS
  GUID and enclosure URL are unchanged.
- A changed engine version or locale generates a different record.
- Corrupt or unsupported files are deleted individually.
- Clearing app cache removes prepared audio and transcripts without touching
  Radio playback/completion history.
- Transcript records may outlive their audio files because they are small; if
  the exact asset is reacquired with the same fingerprint, the transcript is
  immediately reusable.

### TimedTranscriptProjection

`TimedTranscriptProjection` is a pure value type built on
`TimedTranscriptIndex`.

It produces:

- active word index;
- prior, active, and next stable line;
- word emphasis inside each line;
- expanded-view line groups;
- seek target for each line.

Projection is unit tested independently of SwiftUI and accepts explicit width
and text-size categories rather than reading global UI state.

### RadioTranscriptViewer

`RadioTranscriptViewer` is the compact SwiftUI presentation. It receives an
immutable presentation model and intents:

- open expanded transcript;
- retry preparation;
- seek to line.

It does not start downloads or call `SpeechAnalyzer` directly.

### App Composition

`RadioServiceContainer` owns one production transcript coordinator and injects
the same instance into `UnifiedAudioPlayer`/`AudioPlayerViewModelV2` and app
lifecycle handling.

No new global singleton is introduced. DEBUG fixtures can replace the engine,
asset service, store, and clock before container resolution.

### RadioTranscriptBackgroundTaskDriver

An iOS 26 availability-gated driver owns the explicit continued-processing
integration.

Responsibilities:

- add the permitted wildcard identifier to `Info.plist`;
- register each submitted task identifier exactly once;
- submit only from the foreground Prepare All action;
- use the default CPU/network resource class, not GPU entitlement;
- report monotonic progress to `BGContinuedProcessingTask.progress`;
- update the localized title/subtitle as episodes complete;
- install an expiration handler that cancels active analysis and persists
  completed work;
- call `setTaskCompleted(success:)` promptly on completion, cancellation, or
  failure;
- restore the in-app preparation state when the app returns foreground.

The driver does not submit a continued-processing task for autoplay, automatic
lookahead, refresh, launch, or a timer.

## Exact-Asset and Dynamic-Ad Safety

Some podcast publishers dynamically insert different sponsor audio for
different requests. A transcript generated from a second HTTP request can be
wrong even if the RSS episode GUID is unchanged.

V1 uses these safeguards:

1. Every transcript is keyed by a SHA-256 fingerprint of downloaded bytes.
2. Cached episodes play from that exact local asset on subsequent playback.
3. For the currently streaming first play, the coordinator compares final URL,
   response validators, content length, and media duration before exposing the
   new transcript.
4. If duration differs beyond a small tested tolerance, synchronized text stays
   unavailable for that stream. The prepared transcript becomes eligible only
   when playback uses its exact cached asset.
5. The player never silently hot-swaps a remote stream to a local file unless a
   dedicated continuity test proves the transition is inaudible and time-safe.

This means the common first-play case can show text as soon as preparation
finishes, while the app fails closed if a dynamically inserted version appears
inconsistent.

The future ad classifier must use the same fingerprinted asset identity. The
58.62/59.40 Marketplace boundary is research evidence, not a reusable rule.

## Background and Lifecycle Contract

### Foreground Active

- Playback starts or continues.
- Current transcript work begins immediately.
- The pipeline prepares next one and next two after current is ready.
- One analyzer runs at utility priority off the main actor.
- UI progress and current-word changes are published on the main actor.

### Background With Audio Playing

- Radio playback continues through the existing audio background mode.
- Background `URLSession` downloads may continue in the system process.
- Already-ready transcript state remains persisted.
- Automatic current-plus-two analysis does not rely on the background audio
  entitlement as permission for unrelated sustained CPU work. It gets a short
  lifecycle handoff to save/cancel cleanly and is resumable when Briefeed
  returns active.
- A user-started Prepare All operation may continue through its
  `BGContinuedProcessingTask`, with system-visible progress and cancellation.

### Background Without Audio

- Existing background downloads may finish.
- No new automatic analysis begins. A previously user-started Prepare All task
  may continue.
- No periodic polling or timer keeps the app alive.

### System-Terminated

- A background download session may be re-associated on system relaunch and
  move a completed file into cache.
- Transcript analysis does not begin during a download-only relaunch unless the
  system is delivering an active user-started continued-processing task.
- On the next foreground launch, the coordinator restores the cache index,
  reconciles the current Radio queue, and resumes preparation.

### Continued-Processing Boundary

iOS 26 `BGContinuedProcessingTask` can continue CPU-intensive work after an app
is backgrounded, but Apple requires a clear explicit action such as a tap or
gesture. The system displays a cancelable Live Activity and expects measurable
progress.

Briefeed uses it only for Prepare All. The button is an explicit command with a
bounded episode count and a clear completion condition. The system interface
reports progress and preserves user cancellation.

Autoplay and current-plus-two lookahead remain automatic foreground work.
Silently submitting a continued-processing task for either would violate
Apple's interaction contract.

`BGProcessingTask` is also not an immediate-Next guarantee: the system chooses
when it runs. It may later be used for opportunistic maintenance, not the V1
critical path.

## Resource Policy

To protect playback:

- Audio transport and its callbacks retain priority over transcription.
- Speech analysis runs serially and off the main actor.
- Lookahead work pauses in Low Power Mode.
- Lookahead work pauses at serious or critical thermal state.
- Current-episode work may continue at fair thermal state but cancels at
  critical state.
- A memory warning cancels lookahead, releases speech-model retention, and
  evicts least-recently-used prepared audio.
- The working audio cache retains current plus two desired episodes and uses a
  500 MB LRU ceiling during automatic preparation. Prepare All may temporarily
  exceed the three-episode working-set count but not the disk ceiling; when the
  ceiling is reached, completed transcripts are retained and least-recently-used
  audio is evicted.
- The coordinator never downloads on a loop after a persistent HTTP, storage,
  unsupported-format, or engine error.
- Retry uses bounded exponential backoff and resets only after episode identity,
  connectivity, asset availability, or explicit user Retry changes.
- Continued-processing expiration or user cancellation is resumable work, not a
  playback failure.

Network policy in V1 follows the user's existing system cellular permission.
A separate Wi-Fi-only transcript setting is deferred unless device testing
shows material data use.

## Failure Behavior

- Transcript failure never pauses, skips, or restarts audio.
- Next advances immediately even if its transcript is not ready.
- A failed current job does not block preparation of later episodes.
- Asset-model download denial becomes `assetRequired`, not a generic error.
- Unsupported locale or device becomes a stable unavailable state.
- An invalid/corrupt audio file is discarded and retried once from the network.
- Fingerprint mismatch invalidates only that prepared artifact.
- Relaunch clears transient `downloading` and `transcribing` states back to
  `queued`; it does not show stale indefinite progress.
- Prepare All expiration preserves completed results and returns unfinished
  entries to `queued`.

## Privacy and Permissions

- Speech analysis is on device.
- `SpeechAnalyzer` transcript modules do not send the audio to Apple's speech
  servers.
- Briefeed does not record the microphone.
- No transcript, word timing, or publisher audio leaves the app container.
- `NSSpeechRecognitionUsageDescription` is added before production use with
  accurate local-processing language, even though this path does not use
  `SFSpeechRecognizer` server recognition.
- Settings gains a clear-cache action that reports the combined prepared-audio
  and transcript size.

## Interaction With Existing Systems

- `RadioSessionCoordinator` remains the single source of truth for Radio order,
  current episode, completion, and position.
- `QueueCoordinator` remains the single source of truth for Brief and article
  playback.
- The transcript coordinator observes Radio state; it never writes queue order.
- `UnifiedAudioPlayer` remains the playback facade and exposes current media
  time.
- The legacy `TranscriptReaderView` remains article-summary UI and is not
  modified into the Radio viewer.
- Article summarization, Gemini TTS, PocketTTS, Reddit discovery, Supabase, and
  Render are not dependencies.

## Verification

### Unit Tests

- Cache key changes with episode, fingerprint, engine version, and locale.
- Cache hit restores a valid transcript.
- Fingerprint change invalidates a transcript.
- Corrupt index or transcript deletes only the bad record.
- Projection chooses the correct word at boundaries and gaps.
- Stable line grouping does not shift before a boundary.
- Seek target maps to the line's first word.
- Current job preempts lookahead.
- Queue reorder recalculates next two without duplicates.
- Prepare All snapshots only eligible session entries and de-duplicates keys.
- Continued-processing progress is monotonic and reaches completion exactly
  once.
- Expiration and user cancellation preserve completed records and requeue
  unfinished jobs.
- Automatic launch/lookahead never submits a continued-processing task.
- Stale canceled generation cannot publish.
- Relaunch normalizes transient preparation states.
- Low-power, thermal, memory-warning, and background transitions apply the
  resource policy.

### Integration Tests

- Start uncached episode: audio play request occurs before transcript readiness.
- Current transcript becomes visible without restarting playback when asset
  validation passes.
- Next two prepare in deterministic Radio order.
- Next during transcription cancels/promotes correctly.
- Pause and resume freeze and continue the active word.
- +/-10, scrub, and transcript-line seek update immediately.
- 0.5x, 1x, 2x, and 3x use media time without drift.
- Background download completion survives app suspension.
- Returning active resumes analysis from cached audio.
- Prepare All continues download and analysis after foreground-to-background on
  iOS 26 when the system grants runtime.
- Cancel Prepare All from the system interface and confirm audio continues,
  completed transcripts remain, and unfinished work is resumable.
- Expire the continued-processing task and confirm the same partial-success
  behavior.
- Offline playback from cached audio restores its cached transcript.
- Dynamic-ad duration mismatch fails closed.

### Visual and Accessibility Tests

- Compact and largest Dynamic Type.
- Light and dark appearance.
- Reduce Motion.
- Narrow iPhone and large Pro Max layouts.
- Three-line loading, ready, unavailable, and failed states have stable height.
- Long words and punctuation do not clip.
- VoiceOver does not announce every active word.
- Expanded transcript preserves transport reachability.

### Physical-Device Gates

On the approved iPhone:

- first audio begins with no transcript-induced startup regression;
- a 90-second current episode prepares near the proven 40x analysis rate after
  download;
- next and next-two preparation do not cause audible stalls;
- foreground-to-background preserves audio;
- background download completes;
- analysis resumes after foregrounding;
- explicit Prepare All exposes system progress, continues in background, and
  reports monotonic completion;
- system/user cancellation stops promptly without corrupting completed cache;
- seeking and 2x/3x remain visually synchronized;
- memory and thermal state remain acceptable over a 60-minute Radio session;
- killing and reopening restores the prepared transcript;
- no publisher audio or transcript appears in logs, test attachments, or the
  repository.

The feature is not ready for phone distribution until these gates pass on the
simulator where applicable and on a physical device for SpeechAnalyzer,
background transfer, audio continuity, memory, and thermal behavior.

## Shortest Implementation Sequence

1. Add pure cache/state/projection models and tests.
2. Add the versioned transcript store and fingerprinted audio cache.
3. Add the background download asset service with injectable test transport.
4. Add the serial preparation pipeline and coordinator.
5. Add the iOS 26 continued-processing driver and Prepare All command.
6. Integrate coordinator lifecycle and Radio current/next-two observation.
7. Add compact and expanded transcript views.
8. Add exact-asset validation and cached-local playback preference.
9. Run focused unit/integration/UI tests.
10. Run simulator layout and lifecycle tests using the app-testing runbook.
11. Run physical-device SpeechAnalyzer, continued-processing, background audio,
    cancellation, memory, and thermal gates.
12. Produce a verified build suitable for the next iOS distribution step.

The detailed TDD implementation plan will be written only after this design is
reviewed and approved.

## Explicit Non-Goals

- Ad classification, "Skip Ad", or automatic ad skipping.
- Treating 58.62 or 59.40 seconds as a rule for other episodes.
- Cloud speech-to-text.
- FluidAudio/Parakeet or WhisperKit fallback.
- Raising the global iOS 18.2 deployment target.
- Automatic transcript preparation while Briefeed is suspended without an
  explicit Prepare All action.
- Full-feed or archive pretranscription.
- Transcript search, export, editing, translation, or speaker diarization.
- Phoneme-level forced alignment.
- CarPlay transcript display.
- Repairing article TTS or Reddit ingestion.

## Primary References

- [Apple SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [Apple SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [Apple SpeechTranscriber presets](https://developer.apple.com/documentation/speech/speechtranscriber/preset)
- [Apple AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)
- [Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- [Configuring background execution modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes)
- [Performing long-running tasks on iOS and iPadOS](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)
- [WWDC25: Finish tasks in the background](https://developer.apple.com/videos/play/wwdc2025/227/)
- [Asking permission to use speech recognition](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition)
