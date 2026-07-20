# Task 10 Implementation Report

Status: DONE_WITH_CONCERNS

## Implemented

- Added `AppTab.radio`, `.brief`, and `.feed`, with Radio selected at launch.
- Replaced the visible native tab bar with one compact icon-only custom rail in a bottom safe-area inset.
- Kept 44 by 44 point tab and Settings hit targets, labels, identifiers, and selected traits.
- Added iOS 26 Liquid Glass for the grouped rail and Settings control, an iOS 18.2 material fallback, and an opaque Reduce Transparency path.
- Moved Settings out of bottom navigation into a full-height sheet available from each primary root.
- Added a state-driven Radio home for current metadata, source enablement/reordering, refresh, retry, offline, no-source, failure, degraded-source, and true exhausted states.
- Added Radio autoplay and canonical playback-speed controls at the top of Settings' Audio section.
- Added Task 10 XCUITests for default navigation, hidden native chrome, 44-point controls, selected traits, and Settings presentation/dismissal.

## TDD Evidence

RED was attempted before production changes:

```text
bash Briefeed/skills/app-testing/scripts/run-radio.sh radio-nav ui
PRESSURE=critical swap_free=1018MB reclaimable=16276MB load=18
SIMULATOR_APP=open
TASK10_RED_EXIT=1
```

The shared fleet safety preflight refused the simulator lane before XCTest could execute. No pressure override, foreign simulator, GUI action, or CoreSimulator recovery was attempted.

GREEN compile evidence:

```text
make radio-compile
** TEST BUILD SUCCEEDED **
```

The build-for-testing compiled the app, unit-test bundle, and `RadioUITests.swift` on both simulator architectures.

Static verification:

```text
git diff --check
Task-scoped gates for Radio default, safeAreaInset, hidden tab bar,
no fixed 49-point padding, three AppTab cases, 44-point rail controls,
glass/fallback/Reduce Transparency, state surfaces, and Settings ID
TASK10_STATIC_GATES=PASS
```

## Concern / Deferred Runtime Proof

The UI tests and requested screenshot matrix could not run because the shared simulator host was at critical pressure and `Simulator.app` was open. The `partial` fixture content used by the XCUITests is also intentionally supplied by Task 12, not Task 10. Runtime navigation, visual overlap, Dark Mode, Reduce Transparency, and large-type evidence remain required after Task 12 and a safe fleet preflight.

## Review Repair

- Source enablement and priority changes now reconcile the persisted Radio session immediately from the local Core Data candidate repository. Reconciliation preserves the active episode only while it remains eligible, rebuilds pending order deterministically, removes disabled episodes, cancels stale pending requests when the current episode changes, persists the new snapshot, and emits a pause intent when stale transport must be stopped. This path performs no feed refresh or network request.
- Source-management controls are reusable from both Radio and Settings. Settings exposes the exact `Feed Order and Enablement` destination, and successful Core Data saves notify the coordinator; failed saves roll back without changing the active session.
- The degraded-source banner is restricted to playable/current buffered Radio states and is not shown for no-sources, exhausted, or all-sources-unavailable outcomes.
- The current-episode accessibility label now uses the same Radio-playing predicate as its icon and action.
- The Settings button boundary now follows the rail's Increase Contrast treatment.

Focused tests were added for source reconciliation, current-source removal, pending reorder/removal, no-source transition, repository and snapshot-save failures, degraded-state presentation, and playback accessibility labeling. The Settings UI test also verifies the source-management destination.

RED was captured before production changes: the new tests failed on the missing presentation and reconciliation APIs. The earlier Task 10 build-for-testing remains green at `c92b7ed`. A final global `make radio-compile` is currently blocked only by concurrent Task 9 lifecycle work (`BriefeedApp.swift` lifecycle callback signatures and `RadioAppLifecycleTests.swift`); no Task 10 compile diagnostics were reported. Task-scoped static gates and `git diff --check` pass.

## Second Review Repair

- Radio source management now retains episode-detail navigation while exposing separate enablement toggles, drag reordering, swipe deletion, and the add-source flow.
- Deleting a source uses the same Core Data save/rollback handling as toggle and reorder. A successful deletion immediately reconciles the local Radio session, removes deleted current or pending episodes, persists the snapshot, and pauses stale transport when the current source was deleted.
- `FeedDetailsViewV2` still presents its existing sheet experience; its list content is minimally extracted for push navigation from Radio source management.
- `AddRSSFeedViewV2` now accepts an optional async completion callback with a default of `nil`, so the existing Live News caller is unchanged. Radio callers reconcile after `RSSAudioService.addFeed` has saved, loaded, and refreshed the new source.
- The add workflow has a small injected async seam. Focused tests prove callback ordering without network traffic and prove adding the first eligible source transitions `noSources` to `readyPaused` with a current episode without another refresh.

Strict TDD evidence:

```text
RED: make radio-compile
RadioSourceConfigurationTests.swift: cannot find 'AddRSSFeedWorkflow' in scope
** TEST BUILD FAILED **

GREEN: make radio-compile
** TEST BUILD SUCCEEDED **
```

Additional focused coverage exercises deletion of the playing current source, deletion of a pending source, callback suppression after add failure, and UI presence of both source details and swipe Delete affordances. Simulator execution remains deferred to the fleet-safe runtime pass.
