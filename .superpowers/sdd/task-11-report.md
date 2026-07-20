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

## Review Repair

The Task 11 review identified restored-session routing, exhausted-state truthfulness, hit-target, finite-value, Dynamic Type, and behavioral-test gaps. The repair adds one effective playback context shared by the transport and both player surfaces, so a restored Radio episode routes Play, ten-second seeks, Next, metadata, progress, remote commands, sleep, and queue gating to Radio even before an audio item is loaded. A completed queue now becomes an explicit stopped "You're caught up" surface with Refresh and no fake seek/play/expand controls.

Playback speed persistence now has injected load/save seams and loads before Combine bindings can overwrite the saved value. Custom sleep deadlines are tested through the actual coordinator. Stale restore completion projects the restored Radio state without replaying a discarded autoplay intent, immediately when active or once on the next foreground transition. All mini-player interactive elements have at least 44 by 44 point frames, every clock/accessibility conversion rejects non-finite values, and the expanded player uses semantic text styles with accessibility-size-aware artwork.

An adjacent Brief regression audit also preserves the pre-existing mini-player path: when the app restores queued Brief items without an active transport, the effective context is Brief, the primary Play action loads the selected item instead of sending a false transport resume, and genuinely unavailable surfaces expose no seek or transport controls.

Review RED evidence:

```text
make radio-compile
RadioPlayerPresentationTests.swift: AudioPlayerViewModelV2 has no member 'effectivePlaybackMode'
RadioPlayerPresentationTests.swift: AudioPlayerViewModelV2 has no member 'playerPresentation'
RadioPlayerPresentationTests.swift: extra argument 'persistPlaybackRate' in call
RadioPlayerPresentationTests.swift: extra argument 'playbackSpeedLoad' in call
** TEST BUILD FAILED **
```

Review GREEN/static evidence:

```text
make radio-compile
** TEST BUILD SUCCEEDED **
git diff --check
rg 'font\(\.system\(size:' Briefeed/Features/Audio/ExpandedAudioPlayerV2.swift
# no matches
```

The focused safe runtime lane remained correctly blocked at preflight because `Simulator.app` was open. The agent did not quit the user's Simulator window or bypass the fleet guard:

```text
RADIO_TEST_SELECTOR='BriefeedTests/RadioPlayerPresentationTests' make radio-unit
SIMULATOR_APP=open
NEXT: sim-gui.sh hide
make: *** [radio-unit] Error 1
```

## Brief Interoperability Re-review

The second review found three Brief-to-Radio handoff defects. New behavioral coverage now requires restored Brief presentation and pre-play ten-second seeks to originate at `BriefQueueCoordinating.currentPosition`, requires both direct and remote Play to load the effective current item through one async entry point, and requires final Brief removal to release stale transport ownership so an available restored Radio episode immediately becomes effective. A deterministic injected completion delay keeps the completion regression free of arbitrary sleeps. The expand and title hit regions also now place their 44-point frame and `contentShape` inside each Button label.

RED:

```text
make radio-compile
RadioPlayerPresentationTests.swift: UnifiedAudioPlayer has no member 'beginEffectiveCurrent'
RadioPlayerPresentationTests.swift: extra argument 'briefCompletionDelay' in call
** TEST BUILD FAILED **
REREVIEW_RED_EXIT=2
```

GREEN:

```text
make radio-compile
** TEST BUILD SUCCEEDED **
REREVIEW_GREEN1_EXIT=0
```

The final scoped diff was compiled again immediately before landing and also completed with `** TEST BUILD SUCCEEDED **`.

The focused runtime lane was requested again through the safe fleet adapter and remained blocked before simulator ownership because `SIMULATOR_APP=open`. No override or GUI mutation was attempted.
