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
- Shared Radio freshness filtering for automatic and Prepare All work, with
  immutable batch restoration serialized ahead of user-started preparation.
- Deferred refresh reconciliation that preserves newly visible episodes across
  batch start, stop, resume, expiration, and terminal completion.
- Compact synchronized transcript band plus expanded reader with audio-clock
  following, manual-scroll suspension, Resume Live, line seeking, and existing
  transport controls.
- Exact prepared-local playback validation, stale-result rejection, and
  fail-closed remote playback validation.
- Duration-gated promotion from an active remote stream to exact prepared audio
  at the current media time, with original-stream restoration if local loading
  fails.
- Debug transcript fixture and accessibility identifiers for deterministic
  simulator UI verification.

## Automated Verification

| Gate | Result | Evidence |
| --- | --- | --- |
| Earlier generic simulator compile | PASS | `make radio-compile` ended with `** TEST BUILD SUCCEEDED **` before the final freshness and restore-race hardening |
| Current-head Swift parse and diff checks | PASS | `swiftc -frontend -parse` passed for every changed Swift file; `git diff --check` is clean at `6a3e6f6` |
| Current-head generic simulator compile | PASS | `xcodebuild build-for-testing` completed for arm64 iOS Simulator after the exact-audio promotion change |
| Focused Radio unit tests | PENDING | Managed simulator lane refused work while host pressure was critical |
| Full Radio unit suite | PENDING | Run after focused suite |
| Transcript UI tests | PENDING | Run after unit suite |
| Radio smoke and lifecycle | PENDING | Run after UI suite |

The current compile gate included the Briefeed app, unit-test target, and
UI-test target. Existing Swift concurrency warnings in legacy audio/Core Data
paths remain. Runtime claims intentionally remain open until the managed lane
accepts work.

The latest managed-fleet check reported `PRESSURE=critical` because swap
headroom was below 1 GB even after scheduler load fell. The pressure gate was
not bypassed and no unowned simulator was targeted.

## Exact-Asset Boundary

The current SwiftAudioEx 1.0.0 adapter does not expose final response identity
from the bytes it is actively playing. The viewer therefore does not use a
separate preparation download as proof of the active stream:

- prepared-ahead and replay playback use the exact fingerprinted local asset
  and may display synchronized text;
- uncached remote first-play audio starts immediately; when preparation
  finishes, the player may switch to the exact prepared local bytes at the
  current media time after duration validation, then expose synchronized text;
- a duration mismatch or failed promotion keeps synchronized text hidden, and
  failed local loading restores the original stream at the same media time;
- GitHub issue #24 tracks a transport-owned identity or single-fetch solution.

This keeps dynamic-ad mismatches fail-closed while allowing first-play text on
the exact prepared bytes. Audible continuity still requires physical-device
verification.

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
