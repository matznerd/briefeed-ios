# Radio Transcript Viewer Verification Receipt

**Date:** 2026-07-23
**Branch:** `codex/live-radio-mvp`
**Tracking:** GitHub issues #23 and #24

## Implemented

- Persisted, fingerprint-keyed timed transcripts and resumable Prepare All
  manifests.
- Serial Apple SpeechAnalyzer preparation with automatic current-plus-two
  scheduling and explicit visible-latest Prepare All scheduling.
- Durable per-episode checkpoints, startup reconciliation, terminal failure
  accounting, cancellation generation guards, and background-task restoration.
- Compact synchronized transcript band plus expanded reader with audio-clock
  following, manual-scroll suspension, Resume Live, line seeking, and existing
  transport controls.
- Exact prepared-local playback validation, stale-result rejection, and
  fail-closed remote playback validation.
- Debug transcript fixture and accessibility identifiers for deterministic
  simulator UI verification.

## Automated Verification

| Gate | Result | Evidence |
| --- | --- | --- |
| Generic simulator compile | PASS | `make radio-compile` ended with `** TEST BUILD SUCCEEDED **` |
| Focused Radio unit tests | PENDING | Managed simulator lane refused work while host pressure was critical |
| Full Radio unit suite | PENDING | Run after focused suite |
| Transcript UI tests | PENDING | Run after unit suite |
| Radio smoke and lifecycle | PENDING | Run after UI suite |

The compile gate includes the Briefeed app, unit-test target, and UI-test target.
Existing Swift concurrency warnings in legacy audio/Core Data paths remain; the
new transcript files compile without a blocking diagnostic.

## Exact-Asset Boundary

The current SwiftAudioEx 1.0.0 adapter does not expose final response identity
from the bytes it is actively playing. The viewer therefore does not use a
separate preparation download as proof of the active stream:

- prepared-ahead and replay playback use the exact fingerprinted local asset
  and may display synchronized text;
- uncached remote first-play audio starts immediately, but synchronized text
  stays hidden until the player can prove matching response identity; the
  prepared transcript becomes available on the next exact local playback;
- GitHub issue #24 tracks a transport-owned identity or single-fetch solution.

This is intentional fail-closed behavior for publishers that dynamically insert
different audio into separate requests.

## Physical-Device Gate

Do not treat simulator success as proof of Apple SpeechAnalyzer or continued
background processing. Before distribution, test a supported iOS 26 device:

1. Launch Radio with autoplay enabled and confirm audio starts without waiting
   for transcription.
2. Confirm the compact transcript appears for exact prepared-local playback,
   follows at 1x and 2x, and survives seek, pause, foreground/background, and
   relaunch.
3. Open the expanded reader; verify line tap seeking, manual-scroll suspension,
   Resume Live, Dynamic Type, VoiceOver, and right-thumb transport controls.
4. Trigger Prepare All, background the app, interrupt the task, relaunch, and
   confirm only unfinished work resumes without losing completed artifacts.
5. Exercise thermal, Low Power Mode, offline, failed-source, low-storage, and
   empty-eligible-queue states.
