# Task 12 Implementation Report

Status: IMPLEMENTATION_COMPLETE_RUNTIME_BLOCKED

## Implemented

- Added DEBUG-only deterministic Radio fixture scenarios for partial, completed,
  offline, all-failed, degraded, no-sources, refreshing, and exhausted states.
- Seeded three fixed-priority feeds plus fresh, partially played, completed,
  stale, malformed, duplicate-GUID, and duplicate-enclosure episodes.
- Generated a reusable 90-second mono 44.1 kHz PCM WAV in Application Support;
  no binary audio fixture is committed.
- Added narrow reset semantics for the isolated fixture store and exact Radio
  preferences, while preserving unrelated defaults and no-reset relaunch state.
- Installed one fixture connectivity monitor, Core Data repository, session
  store, and coordinator before singleton playback dependencies are resolved.
- Kept fixture startup and recovery actions independent of production RSS feed
  creation, refresh networking, and polling.
- Added relaunch, completion, autoplay, reset-boundary, state-surface, recovery,
  playback-speed, sleep-timer, and transport XCUITest coverage.
- Added bounded manual fixture and headless smoke scripts that require an exact
  simulator UUID and produce screenshot, log, xcresult, and receipt paths.

## TDD Evidence

The fixture tests were written before the production fixture types. The first
compile failed on the intentionally missing `RadioFixtureScenario` and
`RadioFixtureSeeder` definitions:

```text
make radio-compile
error: cannot find type 'RadioFixtureScenario' in scope
error: cannot find 'RadioFixtureSeeder' in scope
** TEST BUILD FAILED **
```

RED log: `/tmp/briefeed-task12-red.log`

After implementation, the final build-for-testing compiled the app, unit-test
bundle, and UI-test bundle for both simulator architectures:

```text
make radio-compile
** TEST BUILD SUCCEEDED **
```

GREEN log: `/tmp/briefeed-task12-final-compile.log`

The Release configuration also compiled without fixture leakage:

```text
xcodebuild build -project Briefeed.xcodeproj -scheme Briefeed \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/briefeed-task12-release \
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO
** BUILD SUCCEEDED **
```

Release log: `/tmp/briefeed-task12-release.log`

Static verification passed:

```text
git diff --check
bash -n skills/app-testing/scripts/radio-fixtures.sh \
  skills/app-testing/scripts/radio-smoke.sh
```

The manual launcher rejects unknown fixture names with exit 64. A source scan
found no broad shutdown, erase, delete, Simulator GUI, CoreSimulator service,
or pressure-override action. Its `SIMCTL_CHILD_BRIEFEED_RADIO_RESET_STORE`
assignment is the intentional bounded environment handoff specified by the
Task 12 plan.

## Deferred Runtime Proof

The deterministic unit, UI, and smoke lanes were not run. The July 20 fleet
preflight showed pressure at warning level and a foreign Protact2-owned iOS 26
simulator booted as UUID `5F95C5AD-D94B-48BC-A230-B610FB35801B`.
`Simulator.app` PID 30516 was also open against that exact foreign device.

Per the shared app-testing contract, this task did not borrow, hide, shut down,
erase, or otherwise touch that simulator, did not open another Simulator GUI,
and did not override pressure safeguards. Consequently, authored runtime tests
are not claimed as passing. Once the GUI is closed and the fleet preflight is
safe, the remaining proof is:

```bash
bash skills/app-testing/scripts/run-radio.sh live-radio-mvp-task12-unit unit
bash skills/app-testing/scripts/run-radio.sh live-radio-mvp-task12-ui ui
bash skills/app-testing/scripts/run-radio.sh live-radio-mvp-task12-smoke smoke
```

The smoke lane should then provide its receipt, screenshot, bounded app log,
and `RadioSmoke.xcresult` for simulator verification before device testing.

## Review Repair

The first Task 12 review found no critical issues and three important gaps. All
three are repaired:

- `.failed(.allSourcesUnavailable)` now presents a real source **Refresh**
  action and calls `refreshRadio()`. Playback and persistence failures retain
  transport retry behavior. A pure routing test covers all three failure kinds,
  and the fixture UI test asserts that the source-refresh invocation counter
  advances rather than accepting an unchanged error title as proof.
- Fixture diagnostics now count actual `.play` intents passed through the
  fixture bootstrap executor and source-refresh invocations. The counter resets
  for each fixture process, is exposed only in DEBUG through one stable
  accessibility value, and has no Release or production path. XCUITests assert
  autoplay Off executes zero bootstrap play intents and On executes exactly one,
  both before and after process relaunch.
- Smoke log collection is now a short synchronous `with_timeout` call. Timeout
  status 142 is explicitly accepted before XCUITest begins; there is no
  background subshell, trap, or orphanable timeout/simctl process.

The fixture tests also fetch the selected offline and degraded Core Data
episodes directly. Offline proves its current item has no downloaded path;
degraded proves its local path is readable. The degraded UI assertion is only
evidence that available local playback continues, not a source-recovery claim.

Strict review-repair TDD evidence:

```text
RED: make radio-compile
RadioFixtureSeederTests.swift: cannot find 'RadioFixtureDiagnostics' in scope
RadioHomePresentationTests.swift: type 'RadioHomePresentation' has no member 'failureRecovery'
** TEST BUILD FAILED **

GREEN: make radio-compile
** TEST BUILD SUCCEEDED **
```

Repair RED log: `/tmp/briefeed-task12-review-red.log`

Final GREEN log: `/tmp/briefeed-task12-review-green-final.log`

The final Release build also succeeded at
`/tmp/briefeed-task12-review-release.log`. `git diff --check`, both scripts'
`bash -n`, the no-background-log static assertion, and a direct shared
`with_timeout` probe returning status 142 passed. Simulator runtime remains
unrun for the same foreign-GUI safety condition recorded above.
