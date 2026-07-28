# Article Preparation and Unified Playback Audit

Date: 2026-07-27

Branch: `codex/article-pipeline-audit`

Baseline: `2176f0f` (the working Live Radio build now on `origin/master`)

Implementation plan:
`docs/superpowers/plans/2026-07-27-local-article-audio-radio-continuation.md`

## Executive decision

Do not replace Firecrawl, Gemini, or cloud voices. Put each behind a provider
boundary and add local providers beside them.

The product should have two durable concepts rather than one giant mixed queue:

1. **Radio session:** an ephemeral, latest-news lane owned by
   `RadioSessionCoordinator`. It keeps only the useful current episode state for
   each source and should not copy every episode into the Brief.
2. **Brief:** a durable user-curated article lane. Saved articles can prepare in
   the background, while Play Next and Play Now create higher-priority playback
   intents.

A small playback scheduler should project those lanes into one "what plays
next" experience. It should capture a continuation before an article interrupts
Radio, then resume the exact Radio episode and media position after the article.
This is not safely expressible by reordering one persisted mixed array.

## What exists now

### Discovery

- Feed discovery is Reddit's unauthenticated JSON API, not Reddit RSS:
  `DefaultDataService.generateFeedURL` appends `.json`, `limit`, and
  `raw_json=1` (`Core/Services/DefaultDataService.swift:67-130`).
- `RedditService` decodes the listing and filters it before storage
  (`Core/Services/RedditService.swift:67-166`).
- Self posts, videos, files, and selected internal Reddit links are filtered
  out. The stored article URL is normally already the external publisher URL
  (`DefaultDataService.swift:133-185`,
  `RedditService.swift:169-203`).

This means the DeciphVR Reddit URL resolver is useful for future share/comment
URLs, but it is not required for normal Briefeed feed rows.

### Reading and summary display

Opening an article currently does this serially:

```text
ArticleView task
  -> Firecrawl scrape
  -> save markdown/content to Article.content
  -> Gemini structured summary
  -> save only the story string to Article.summary
  -> display content
```

Evidence:

- `ArticleView` calls `loadArticleContent()` before there is content to render
  (`Features/Article/ArticleView.swift:49-55`).
- `ArticleViewModel` calls Firecrawl directly and then automatically calls
  Gemini (`Core/ViewModels/ArticleViewModel.swift:76-145`).
- Quick Facts and the structured result are only in the view model. Persistence
  stores the `story` string, so structured fields do not survive reconstruction
  (`ArticleViewModel.swift:125-138`).
- `ArticleReaderView` can display content or an ordinary `WKWebView`, but its
  "reader mode" only removes a small selector list after a timer. It does not
  return extracted text to the preparation pipeline
  (`Features/Article/ArticleReaderView.swift:222-260`).

### Audio preparation

Article audio duplicates the extraction and summary path inside
`UnifiedAudioPlayer`:

```text
Play article
  -> use stored summary, otherwise:
       use stored content or Firecrawl
       truncate to 20,000 characters
       Gemini plain-text summary
  -> format spoken script
  -> PocketTTS when preferred
  -> OpenAI fallback when configured
  -> Gemini TTS fallback
  -> AVSpeechSynthesizer fallback inside TTSGeneratorService
  -> play completed audio file
```

Evidence:

- The second Firecrawl/Gemini implementation is in
  `Core/Services/Audio/UnifiedAudioPlayer.swift:1523-1650`.
- Provider selection is hard-coded in the player at
  `UnifiedAudioPlayer.swift:1668-1732`.
- PocketTTS is already local and on-device through FluidAudio 0.14.5. It
  downloads/compiles its Core ML assets on first use and currently creates the
  complete WAV before playback (`Core/Services/Audio/FluidAudioTTSService.swift:
  201-305`).
- Only the immediately next Brief item is warmed
  (`UnifiedAudioPlayer.swift:1794-1814`).
- The `CachedAudio` Core Data entity exists, but `TTSGeneratorService` still
  only prints "Would track in Core Data"; provider/model provenance is not
  recorded (`Core/Services/Audio/TTSGeneratorService.swift:397-408`).

### Brief and Radio

- `QueueCoordinator` still supports a legacy `.liveNews` item type, expiration,
  and mixed-queue filters (`Core/Services/QueueCoordinator.swift:13-60`,
  `312-349`, `548-608`).
- The new Radio implementation does not use that queue. It has its own
  `RadioSessionCoordinator`, and `UnifiedAudioPlayer` builds a separate
  `radioQueue` projection (`UnifiedAudioPlayer.swift:431-465`).
- Brief's Live News tab still filters `QueueCoordinator` for RSS items and says
  they will appear after refresh (`Features/Brief/BriefView+Filtering.swift:
  30-41`, `203-220`, `289-295`).

Therefore the screenshot's **No Live News** state is not evidence that Radio
failed to refresh. It is a stale projection of the pre-Radio queue design.

Brief also has two persistence mechanisms:

- saved `Article` rows in Core Data, loaded newest-first
  (`Core/ViewModels/BriefViewModel.swift:46-60`);
- a separately persisted `QueueCoordinator` array and current position
  (`QueueCoordinator.swift:634-680`).

The Brief view hydrates saved articles only when the transport queue is empty
(`BriefView+Filtering.swift:83-90`). Those stores can diverge.

## Findings

### P0: Article interruption cannot resume Radio

When an article begins, the player calls Radio's user-pause operation, stops the
transport, and switches `activeMode` to Brief
(`UnifiedAudioPlayer.swift:659-681`). When the final Brief item completes, it
sets the mode to none; it does not resume Radio
(`UnifiedAudioPlayer.swift:762-808`).

The result conflicts with the intended experience: an article cannot
temporarily sit above Radio and then return to the exact episode position.

### P0: Play Next does not mean "interrupt when ready"

Feed Play Next saves the article and calls `addToQueue(... playNext: true)`
(`Features/Article/ArticleRowView.swift:304-315`). The coordinator inserts it
after the current Brief index (`QueueCoordinator.swift:352-367`).

If Radio is playing, there is no current Brief index. The player may prepare the
article, but it never switches to it when preparation completes
(`UnifiedAudioPlayer.swift:608-622`). This is materially different from:

> keep current audio playing while the article prepares, switch as soon as it is
> ready, then resume what was interrupted.

### P0: Preparation is blocking and duplicated

Play Now switches away from Radio before Firecrawl, Gemini, and full-file TTS
finish. A one- or two-minute local generation can therefore create silence
instead of letting ready Radio audio continue. Article detail and article audio
also run different extraction/summary code paths with different output formats.

One preparation coordinator should own the artifact once and publish it to both
the reader and player.

### P1: Failure state cannot identify the failed stage

`QueueItem.summaryState` is used to represent the whole content-to-audio
pipeline even though "summary ready" and "audio ready" are different facts.
There is one error string and retry counter
(`QueueCoordinator.swift:24-40`, `495-545`).

A red failed row cannot currently tell us whether a rotated Firecrawl key,
Gemini quota/key, content quality rejection, model download, PocketTTS, cache,
or playback failed. The screenshots alone cannot attribute the failed rows to
an API key.

### P1: AVSpeech file fallback is not trustworthy

`TTSGeneratorService.generateWithAVSpeech` starts asynchronous buffer delivery,
then immediately reads the output file. It also constructs a new
`AVAudioFile(forWriting:)` for each buffer callback
(`Core/Services/Audio/TTSGeneratorService.swift:231-294`).

Apple's API delivers speech through repeated asynchronous buffer callbacks.
The implementation needs one retained writer, an explicit terminal-buffer
condition, and exactly-once continuation completion before it can be treated as
a reliable native fallback.

### P1: Article persistence lacks artifact identity

`Article` stores only URL, content, and summary. `QueueItem` stores one cached
audio URL (`Briefeed.xcdatamodeld/.../contents:3-18`,
`QueueCoordinator.swift:15-40`).

There is no content fingerprint, canonical URL, extraction provider, summary
provider/model/prompt version, TTS provider/model/voice, or per-stage timestamp.
Provider changes and stale cached artifacts therefore cannot be invalidated
deterministically.

### P2: The local TTS path is real, but its UX still hides latency

The app pins FluidAudio 0.14.5 and already uses PocketTTS locally. Two existing
issues correctly cover streaming the first chunks instead of waiting for the
entire WAV (#8) and the currently ineffective synthesis-speed setting/cache key
(#18).

PocketTTS should remain the local default candidate. Cloud voices remain a
useful quality tier, not a fallback that must be removed.

## DeciphVR extraction audit

The requested checkout is actually:

`/Users/me/ericode/dechiphvr/Deciphvr`

on `codex/reader-first-system`. It is a heavily dirty worktree, and the relevant
extractor files are currently untracked. Briefeed should consume the ideas, not
silently mutate or depend on that worktree.

Useful pieces:

- URL normalization removes credentials, fragments, common tracking parameters,
  and non-HTTP schemes (`Deciphvr/SharedURLImport.swift:133-181`).
- Public-destination validation rejects localhost and common private/reserved
  IPv4 ranges (`SharedURLImport.swift:184-225`).
- The Safari share preprocessing script captures the already-rendered page text
  before handing the URL to the app
  (`deciphvrShareExtension/SafariAction.js:1-36`).
- The in-app extractor loads a real `WKWebView`, clones the DOM, removes common
  junk, scores semantic content containers, samples until text length
  stabilizes, and returns title/byline/canonical/final URLs
  (`Deciphvr/ArticleTextExtractor.swift:42-190`, `193-407`).
- A quality gate rejects very short results and known browser challenge text
  (`Deciphvr/SharedURLImport.swift:251-304`).
- Safari-captured text is retained as a fallback if a later clean WebKit
  extraction fails (`Deciphvr/ImportCoordinator.swift:174-194`).

The deterministic story-pipeline gate passes: `21` passed, `0` failed.
However, those tests validate normalization, redirect policy, quality rules,
and serialization. They are not a current live-site extraction benchmark.

Recommended adaptation:

1. Copy the bounded URL safety, text cleaner, quality gate, DOM extractor, and
   extraction-session concepts into a Briefeed-owned module.
2. Skip DeciphVR's Reddit resolver for ordinary feed items because Briefeed
   already stores publisher URLs.
3. Add HTML fixtures for article, navigation-heavy, paywall/challenge, and
   malformed pages before enabling local-first extraction.
4. Run an opt-in live matrix against representative publishers; never make live
   requests part of the normal unit suite.
5. Keep Firecrawl as the next provider when local extraction fails quality,
   navigation, timeout, or content-type checks.

## Apple on-device capability

### Summarization

Apple's Foundation Models framework is a viable local summarizer on supported
systems:

- Apple describes the on-device model as optimized for summarization and
  extraction, able to run offline without increasing app size.
- `@Generable` and guided generation can produce the existing Quick Facts and
  Story shape as typed Swift data rather than best-effort JSON.
- The model is device-scale, not a source of current world knowledge. Prompts
  must constrain it to the extracted article.
- Runtime availability must be checked. The documented unavailable reasons
  include Apple Intelligence disabled, device ineligible, and model not ready.
- The context window is around 4K tokens, so the present 20,000-character input
  needs a chunk-and-reduce or extract-then-summarize strategy.

The app currently targets iOS 18.2. A Foundation Models provider must be
availability-gated (iOS 26+ for the introduced API) while the provider protocol
and Gemini fallback continue to compile and work on older devices.

Primary references:

- [Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)
- [SystemLanguageModel availability reasons](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum/unavailablereason)
- [Managing the on-device model context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [Apple DTS clarification on the approximately 4K context window](https://developer.apple.com/forums/thread/813557)

### Text to speech

There are already two local choices:

1. **PocketTTS through FluidAudio:** the current higher-quality local path,
   with model download/compile cost and a need for streaming/caching work.
2. **AVSpeechSynthesizer:** built into Apple platforms, supports generating
   buffers for storage, and is suitable as the no-model emergency fallback once
   the file writer is fixed.

FluidAudio documents PocketTTS as a local Core ML, streaming-capable engine.
Briefeed should benchmark the pinned version and chosen voices on the minimum
supported phones before calling any voice "newscaster quality."

Primary references:

- [AVSpeechSynthesizer buffer generation](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/write(_:tobuffercallback:))
- [FluidAudio PocketTTS API](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/API.md)

## Target provider architecture

Keep provider choice independent at each stage:

```swift
protocol ArticleContentExtracting {
    func extract(_ request: ContentExtractionRequest) async throws -> ContentArtifact
}

protocol ArticleSummarizing {
    func summarize(_ request: SummaryRequest) async throws -> SummaryArtifact
}

protocol SpeechRendering {
    func render(_ request: SpeechRequest) async throws -> AudioArtifact
}
```

Recommended automatic strategy:

| Stage | Local first | Cloud fallback / quality option |
| --- | --- | --- |
| Discovery | Existing Reddit listing | Future authenticated/server discovery only if needed |
| Content | Stored validated content, then Briefeed WebKit extractor | Firecrawl |
| Summary | Foundation Models when available and input fits/chunks safely | Gemini |
| Speech | Cached artifact, then PocketTTS | OpenAI/Gemini premium voice |
| Emergency speech | Fixed AVSpeechSynthesizer writer | None required |

Each artifact should carry:

- canonical and submitted URL;
- source content fingerprint and character/word counts;
- provider, model/library version, and completion date;
- prompt/schema version for summaries;
- voice, locale, synthesis settings, and cache key for audio;
- stage-specific error category and provider attempts.

Provider policy should be user-readable:

- **Automatic:** private/local first, cloud fallback.
- **On Device:** never send article text to a summarization or TTS provider.
- **Cloud Quality:** allow the selected premium providers.

Firecrawl and premium model credentials must eventually be server-owned for
distribution; existing issue #16 already tracks the current embedded-key
release blocker.

## Unified playback contract

### User actions

| Action | Durable effect | Playback effect |
| --- | --- | --- |
| Save | Add article to Brief FIFO | Do not interrupt. Prepare opportunistically. |
| Play Next | Add/move article to urgent Brief position | Keep current audio playing while preparing; interrupt as soon as ready. |
| Play Now | Add/move article to immediate intent | Same no-silence preparation, then interrupt as soon as ready. |
| Remove | Remove the Brief intent/artifacts according to cache policy | If currently playing, resume the captured continuation. |

### Scheduler priority

1. Active explicit Play Now/Play Next article when its audio becomes ready.
2. Next ready saved article at a natural Radio boundary.
3. Captured continuation from an interrupted article or Radio item.
4. `RadioSessionCoordinator`'s latest eligible episode.

Play Next needs a LIFO continuation token:

```swift
enum PlaybackContinuation {
    case radio(key: RadioEpisodeKey, position: TimeInterval)
    case brief(itemID: UUID, position: TimeInterval)
}
```

When the article completes, resume the exact token. If the referenced Radio
episode is no longer valid, ask `RadioSessionCoordinator` for its current
eligible item rather than reviving stale audio.

The player must not pause or stop the active transport until the replacement
article has a verified playable audio artifact. Preparation state is not
playback state.

### Brief screen

- **Articles** should remain the durable queue.
- **Live News** should not read legacy `QueueCoordinator.liveNews`. It can
  become a projection of the current Radio item and current/latest source
  entries, or be removed.
- **All** can be a read-only playback-plan projection combining Radio's current
  continuation with Brief intents. It should not persist copies of Radio
  episodes into Brief.
- The 93/94 legacy article rows need an explicit migration/cleanup rule rather
  than being silently deleted.

## Preparation state machine

Persist separate stages:

```text
queued
  -> extracting -> contentReady
  -> summarizing -> summaryReady
  -> synthesizing -> audioReady
  -> playing -> completed
```

Every working stage can also be `waiting`, `failed(provider, category,
retryAfter)`, or `skipped`. A fallback attempt appends provenance instead of
overwriting the original error.

Use a bounded worker pool:

- urgent Play Now/Play Next: one high-priority job;
- saved Brief items: one low-priority lookahead worker;
- keep Radio playing whenever the requested article is not ready;
- retry only the failed stage;
- resume persisted jobs after launch.

## Background execution

Do not promise arbitrary immediate work after suspension.

- On iOS 26+, `BGContinuedProcessingTaskRequest` is specifically for work
  initiated by a person's foreground action and can continue after the app is
  backgrounded. Play Now and Play Next fit that shape, with system-visible
  progress and cancellation.
- `BGProcessingTask` can opportunistically prepare saved backlog for minutes,
  but the system chooses when it runs; it is not an immediate queue guarantee.
- A short `beginBackgroundTask` is for finishing critical transition work, not
  a durable one- or two-minute pipeline.
- Local WebKit extraction should happen while foregrounded whenever possible.
  If the app backgrounds before usable text is captured, persist the job and
  use Firecrawl/cloud as policy allows or retry local extraction on return.
- Cloud generation remains the most reliable path for completing work while
  the app is fully suspended.

Primary references:

- [BGContinuedProcessingTaskRequest](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest)
- [Finish tasks in the background](https://developer.apple.com/videos/play/wwdc2025/227/)

## Phased delivery

### Phase 1: Make state truthful

- Introduce provider-neutral content, summary, and audio artifacts.
- Persist per-stage state and provenance.
- Route both Article detail and audio preparation through one coordinator.
- Fix the AVSpeech file writer.
- Do not change the current provider order yet.

### Phase 2: Local extraction beside Firecrawl

- Port the bounded DeciphVR extractor subset into Briefeed.
- Add fixture and quality tests.
- Enable local-first, Firecrawl-fallback strategy behind a setting/feature flag.
- Measure extraction success, latency, and content length without storing
  article text in analytics.

### Phase 3: Apple summary beside Gemini

- Add an availability-gated Foundation Models provider.
- Use guided generation for typed Quick Facts and Story.
- Implement deterministic chunk/reduce and context-overflow fallback.
- Run a fixed article evaluation set for factual support, omission, latency,
  battery, and failure rate before making it the automatic default.

### Phase 4: Scheduler and Brief projection

- Implement continuation tokens and no-silence prepared handoff.
- Make Play Next interrupt when ready and resume exact prior media time.
- Remove the stale legacy Live News queue projection.
- Reconcile saved-article and queue persistence.
- Add migration and focused mode-switch/relaunch tests.

### Phase 5: TTS latency and product tiers

- Complete existing PocketTTS streaming issue #8.
- Complete synthesis setting/cache identity issue #18.
- Benchmark local voices against premium cloud voices.
- Add Automatic, On Device, and Cloud Quality policies.

## Verification matrix

- local extraction succeeds, fails quality, times out, redirects, and hits a
  browser challenge;
- Firecrawl succeeds after each local failure class;
- Foundation Models unavailable for each documented reason;
- context overflow chunks or falls back without losing stage state;
- Gemini/Firecrawl key invalid, quota, timeout, and retry-after;
- PocketTTS cold model download, warm synthesis, cancellation, and cache hit;
- AVSpeech multi-buffer file generation and terminal callback;
- Radio -> Play Next preparation -> article -> exact Radio resume;
- article -> Play Next article -> exact article resume;
- app background during every stage on iOS 18 and iOS 26+;
- relaunch with queued, working, ready, and failed jobs;
- stale Radio replacement while an article is playing;
- Brief migration with the current large saved queue;
- no external network/model downloads in the default unit suite.

## Existing issue alignment

- #8: PocketTTS streaming
- #14: hermetic hosted tests
- #16: embedded provider credentials
- #18: PocketTTS synthesis speed and cache identity
- #19: Brief/Radio action and queue contract
- #26: Apple Foundation Models summarizer spike
- #27: persisted provider-neutral article preparation
- #28: local WebKit extraction with Firecrawl fallback
- #29: AVSpeechSynthesizer file-rendering fallback

Queue handoff work belongs under #19 rather than a second competing queue epic.
