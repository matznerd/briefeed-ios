# Task 4 Receipt

## RED

- Added the Radio queue-builder and Core Data repository test suites before production symbols existed.
- `make radio-compile` failed as expected because `RadioEpisodeCandidate` and `RadioQueueBuilder` were undefined in `RadioQueueBuilderTests.swift`.

## GREEN

- Added `RadioEpisodeCandidate`, a main-actor repository protocol, and a Core Data implementation that fetches exact `(feedId, id)` rows, preserves the original playback URL, canonicalizes enclosure URLs, normalizes only finite positive-duration progress, and saves all completion fields together.
- Completion save failure rolls the context back, leaving the episode incomplete. This is the repository-side safety condition Task 6 needs before it removes a session entry.
- Added a time-injected pure queue builder. Initial builds use feed priority, feed ID, publication date, then episode ID; select one newest candidate per source; obey 2-hour/24-hour freshness; do not backfill an older item after a completed newest item; and de-duplicate keys and canonical enclosure URLs.
- Restore applies 24-hour/7-day retention, repairs positions, preserves valid restored current/order, normalizes cold-launch playing and failed entries, and drops invalid, completed, duplicate, or expired rows.
- Reconciliation pins current, sorts pending only, preserves deferred and failed relative order, appends new entries after current, and makes failed entries ineligible to `nextEligible`.

## Verification

- `make radio-compile` passed (`TEST BUILD SUCCEEDED`) after implementation.
- `git diff --check` passed.
- Read `skills/app-testing/SKILL.md`, the shared `/Users/me/ericode/skills/app-testing/SKILL.md`, and ran `make sim-status` before considering hosted tests. The fleet reported `PRESSURE=critical` and load `153`; per the no-override rule, `bash skills/app-testing/scripts/run-radio.sh radio-builder unit` was deferred rather than risking a simulator boot. This is runtime deferral, not a test pass.

## Review Fixes

### RED

- Added regressions for exact freshness and retention boundaries, equal-date episode-ID ordering, restored queue append behavior, failed-current repair, live playing preservation, stable deferred/failed partitions, composite-key candidate lookup, original playback URL retention, invalid duration progress, and preserving unrelated Core Data dirty state after a failed completion save.
- The hosted `radio-builder` unit lane was attempted after the gate improved to `PRESSURE=warn`, but its preflight stopped after reporting that Simulator.app is open. No simulator was booted, reused, shut down, erased, or otherwise touched; that open window belongs to another stream and was not hidden.

### GREEN

- Cold restore now appends only newly eligible source-balanced candidates after retained snapshot entries, while live reconciliation remains partition-aware.
- Cold restore alone normalizes `playing`; reconciliation preserves an active current `.playing` entry.
- Invalid or failed current keys repair to pending first, then deferred, and never select failed entries.
- Completion save failure restores only `isListened`, `listenedDate`, and `lastPosition`; unrelated unsaved context mutations remain untouched.
- `make radio-compile` passed after the fixes.
