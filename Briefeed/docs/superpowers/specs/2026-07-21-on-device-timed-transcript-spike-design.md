# On-Device Timed Transcript Spike Design

**Date:** 2026-07-21  
**Status:** Approved direction; written-spec review pending  
**Related work:** GitHub issue #10 and `docs/research/2026-07-20-podcast-ad-skip-spike.md`

## Objective

Prove that Briefeed can transcribe a prerecorded podcast episode entirely on
device and synchronize readable transcript phrases to the existing Radio
playback clock at playback rates from 0.5x through 3x.

This spike answers one question before production integration: does Apple's
SpeechAnalyzer produce timing granularity, accuracy, latency, and resource use
that are good enough for a compact two-line teleprompter during Radio playback?

The spike does not detect ads. Its persisted timed transcript becomes an input
to that separate investigation only after this synchronization work passes.

## Product Behavior Under Evaluation

The proposed Radio transcript is not a traditional one-word RSVP display.
While the expanded player is open, it presents a compact two-line window:

- the current two-to-four-word phrase is bright;
- the immediately preceding phrase remains readable at lower contrast;
- the upcoming phrase is visible at lower emphasis;
- phrase changes use a restrained crossfade or step, not continuous scrolling;
- transcript display is optional and does not replace transport controls.

At high playback rates, Briefeed continues to highlight by media position. It
does not accelerate an independent wall-clock animation. This keeps seeking,
pausing, interruptions, and resuming aligned to the episode.

## Current Foundations

- `UnifiedAudioPlayer.currentTime` already exposes the active media position.
- `SwiftAudioExService` samples playback position every 100 milliseconds.
- Radio already persists episode identity and playback position.
- FluidAudio `0.14.5` is linked for PocketTTS but Briefeed has no speech-to-text
  implementation.
- Radio normally plays a remote enclosure URL. The current transport does not
  expose decoded PCM to the app, so transcription requires a local audio asset
  or a separately staged cache of the same enclosure bytes.
- The app deployment target is iOS 18.2. SpeechAnalyzer is available on iOS 26.

## Approaches

### Option A: Apple SpeechAnalyzer First, Availability-Gated - Recommended

Use SpeechAnalyzer and SpeechTranscriber on iOS 26 with audio time-range
attributes enabled. Keep the application's iOS 18.2 deployment target and gate
the probe with `if #available(iOS 26, *)` plus runtime locale and asset checks.

Advantages:

- Apple manages the speech model outside Briefeed's binary and process memory.
- The API accepts prerecorded audio files and uses the audio sample timeline.
- Apple's own playback example highlights transcript words from audio ranges.
- It avoids loading another large model beside the existing PocketTTS stack.

Limitations:

- It is unavailable before iOS 26 and may have device or locale restrictions.
- Audio time ranges may cover a word or a short phrase. The probe must measure
  the returned granularity rather than inventing timestamps within a range.
- It does not expose phoneme boundaries. Phoneme-level animation would require
  a separate forced-alignment system and is not needed for this experience.

### Option B: FluidAudio Parakeet as the Primary Engine

Upgrade FluidAudio from `0.14.5` to `0.15.5` and use its newer unified Parakeet
ASR path with word-level timestamps.

Advantages:

- Runs through Core ML on iOS 17 and later.
- Provides an app-controlled model and timing representation.
- Can later contribute VAD and diarization evidence to ad-boundary research.

Limitations:

- `0.15.5` includes breaking download-stack changes, and the same package also
  backs production PocketTTS. An upgrade could destabilize existing TTS.
- The ASR model adds a substantial download, memory, and thermal burden.
- Device throughput while audio is playing is not yet measured.

### Option C: Ship Apple and FluidAudio Engines Together

Implement a runtime selector that prefers Apple and falls back to Parakeet.

This offers the broadest availability, but it doubles model lifecycle, error,
storage, and verification work before either path is proven. The first spike
will define an engine-neutral output contract without implementing this
fallback.

## Decision

Implement Option A for the first spike. Do not raise the global deployment
target and do not upgrade FluidAudio in the same change. Preserve a narrow
`TimedTranscriptEngine` boundary so a separately reviewed Parakeet comparison
can be added if Apple fails the acceptance gates or broader OS support becomes
a launch requirement.

## Architecture

### Timed Transcript Contract

The normalized output uses timed units rather than assuming every engine emits
one timing range per lexical word:

```swift
struct TimedTranscriptUnit: Codable, Equatable, Sendable {
    let text: String
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let confidence: Double?
    let granularity: Granularity

    enum Granularity: String, Codable, Sendable {
        case word
        case phrase
    }
}

struct TimedTranscript: Codable, Equatable, Sendable {
    let assetFingerprint: String
    let engineIdentifier: String
    let engineVersion: String
    let localeIdentifier: String
    let audioDurationSeconds: TimeInterval
    let processingDurationSeconds: TimeInterval
    let units: [TimedTranscriptUnit]
}
```

An Apple attributed-string run with one lexical word becomes a `.word` unit.
A run containing multiple words remains one `.phrase` unit. The normalizer must
not distribute a phrase's duration evenly across words because that would
fabricate precision.

### Probe Boundary

Add a DEBUG-only `PodcastTranscriptionProbe` that:

1. accepts an explicitly supplied, rights-cleared local audio fixture;
2. computes a SHA-256 fingerprint of the actual audio bytes;
3. checks SpeechTranscriber availability, locale support, and model assets;
4. transcribes the file with audio time ranges and confidence requested;
5. normalizes final results into `TimedTranscriptUnit` values;
6. writes a JSON receipt to a temporary diagnostics directory;
7. never mutates RSS episodes, Radio state, Core Data, or production settings.

The probe must not silently download a speech asset during automated tests.
Model installation is an explicit interactive diagnostic step.

### Synchronization

`TimedTranscriptIndex` is a pure value type that binary-searches units by media
position. Its input is `UnifiedAudioPlayer.currentTime`, not elapsed wall time.

- Playback-rate changes require no timestamp scaling.
- A seek performs a new lookup and immediately changes the active phrase.
- Pausing freezes the active phrase.
- A position in a timing gap retains the prior unit until the next begins.
- A position before or after all ranges returns no active unit.

The existing 100-millisecond transport sample is enough for phrase-level
updates. The production UI must consume a presentation-only projection so it
does not reintroduce the prior whole-app 10 Hz SwiftUI invalidation problem.

### Future Production Audio Flow

Production integration is deliberately deferred until the probe passes. The
intended flow is:

1. start playback from the enclosure immediately;
2. stage the same enclosure bytes into an interruptible local cache;
3. fingerprint the cached asset because dynamic ad insertion can change bytes
   while retaining the same feed GUID or URL;
4. transcribe the first useful portion at high priority, then work ahead of the
   playhead;
5. reuse a transcript only when episode identity, audio fingerprint, locale,
   and engine version all match.

The app must never record speaker output through the microphone to obtain the
transcript.

## Failure Behavior

- Unsupported OS, hardware, or locale: report `unsupported`; playback is
  unchanged.
- Missing speech asset: report `assetRequired`; no silent test download.
- Corrupt or unsupported audio: report a typed diagnostic failure.
- Cancellation, interruption, or memory pressure: cancel analysis and retain
  any finalized diagnostic receipt; playback remains authoritative.
- Empty or non-monotonic results: fail the probe rather than showing an
  apparently synchronized transcript.

No transcription failure may stop, pause, seek, or advance Radio playback.

## Test Strategy

### Deterministic Unit Tests

- normalize one-word and multiword attributed runs without fabricated timing;
- reject negative, reversed, overlapping, and out-of-duration ranges;
- binary-search exact starts, interiors, gaps, and exact ends;
- prove the same media position selects the same unit at 0.5x, 1x, 2x, and 3x;
- prove pause and arbitrary seek projections;
- encode and decode the JSON receipt without losing timing precision.

### Integration Fixture

Use a generated or otherwise rights-cleared 60-to-180-second spoken-news
fixture with a known script. The receipt must contain nonempty finalized text,
monotonic in-bounds ranges, timing coverage, processing duration, locale,
engine identity, OS version, and asset fingerprint.

### Simulator and Device

The iOS 26 simulator proves availability handling, model-asset flow where
supported, receipt generation, and UI projection. A later explicitly approved
physical-device run measures:

- time to first finalized timed text;
- total real-time factor;
- peak memory and thermal state while playback continues;
- visible alignment at 1x, 2x, and 3x;
- alignment after forward/back ten seconds and arbitrary scrubbing;
- behavior during pause, background, interruption, and cancellation.

No phone installation is part of the initial implementation.

## Acceptance Gates

The Apple path is suitable for the production transcript slice only when:

- every emitted range is finite, monotonic, and within the audio duration;
- at least 95 percent of recognized non-whitespace text is covered by timing
  ranges;
- the median timed unit is no larger than four words;
- visible phrase selection follows seeking without stale intermediate state;
- human review of the known fixture finds no sustained alignment drift at 2x;
- analysis does not interrupt or materially degrade audio playback;
- cancellation releases analysis resources cleanly.

If Apple fails timing granularity, accuracy, device support, or resource gates,
the next isolated spike upgrades FluidAudio and compares Parakeet word timing
against the same fixture and receipt contract.

## Explicit Non-Goals

- Production feed downloading or transcript persistence.
- Core Data migration.
- Ad classification, Skip Ad, or automatic skipping.
- Speaker diarization, VAD, or phoneme-level forced alignment.
- Cloud transcription or transcript upload.
- A FluidAudio package upgrade.
- Raising Briefeed's global minimum deployment target.
