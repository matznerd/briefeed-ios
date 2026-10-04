# Radio Foreground Playback Continuity

Issue: #36. Baseline: deployed PR #35 merge
`ebd9c324a27bb159156729e48271575195e7bd66`.
Implementation branch: `codex/foreground-playback-continuity`.

## Diagnosis

The user reported an audible position jump when returning to Briefeed while
an episode continued playing in background. Sometimes the user suspected an
episode change; that specific physical occurrence is not yet captured.

The scene's direct foreground handler only restarts presentation polling.
However, foreground also resumes transcript reconciliation. Its presentation
publisher calls `AudioPlayerViewModelV2.validateTranscriptPlayback`, which calls
`UnifiedAudioPlayer.validateActiveRadioTranscript`.

Previously, validation could replace the active remote transport with a
separately downloaded prepared file at the current timestamp, guarded only by
a duration tolerance. Equal duration does not establish equal inserted ads or
equal content at that timestamp. Replacement also created a new playback ID
and could reload the original URL again if the prepared load failed.

A separate same-episode play path reapplied `request.positionSeconds` before
resume. The request may contain an older background snapshot, not the position
of the transport that kept playing.

## Corrected Contract

- Transcript validation only updates presentation synchronization state. It
  never reloads, seeks, resumes, completes, or advances audio.
- Same-item start/resume keeps the existing transport and its live position.
  A redundant start on an already-playing item reconciles coordinator state
  without touching the transport.
- The initial restore seek remains pending until item readiness and is consumed
  once. Explicit user seek commands are unchanged.
- New transport loads still prefer cached fingerprinted assets; preparation,
  lookahead, original audio, ad records, and queues remain intact.
- Unverified remote transcripts stay hidden. Prepared-ahead playback can still
  show synchronized text. First-play stream capture/identity is issue #24; do
  not regain transcript visibility by changing the audio underneath the user.

The transcript design and implementation plan now explicitly supersede the
earlier duration-gated promotion behavior.

## Verification

Tests use in-memory repositories, synthetic asset metadata, and spy transports.
No live feed, paid model, real ASR, or phone installation was used for these
regressions. The owned test simulator runs iOS 18.6 with hosted XCTest startup
disabled; no other task's simulator was adopted.

- RED: the two new regressions fail against a frozen copy of the deployed merge.
  The 20-test transcript suite reports six failed expectations in those two
  tests: active reload/seek and rewind from 35 seconds to the saved 10 seconds.
  An earlier zero-test selector run is not counted as evidence.
- GREEN: 72 tests in five suites pass: Radio transcript playback, Unified Radio
  playback, app lifecycle, transcript presentation, and completion routing.
- Covered: partial/final transcript arrival after background progress,
  stale same-item intents, paused resume retaining a newer transport position,
  readable but unplayable prepared files, fresh-feed foreground refresh, initial
  pending restore seek, exact identity checks, and stale terminal callbacks.
- Full portable suite: 166 of 167 tests pass. The sole failure is the existing
  #33 expectation in
  `directPauseNextCompletionInterruptionAndRouteSaveBeforeReturningIntent`;
  this patch does not change the coordinator's hourly-next policy. The broad
  suite is not reported as green and no test was skipped for this run.

Local simulator result: `/tmp/briefeed-foreground-broader-1791146947.xcresult`.
Physical iPhone return/lock, audible continuity, and Now Playing checks remain
release gates. This receipt does not claim the fix is merged or installed.
