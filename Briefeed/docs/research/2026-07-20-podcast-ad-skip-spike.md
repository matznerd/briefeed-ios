# Podcast Ad-Skip Feasibility Spike

**Date:** July 20, 2026  
**Status:** Research proposal only; not part of the Live Radio launch slice

## Product Goal

Identify likely sponsor segments in podcast episodes, beginning with lead-in and
end ads, so Briefeed can offer a reversible **Skip Ad** action. Automatic
skipping remains a later, opt-in capability after measured false-positive risk
is low enough.

The first reference case is the Odoo lead-in ad in a Marketplace Morning Report
episode from July 20, 2026. The fixture must be preserved by enclosure asset
hash rather than GUID alone because podcast ads may be dynamically inserted.

## Current Briefeed Capability

- FluidAudio `0.14.5` is already pinned, but Briefeed currently integrates only
  PocketTTS. FluidAudio also contains local ASR, token timing, VAD, and offline
  diarization APIs that are not wired into the app.
- The current SwiftAudioEx wrapper exposes transport state, not decoded PCM.
  Analysis therefore needs a separately downloaded local episode asset or a
  separate AVFoundation decoding path.
- `RSSEpisode.downloadedFilePath` exists but production Radio does not populate
  it. The data model has no transcript, timing, speaker, or ad-segment fields.
- The existing `TranscriptReaderView` displays article text; it is not speech
  recognition.

## Recommended Stack

Use an Apple-first hybrid rather than an LLM-only detector:

1. On iOS 26+, use `SpeechAnalyzer` and `SpeechTranscriber` for file-based,
   timestamped transcription. Apple manages the speech assets outside the app's
   binary and exposes word or phrase time ranges and transcription confidence.
2. On the current iOS 18.2 deployment floor, benchmark FluidAudio's small
   English ASR model. Use its VAD and diarization only as additional boundary
   evidence.
3. Build deterministic features from transcript wording, episode position,
   silence, music or energy changes, recurrence across episodes, and optional
   speaker changes.
4. On supported Apple Intelligence devices, use Foundation Models structured
   output as one semantic feature: `paidAd`, `showPromo`, `underwriting`,
   `editorial`, or `uncertain`. Do not treat model-reported confidence as a
   calibrated probability.
5. Smooth evidence into contiguous candidate spans and expose manual Skip Ad
   first. Auto-skip stays disabled until an explicit safety gate passes.

Apple references: [SpeechAnalyzer and SpeechTranscriber](https://developer.apple.com/videos/play/wwdc2025/277/),
[Foundation Models task generation](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models),
[Sound Analysis](https://developer.apple.com/documentation/soundanalysis/), and
[BackgroundTasks](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask).

FluidAudio references: [API](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/API.md),
[models](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md), and
[benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md).

## Phase A: Local Transcription Probe

Build a DEBUG or integration-test-only `PodcastTranscriptionProbe`:

- Input is an explicitly supplied, rights-cleared local audio fixture of 60 to
  180 seconds. No production feed downloading or Core Data mutation.
- First-time model download is gated by an environment flag and never happens
  silently in tests.
- Emit a temporary JSON receipt with text, confidence, token or word timings,
  audio duration, processing time, model version, OS version, peak memory, and
  asset SHA-256.
- Assert nonempty text and monotonic timestamps contained within the asset.
- Compare Apple SpeechAnalyzer on an eligible iOS 26 device with FluidAudio on
  the iPhone 13 deployment floor.

This phase proves transcription and timing only. It does not classify ads.

## Phase B: Odoo Boundary Spike

1. Preserve the Marketplace episode fixture with feed ID, GUID, enclosure URL,
   ETag if present, byte count, SHA-256, and human-labeled ad start/end plus the
   first editorial word.
2. Analyze only the first five and final four minutes.
3. Generate sentence-window features: sponsor and call-to-action wording,
   brand density, URL or offer language, positional prior, recurrence, ASR
   confidence, silence, audio-energy change, music probability, and speaker
   transition.
4. Ask Foundation Models to label only candidate windows with before/after
   context and stable transcript anchors. The detector must not hard-code Odoo.
5. Choose the end boundary only after a confirmed transition followed by two
   editorial sentences. Manual skip seeks to about 250 milliseconds before the
   boundary to avoid clipping the first news word.
6. Expand to 25-50 Marketplace episodes before adding other shows. Host-read
   midrolls are explicitly later work.

The research basis for using context and sequence smoothing is
[Detecting Extraneous Content in Podcasts](https://arxiv.org/abs/2103.02585).

## Safety Gate

- A brand mention alone is never enough to skip.
- Lead-in and end candidates must be contiguous, close to an episode edge, and
  within a plausible duration cap.
- Show promos, fundraising, underwriting, and editorial brand coverage remain
  distinct labels and user policies.
- Low ASR confidence, uncertain boundaries, changed asset hashes, unavailable
  models, or model-version drift disable auto-skip.
- Speaker change is supporting evidence only; host-read ads may not change
  speaker.
- A user seek into a detected ad cancels automatic behavior. Every automatic
  action must offer an immediate, reversible "Skipped ad" affordance.
- Before any opt-in auto-skip beta, require zero harmful skips over at least 600
  diverse negative opportunities, then keep monitoring toward a harmful-skip
  target below 0.1%.

Primary metrics are harmful over-skip rate, segment precision/recall, signed
boundary error and P95, candidate coverage, analysis readiness latency,
real-time factor, memory, download size, energy, and thermal state.

## Proposed Data Contract

```text
EpisodeAssetKey: feedID, guid, enclosureURL, etag, byteCount, sha256
TranscriptSpan: id, start, end, text, asrConfidence, speakerID?
AudioEvidence: range, speech/music/silence scores, rms, spectralFlux, speakerChange
AdSegment: range, kind, calibratedProbability, evidence, boundaryConfidence
AnalysisReceipt: assetKey, pipelineVersion, ASR/model/OS versions, createdAt
```

## Explicit Non-Goals

- No launch-build model download, episode downloader, schema migration, or ad
  UI in this spike.
- No microphone permission; analysis is of an explicitly supplied local file.
- No cloud transcription or upload of episode audio/transcripts.
- No misuse of background-audio mode to keep ML work alive.
- No automatic publication or redistribution of third-party podcast assets.

Before shipping downloads or derived analysis, confirm the source permissions,
model-license attribution, Background Assets packaging, and App Review policy
for third-party media access.
