# Task 11 Implementation Report

Status: IMPLEMENTED_PENDING_REVIEW

## Implemented

- Rebuilt the mini player as a compact asymmetric surface: flexible artwork/title/source/speed/sleep metadata on the left and a fixed right-hand Back 10, Play/Pause, Forward 10, Next cluster.
- Removed the mini-player waveform and Radio Previous control while retaining Brief Previous behavior.
- Added a reusable thin progress rail inside a 44-point tap/drag lane with deterministic geometry, 0...duration clamping, ten-second VoiceOver adjustment, and elapsed/remaining accessibility values.
- Added a canonical playback-speed Menu using `PlaybackSpeedPolicy.supported`; selection continues through the existing normalized persisted ViewModel/player path.
- Added exact sleep options: Off, End of Episode, 10/20/30/45/60 minutes, and Custom. The custom sheet starts at 20 minutes and clamps its Stepper to 1...180. Deadline values update visibly and accessibly.
- Updated the expanded player to use the shared scrubber, 10/10 transport intervals, shared speed/sleep controls, active Radio metadata/position, and no Brief queue or Previous affordance while Radio owns playback.
- Added stable accessibility identifiers and focused UI expectations for minimum hit sizes and Radio control availability.
- Replaced legacy seek tests that depended on remote audio and arbitrary sleeps with pure clamping/geometry tests, and added a pure Radio player presentation suite.

## Strict TDD Evidence

RED was captured before production edits:

```text
make radio-compile
MiniPlayerSeekTests.swift: cannot find 'PlayerSeekGeometry' in scope
RadioPlayerPresentationTests.swift: cannot find 'PlayerPresentationPolicy' in scope
RadioPlayerPresentationTests.swift: cannot find 'RadioSleepMenuOption' in scope
RadioPlayerPresentationTests.swift: cannot find 'PlayerPresentationFormat' in scope
RadioPlayerPresentationTests.swift: MiniPlayer has no member 'scrubber'
** TEST BUILD FAILED **
TASK11_RED_EXIT=2
```

GREEN build-for-testing evidence:

```text
make radio-compile
** TEST BUILD SUCCEEDED **
TASK11_GREEN2_EXIT=0
```

Static verification:

```text
git diff --check
rg gates: no 15/30-second expanded transport, no 20x copy, no WaveformMiniView in owned player surfaces
```

## Runtime Evidence Deferred by Fleet Gate

The focused owned lane was requested without overrides:

```text
RADIO_TEST_SELECTOR='BriefeedTests/MiniPlayerSeekTests' \
  bash skills/app-testing/scripts/run-radio.sh task11-seek unit
PRESSURE=warn swap_free=1530MB reclaimable=18532MB load=31
SIMULATOR_APP=open
NEXT: sim-gui.sh hide
```

The adapter stopped before acquiring or booting a Briefeed simulator. No pressure override, GUI action, foreign simulator mutation, or CoreSimulator recovery was attempted. Focused unit execution, Radio UI execution, and the requested visual matrix remain for the shared fleet verification pass.
