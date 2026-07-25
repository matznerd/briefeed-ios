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
- A finite playback-sync state that distinguishes ordinary catch-up from a
  confirmed audio-version mismatch instead of leaving the viewer on an
  indefinite "Syncing transcript" message.
- Single-download first playback: the player and transcript pipeline now
  coalesce on one fingerprinted local audio asset, preventing dynamic publisher
  responses from giving them different bytes.
- Debug transcript fixture and accessibility identifiers for deterministic
  simulator UI verification.

## Automated Verification

| Gate | Result | Evidence |
| --- | --- | --- |
| Earlier generic simulator compile | PASS | `make radio-compile` ended with `** TEST BUILD SUCCEEDED **` before the final freshness and restore-race hardening |
| Current-head diff check | PASS | `git diff --check` is clean after the same-session sync copy and fixture correction |
| Earlier exact-promotion generic compile | PASS | `xcodebuild build-for-testing` completed for arm64 iOS Simulator after the exact-audio promotion change |
| Physical-device test bundle build | PASS | Xcode built and signed the app and focused test bundle for Eric's iPhone 13 Pro |
| Focused transcript playback and presentation tests | PASS | Both suites executed on Eric's iPhone 13 Pro with zero failures after correcting cross-source transition fixtures |
| Current transcript playback and presentation suites | PASS | 23 tests passed on an iOS 26.5 simulator, including the 326.0s played / 304.196s prepared duration-mismatch regression |
| Physical-device app build and install | PASS | Debug app built, signed, installed, and launched on Eric's iPhone 13 Pro |
| Full app unit suite | BLOCKED (pre-existing) | The managed-fleet run reached unrelated Core Data duplicate-entity crashes and known intentional InfiniteScroll failures; GitHub issue #9 tracks the Core Data test-host defect |
| Transcript UI tests | PARTIAL | Compact live-text behavior passed on the physical phone; expanded-reader gestures, accessibility, and lifecycle behavior remain in the distribution gate |
| Same-session audio-to-transcript handoff | PASS | On Eric's iPhone 13 Pro, ABC first-play preparation advanced from queued to synchronized live text at the current media time and continued following at 1.5x and 2x |
| Dynamic-audio mismatch presentation | PASS | On Eric's iPhone 13 Pro, NPR advanced from queued to the finite mismatch message in about 15 seconds rather than remaining on an indefinite sync state |
| Single-download playback regression | PASS | 24 focused exact-playback and asset-service tests passed on Eric's iPhone 13 Pro, including one-download coalescing, local first playback, remote fallback, and unchanged immediate playback when transcription is unavailable |
| Current-head generic simulator compile | PASS | `make radio-compile` completed with `** TEST BUILD SUCCEEDED **` after the single-download change |
| Current-head signed physical app | PARTIAL | The app built, passed strict code-sign verification, and installed over the existing iPhone app without clearing data; launch/runtime verification is waiting for the locked phone and iPhone Mirroring session |
| Broader transcript suites on physical device | PARTIAL (pre-existing harness failures) | 68 tests executed; the exact playback, asset, presentation, models, and background-task suites passed, while store/coordinator fixtures reported `invalidRelativePath` and pipeline timing failures unrelated to the three changed files |
| Radio smoke and lifecycle | PASS | `RadioUITests.testHeadlessRadioSmoke` passed on the managed simulator, including playlist, transport, Next, terminate/relaunch, and current-title restoration; receipt: `/tmp/briefeed-radio-radio-smoke-derived-data/RadioSmokeEvidence/20260725T213013Z/receipt.txt` |

The compile gate included the Briefeed app, unit-test target, and UI-test
target. Existing Swift concurrency warnings in legacy audio/Core Data paths
remain. The focused suites execute on the physical phone, and the installed
build has now been exercised through iPhone Mirroring for both synchronized
first-play text and the dynamic-audio mismatch path.

The latest managed-fleet check reported `PRESSURE=critical` because swap
headroom was below 1 GB even after scheduler load fell. The pressure gate was
not bypassed and no unowned simulator was targeted. Physical-device execution
was used for the focused suites instead.

## Exact-Asset Boundary

The current SwiftAudioEx 1.0.0 adapter does not expose final response identity
from the bytes it is actively playing. First playback therefore owns the audio
before handing it to the transport:

- playback and transcript preparation make concurrent requests to one asset
  service, which coalesces them into one download;
- playback begins from that fingerprinted local file as soon as download
  acquisition completes, without waiting for transcription;
- prepared-ahead and replay playback use the cached exact asset;
- if acquisition fails, playback falls back to the publisher URL and transcript
  validation remains fail-closed;
- a duration mismatch or failed promotion keeps synchronized text hidden, and
  failed local loading restores the original stream at the same media time;
- GitHub issue #24 tracks progressive play-while-capturing if physical-device
  measurement shows the download-only startup delay is unacceptable.

This removes the NPR two-request mismatch for newly acquired audio because
playback and SpeechAnalyzer now consume the same bytes. The previous fail-closed
validation remains for remote fallback and old active streams.

### NPR dynamic-audio evidence

On July 25, 2026, the active NPR News Now play remained on "Syncing
transcript." The saved physical-device artifacts showed that transcription had
already completed:

- played stream duration inferred from the player: approximately 326 seconds;
- downloaded/transcribed asset duration: 304.195918 seconds;
- on-device transcription processing time: 6.527490 seconds;
- timed units: 817;
- asset fingerprint:
  `0ce3a74d2175c9adb705b5da9cda36377d7f7ff4427640669f17827a7623c2b3`.

The approximately 21.8-second difference is consistent with a dynamically
inserted preroll in the played response. The transcript begins with NPR
editorial audio and therefore must not be aligned to that longer stream. The
player now reports that the transcript does not match the current audio rather
than promising that synchronization is still in progress.

### July 25 physical-phone result

The pushed `479a5cd` build was signed, installed over the existing app without
clearing listening history, and exercised on Eric's iPhone 13 Pro through
iPhone Mirroring:

- NPR's playback clock advanced immediately, queued transcript work, and changed to
  "Transcript doesn't match this audio" in about 15 seconds after validation;
- ABC's playback clock advanced immediately, completed on-device preparation, switched to
  "Live transcript" at the current playback position, and visibly followed the
  spoken words at both 1.5x and 2x;
- the player was paused after verification without completing or resetting the
  episode;
- no mismatched text was exposed and no app crash occurred.

This verifies the two user-visible first-play outcomes. It does not close the
transport-identity limitation tracked by GitHub issue #24.

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
