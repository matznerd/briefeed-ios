# Radio Startup Latency Contract

Date: October 2, 2026
Branch: `codex/live-radio-mvp`
Baseline: `67d3a69`

## Diagnosis

Opening autoplay previously waited for the complete enabled-source RSS batch.
The committed implementation fetched sources sequentially. The pending concurrent
refresh change shortened that to the slowest source, but retained the batch barrier.
An all-source failure cancelled opening autoplay despite playable restored audio.
The 60-second opening-intent deadline could also expire before the batch returned.

Transcript acquisition was no longer explicitly awaited by the player, but a
restored/selected episode started automatic transcript jobs before audio started.
Those downloads and text processing could compete with first-buffer loading.

## Required Invariants

- Network RSS loads overlap; Core Data changes remain on MainActor.
- Completed feed results are cumulative and ordered by source priority. The
  queue can reconcile a result before unrelated providers finish.
- During the opening freshness window, prefer the highest-priority enabled
  source (NPR by default), not whichever network request finishes first.
- After 1.5 seconds from restore projection, start an available restored/current
  item rather than waiting for the full batch. A failed batch can fall back sooner.
- If reachability is still unknown/offline after that window, retain a cancellable
  reconnect intent. The existing 60-second expiry still prevents surprise playback
  much later. No available item means waiting for a fresh candidate, not inventing one.
- Once fallback or fresh playback is loading/playing, later results update the
  queue without replacing the active episode or issuing a second play intent.
- Manual pause, source selection, Brief playback, backgrounding, and termination
  retain their existing autoplay/cancellation boundaries. Background RSS is not
  permission to begin playback.
- Automatic current/next transcript preparation starts only after the Radio
  transport reports `.playing`. Restore, selection, and `.loading` are not proof.
  Selection changes reset that permission. Explicit Retry/Prepare All remain
  user-requested actions. Batch expiry cannot bypass the automatic readiness gate.

The 1.5-second window bounds selection waiting, not guaranteed time to sound.
Cached audio is preferred without acquiring a file on the startup path. Uncached
audio still resolves redirects via a HEAD request with a 2-second request timeout,
then buffers the remote stream. Transcription is never a playback prerequisite.
Resolved URL sharing does not by itself prove identical bytes across requests;
the existing transcript-rendition validation must remain intact.

## Diagnostics

The `RadioStartup` OSLog category records `stage` and `elapsed_ms`, beginning
after the existing 300-ms active-scene settle. Stages include `opening`,
`refresh-began`, `feed-result`, `opening-fallback`, `play-intent`, `transport-load`,
`transport-playing`, and `refresh-complete`. No story text, audio URLs, or credentials
are logged. Compare play intent versus actual transport start to distinguish
selection/RSS delay from redirect/buffering delay.

## Regression Evidence

`Scripts/run-radio-startup-host-tests.sh` mechanically copies portable production
code into a temporary dependency-free macOS Swift package. It exercises the real
state machine, lifecycle driver, and transcript coordinator using synthetic data.
Its direct smoke test failed against the baseline all-source-failure path and
passes after the fallback fix. Temporary source copies are removed on exit.

The unfiltered portable run reproduced the known issue #33: 143 tests ran, 142
passed, and the contradictory hourly-Next completion expectation failed. That
existing product-contract disagreement is not changed here. Arguments pass through
to SwiftPM; the explicit focused command is:

```bash
bash Scripts/run-radio-startup-host-tests.sh \
  --skip directPauseNextCompletionInterruptionAndRouteSaveBeforeReturningIntent
```

Result: 145 tests in 9 suites passed. The known #33 test is the only explicit
exclusion; the runner does not hide it by default. Swift parsing of the changed
app/test files and `git diff --check` also pass.

New coverage includes early NPR versus a stalled batch, the lifecycle/state-machine
integration, one-shot fallback, late-result non-interruption, all-source failure,
reconnect and manual cancellation, background rejection of delayed callbacks,
transport-gated transcripts, selection reset, and explicit batch expiry.

The Core Data RSS service regression additionally verifies actual NPR progress
publication while a secondary feed remains blocked. It belongs to the iOS test
target, not the portable subset. The host harness also omits the Core Data repository
adapter, SwiftUI add-feed composition, and two UIKit/transport lifecycle tests.
It does not test AVPlayer audibility, Lock Screen commands, or a phone install.

## Remaining Release Gates

The shared host admission report blocked new simulator work because of critical
resource pressure. No simulator was booted, no device was installed, and no full
iOS build/XCTest result is claimed for this change. Existing asset-service
Sendable warnings remain outside this scope.

Before deployment, compile the complete iOS targets and run the changed RSS,
restore, lifecycle, and transcript suites. Then use issue #13's physical-device
matrix to verify cold launch, foreground refresh, a slow secondary feed, fresh NPR
priority, restored fallback, manual pause, lock/background continuity, and
transcript/audio rendition alignment. Record timing logs and the installed commit.
The remaining iOS/startup acceptance gates are tracked in GitHub issue #34.
