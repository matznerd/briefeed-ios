# Briefeed Radio Transcript Viewer Design

**Date:** 2026-07-23  
**Status:** Implemented on `codex/live-radio-mvp`; focused simulator and physical first-play verification passed, broader distribution gate remains
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
6. An explicit **Prepare All** command snapshots the visible, fresh,
   uncompleted latest-per-source rows and starts a user-visible iOS 26
   continued-processing task that may finish after Briefeed enters the
   background.

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

- the fresh episodes currently presented in "Your radio brief";
- at most one latest eligible episode per enabled source;
- only entries that are not completed/listened;
- no duplicate `RadioEpisodeKey` values.

The snapshot comes from the same `RadioHomePresentation.playlistItems` value
used to render the visible rows. The transcript coordinator does not rebuild a
different "all" list from Core Data.

It does not include manually selected archive episodes, earlier episodes behind
a source disclosure, every historical episode in each source, retired hourly
bulletins, completed/listened rows, Brief articles, or episodes that arrive
after the task begins. A later refresh may offer Prepare All again for newly
visible eligible work.

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
return to `queued`. The row becomes `Resume preparation · N remaining`; tapping
it is a new explicit action that may submit another continued-processing task.

Prepare All is hidden or replaced by a clear unavailable message on iOS 18
through 25. It is disabled when there is no eligible work or when required
speech support is unavailable.

### Playing an Earlier Episode

An episode selected from source history is prepared on demand, not as part of
Prepare All:

1. The user selects the earlier episode.
2. Audio starts immediately through the normal Radio playback path.
3. The transcript coordinator observes the new current `RadioEpisodeKey` and
   promotes it above every lookahead or batch job.
4. A valid cache hit displays immediately. Otherwise, audio acquisition and
   on-device transcription begin without pausing playback.
5. Synchronized text appears as soon as the exact-asset validation succeeds.

No neighboring archive episodes are prepared. Leaving the episode does not
discard a completed transcript, and returning to it reuses the fingerprinted
cache.

### Episode Language

Every transcript job carries an immutable BCP 47 language tag.

Locale selection is deterministic:

1. Use the RSS channel-level `<language>` value when present.
2. For Atom feeds, use the feed-level `xml:lang` value when present.
3. Normalize common underscore/hyphen variants to a BCP 47 identifier.
4. If feed language metadata is absent or invalid, use the V1 default `en-US`.
5. Pass that locale to `SpeechTranscriber.supportedLocale(equivalentTo:)`.
6. Use the equivalent supported locale returned by Apple in the transcript
   cache key.
7. If Apple returns no equivalent supported locale, enter
   `unsupportedLocale`; do not silently retry as English.

The current RSS parser and `RSSFeed` Core Data entity do not retain feed
language. V1 extends parsing to surface channel/feed language and persists the
normalized tag in a lightweight, versioned speech-metadata store keyed by feed
ID. This avoids a Core Data model migration for one optional transcription
field.

Default Briefeed sources may seed `en-US` metadata, but parsed publisher
metadata replaces the seed after a successful refresh. A later product version
may add a per-source language override; that is not required for V1.

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
- Accept the exact visible, uncompleted latest-per-source keys for Prepare All
  rather than independently querying archive data.
- Resolve and snapshot the episode language before a job leaves the main actor.
- Restore cached transcript records at launch.
- Maintain an ordered desired working set of current plus two.
- Promote the current episode above any lookahead work.
- Cancel obsolete analysis when Next, refresh, source order, or episode
  replacement changes the working set.
- Ask the asset service to acquire exact episode audio.
- Invoke one `TimedTranscriptEngine` at a time.
- Validate and persist successful transcripts.
- Expose an exact prepared local playback URL before a Radio episode load.
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
5. Remaining visible Prepare All snapshot entries in Radio order.

Limits:

- maximum one `SpeechAnalyzer` operation;
- maximum two active audio download tasks;
- maximum three episodes in the automatic current-plus-two working set;
- a Prepare All manifest may contain more entries, but only the bounded
  download/analyzer window becomes active at once;
- current episode preempts lookahead analysis;
- Prepare All expands the desired set but never outranks the current episode or
  the next-two interactive path;
- cancellation must reach the analyzer and downloader;
- a canceled result may never publish after a newer job generation wins.

Each job captures a generation and an immutable `RadioEpisodeKey`. Completion
must verify both before changing visible state.

An out-of-order archive episode that becomes current follows rule 1 or 2. It is
never followed by automatic preparation of the rest of that source's history.

### RadioTranscriptAssetService

The asset service acquires podcast audio without replacing or pausing current
remote playback.

It uses one background `URLSession` with a stable application identifier.
Downloads may continue if the app is suspended. Delegate events move completed
temporary files into `Library/Caches/Briefeed/RadioTranscriptAudio`.

The configuration sets `isDiscretionary = false`. Automatic lookahead begins
only while the user is actively using Radio, and Prepare All is explicitly
requested; neither transfer class should be deferred as overnight maintenance.

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

Pending current/lookahead/batch audio is pinned against LRU eviction until its
transcript reaches `transcriptReady`, fails terminally, or the user discards the
batch. A prepared current/next-two asset remains playback-pinned while its
episode stays in that automatic working set, ensuring the player can start from
the exact local file. Eviction order is:

1. transcript-ready batch audio outside current plus next two;
2. transcript-ready audio outside the current desired working set;
3. never a current/next-two playback-pinned asset or an input still needed by a
   pending transcript job.

If pinned assets would breach the 500 MB ceiling, the service throttles or
pauses new downloads rather than evicting an input and redownloading it. An
individual asset larger than the ceiling is not automatically prepared ahead;
it remains eligible for current-episode on-demand handling with a clear storage
failure if it cannot be cached.

### RadioFeedSpeechMetadataStore

A small versioned file in Application Support maps `feedID` to a normalized
language tag and its source (`publisher`, `seed`, or `fallback`).

The RSS parser returns feed language alongside parsed episodes. A successful
refresh writes publisher language metadata before transcript preparation
reconciles the queue. Corrupt metadata falls back to the deterministic `en-US`
rule without deleting RSS episodes or Radio state.

The store is injectable for tests and is owned by `RadioServiceContainer`.

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

Prepare All also persists a resumable manifest:

```swift
enum RadioTranscriptBatchEntryState: Codable, Equatable, Sendable {
    case pending
    case audioReady(assetFingerprint: String)
    case transcriptReady(cacheKey: RadioTranscriptCacheKey)
    case failed(message: String)
}

struct RadioTranscriptBatchEntry: Codable, Equatable, Sendable {
    let episodeKey: RadioEpisodeKey
    let order: Int
    var state: RadioTranscriptBatchEntryState
}

struct RadioTranscriptBatchManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var entries: [RadioTranscriptBatchEntry]
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
- Download completion, transcript completion, and batch-manifest changes use
  immediate atomic writes. They are never held behind the normal progress
  debounce.
- A transcript artifact is atomically written and validated before its cache
  index and batch entry change to `transcriptReady`.
- Continued-processing progress advances only after the corresponding
  transcript is durably committed.
- At launch, the store reconciles the manifest against valid transcript files
  and asset records, so an interruption between file and index writes cannot
  discard completed work.
- A manifest remains until all entries are ready or the user explicitly
  discards it.

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
- set `BGContinuedProcessingTaskRequest.strategy = .fail`;
- use the default CPU/network resource class, not GPU entitlement;
- report monotonic progress to `BGContinuedProcessingTask.progress`;
- update the localized title/subtitle as episodes complete;
- install an expiration handler that cancels active analysis and persists
  the active operation and flushes its current durable stage;
- call `setTaskCompleted(success:)` promptly on completion, cancellation, or
  failure;
- restore an unfinished manifest as `Resume preparation · N remaining`;
- restore the in-app preparation state when the app returns foreground.

The driver does not submit a continued-processing task for autoplay, automatic
lookahead, refresh, launch, or a timer.

If `.fail` submission reports that immediate continued execution is
unavailable, the in-app preparation pipeline still runs while Briefeed remains
active. The row explains that background continuation is unavailable right now
and offers another explicit retry; it does not pretend the system accepted the
request.

Checkpoint behavior:

- Each successfully downloaded asset is moved and indexed immediately.
- Each successfully validated transcript is saved immediately.
- The batch manifest is saved after each durable stage and each completed
  episode.
- If expiration occurs during speech analysis, that episode returns to
  `audioReady`. Apple SpeechAnalyzer analysis restarts from the already cached
  audio next time; previously completed episodes are not repeated.
- If expiration occurs during a download, resumable URLSession state is used
  when available. Otherwise only that incomplete download restarts.
- The SpeechAnalyzer result is all-or-nothing in V1. Briefeed does not persist
  or display a partial transcript as if it were complete.

## Exact-Asset and Dynamic-Ad Safety

Some podcast publishers dynamically insert different sponsor audio for
different requests. A transcript generated from a second HTTP request can be
wrong even if the RSS episode GUID is unchanged.

V1 uses these safeguards:

1. Every transcript is keyed by a SHA-256 fingerprint of downloaded bytes.
2. Before first playback, the player and transcript pipeline request the same
   owned audio asset. `RadioTranscriptAssetService` coalesces those requests
   into one download, fingerprints the resulting bytes, and gives both
   consumers the same local file.
3. Playback waits only for that audio acquisition, not for SpeechAnalyzer.
   Audio then starts from the exact local bytes while transcription proceeds
   against that file. Prepared-ahead and replay playback use the same path
   without another download.
4. If owned-asset acquisition fails, audio falls back to the publisher URL.
   Synchronized text remains hidden unless playback later moves to an exact
   prepared file or the transport independently validates the active response.
5. On iOS versions or devices where on-device transcript preparation is
   unavailable, playback keeps the existing immediate remote path and does not
   perform transcript-only audio acquisition.
6. A fallback remote stream may still be promoted to the exact local asset
   after duration validation. The replacement transport starts at the current
   media time; stale callbacks from the old playback ID are ignored.
7. If duration differs beyond the tolerance, synchronized text stays
   unavailable for that fallback stream.
8. If an exact local load fails during fallback promotion, Briefeed restores
   the original playback URL at the same media time. Transcript work must not
   strand, complete, or advance the Radio queue.
9. A transport that exposes final URL, response validators, positive content
   length, and duration may validate the active remote response directly
   instead of performing the local promotion.

For an uncached episode, the first play may incur a bounded download-only
startup delay. This is the smallest reliable implementation with the current
SwiftAudioEx adapter, which cannot expose or tee the bytes it streams. The
delay must be measured on physical hardware for short Radio bulletins. A
follow-up transport task owns progressive play-while-capturing if the measured
delay is unacceptable. The viewer never substitutes metadata from one request
as proof of the bytes returned by another.

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

If Apple expires the task, Briefeed does not silently resubmit another
continued-processing request. Completed episodes and downloaded assets remain
checkpointed. When the app next becomes active, normal current-plus-two work may
resume automatically; resuming the entire remaining snapshot requires the
user's `Resume preparation` tap.

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
  ceiling is reached, completed transcripts are retained, already-transcribed
  audio is evicted first, and pending inputs remain pinned.
- Automatic lookahead skips episodes longer than 45 minutes. Long episodes
  still prepare when they become current or when the user explicitly includes
  their visible row through Prepare All.
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
  entries to their last durable state.
- An interrupted `audioReady` episode resumes transcription without
  redownloading.
- An interrupted transcript operation restarts only that transcript; it does
  not repeat completed batch entries.
- Selecting an earlier source episode starts audio immediately and prepares
  only that selected episode on demand.

## Privacy and Permissions

- Speech analysis is on device.
- `SpeechAnalyzer` transcript modules do not send the audio to Apple's speech
  servers.
- Briefeed does not record the microphone.
- No transcript, word timing, or publisher audio leaves the app container.
- Do not add `NSSpeechRecognitionUsageDescription` defensively. The production
  app path must be exercised on a physical iOS 26 device without the key and the
  result recorded in the verification receipt. Add the key only if that test or
  Apple's applicable `SpeechAnalyzer` contract requires authorization.
- If a usage key is required, its text must accurately state that Briefeed
  transcribes publisher audio on device and does not record the microphone or
  send audio to a speech server.
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
- Before starting a Radio episode, `UnifiedAudioPlayer` acquires the transcript
  pipeline's owned audio asset. Concurrent playback and transcript requests are
  coalesced, so both use one fingerprinted local file. If acquisition fails,
  the player falls back to the remote enclosure and retains the fail-closed
  validation and promotion behavior defined above.
- The legacy `TranscriptReaderView` remains article-summary UI and is not
  modified into the Radio viewer.
- Article summarization, Gemini TTS, PocketTTS, Reddit discovery, Supabase, and
  Render are not dependencies.

## Verification

### Unit Tests

- Cache key changes with episode, fingerprint, engine version, and locale.
- Feed `<language>` and Atom `xml:lang` normalize to the expected locale.
- Missing language uses `en-US`; unsupported publisher language fails
  explicitly instead of retrying as English.
- Cache hit restores a valid transcript.
- Fingerprint change invalidates a transcript.
- Corrupt index or transcript deletes only the bad record.
- Pending current/lookahead/batch assets and prepared current/next-two playback
  assets are pinned against LRU eviction.
- Pinned assets at the disk ceiling throttle downloads instead of cycling
  download, eviction, and redownload.
- Automatic lookahead excludes episodes over the configured 45-minute cap;
  current and Prepare All work remain eligible.
- Projection chooses the correct word at boundaries and gaps.
- Stable line grouping does not shift before a boundary.
- Seek target maps to the line's first word.
- Current job preempts lookahead.
- Queue reorder recalculates next two without duplicates.
- Prepare All snapshots only eligible session entries and de-duplicates keys.
- Prepare All selection exactly matches visible uncompleted
  latest-per-source rows and excludes source-history episodes.
- Continued-processing progress is monotonic and reaches completion exactly
  once.
- Each completed episode is atomically durable before batch progress advances.
- Expiration and user cancellation preserve completed records, downloaded
  assets, and the resumable manifest.
- An expired mid-transcription entry returns to `audioReady` and resumes without
  redownload.
- Automatic launch/lookahead never submits a continued-processing task.
- Stale canceled generation cannot publish.
- Relaunch normalizes transient preparation states.
- Low-power, thermal, memory-warning, and background transitions apply the
  resource policy.

### Integration Tests

- Start uncached episode: one audio acquisition serves both playback and
  transcription; playback begins before transcript readiness.
- Select an earlier source-history episode: audio starts first, its transcript
  appears when ready, and adjacent history is not prepared.
- Current transcript becomes visible after exact-local promotion preserves the
  current media time, or after active-response identity validation passes.
- Next two prepare in deterministic Radio order.
- Next during transcription cancels/promotes correctly.
- Pause and resume freeze and continue the active word.
- +/-10, scrub, and transcript-line seek update immediately.
- 0.5x, 1x, 2x, and 3x use media time without drift.
- Background download completion survives app suspension.
- Returning active resumes analysis from cached audio.
- Prepare All continues download and analysis after foreground-to-background on
  iOS 26 when the system grants runtime.
- Continued-processing submission uses `.fail`; rejection keeps foreground
  preparation alive and reports background continuation as unavailable.
- Cancel Prepare All from the system interface and confirm audio continues,
  completed transcripts remain, and unfinished work is resumable.
- Expire the continued-processing task and confirm the same partial-success
  behavior.
- Expire during episode N, relaunch, and verify episodes 1 through N-1 are cache
  hits while only episode N resumes from its last durable stage.
- Offline playback from cached audio restores its cached transcript.
- A prepared-ahead episode starts playback from its exact local asset on its
  first play.
- Prepared audio promotion preserves media time for playing and paused/resume
  paths.
- A failed prepared-audio load restores the original stream at the same media
  time and keeps synchronized text hidden.
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
- a rejected `.fail` submission leaves foreground preparation working and
  reports the limitation;
- system/user cancellation stops promptly without corrupting completed cache;
- seeking and 2x/3x remain visually synchronized;
- memory and thermal state remain acceptable over a 60-minute Radio session;
- killing and reopening restores the prepared transcript;
- the signed production app invokes `SpeechAnalyzer` without
  `NSSpeechRecognitionUsageDescription`; the receipt records whether iOS
  prompts, rejects, or permits the on-device file-transcription path before the
  key decision is finalized;
- no publisher audio or transcript appears in logs, test attachments, or the
  repository.

`BGTaskScheduler` continued-processing behavior is not considered verified by a
normal simulator run. Simulator integration uses Apple's LLDB task launch and
expiration simulation hooks where supported; real submission, system progress,
background continuation, cancellation, and expiration require a physical
iPhone.

During implementation, inspect the current `RadioHomeView` on supported phone
shapes before treating the transcript band's proposed placement as final. The
band must fit the actual list, floating navigation, mini-player, and safe-area
layout rather than assuming an obsolete artwork region exists.

The feature is not ready for phone distribution until these gates pass on the
simulator where applicable and on a physical device for SpeechAnalyzer,
background transfer, audio continuity, memory, and thermal behavior.

## Shortest Implementation Sequence

1. Add pure cache/state/projection models and tests.
2. Add the versioned transcript store and fingerprinted audio cache.
3. Add RSS/Atom language parsing and the feed speech-metadata store.
4. Add the non-discretionary background download asset service with pinned
   pending inputs and injectable test transport.
5. Add the serial preparation pipeline and coordinator.
6. Add the iOS 26 continued-processing driver and Prepare All command.
7. Integrate coordinator lifecycle and Radio current/next-two observation.
8. Add compact and expanded transcript views.
9. Add exact-asset validation and prepared-local playback preference.
10. Run focused unit/integration/UI tests.
11. Run simulator layout and lifecycle tests using the app-testing runbook.
12. Run physical-device SpeechAnalyzer, continued-processing, background audio,
    cancellation, memory, and thermal gates.
13. Produce a verified build suitable for the next iOS distribution step.

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
- Inclusion of manually selected source-history episodes in Prepare All.
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
