# Apple Speech Transcript Probe Receipt

**Date:** July 22, 2026  
**Status:** `APPLE_PROCEED` - Apple SpeechAnalyzer produced complete word-level
timing on both the rights-cleared fixture and a current podcast excerpt on the
approved physical iPhone.

## Verified Configuration

- Source commit: `927080ab2c01f10ae63a45f8e81c9be87458aa4f`.
- Device: iPhone 13 Pro, iOS 26.5.2 (`23F84`).
- Engine: `SpeechAnalyzer` with `SpeechTranscriber`, locale `en-US`.
- Attributes requested: `audioTimeRange` and `transcriptionConfidence`.
- The test process explicitly allowed `AssetInventory` to install the required
  system-managed speech asset. The asset was available by transcription time;
  the probe does not infer whether it was already installed.
- Result bundle:
  `/tmp/briefeed-transcript-device-authorized-2-20260722.xcresult`.
- Retrieved JSON:
  `/tmp/briefeed-transcript-receipt-device-20260722/transcript.json`.

Apple documents `SpeechTranscriber` as an on-device general-purpose
transcription module and requires applications to check device and locale
support. `AssetInventory` owns the model download and lifecycle; the model does
not need to be bundled in Briefeed.

## Rights-Cleared Fixture Result

The 68.232834-second mono AIFF fixture passed every acceptance gate:

| Metric | Result |
| --- | ---: |
| Processing duration | 1.524 seconds |
| Throughput | 44.76x real time |
| Timing coverage | 100% |
| Reference word error rate | 6.55% |
| Word units | 161 |
| Phrase units | 0 |
| Median words per unit | 1 |

Every timed unit was monotonic, within the audio duration, and emitted at true
word granularity. This empirically supports either a one-word RSVP projection
or a two/three-line teleprompter projection without inventing timestamps.

The cancellation case also passed on the phone. Cancellation completed in
0.501 seconds and did not exceed the test's two-second bound.

## Current Podcast Result

A second local-only probe used the opening 90 seconds of the July 22, 2026
Marketplace Morning Report episode, "Tallying the costs of Europe's heatwaves."
The excerpt was generated temporarily from the current public enclosure, added
only to the signed test bundle, and removed from the worktree after the run. No
publisher audio or transcript is committed.

| Metric | Result |
| --- | ---: |
| Processing duration | 2.233 seconds |
| Throughput | 40.30x real time |
| Timing coverage | 100% |
| Word units | 217 |
| Phrase units | 0 |
| Median words per unit | 1 |

Result bundle:
`/tmp/briefeed-transcript-marketplace-device-20260722.xcresult`.

Retrieved JSON:
`/tmp/briefeed-transcript-receipt-marketplace-20260722/transcript.json`.

The transcript captured two dynamically inserted sponsor reads followed by the
program introduction. The final sponsor word ended at 58.62 seconds and the
first program word began at 59.40 seconds. This is useful boundary evidence,
but it is not an ad-classification or auto-skip implementation.

## Third-Party Comparison Boundary

Briefeed already pins
[FluidAudio 0.14.5](https://github.com/FluidInference/FluidAudio). That package
contains Parakeet ASR APIs and exposes token start/end timing, but Briefeed
currently initializes only its PocketTTS path. FluidAudio is therefore a
credible future iOS 18-25 fallback, not a dependency that needs to be added for
the first viewer.

[Argmax's Swift SDK](https://github.com/argmaxinc/argmax-oss-swift) also exposes
WhisperKit word timestamps. It would add another model/runtime surface and is
not justified while the native path already provides complete word timing at
about 40x real time on the target phone.

Do not upgrade or initialize either fallback in the production viewer slice.
First isolate the existing PocketTTS launch exception tracked in GitHub #22;
then evaluate one fallback only if supporting iOS 18-25 becomes a launch
requirement.

## Verdict

`APPLE_PROCEED` for the iOS 26 production transcript and synchronized-reader
slice.

- Use Apple SpeechAnalyzer first. A Parakeet or WhisperKit comparison is no
  longer required to establish word timing on the approved iPhone.
- Keep Briefeed's iOS 18.2 deployment floor. On iOS 18 through 25, the
  transcript viewer should report that on-device transcription is unavailable
  until a separately tested fallback is approved.
- Drive word selection from episode media time, not wall-clock timers or
  playback-rate multiplication. The existing `TimedTranscriptIndex` already
  provides that contract.
- Write the production coordinator and UI plan before adding episode downloads,
  persistence, or Radio playback integration.
- Treat ad classification and manual/automatic skipping as a separate staged
  feature with false-positive controls.

The prior `INCONCLUSIVE` result was caused only by the safe simulator runner's
critical-pressure refusal. It is superseded by these physical-device results.

## Primary References

- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)
- [WWDC25: Bring advanced speech-to-text to your app with SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)
