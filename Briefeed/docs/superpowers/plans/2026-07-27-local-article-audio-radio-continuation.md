# Local Article Audio and Radio Continuation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn publisher article text into progressively playable on-device audio while Radio keeps playing, then resume the exact interrupted Radio item when the article ends.

**Architecture:** Keep `RadioSessionCoordinator` as the ephemeral latest-news lane and `QueueCoordinator` as the durable article Brief. Add a persisted article-preparation pipeline, a local WebKit extractor with Firecrawl fallback, PocketTTS frame streaming with a file cache, and a playback scheduler that owns temporary continuations instead of pretending Radio episodes belong in the Brief.

**Tech Stack:** Swift 5, Swift Concurrency, SwiftUI, WebKit, AVFoundation, FluidAudio 0.14.5 PocketTTS, Core Data for existing articles, atomic JSON/files in Application Support for preparation artifacts, existing Firecrawl/cloud TTS providers as fallbacks.

## Global Constraints

- The deployment target remains iOS 18.2.
- The current working Radio implementation on `origin/master` is the baseline.
- Do not remove Firecrawl, Gemini, OpenAI TTS, Gemini TTS, or AVSpeech fallback paths.
- The first delivery speaks cleaned raw publisher text. It does not require or invoke summarization.
- Normal Reddit feed items already contain the publisher URL; resolve Reddit wrapper URLs only when one is actually supplied.
- Never copy temporary Radio episodes into the persistent Brief queue.
- Never stop Radio merely because article preparation started.
- Switch away from Radio only after article audio is verified playable.
- Preserve the interrupted Radio episode key and exact transport position.
- Save is FIFO and non-interrupting; Play Next and Play Now are urgent.
- At a natural Radio boundary, play at most one ready saved article, then return to Radio.
- Play Next and Play Now interrupt as soon as their article becomes safely playable.
- Natural article completion or Skip resumes the captured continuation. Explicit Stop clears it and leaves playback stopped.
- Speak the title once, followed by cleaned body paragraphs.
- Accept at least 120 characters and 20 words; cap spoken source text at 40,000 characters on a sentence boundary and record truncation.
- Automatic policy is local extraction and PocketTTS first, with current cloud providers as fallback.
- On Device policy never sends article text to cloud extraction, summary, or speech providers.
- Cloud Quality policy may use Firecrawl and the selected premium voice.
- Background completion is best effort on iOS 18; persist and resume work instead of promising indefinite execution.
- All default unit tests must be hermetic. Live publisher and model benchmarks are explicit integration tests.
- The historical `2026-03-16-on-device-content-extraction.md` plan is superseded by this plan; do not add Jina Reader or a new Readability package for this slice.

## Locked Product Contract

```text
App opens
  -> opening Radio refresh
  -> newly inserted top Radio item wins cold-launch autoplay

User saves article
  -> durable Brief FIFO
  -> low-priority local preparation
  -> no playback interruption

User chooses Play Next / Play Now
  -> urgent preparation
  -> Radio continues
  -> article reaches playable buffer
  -> capture Radio(key, exact position)
  -> play article
  -> article completes or is skipped
  -> resume Radio(key, exact position)
```

Preparation and playback are deliberately separate:

```swift
enum ArticlePreparationState: Codable, Equatable, Sendable {
    case queued
    case extracting
    case contentReady
    case synthesizing
    case playable(bufferedSeconds: Double)
    case audioReady
    case failed(ArticlePreparationFailure)
}

enum PlaybackContinuation: Equatable, Sendable {
    case radio(key: RadioEpisodeKey, positionSeconds: TimeInterval)
    case brief(itemID: UUID, positionSeconds: TimeInterval)
}
```

---

### Task 1: Persist Provider-Neutral Preparation Records

**Files:**
- Create: `Briefeed/Core/ArticlePreparation/ArticlePreparationModels.swift`
- Create: `Briefeed/Core/ArticlePreparation/ArticlePreparationStore.swift`
- Test: `BriefeedTests/ArticlePreparation/ArticlePreparationStoreTests.swift`

**Interfaces:**
- Consumes: existing `Article.id`, `Article.url`, `QueueItem.articleID`.
- Produces: `ArticlePreparationRecord`, `ArticlePreparationStoreProtocol`, and atomic artifact directories used by every later task.

- [ ] **Step 1: Write the failing persistence tests**

Cover atomic round-trip, missing record, corrupt JSON quarantine, state replacement, artifact deletion, and two records writing concurrently without sharing files.

```swift
@Test func roundTripsRecordAndUsesOneDirectoryPerArticle() async throws {
    let root = temporaryDirectory()
    let store = ArticlePreparationStore(rootDirectory: root)
    let articleID = UUID()
    let record = ArticlePreparationRecord.queued(
        articleID: articleID,
        sourceURL: URL(string: "https://example.com/story")!,
        priority: .saved
    )

    try await store.save(record)

    #expect(try await store.load(articleID: articleID) == record)
    #expect(
        FileManager.default.fileExists(
            atPath: root
                .appendingPathComponent(articleID.uuidString)
                .appendingPathComponent("record.json").path
        )
    )
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}
```

- [ ] **Step 2: Run the test and verify the missing types fail compilation**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/ArticlePreparationStoreTests make radio-unit
```

Expected: FAIL because `ArticlePreparationStore` and record types do not exist.

- [ ] **Step 3: Implement the records**

Use these exact core shapes:

```swift
enum ArticlePreparationPriority: Int, Codable, Comparable, Sendable {
    case playNow = 0
    case playNext = 1
    case saved = 2

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ArticleContentProvider: String, Codable, Sendable {
    case stored
    case localWebKit
    case firecrawl
}

enum ArticleSpeechProvider: String, Codable, Sendable {
    case pocketTTS
    case openAI
    case gemini
    case avSpeech
}

struct ArticleContentArtifact: Codable, Equatable, Sendable {
    let submittedURL: URL
    let canonicalURL: URL
    let title: String
    let byline: String?
    let textFileName: String
    let contentSHA256: String
    let characterCount: Int
    let wordCount: Int
    let wasTruncated: Bool
    let provider: ArticleContentProvider
    let createdAt: Date
}

struct ArticleAudioArtifact: Codable, Equatable, Sendable {
    let fileName: String
    let contentSHA256: String
    let provider: ArticleSpeechProvider
    let engineVersion: String
    let voice: String
    let voiceSpeed: Float
    let sampleRate: Double
    let durationSeconds: Double?
    let isComplete: Bool
    let createdAt: Date
}

struct ArticlePreparationAttempt: Codable, Equatable, Sendable {
    let stage: String
    let provider: String
    let startedAt: Date
    let finishedAt: Date
    let outcome: String
}

struct ArticlePreparationFailure: Codable, Equatable, Sendable {
    enum Stage: String, Codable, Sendable {
        case extraction, speech, cache, playback
    }

    let stage: Stage
    let provider: String
    let category: String
    let message: String
    let retryAfter: Date?
}

struct ArticlePreparationRecord: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let articleID: UUID
    let sourceURL: URL
    var priority: ArticlePreparationPriority
    var state: ArticlePreparationState
    var content: ArticleContentArtifact?
    var audio: ArticleAudioArtifact?
    var attempts: [ArticlePreparationAttempt]
    var updatedAt: Date
}

extension ArticlePreparationRecord {
    static func queued(
        articleID: UUID,
        sourceURL: URL,
        priority: ArticlePreparationPriority,
        now: Date = Date()
    ) -> Self {
        .init(
            schemaVersion: schemaVersion,
            articleID: articleID,
            sourceURL: sourceURL,
            priority: priority,
            state: .queued,
            content: nil,
            audio: nil,
            attempts: [],
            updatedAt: now
        )
    }
}
```

- [ ] **Step 4: Implement the atomic store**

`ArticlePreparationStore` is an actor. Store each record under:

```text
Application Support/ArticlePreparation/<article UUID>/
  record.json
  content.txt
  audio.partial.wav
  audio.wav
```

Write `record.json.tmp`, call `FileHandle.synchronize()`, and replace `record.json`. Never put article text or audio bytes in UserDefaults.

```swift
protocol ArticlePreparationStoreProtocol: Sendable {
    func load(articleID: UUID) async throws -> ArticlePreparationRecord?
    func save(_ record: ArticlePreparationRecord) async throws
    func writeContent(_ text: String, articleID: UUID) async throws -> URL
    func artifactURL(articleID: UUID, fileName: String) async -> URL
    func remove(articleID: UUID) async throws
}
```

- [ ] **Step 5: Run the focused tests**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/ArticlePreparationStoreTests make radio-unit
```

Expected: PASS with no network access.

- [ ] **Step 6: Commit**

```bash
git add Briefeed/Core/ArticlePreparation \
  BriefeedTests/ArticlePreparation/ArticlePreparationStoreTests.swift
git commit -m "feat: persist article preparation artifacts"
```

---

### Task 2: Port the Bounded DeciphVR Article Cleaner

**Files:**
- Create: `Briefeed/Core/ArticlePreparation/Extraction/ArticleExtractionResult.swift`
- Create: `Briefeed/Core/ArticlePreparation/Extraction/ArticleTextQuality.swift`
- Create: `Briefeed/Core/ArticlePreparation/Extraction/ArticleDOMExtractor.js`
- Create: `BriefeedTests/ArticlePreparation/ArticleTextQualityTests.swift`
- Create: `BriefeedTests/Fixtures/Articles/simple-news.html`
- Create: `BriefeedTests/Fixtures/Articles/navigation-heavy.html`
- Create: `BriefeedTests/Fixtures/Articles/challenge-page.html`

**Interfaces:**
- Consumes: rendered page DOM.
- Produces: a deterministic extraction result and quality decision used by local WebKit and Firecrawl.

- [ ] **Step 1: Write failing quality tests**

Test these exact rules:

```swift
#expect(ArticleTextQuality.evaluate(validStory).isAcceptable)
#expect(!ArticleTextQuality.evaluate("Enable JavaScript to continue").isAcceptable)
#expect(!ArticleTextQuality.evaluate(navigationOnly).isAcceptable)
#expect(ArticleTextQuality.evaluate(longStory).normalizedText.count == 40_000)
```

The long-story cap must backtrack to `.`, `!`, or `?` within the last 500 characters when possible.

- [ ] **Step 2: Run the failing tests**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/ArticleTextQualityTests make radio-unit
```

- [ ] **Step 3: Implement the pure Swift quality gate**

Normalize Unicode whitespace, collapse repeated blank lines, remove duplicate adjacent paragraphs, count words with `NLTokenizer` when available, and reject:

- fewer than 120 characters;
- fewer than 20 words;
- known challenge/error phrases occupying most of the result;
- results whose link/menu label density exceeds body sentence density.

Return:

```swift
struct ArticleTextQualityResult: Equatable, Sendable {
    let normalizedText: String
    let characterCount: Int
    let wordCount: Int
    let wasTruncated: Bool
    let rejection: ArticleTextRejection?
    var isAcceptable: Bool { rejection == nil }
}
```

- [ ] **Step 4: Port only the proven DOM concepts**

The JavaScript must:

1. Clone the DOM so the visible page is not mutated.
2. Remove `script`, `style`, `nav`, `footer`, `aside`, forms, cookie banners, ads, related-story regions, share controls, and hidden nodes.
3. Score `article`, `main`, `[role=main]`, and content-like containers by paragraph text, punctuation, heading count, and link density.
4. Extract `h2`, `h3`, `p`, `blockquote`, and meaningful `li` nodes in document order.
5. Return title, byline, canonical URL, final URL, paragraphs, and diagnostics as JSON.

Do not copy the DeciphVR share-extension queue, app-group code, or its dirty project files.

- [ ] **Step 5: Run tests and commit**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/ArticleTextQualityTests make radio-unit
git add Briefeed/Core/ArticlePreparation/Extraction \
  BriefeedTests/ArticlePreparation/ArticleTextQualityTests.swift \
  BriefeedTests/Fixtures/Articles
git commit -m "feat: add article text cleaner and quality gate"
```

---

### Task 3: Add Local WebKit Extraction With Firecrawl Fallback

**Files:**
- Create: `Briefeed/Core/ArticlePreparation/Extraction/ArticleContentExtracting.swift`
- Create: `Briefeed/Core/ArticlePreparation/Extraction/WebKitArticleExtractor.swift`
- Create: `Briefeed/Core/ArticlePreparation/Extraction/FirecrawlArticleExtractor.swift`
- Create: `Briefeed/Core/ArticlePreparation/Extraction/ArticleExtractionCascade.swift`
- Test: `BriefeedTests/ArticlePreparation/WebKitArticleExtractorTests.swift`
- Test: `BriefeedTests/ArticlePreparation/ArticleExtractionCascadeTests.swift`

**Interfaces:**
- Consumes: `ContentExtractionRequest`.
- Produces: `ContentArtifactDraft`, which Task 4 persists as `ArticleContentArtifact`.

- [ ] **Step 1: Define the provider boundary**

```swift
struct ContentExtractionRequest: Sendable {
    let articleID: UUID
    let submittedURL: URL
    let storedTitle: String
    let storedContent: String?
    let policy: ArticleProviderPolicy
}

struct ContentArtifactDraft: Equatable, Sendable {
    let submittedURL: URL
    let canonicalURL: URL
    let title: String
    let byline: String?
    let text: String
    let provider: ArticleContentProvider
    let wasTruncated: Bool
}

protocol ArticleContentExtracting: Sendable {
    func extract(_ request: ContentExtractionRequest) async throws
        -> ContentArtifactDraft
}
```

- [ ] **Step 2: Write hermetic WebKit tests using bundled HTML**

Load fixture HTML with a base URL through an injected `WKWebViewLoading` seam. Verify redirect/final URL capture, canonical URL, body order, challenge rejection, timeout, cancellation, and that scripts cannot navigate to non-HTTP schemes.

- [ ] **Step 3: Implement `WebKitArticleExtractor`**

Use an ephemeral `WKWebsiteDataStore`, disable window opening, allow only `http` and `https`, and sample the extraction every 650 ms. Accept after two equivalent acceptable samples or at the 12-second deadline. Stop loading and release the web view on completion or cancellation.

The normal Briefeed path starts at `Article.url`. Add Reddit/X resolution only when the submitted host is a wrapper host; never send ordinary publisher URLs back through Reddit.

- [ ] **Step 4: Wrap existing Firecrawl without changing it**

`FirecrawlArticleExtractor` calls the current `FirecrawlService`, converts markdown/HTML to paragraph text, then runs the same `ArticleTextQuality` gate. Record `.firecrawl` as provider.

- [ ] **Step 5: Implement provider policy and fallback**

```swift
enum ArticleProviderPolicy: String, Codable, Sendable {
    case automatic
    case onDevice
    case cloudQuality
}
```

Cascade:

```text
validated stored content
  -> local WebKit
  -> Firecrawl only when policy permits
```

`onDevice` ends with a stage-specific extraction failure. `cloudQuality` may start with Firecrawl. Automatic tries local first.

- [ ] **Step 6: Run tests**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/WebKitArticleExtractorTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/ArticleExtractionCascadeTests make radio-unit
```

- [ ] **Step 7: Commit**

```bash
git add Briefeed/Core/ArticlePreparation/Extraction \
  BriefeedTests/ArticlePreparation/WebKitArticleExtractorTests.swift \
  BriefeedTests/ArticlePreparation/ArticleExtractionCascadeTests.swift
git commit -m "feat: extract article text locally with fallback"
```

---

### Task 4: Build the Raw-Text Preparation Coordinator

**Files:**
- Create: `Briefeed/Core/ArticlePreparation/ArticlePreparationCoordinator.swift`
- Create: `Briefeed/Core/ArticlePreparation/ArticleSpeechScript.swift`
- Modify: `Briefeed/Core/ViewModels/ArticleViewModel.swift`
- Modify: `Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift`
- Test: `BriefeedTests/ArticlePreparation/ArticlePreparationCoordinatorTests.swift`

**Interfaces:**
- Consumes: extraction cascade and preparation store.
- Produces: persisted content, a speech script, priority updates, and observable state; it does not own playback.

- [ ] **Step 1: Write coordinator tests**

Cover:

- duplicate requests share one extraction;
- Play Next promotes an existing Save job;
- Play Now supersedes another pending urgent request but does not delete it;
- stored valid content skips network extraction;
- local rejection falls back to Firecrawl under Automatic;
- local rejection does not call Firecrawl under On Device;
- cancellation persists queued state;
- retry restarts only the failed stage;
- no summarizer is called.

- [ ] **Step 2: Define the coordinator interface**

```swift
protocol ArticlePreparing: Sendable {
    func enqueue(
        article: ArticlePreparationInput,
        priority: ArticlePreparationPriority
    ) async
    func retry(articleID: UUID) async
    func cancel(articleID: UUID) async
    func record(articleID: UUID) async -> ArticlePreparationRecord?
    func states() -> AsyncStream<[UUID: ArticlePreparationState]>
}

struct ArticlePreparationInput: Sendable {
    let id: UUID
    let url: URL
    let title: String
    let storedContent: String?
}
```

- [ ] **Step 3: Implement bounded scheduling**

Use one urgent worker and one saved-lookahead worker. Dedupe by article ID. Priority changes reorder waiting work but never start two synthesis jobs for the same article.

Persist state before and after every awaited provider call. On cancellation, remove partial audio but retain validated content.

- [ ] **Step 4: Build the speech script without summarization**

```swift
enum ArticleSpeechScript {
    static func make(title: String, body: String) -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedTitle.isEmpty ? body : "\(normalizedTitle).\n\n\(body)"
    }
}
```

Do not call Gemini or Foundation Models in this path. Existing summaries remain displayable and existing cloud generation remains available behind the old feature flag during rollout.

- [ ] **Step 5: Route article detail through the same content artifact**

`ArticleViewModel` first asks the coordinator for validated content. If content is ready, display it. If no record exists, enqueue extraction. Do not launch a second Firecrawl/Gemini chain from the view.

- [ ] **Step 6: Remove duplicate preparation from the new player path**

Keep the legacy `generateAudioForItem` implementation intact behind the fallback flag, but make the new path consume the coordinator's script and state. This allows rollback without deleting working cloud code.

- [ ] **Step 7: Run tests and commit**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/ArticlePreparationCoordinatorTests make radio-unit
git add Briefeed/Core/ArticlePreparation \
  Briefeed/Core/ViewModels/ArticleViewModel.swift \
  Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift \
  BriefeedTests/ArticlePreparation/ArticlePreparationCoordinatorTests.swift
git commit -m "feat: coordinate raw article preparation"
```

---

### Task 5: Stream PocketTTS Frames and Cache the Completed WAV

**Files:**
- Create: `Briefeed/Core/ArticlePreparation/Speech/ArticleSpeechRendering.swift`
- Create: `Briefeed/Core/ArticlePreparation/Speech/PocketTTSStreamRenderer.swift`
- Create: `Briefeed/Core/Services/Audio/PCMStreamingPlayer.swift`
- Modify: `Briefeed/Core/Services/Audio/FluidAudioTTSService.swift`
- Modify: `Briefeed/Core/Services/Audio/SwiftAudioExService.swift`
- Modify: `Briefeed/Core/Services/Audio/TTSGeneratorService.swift`
- Test: `BriefeedTests/ArticlePreparation/PocketTTSStreamRendererTests.swift`
- Test: `BriefeedTests/ArticlePreparation/PCMStreamingPlayerTests.swift`
- Test: `BriefeedTests/ArticlePreparation/AVSpeechFileWriterTests.swift`

**Interfaces:**
- Consumes: raw speech script and voice settings.
- Produces: a `PreparedArticleAudio` frame stream immediately and an atomic completed WAV later.

- [ ] **Step 1: Define the streaming contract**

```swift
struct PCMFrame: Sendable {
    let samples: [Float]
    let sampleRate: Double
}

struct PreparedArticleAudio: Sendable {
    let articleID: UUID
    let frames: AsyncThrowingStream<PCMFrame, Error>
    let completedFile: Task<URL, Error>
    let provider: ArticleSpeechProvider
}

protocol ArticleSpeechRendering: Sendable {
    func render(
        articleID: UUID,
        text: String,
        voice: String,
        voiceSpeed: Float
    ) async throws -> PreparedArticleAudio
}
```

- [ ] **Step 2: Write renderer tests with a fake frame source**

Verify frames arrive before file completion, cancellation stops generation, the final WAV is valid 24 kHz mono Float/PCM data, partial files are never returned as cache hits, and the cache key changes with content hash, voice, voice speed, engine, or engine version.

- [ ] **Step 3: Expose FluidAudio 0.14.5 session streaming**

Use the pinned API:

```swift
let session = try await manager.makeSession(voice: voice)
session.enqueue(text)
session.finish()
for try await frame in session.frames {
    continuation.yield(
        PCMFrame(samples: frame.samples, sampleRate: 24_000)
    )
}
```

The current `voiceSpeed` parameter is not implemented by PocketTTS. Until issue #18 is completed, accept only `1.0` for synthesis identity and use player playback rate for faster listening. Do not claim that PocketTTS generated a different-speed file.

- [ ] **Step 4: Buffer and write concurrently**

Append every frame to `audio.partial.wav` while also yielding it. When the session finishes, close and validate the file, rename it to `audio.wav`, then persist `isComplete = true`.

Before switching from Radio, require:

- at least 20 seconds buffered; and
- observed generation real-time factor no worse than 0.8; or
- the complete file is ready.

If the renderer cannot stay ahead, keep Radio playing until the full file is ready. This favors no silence over nominally earlier playback.

- [ ] **Step 5: Add PCM scheduling to the transport**

`PCMStreamingPlayer` uses `AVAudioEngine` and `AVAudioPlayerNode` with a stable 24 kHz mono `AVAudioFormat`. Convert each `[Float]` into `AVAudioPCMBuffer`, schedule in order, and report:

- first buffer playable;
- current played time;
- buffered seconds;
- underrun;
- terminal success/failure.

`SwiftAudioExService` owns either its existing URL player or `PCMStreamingPlayer`, never both. Remote controls and Now Playing metadata continue to flow through the existing service.

- [ ] **Step 6: Repair the AVSpeech file fallback**

Use one `AVAudioFile` for the entire utterance. Await `AVSpeechSynthesizer.write`
until its terminal zero-length buffer arrives, then close and validate the file.
Never create the output file inside the callback for every buffer.

Test multiple non-empty buffers followed by a terminal buffer, write failure,
cancellation, and that the returned file contains all frames rather than only
the final callback.

- [ ] **Step 7: Keep current fallbacks**

If PocketTTS fails before handoff, Automatic may try OpenAI, Gemini, then the repaired AVSpeech writer while Radio continues. If it fails after handoff, resume the captured continuation immediately and mark the speech stage failed; do not leave dead air while a fallback starts.

- [ ] **Step 8: Run tests and commit**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/PocketTTSStreamRendererTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/PCMStreamingPlayerTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/AVSpeechFileWriterTests make radio-unit
git add Briefeed/Core/ArticlePreparation/Speech \
  Briefeed/Core/Services/Audio/FluidAudioTTSService.swift \
  Briefeed/Core/Services/Audio/PCMStreamingPlayer.swift \
  Briefeed/Core/Services/Audio/SwiftAudioExService.swift \
  Briefeed/Core/Services/Audio/TTSGeneratorService.swift \
  BriefeedTests/ArticlePreparation
git commit -m "feat: stream and cache PocketTTS article audio"
```

---

### Task 6: Add Programmatic Radio Continuations

**Files:**
- Modify: `Briefeed/Core/Radio/RadioModels.swift`
- Modify: `Briefeed/Core/Radio/RadioSessionCoordinator.swift`
- Create: `Briefeed/Core/Services/Audio/PlaybackContinuation.swift`
- Create: `Briefeed/Core/Services/Audio/ArticlePlaybackScheduler.swift`
- Modify: `Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift`
- Test: `BriefeedTests/ArticlePreparation/ArticlePlaybackSchedulerTests.swift`
- Modify: `BriefeedTests/Radio/RadioPlaybackStateTests.swift`
- Modify: `BriefeedTests/Radio/UnifiedRadioPlaybackTests.swift`

**Interfaces:**
- Consumes: playable article events from Task 5.
- Produces: no-silence handoff and exact continuation resume.

- [ ] **Step 1: Write the Radio interruption regression**

```swift
@Test func articleInterruptionPreservesRadioWithoutBecomingUserPause() async {
    // Radio is playing BBC at 73 seconds.
    let continuation = coordinator.suspendForArticle(
        positionSeconds: 73,
        duration: 300
    )

    #expect(continuation == .radio(key: bbc.key, positionSeconds: 73))
    #expect(coordinator.state == .readyPaused)
    #expect(coordinator.entries[current].positionSeconds == 73)
}
```

Also test stale replacement: if the captured key is no longer eligible, resume the coordinator's current eligible item rather than reviving stale news.

- [ ] **Step 2: Add explicit coordinator APIs**

```swift
func suspendForArticle(
    positionSeconds: TimeInterval,
    duration: TimeInterval?
) -> PlaybackContinuation?

func resumeAfterArticle(
    _ continuation: PlaybackContinuation
) -> RadioPlaybackIntent?
```

These operations persist progress but do not set `.pausedByUser`. Keep `pauseByUser` unchanged for a real user pause.

- [ ] **Step 3: Implement scheduler state**

```swift
enum ArticlePlaybackIntentKind: Sendable {
    case savedBoundary
    case playNext
    case playNow
}

struct ArticlePlaybackIntent: Sendable {
    let articleID: UUID
    let queueItemID: UUID
    let kind: ArticlePlaybackIntentKind
    let requestedAt: Date
}
```

Priority:

1. playable Play Now;
2. playable Play Next;
3. one ready saved article at a Radio completion boundary;
4. captured continuation;
5. Radio's normal next item.

- [ ] **Step 4: Implement the exact handoff order**

```text
article reaches safe playable threshold
  -> read transport Radio position now
  -> coordinator.suspendForArticle(position)
  -> store continuation
  -> start article stream/file
  -> only after article transport starts, mark article playing
```

If article start fails, immediately execute the continuation and keep the article failed/queued according to retry policy.

- [ ] **Step 5: Implement terminal behavior**

- completion: mark listened and resume continuation;
- Skip: mark skipped and resume continuation;
- Pause: pause article and preserve continuation;
- explicit Stop: stop article, clear continuation, remain stopped;
- explicit Radio selection: abandon the article continuation and play the selected Radio item;
- removal of active article: resume continuation.

- [ ] **Step 6: Remove the old user-pause misuse**

The new article path must not call `radioCoordinator.pauseByUser(...)`. Leave that method for the mini-player Pause button and remote pause command.

- [ ] **Step 7: Run tests and commit**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/ArticlePlaybackSchedulerTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/RadioPlaybackStateTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/UnifiedRadioPlaybackTests make radio-unit
git add Briefeed/Core/Radio \
  Briefeed/Core/Services/Audio \
  BriefeedTests/ArticlePreparation \
  BriefeedTests/Radio
git commit -m "feat: resume Radio after article interruptions"
```

---

### Task 7: Wire Save, Play Next, Play Now, and the Unified Brief Projection

**Files:**
- Modify: `Briefeed/Features/Article/ArticleRowView.swift`
- Modify: `Briefeed/Core/Services/QueueCoordinator.swift`
- Modify: `Briefeed/Core/ViewModels/BriefViewModel.swift`
- Modify: `Briefeed/Features/Brief/BriefView+Filtering.swift`
- Test: `BriefeedTests/ArticlePreparation/ArticleActionRoutingTests.swift`
- Test: `BriefeedTests/ArticlePreparation/BriefProjectionTests.swift`
- Modify: `BriefeedUITests/SwipeInteractionUITests.swift`

**Interfaces:**
- Consumes: coordinator and scheduler from Tasks 4 and 6.
- Produces: one truthful user-facing queue and preparation status.

- [ ] **Step 1: Write action-routing tests**

Assert:

```text
Save      -> QueueCoordinator FIFO + priority saved + no player switch
Play Next -> QueueCoordinator urgent position + priority playNext
Play Now  -> QueueCoordinator current intent + priority playNow
```

Repeated actions must move/promote the existing article rather than duplicate it.

- [ ] **Step 2: Make QueueCoordinator article-only for new writes**

Do not delete legacy decoding yet. Stop adding new `.liveNews` items. `QueueCoordinator.queue` remains the canonical durable article playback intent list; `UnifiedAudioPlayer.queue` stays a derived projection.

- [ ] **Step 3: Build Brief projections**

```swift
struct BriefProjection {
    let radio: [RadioPlaylistItem]
    let articles: [QueueItem]

    var all: [BriefDisplayItem] {
        radio.map(BriefDisplayItem.radio)
            + articles.map(BriefDisplayItem.article)
    }
}
```

- **Live News** reads `RadioSessionCoordinator`, not legacy queue items.
- **Articles** reads durable `QueueCoordinator`.
- **All** combines projections for display only. It does not persist Radio copies.

- [ ] **Step 4: Show stage-specific states**

Replace overloaded `summaryState` presentation with:

- Getting article
- Making audio
- Ready
- Playing
- Failed to get article
- Failed to make audio

Retry calls `ArticlePreparationCoordinator.retry(articleID:)` and restarts only the failed stage.

- [ ] **Step 5: Migrate legacy queue data**

On first launch of the new queue schema:

1. preserve every article item and its position/bookmark;
2. discard expired legacy live-news queue items;
3. do not delete saved `Article` Core Data rows;
4. dedupe by `articleID`;
5. write the migrated queue atomically with schema version 2.

- [ ] **Step 6: Run unit and UI tests**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/ArticleActionRoutingTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/BriefProjectionTests make radio-unit
RADIO_UI_TEST_SELECTOR=BriefeedUITests/SwipeInteractionUITests make radio-ui
```

- [ ] **Step 7: Commit**

```bash
git add Briefeed/Features/Article \
  Briefeed/Core/Services/QueueCoordinator.swift \
  Briefeed/Core/ViewModels/BriefViewModel.swift \
  Briefeed/Features/Brief \
  BriefeedTests/ArticlePreparation \
  BriefeedUITests/SwipeInteractionUITests.swift
git commit -m "feat: unify Radio and article Brief projections"
```

---

### Task 8: Persist, Resume, and Bound Background Work

**Files:**
- Create: `Briefeed/Core/ArticlePreparation/ArticlePreparationLifecycleDriver.swift`
- Modify: `Briefeed/BriefeedApp.swift`
- Modify: `Briefeed/Info.plist`
- Test: `BriefeedTests/ArticlePreparation/ArticlePreparationLifecycleTests.swift`

**Interfaces:**
- Consumes: persisted jobs and scene/background callbacks.
- Produces: resumable work without overstating iOS guarantees.

- [ ] **Step 1: Write lifecycle tests**

Cover:

- foreground restore requeues `extracting` and `synthesizing` as queued;
- background saves current stage and closes partial files;
- returning active resumes urgent work first;
- Save work may be scheduled as opportunistic processing;
- Play Next/Now retains its intent if iOS suspends the app;
- Radio playback is not stopped by article job persistence.

- [ ] **Step 2: Implement iOS 18 behavior**

Use `beginBackgroundTask` only to finish the current atomic write/cancel transition. Register `BGProcessingTask` for low-priority saved backlog, with network required only when policy/provider requires it. Expect the system to defer or skip it.

If WebKit is suspended before acceptable text exists, persist queued state. On return, retry local extraction. Automatic may use Firecrawl only while execution is actually available.

- [ ] **Step 3: Gate iOS 26 continued processing**

Under `if #available(iOS 26, *)`, Play Now/Next may submit `BGContinuedProcessingTaskRequest` with visible progress and cancellation. Keep this an enhancement; no iOS 18 acceptance criterion may depend on it.

- [ ] **Step 4: Run tests and commit**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/ArticlePreparationLifecycleTests make radio-unit
git add Briefeed/Core/ArticlePreparation/ArticlePreparationLifecycleDriver.swift \
  Briefeed/BriefeedApp.swift Briefeed/Info.plist \
  BriefeedTests/ArticlePreparation/ArticlePreparationLifecycleTests.swift
git commit -m "feat: resume article preparation across lifecycle"
```

---

### Task 9: Feature Policy, Rollout, and Physical-Device Proof

**Files:**
- Modify: `Briefeed/Core/Utilities/UserDefaultsManager.swift`
- Modify: `Briefeed/Features/Settings/SettingsView.swift`
- Create: `Briefeed/docs/receipts/2026-07-27-local-article-audio-verification.md`
- Modify: `Briefeed/docs/article-pipeline-audit-2026-07-27.md`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: reversible rollout, measurement, and device acceptance evidence.

- [ ] **Step 1: Add rollout settings**

Persist:

```swift
var articlePreparationV2Enabled: Bool
var articleProviderPolicy: ArticleProviderPolicy
var pocketTTSVoice: String
```

Default `articlePreparationV2Enabled` to false for the first device build. Existing cloud behavior remains the rollback path.

- [ ] **Step 2: Run the hermetic gate**

```bash
RADIO_TEST_SELECTOR=BriefeedTests/ArticlePreparationStoreTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/ArticleTextQualityTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/ArticleExtractionCascadeTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/ArticlePreparationCoordinatorTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/PocketTTSStreamRendererTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/ArticlePlaybackSchedulerTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/BriefProjectionTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/UnifiedRadioPlaybackTests make radio-unit
make radio-compile
```

- [ ] **Step 3: Run an explicit live extraction benchmark**

Use a fixed, documented set of public articles across simple HTML, JavaScript-heavy, redirecting, challenge, and paywall sites. Record:

- local success/rejection/timeout;
- fallback used;
- time to content ready;
- character/word counts;
- no article text in logs or analytics.

Do not make these publisher-dependent checks part of default unit tests.

- [ ] **Step 4: Run physical-device playback acceptance**

On the user's iPhone:

1. Start Radio and note episode/time.
2. Save an article; confirm Radio never pauses.
3. Choose Play Next on another article.
4. Confirm Radio continues through extraction and synthesis.
5. Confirm article starts only after a safe playable buffer.
6. Background the app and scroll Instagram; confirm Briefeed audio continues subject to iOS audio-session rules.
7. Let the article finish; confirm the exact Radio episode/time resumes.
8. Repeat with Skip, Pause, explicit Stop, provider failure, network loss, and app relaunch.
9. Confirm a new top NPR item still wins a later cold launch over an older restored BBC item.

- [ ] **Step 5: Enable staged rollout**

Enable V2 only after the no-silence and exact-resume checks pass. Keep the old provider path for one release cycle. Remove it only after migration metrics and failure categories show no regression.

- [ ] **Step 6: Update issues and commit**

Update issues #8, #18, #19, #27, #28, and #29 with test/device receipts. Close only acceptance criteria that were actually verified.

```bash
git add Briefeed/Core/Utilities/UserDefaultsManager.swift \
  Briefeed/Features/Settings/SettingsView.swift \
  Briefeed/docs
git commit -m "docs: verify local article audio rollout"
git pull --rebase
git push
git status
```

Expected final status: clean and up to date with the remote branch.

## Acceptance Summary

The slice is complete only when all of these are true:

- an external publisher article can produce acceptable text on device;
- Firecrawl still works as the permitted fallback;
- no summary is required for raw-text playback;
- PocketTTS yields playable frames before full-file completion on supported hardware;
- slow synthesis does not create an underrun or silence because Radio continues until safe handoff;
- Save never interrupts;
- Play Next and Play Now interrupt only when ready;
- article completion and Skip resume the exact Radio continuation;
- explicit Stop stays stopped;
- Brief Live News reflects the Radio coordinator rather than the legacy queue;
- preparation failures identify extraction versus speech;
- queued and failed jobs survive relaunch;
- the old cloud path remains available during rollout;
- the complete interaction is verified on the physical iPhone.
