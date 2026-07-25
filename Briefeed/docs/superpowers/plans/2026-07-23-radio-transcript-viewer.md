# Radio Transcript Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an iOS 26 Radio transcript viewer that starts audio from the
same owned bytes used for transcription, prepares the current episode plus two
upcoming episodes, supports an explicit resumable Prepare All operation, and
follows playback using persisted word-level Apple SpeechAnalyzer timing.

**Architecture:** `RadioTranscriptCoordinator` is the main-actor presentation and scheduling owner. It delegates serial speech work and exact-asset acquisition to actors, persists every durable stage, and exposes a prepared local URL to the existing player before a Radio episode is loaded. SwiftUI renders immutable presentation values and uses `AudioPlayerViewModelV2.currentTime` as its only synchronization clock.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, AVFoundation, CryptoKit, Foundation background `URLSession`, Apple Speech `SpeechAnalyzer` on iOS 26, BackgroundTasks `BGContinuedProcessingTask`, existing Core Data Radio repository, and the isolated Briefeed simulator fleet.

**Implementation status (2026-07-23):** Tasks 1-9 are implemented on
`codex/live-radio-mvp`. Compile verification is green. Managed simulator unit,
UI, smoke, and lifecycle verification remain before physical-device testing.
The current SwiftAudioEx adapter cannot expose observed HTTP response identity.
The player now coalesces its first-play asset request with transcript
preparation so both use one downloaded, fingerprinted local file. Remote
fallback still fails transcript validation closed.

## Global Constraints

- Keep the app deployment target at iOS 18.2; every SpeechAnalyzer and continued-processing reference is availability-gated for iOS 26.
- Playback waits for owned-audio acquisition, not transcription. The player and
  transcript pipeline must share that acquisition so a dynamic publisher
  cannot return different audio to the two consumers.
- Automatic work is exactly current plus the next two eligible Radio episodes while the app is active.
- Prepare All snapshots the visible fresh uncompleted latest-per-source rows supplied by `RadioHomePresentation`; it never queries source history.
- Run at most one speech-analysis operation and two audio downloads concurrently.
- Prepared-ahead playback must use the exact local fingerprinted asset from which its transcript was generated.
- Remote fallback displays a newly prepared transcript only after playback has
  been promoted to the exact fingerprinted local audio at the same media time,
  or final URL, response validators, content length, and duration validation
  succeeds. Duration mismatch fails closed.
- Persist transcript artifacts and each batch stage atomically before advancing progress.
- Use channel `<language>` or Atom feed `xml:lang`, normalize BCP 47, fall back to `en-US` only when metadata is absent or invalid, and surface unsupported Apple locales explicitly.
- Keep prepared/pending current-plus-two and Prepare All inputs pinned. Throttle above the 500 MB cache ceiling rather than evicting and redownloading required inputs.
- Automatic lookahead skips episodes longer than 45 minutes. Current playback and explicit Prepare All remain eligible.
- Submit continued processing only from the explicit Prepare All action with strategy `.fail`; foreground work continues if submission is rejected.
- Do not add speech-recognition usage copy without evidence from the signed physical-device app path.
- Do not implement ad classification, transcript search/edit/share, speaker labels, translation, archive crawling, or automatic ad skipping.
- Use the repository simulator adapter. Do not target an unowned simulator, open Simulator.app, or run broad simulator shutdown/erase commands.

---

### Task 1: Persisted Transcript Domain

**Files:**
- Create: `Briefeed/Core/Transcription/RadioTranscriptModels.swift`
- Create: `Briefeed/Core/Transcription/RadioTranscriptStore.swift`
- Test: `BriefeedTests/Transcription/RadioTranscriptModelsTests.swift`
- Test: `BriefeedTests/Transcription/RadioTranscriptStoreTests.swift`

**Interfaces:**
- Produces: `RadioTranscriptCacheKey`, `RadioTranscriptRecord`, `RadioTranscriptBatchEntryState`, `RadioTranscriptBatchEntry`, `RadioTranscriptBatchManifest`, `RadioTranscriptPreparationState`, and `RadioTranscriptStore`.
- Produces: `RadioTranscriptStore.record(for:)`, `save(transcript:record:)`, `loadTranscript(for:)`, `saveBatch(_:)`, `loadBatch()`, `removeBatch()`, and `reconcile()`.

- [ ] **Step 1: Write failing model round-trip and progress tests**

```swift
@Test func batchManifestRoundTripsEveryDurableStage() throws {
    let key = RadioTranscriptCacheKey(
        episodeKey: .init(feedID: "npr", episodeID: "hour"),
        assetFingerprint: "sha256",
        engineIdentifier: "apple-speech-analyzer",
        engineVersion: "iOS-26",
        localeIdentifier: "en-US"
    )
    let states: [RadioTranscriptBatchEntryState] = [
        .pending,
        .audioReady(assetFingerprint: "sha256"),
        .transcriptReady(cacheKey: key),
        .failed(message: "Unsupported locale")
    ]
    for state in states {
        let entry = RadioTranscriptBatchEntry(
            episodeKey: key.episodeKey,
            order: 0,
            state: state
        )
        let decoded = try JSONDecoder().decode(
            RadioTranscriptBatchEntry.self,
            from: JSONEncoder().encode(entry)
        )
        #expect(decoded == entry)
    }
}
```

- [ ] **Step 2: Run the focused suite and verify RED**

Run:

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RadioTranscriptModelsTests make radio-unit
```

Expected: build failure because the Radio transcript domain types do not exist.

- [ ] **Step 3: Add the versioned value types**

Define the exact cache and batch types from the design spec. Model preparation as a stable enum carrying only UI-safe values:

```swift
enum RadioTranscriptPreparationState: Equatable, Sendable {
    case unavailableOS
    case unsupportedDevice
    case unsupportedLocale(String)
    case assetRequired
    case queued
    case downloading(progress: Double?)
    case transcribing
    case ready(TimedTranscript)
    case deferred
    case failed(message: String, canRetry: Bool)
}
```

- [ ] **Step 4: Verify the model tests GREEN**

Run the Task 1 selector and expect all model tests to pass.

- [ ] **Step 5: Write failing atomic-store tests**

Cover:

```swift
@Test func transcriptIsReadableOnlyAfterArtifactAndIndexCommit() async throws
@Test func corruptTranscriptDeletesOnlyItsOwnRecord() async throws
@Test func reconcilePromotesAValidArtifactBeforeBatchProgress() async throws
@Test func interruptedAudioReadyBatchEntrySurvivesRelaunch() async throws
```

Use a unique temporary directory for each test. Assert that `loadTranscript(for:)` validates the decoded `TimedTranscript` against the cache key before returning it.

- [ ] **Step 6: Implement `RadioTranscriptStore` as an actor**

Use `Data.write(to:options: .atomic)`, versioned JSON index and manifest files, relative paths only, and `URLResourceValues.isExcludedFromBackup`. Write the transcript artifact first, decode it back, then write its record to the index, then update a batch entry. `reconcile()` removes only individually corrupt or missing records and preserves valid artifacts.

- [ ] **Step 7: Verify store tests and the existing timed-transcript suite GREEN**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RadioTranscriptStoreTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/TimedTranscriptTests make radio-unit
```

- [ ] **Step 8: Commit the domain slice**

```bash
git add Briefeed/Core/Transcription/RadioTranscriptModels.swift \
  Briefeed/Core/Transcription/RadioTranscriptStore.swift \
  BriefeedTests/Transcription/RadioTranscriptModelsTests.swift \
  BriefeedTests/Transcription/RadioTranscriptStoreTests.swift
git commit -m "feat: persist radio transcript state"
```

### Task 2: Stable Word and Line Projection

**Files:**
- Create: `Briefeed/Core/Transcription/TimedTranscriptProjection.swift`
- Test: `BriefeedTests/Transcription/TimedTranscriptProjectionTests.swift`

**Interfaces:**
- Consumes: `TimedTranscript` and `TimedTranscriptIndex`.
- Produces: `TimedTranscriptLine`, `TimedTranscriptProjection`, `lines`, `activeLineIndex(at:)`, `window(at:contextLineCount:)`, and `seekTime(forLineAt:)`.

- [ ] **Step 1: Write failing line-stability tests**

Create a word-level transcript containing punctuation and an over-width sentence. Assert:

```swift
#expect(projection.lines.map(\.text) == [
    "Good morning.",
    "This is the latest",
    "news from California."
])
#expect(projection.activeLineIndex(at: 1.3) == 1)
#expect(projection.window(at: 1.3, contextLineCount: 1).map(\.id) ==
        projection.lines[0...2].map(\.id))
#expect(projection.seekTime(forLineAt: 2) == transcript.units[5].startSeconds)
```

Also assert that changing media time within one line does not change line IDs and that playback rate is absent from the API.

- [ ] **Step 2: Verify RED**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/TimedTranscriptProjectionTests make radio-unit
```

- [ ] **Step 3: Implement deterministic grouping**

`TimedTranscriptProjection.init(transcript:maxCharactersPerLine:maxWordsPerLine:)` groups once. Prefer sentence punctuation, otherwise close the line before exceeding either explicit limit. A line ID is the first unit index, and each line retains the original unit indexes and first/last media range.

- [ ] **Step 4: Verify GREEN and commit**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/TimedTranscriptProjectionTests make radio-unit
git add Briefeed/Core/Transcription/TimedTranscriptProjection.swift \
  BriefeedTests/Transcription/TimedTranscriptProjectionTests.swift
git commit -m "feat: project timed transcripts into stable lines"
```

### Task 3: Feed Language Capture

**Files:**
- Create: `Briefeed/Core/Transcription/RadioFeedSpeechMetadataStore.swift`
- Modify: `Briefeed/Core/Services/RSS/RSSParser.swift`
- Modify: `Briefeed/Core/Services/RSS/RSSAudioService.swift`
- Modify: `Briefeed/Core/Radio/RadioServiceContainer.swift`
- Test: `BriefeedTests/Transcription/RadioFeedSpeechMetadataStoreTests.swift`
- Test: `BriefeedTests/Radio/RSSFeedLanguageParsingTests.swift`

**Interfaces:**
- Produces: `ParsedRSSFeed(episodes:languageTag:)`.
- Produces: `RSSParser.parseFeed(data:feedId:) -> ParsedRSSFeed`; preserve `parse(data:feedId:) -> [ParsedRSSEpisode]` as a wrapper.
- Produces: `RadioFeedSpeechMetadataStoreProtocol.languageTag(for:)` and `setLanguageTag(_:source:for:)`.

- [ ] **Step 1: Write failing RSS and Atom language tests**

Verify `en_US` becomes `en-US`, `xml:lang="fr-CA"` is retained, missing/invalid values resolve to `en-US` with `.fallback`, and a later publisher value replaces a seed.

- [ ] **Step 2: Verify RED**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RSSFeedLanguageParsingTests make radio-unit
```

- [ ] **Step 3: Extend parsing without breaking callers**

Track feed-level language outside `<item>`/`<entry>`, return `ParsedRSSFeed`, and retain the old array API as:

```swift
func parse(data: Data, feedId: String) throws -> [ParsedRSSEpisode] {
    try parseFeed(data: data, feedId: feedId).episodes
}
```

- [ ] **Step 4: Write and verify failing metadata-store tests**

Assert versioned atomic persistence, corrupt-file fallback, and publisher-over-seed precedence.

- [ ] **Step 5: Implement the injectable metadata store**

Store `feedID`, normalized tag, source, and updated date in Application Support. Give `RadioServiceContainer` ownership and inject the same store into `RSSAudioService`; fixtures receive an in-memory implementation.

- [ ] **Step 6: Update refresh to save publisher metadata before queue reconciliation**

Only save language after a successful parse. A feed refresh failure must preserve the prior metadata.

- [ ] **Step 7: Verify RSS, service-container, and source-refresh suites GREEN**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RSSFeedLanguageParsingTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/RadioFeedSpeechMetadataStoreTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/RadioServiceContainerTests make radio-unit
```

- [ ] **Step 8: Commit**

```bash
git add Briefeed/Core/Transcription/RadioFeedSpeechMetadataStore.swift \
  Briefeed/Core/Services/RSS/RSSParser.swift \
  Briefeed/Core/Services/RSS/RSSAudioService.swift \
  Briefeed/Core/Radio/RadioServiceContainer.swift \
  BriefeedTests/Transcription/RadioFeedSpeechMetadataStoreTests.swift \
  BriefeedTests/Radio/RSSFeedLanguageParsingTests.swift
git commit -m "feat: persist radio feed speech language"
```

### Task 4: Exact Audio Asset Cache

**Files:**
- Create: `Briefeed/Core/Transcription/RadioTranscriptAssetService.swift`
- Test: `BriefeedTests/Transcription/RadioTranscriptAssetServiceTests.swift`

**Interfaces:**
- Produces: `RadioTranscriptAudioAsset`, `RadioTranscriptAudioRequest`, `RadioTranscriptAssetProviding`, and `RadioTranscriptAssetService`.
- Produces: `asset(for:)`, `acquire(_:)`, `pin(_:reason:)`, `unpin(_:reason:)`, `preparedPlaybackURL(for:)`, `handleEventsCompletionHandler(_:)`, and `trimIfNeeded()`.

- [ ] **Step 1: Write failing fingerprint and pinning tests**

Use local fixture bytes and a fake downloader. Assert SHA-256 identity, atomic move, backup exclusion, deterministic cache hit, maximum two downloads, and that required pins survive LRU trimming.

- [ ] **Step 2: Verify RED**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RadioTranscriptAssetServiceTests make radio-unit
```

- [ ] **Step 3: Implement asset records and cache policy**

Persist final URL, ETag, Last-Modified, response length, AVAsset duration, SHA-256, relative path, completion date, last access, and pin reasons. Enforce 500 MB. If pins consume the limit, return `.storagePressure` instead of evicting required inputs.

- [ ] **Step 4: Add the production background downloader**

Use one background `URLSessionConfiguration` with identifier `Matznerd.Briefeed.radio-transcript-audio`, `isDiscretionary = false`, two maximum host connections, and task descriptions containing stable episode identity. Re-associate delegate completions on relaunch and save the record before notifying callers.

- [ ] **Step 5: Verify GREEN and commit**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RadioTranscriptAssetServiceTests make radio-unit
git add Briefeed/Core/Transcription/RadioTranscriptAssetService.swift \
  BriefeedTests/Transcription/RadioTranscriptAssetServiceTests.swift
git commit -m "feat: cache exact radio transcript audio"
```

### Task 5: Serial Preparation Pipeline

**Files:**
- Create: `Briefeed/Core/Transcription/RadioTranscriptPreparationPipeline.swift`
- Test: `BriefeedTests/Transcription/RadioTranscriptPreparationPipelineTests.swift`

**Interfaces:**
- Consumes: asset provider, transcript store, `TimedTranscriptEngine`, and resolved locale.
- Produces: `RadioTranscriptJob`, `RadioTranscriptPipelineEvent`, `reconcile(interactive:batch:generation:)`, `cancelAutomaticWork()`, and `cancelBatch()`.

- [ ] **Step 1: Write failing scheduler tests**

Prove current outranks next one, next two outranks remaining batch work, duplicate keys collapse, only one engine invocation runs, stale generations cannot publish, automatic jobs over 45 minutes are skipped, and explicit/current jobs remain eligible.

- [ ] **Step 2: Verify RED**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RadioTranscriptPreparationPipelineTests make radio-unit
```

- [ ] **Step 3: Implement the actor scheduler**

The actor owns a priority-ordered desired set and one analysis task. It emits immutable events through an `AsyncStream`. Each success path is:

```text
asset acquired -> asset index durable -> transcript analyzed ->
transcript validated -> artifact durable -> transcript index durable ->
batch entry durable -> progress event
```

Cancellation during analysis leaves a batch entry at `.audioReady`; cancellation during download leaves it `.pending` unless the background session already produced a durable asset.

- [ ] **Step 4: Add the iOS 26 engine factory**

Resolve `SpeechTranscriber.supportedLocale(equivalentTo:)` before creating a cache key. On iOS 26 call `AppleSpeechAnalyzerEngine`; on iOS 18 through 25 emit `.unavailableOS`. Do not silently switch unsupported languages to English.

- [ ] **Step 5: Verify GREEN and commit**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RadioTranscriptPreparationPipelineTests make radio-unit
git add Briefeed/Core/Transcription/RadioTranscriptPreparationPipeline.swift \
  BriefeedTests/Transcription/RadioTranscriptPreparationPipelineTests.swift
git commit -m "feat: schedule radio transcript preparation"
```

### Task 6: Prepare All Continued Processing

**Files:**
- Create: `Briefeed/Core/Transcription/RadioTranscriptBackgroundTaskDriver.swift`
- Modify: `Briefeed/Info.plist`
- Test: `BriefeedTests/Transcription/RadioTranscriptBackgroundTaskDriverTests.swift`

**Interfaces:**
- Produces: `RadioTranscriptBackgroundDriving`, `RadioTranscriptBackgroundSubmission`, `submit(batchID:total:)`, `update(completed:total:)`, `complete(success:)`, and `cancel()`.

- [ ] **Step 1: Write failing pure-policy tests**

Use a fake task adapter to prove:

```swift
@Test func submitUsesUniquePermittedIdentifierAndImmediateFailStrategy()
@Test func progressAdvancesOnlyAfterDurableTranscriptCompletion()
@Test func expirationReturnsActiveAnalysisToAudioReady()
@Test func rejectedBackgroundSubmissionKeepsForegroundBatchRunning()
@Test func automaticLookaheadNeverSubmitsContinuedProcessing()
```

- [ ] **Step 2: Verify RED**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RadioTranscriptBackgroundTaskDriverTests make radio-unit
```

- [ ] **Step 3: Implement the availability-gated driver**

On iOS 26 register a unique identifier beneath `Matznerd.Briefeed.radio-transcripts.*`, submit `BGContinuedProcessingTaskRequest` with `.fail`, publish title `Preparing Radio`, update completed/total progress monotonically, install expiration cancellation, and always call `setTaskCompleted(success:)`. Earlier OS versions return `.unavailableOS`.

- [ ] **Step 4: Add the permitted wildcard**

Add:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER).radio-transcripts.*</string>
</array>
```

Do not add a speech-recognition usage string in this simulator-tested slice.

- [ ] **Step 5: Verify GREEN and compile against the iOS 26 SDK**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RadioTranscriptBackgroundTaskDriverTests make radio-unit
make radio-compile
```

- [ ] **Step 6: Commit**

```bash
git add Briefeed/Core/Transcription/RadioTranscriptBackgroundTaskDriver.swift \
  Briefeed/Info.plist \
  BriefeedTests/Transcription/RadioTranscriptBackgroundTaskDriverTests.swift
git commit -m "feat: continue explicit transcript batches"
```

### Task 7: Production Coordinator and Composition

**Files:**
- Create: `Briefeed/Core/Transcription/RadioTranscriptCoordinator.swift`
- Modify: `Briefeed/Core/Radio/RadioServiceContainer.swift`
- Modify: `Briefeed/Core/ViewModels/AudioPlayerViewModelV2.swift`
- Modify: `Briefeed/BriefeedApp.swift`
- Test: `BriefeedTests/Transcription/RadioTranscriptCoordinatorTests.swift`
- Test: `BriefeedTests/Radio/RadioServiceContainerTests.swift`
- Test: `BriefeedTests/Radio/RadioTranscriptLifecycleTests.swift`

**Interfaces:**
- Produces: `RadioTranscriptPresentation`, `RadioTranscriptBatchPresentation`, `updateCurrent(_:next:)`, `updateVisibleSnapshot(_:)`, `prepareAll()`, `retryCurrent()`, `stopPrepareAll()`, `handleActive()`, `handleBackground()`, and `handleMemoryWarning()`.
- Produces from the view model: published `radioTranscriptPresentation`, `radioTranscriptBatchPresentation`, `updateVisibleRadioTranscriptCandidates(_:)`, `prepareAllRadioTranscripts()`, and `stopPreparingRadioTranscripts()`.

- [ ] **Step 1: Write failing coordinator tests**

Prove:

- current plus exactly two keys are desired;
- an archive current suppresses archive neighbors;
- current preempts a batch;
- refresh cancels removed lookahead generations;
- valid cache is restored at launch;
- Prepare All uses the exact supplied visible snapshot, excluding completed rows and duplicates;
- background cancels automatic analysis but leaves an explicit accepted batch running;
- foreground resumes the highest-priority durable stage;
- source-language metadata is captured immutably per job.

- [ ] **Step 2: Verify RED**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RadioTranscriptCoordinatorTests make radio-unit
```

- [ ] **Step 3: Implement the main-actor coordinator**

Subscribe to pipeline events in one owned task, verify generation and episode key before publishing, and clear presentation immediately when current identity changes. Reconcile automatic pins and desired jobs whenever current, queue, or visible snapshot changes.

- [ ] **Step 4: Compose one production graph**

`RadioServiceContainer` owns metadata store, transcript store, asset service, pipeline, background driver, and coordinator. Fixture construction receives deterministic in-memory fakes. Avoid another global singleton.

- [ ] **Step 5: Bind the view model**

The view model publishes coordinator state, forwards visible snapshots and Prepare All intents, and updates current-plus-two from `RadioSessionCoordinator` entries. It never constructs its own transcript queue.

- [ ] **Step 6: Connect lifecycle**

Foreground resumes reconciliation. Background flushes state and cancels only automatic analysis. AppDelegate forwards background `URLSession` completion handlers to the owned asset service. Memory warning releases decoded inactive transcripts without deleting durable files.

- [ ] **Step 7: Verify GREEN and commit**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RadioTranscriptCoordinatorTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/RadioTranscriptLifecycleTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/RadioServiceContainerTests make radio-unit
git add Briefeed/Core/Transcription/RadioTranscriptCoordinator.swift \
  Briefeed/Core/Radio/RadioServiceContainer.swift \
  Briefeed/Core/ViewModels/AudioPlayerViewModelV2.swift \
  Briefeed/BriefeedApp.swift \
  BriefeedTests/Transcription/RadioTranscriptCoordinatorTests.swift \
  BriefeedTests/Radio/RadioTranscriptLifecycleTests.swift \
  BriefeedTests/Radio/RadioServiceContainerTests.swift
git commit -m "feat: coordinate radio transcripts"
```

### Task 8: Exact Prepared Playback

**Files:**
- Modify: `Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift`
- Test: `BriefeedTests/Radio/RadioTranscriptPlaybackTests.swift`
- Modify: `BriefeedTests/Radio/RadioPlayerPresentationTests.swift`

**Interfaces:**
- Consumes: `RadioTranscriptPreparedAssetProviding.preparedPlaybackURL(for:)`.
- Preserves: existing `RadioPlaybackIntent` and queue ownership.

- [ ] **Step 1: Write failing playback identity tests**

Assert:

```swift
@Test func preparedAheadEpisodeLoadsExactFingerprintLocalURL()
@Test func unpreparedEpisodePlaysTheSameAssetPreparedForItsTranscript()
@Test func failedOwnedAssetDownloadFallsBackToRemotePlayback()
@Test func unavailableTranscriptionKeepsImmediateRemotePlayback()
@Test func finishingPreparationAloneDoesNotMutateActivePlayback()
@Test func readyTranscriptPromotesActivePlaybackAtCurrentMediaTime()
@Test func pausedResumePromotesPreparedPlaybackAtSavedMediaTime()
@Test func failedPreparedLoadRestoresOriginalStream()
@Test func mismatchedCurrentStreamDurationKeepsTranscriptHidden()
@Test func nextLoadsLocalAssetAfterPreparationCompletes()
```

- [ ] **Step 2: Verify RED**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RadioTranscriptPlaybackTests make radio-unit
```

- [ ] **Step 3: Inject the prepared-asset provider**

Before a new Radio load, acquire the transcript pipeline's fingerprinted audio
asset and play that local URL. The asset service coalesces simultaneous player
and pipeline requests into one download. Preserve the existing
`RSSEpisode.downloadedFilePath` fallback for non-transcript downloads. If
acquisition fails, play the remote URL. When a fallback stream's exact asset
later completes, replace the active transport only after duration validation
and start the local item at the current media time. A local load failure
restores the original URL at that same time.

- [ ] **Step 4: Add current-stream validation reporting**

Capture observed final URL, validators, positive response length, and duration
from the response the transport is actually playing when the transport exposes
them. Report that identity to the transcript coordinator; publish ready text
only when its validation policy passes. Never use the separate preparation
download's metadata as a proxy for the active stream. Until SwiftAudioEx
exposes that identity, use only exact prepared local playback, including the
duration-gated media-time-preserving promotion in Step 3.

- [ ] **Step 5: Verify the playback regression suites GREEN**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RadioTranscriptPlaybackTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/RadioPlayerPresentationTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/UnifiedRadioPlaybackTests make radio-unit
```

- [ ] **Step 6: Commit**

```bash
git add Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift \
  BriefeedTests/Radio/RadioTranscriptPlaybackTests.swift \
  BriefeedTests/Radio/RadioPlayerPresentationTests.swift
git commit -m "feat: play exact prepared transcript audio"
```

### Task 9: Compact and Expanded Transcript UI

**Files:**
- Create: `Briefeed/Features/Radio/RadioTranscriptViews.swift`
- Modify: `Briefeed/Features/Radio/RadioHomeView.swift`
- Modify: `Briefeed/Core/Utilities/AccessibilityIdentifiers.swift`
- Test: `BriefeedTests/Radio/RadioTranscriptPresentationTests.swift`
- Modify: `BriefeedUITests/RadioUITests.swift`

**Interfaces:**
- Consumes: immutable `RadioTranscriptPresentation`, `currentTime`, retry/open/seek intents.
- Produces: `RadioTranscriptViewer`, `RadioExpandedTranscriptView`, and `RadioTranscriptPrepareAllRow`.

- [ ] **Step 1: Write failing presentation tests**

Test copy and stable height state mapping, active-word lookup from media time, Prepare All counts, stopped/resumable state, Dynamic Type context reduction, Reduce Motion policy, and source-snapshot eligibility.

- [ ] **Step 2: Verify RED**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RadioTranscriptPresentationTests make radio-unit
```

- [ ] **Step 3: Implement the compact band**

Place the fixed-height three-line teleprompter above `Your radio brief`. Hide changing word children from VoiceOver, expose one stable accessibility element, emphasize the active word with color plus weight, and update only when active word or line changes.

- [ ] **Step 4: Implement expanded reading**

Open from the band in a sheet or navigation destination. Keep the active line centered while auto-follow is enabled; manual scroll suspends it; `Resume Live` restores following; tapping a line seeks to its first word. Keep existing transport controls reachable.

- [ ] **Step 5: Implement Prepare All from the rendered list value**

Place the row after the final playlist item and above safe-area content insets. Pass `playlistItems.filter { !$0.candidate.isCompleted }.map(\.candidate)` directly to the view model. Show eligible, active progress, complete, unavailable, stopped, and submission-rejected states.

- [ ] **Step 6: Add accessibility IDs and UI coverage**

Add stable IDs for transcript band, state, active line, expanded transcript, resume-live, Prepare All, stop, and progress. UI tests must assert that the band does not obstruct the floating navigation or mini-player at small and large Dynamic Type sizes.

- [ ] **Step 7: Verify UI and presentation suites GREEN**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/RadioTranscriptPresentationTests make radio-unit
RADIO_UI_TEST_SELECTOR=BriefeedUITests/RadioUITests make radio-ui
```

- [ ] **Step 8: Commit**

```bash
git add Briefeed/Features/Radio/RadioTranscriptViews.swift \
  Briefeed/Features/Radio/RadioHomeView.swift \
  Briefeed/Core/Utilities/AccessibilityIdentifiers.swift \
  BriefeedTests/Radio/RadioTranscriptPresentationTests.swift \
  BriefeedUITests/RadioUITests.swift
git commit -m "feat: show synchronized radio transcripts"
```

### Task 10: Full Verification, Documentation, and Device Handoff

**Files:**
- Modify: `Briefeed/docs/superpowers/specs/2026-07-23-radio-transcript-viewer-design.md`
- Modify: `Briefeed/docs/research/receipts/2026-07-21-apple-speech-transcript-probe.md`
- Create: `Briefeed/docs/research/receipts/2026-07-23-radio-transcript-viewer-verification.md`

**Interfaces:**
- Produces: a reproducible test receipt and a signed-device checklist.

- [ ] **Step 1: Run all automated gates**

```bash
make radio-compile
make radio-unit
make radio-ui
make radio-smoke
```

Expected: all commands exit 0. Exit 75 means fleet capacity blocked verification and must be retried after safe capacity returns, not bypassed.

- [ ] **Step 2: Run headless simulator visual inspection**

Capture light/dark screenshots for:

- queued/preparing;
- ready three-line transcript;
- expanded transcript;
- Prepare All idle and progress;
- failure and unsupported-OS;
- small phone and accessibility Dynamic Type.

Inspect the accessibility tree and assert no overlap with the floating navigation or mini-player. Record exact artifact paths in the verification receipt.

- [ ] **Step 3: Exercise lifecycle and persistence**

On the isolated simulator fixture, verify pause, seek, +/-10, Next, refresh, background, foreground, and relaunch preserve media-time selection and never show stale text. Use test adapters for continued-processing expiration because ordinary simulator runs do not prove system background execution.

- [ ] **Step 4: Update documentation truthfully**

Change the design status from proposed to implemented only for verified behavior. Keep physical-device-only checks explicitly open:

- signed app SpeechAnalyzer permission behavior;
- exact local audio plus transcript on iOS 26 hardware;
- continued-processing system progress and cancellation;
- background expiration/resume;
- thermal behavior for Prepare All;
- VoiceOver and 0.5x through 3x playback.

- [ ] **Step 5: Update GitHub issue #23**

Comment with commit, automated gate output, simulator artifacts, remaining device-only checks, and the ad-skip non-goal. Close #23 only after the required signed-device checks pass.

- [ ] **Step 6: Commit, rebase, and push**

```bash
git add Briefeed/docs/superpowers/specs/2026-07-23-radio-transcript-viewer-design.md \
  Briefeed/docs/research/receipts/2026-07-21-apple-speech-transcript-probe.md \
  Briefeed/docs/research/receipts/2026-07-23-radio-transcript-viewer-verification.md
git commit -m "docs: verify radio transcript viewer"
git pull --rebase
git push
git status --short --branch
```

Expected: branch reports up to date with `origin/codex/live-radio-mvp` and no uncommitted files.

## Self-Review

- Spec coverage: all persisted models, locale capture, exact-asset rules, bounded scheduling, Prepare All, continued processing, lifecycle, playback integration, compact/expanded UI, accessibility, simulator verification, and physical-device boundaries map to Tasks 1 through 10.
- Non-goals remain outside the implementation: ad classification/skip, transcript search/edit/share, archive preparation, server upload, and a general offline podcast system.
- Type consistency: the cache key and batch types match the design; the pipeline is the single actor performing analysis; the coordinator is the single production presentation writer; the player consumes only a prepared-asset provider; the view consumes immutable presentation state.
- Placeholder scan: every task names concrete files, interfaces, expected failing behavior, verification commands, and commit boundaries.
