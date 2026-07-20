# Task 6 Receipt

## Implementation

- Added the injected `ConnectivityMonitoring` protocol and `RadioNetworkMonitor`; path callbacks are delivered onto the main actor and the monitor is canceled with its owner.
- Added `RadioServiceContainer` as the only Radio composition root. It owns one monitor and passes that exact instance into its coordinator; the DEBUG override is guarded against post-resolution installation.
- Extended the coordinator with semantic playback, progress, failure, retry, sleep, interruption, and route-removal commands. Progress writes are bucketed at five seconds while user/system transition points force a snapshot save.
- Completion writes Core Data first, retains the queue on a completion failure, and leaves the stale-snapshot repair boundary intentionally recoverable through the existing Core Data-authoritative queue restore.
- Manual Next defers partial entries, treats 95 percent progress as completion, clears end-of-episode sleep, and selects pending before deferred entries. Online failures are capped at two per entry; offline failures consume no attempt.

## Tests

- Added focused state tests for progress bucketing, forced pause persistence, Next deferral, completion persistence failure, two online failures, and explicit retry reset.
- Added sleep tests for exact deadline one-shot pause and end-of-episode cancellation by manual Next.
- Added a direct-construction container test proving the coordinator observes the container's exact fake monitor. It does not resolve the static container or install a process override.

## Verification

- `make radio-compile` passed: `TEST BUILD SUCCEEDED`.
- `make sim-status` reported `PRESSURE=warn`, safe capacity, but `Simulator.app=open`.
- `bash skills/app-testing/scripts/run-radio.sh radio-state unit` stopped at its safety preflight because `Simulator.app` was open. No simulator was claimed, booted, reused, stopped, erased, or otherwise touched.
- `git diff --check` passed.

## Interruption Eligibility Correction

- Corrected the final interruption-begin branch so a failed force-save clears `interruptionResumeEligible` at the interruption boundary itself. Interruption end therefore cannot resume transport or overwrite the persistence failure.
- The focused regression starts from active playback, injects the interruption-begin snapshot failure, requires `.pause`, and proves `shouldResume: true` remains a no-op with the persistence error intact.

## Final Review Blockers

- Completion recovery now records whether Core Data still needs `markCompleted` or whether only the repaired session snapshot remains. Retry reattempts the exact failed stage: a pre-Core-Data failure retains the current key, entry, and exact position; a post-Core-Data failure keeps the completed row removed in memory and only re-saves the authoritative snapshot before continuing.
- `selectEpisode(_:)` applies the 95-percent-on-leave rule from the current entry's live seconds and known duration. It force-saves the exact position, completes Core Data, removes the completed entry, and then persists/selects the requested episode; a failed completion remains recoverable through Retry without deferring the nearly finished row.
- Progress sanitizes non-finite seconds before bucket conversion. User pause still emits `.pause` when persistence fails, and interruption resume eligibility is revoked when the interruption-begin force-save fails.
- Added same-session failed-entry partition and selection tests, completion Retry tests for both persistence stages, reconstructed crash-window restores, natural completion cursor/order, direct force-save ordering, reconnect retry-budget preservation, cold-launch failure reset, deadline/Next behavior, and concrete autoplay-cancellation coverage for pause, seek, Next, Retry, sleep, and selection.

## Final Review Verification

- `make radio-compile` passed after the final review repairs: `TEST BUILD SUCCEEDED`.
- The isolated `radio-state` lane again exited at fleet preflight because host pressure remained critical (`load=128`, `Simulator.app=open`); no override or foreign simulator was used.
- `git diff --check` passed.

## Review Repair

- Remote playback is now held while connectivity is unknown or offline (except readable local files). The coordinator records the pending request and publishes its replay intent when the injected monitor becomes online.
- Playback callbacks now have identity-bearing coordinator commands so stale transport events are rejected. Background and termination force-save commands were added.
- Next and completion stage their new cursor and write Core Data progress/completion before forcing the snapshot; End of Episode persists its paused next cursor before publishing it.
- A failed-only queue preserves its failed current for explicit Retry. Retry resets and force-saves before any replay. Refresh reset scope is limited to successful source results.
- Deadline timers survive Next, and still pause transport when persistence fails. Interruption resume eligibility is captured before the interruption rather than inferred from the post-pause state.

## Final Hardening

- Replaced the unscoped pending-network Boolean with identity-, purpose-, and generation-bound requests plus an injectable 500 ms retry scheduler. Reconnect and automatic retry emissions revalidate the current key, playback eligibility, connectivity, generation, and cold-launch deadline; pause, background, termination, autoplay cancellation, and current changes invalidate delayed work.
- Restore and initial-refresh autoplay now require either a readable local file or online connectivity. Offline and unknown callbacks consume no playback attempt, force-save their exact keyed position, and wait for a delayed reconnect emission.
- Successful source refreshes reset only matching playback failures before reconciliation, allowing failed-only queues to be selected again and recomputing Next eligibility. Failed refreshes preserve the existing budget.
- Completion now makes a successful Core Data row authoritative in memory before the snapshot write. Snapshot failure cannot replay the completed entry, and Core Data progress writes refuse to lower a completed row. Manual Next at or above 95 percent first persists the exact supplied position so a completion failure remains resumable.
- Deadline, interruption, route, end-of-episode, second-failure advancement, and Next transitions now preserve their required pause/error/cursor/save-order semantics. Unkeyed low-level progress, completion, and failure commands were removed from the public coordinator protocol.
- Added regression coverage for real five-second progress boundaries, all force-save families, both completion crash windows with Core Data, stale identities, automatic retry count and cancellation, local/remote network gates, delayed reconnect expiry, failure-reset scope, all-failed Retry, deadline one-shot behavior, EOE paused cursors, repository completion guards, and monitor start/cancel ownership.

## Final Verification

- Strict RED was observed after adding the scheduler/keyed-callback regressions: `make radio-compile` failed on the missing `RadioRetryScheduling` contract and initializer injection.
- Final `make radio-compile` passed with `TEST BUILD SUCCEEDED`.
- `bash skills/app-testing/scripts/run-radio.sh radio-state unit` exited at the fleet safety preflight because host pressure was critical (`load=136`, `Simulator.app=open`). No capacity override or unowned simulator was used.
- `git diff --check` passed.
