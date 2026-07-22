# Apple Speech Transcript Probe Receipt

**Date:** July 22, 2026  
**Status:** `INCONCLUSIVE` - the one permitted integration invocation did not
start XCTest because the shared simulator runner rejected critical host pressure.

## Evidence Tree and Deterministic Gates

- Verified code commit: `8e731f72d89e18907a35b22de9842d31cb88c1d6`
  (`test: correct deterministic receipt key ordering`). This was the current
  `HEAD` when every command below ran.
- `make radio-compile`: passed, `** TEST BUILD SUCCEEDED **`.
  Xcode build: `17F113`; iPhone Simulator SDK: `26.5` (`23F81a`).
- `RADIO_TEST_SELECTOR=BriefeedTests/TimedTranscriptTests make radio-unit`:
  passed, 4 Swift Testing cases in 1 suite.
- `RADIO_TEST_SELECTOR=BriefeedTests/TimedTranscriptNormalizerTests make radio-unit`:
  passed, 2 Swift Testing cases in 1 suite.
- `RADIO_TEST_SELECTOR=BriefeedTests/PodcastTranscriptionProbeTests make radio-unit`:
  passed, 4 Swift Testing cases in 1 suite. The prescribed selector executed
  the intended suite; no narrow fallback selector was needed.

All focused runs used `Briefeed-Codex-radio-unit-20260722-143738`
(`8E698E75-47DC-4826-8219-A32D748A120E`), an arm64 iOS 18.6 simulator. This
is simulator evidence only, not physical-device evidence.

- Device model: not captured. The owned runner evidence exposed only the clone
  name, UDID, architecture, and runtime, so no iPhone model is inferred.

## Fixture Provenance

The historical `bash skills/app-testing/scripts/run-transcript-probe.sh`
invocation attempted to generate the rights-cleared `apple-news-fixture.aiff`
before the runner guard stopped work. It did not prove regeneration: the old
generator wrote directly to the tracked destination, printed `Opening output
file failed: fmt?`, and only then measured the destination. The following
fixture measurements therefore establish that the existing fixture was
readable, not that the attempt produced it:

- Duration: `68.232834` seconds.
- SHA-256: `8f4f67bb0b867e1346ba21de9d9c69d5329a3f35b84efa061e2de4ed19c05b5e`.
- Format: mono AIFF, 22,050 Hz, signed 16-bit PCM.

## Post-Review Generator Validation

After the review fix, `bash skills/app-testing/scripts/make-transcript-fixture.sh`
ran once, separately from the integration runner. It generated and validated the
new candidate at
`.apple-news-fixture.0vI6fu/apple-news-fixture.aiff` before atomically replacing
the tracked fixture. The primary `say` command exited `0`; fallback was not
used. The newly validated candidate and replaced fixture both measured
`68.232834` seconds with SHA-256
`8f4f67bb0b867e1346ba21de9d9c69d5329a3f35b84efa061e2de4ed19c05b5e`.
The temporary directory was absent after the script exited.

This is generator evidence only. It did not invoke `run-transcript-probe.sh`,
XCTest, or Apple SpeechAnalyzer.

## Single Integration Invocation

The command `bash skills/app-testing/scripts/run-transcript-probe.sh` was run
exactly once for this task. Its runner reported `PRESSURE=critical`, with
`swap_free=947MB`, and printed `Radio lane transcript-probe will not start new
work while host pressure is critical`. The runner's documented critical-pressure
path exits `75`; no simulator work or XCTest began, and no JSON receipt was
written. The fixture-generation command also printed `Opening output file
failed: fmt?`, though the tracked AIFF above existed and `afinfo` read it.

The configured integration locale was `en-US` and its asset policy allowed a
system asset request, but no Apple SpeechAnalyzer asset request or availability
check ran. Asset status is therefore unavailable.

## Unavailable Product Metrics

No integration JSON exists, so the following are unavailable rather than zero:

- Processing duration and real-time factor.
- Recognized and timed character counts; timing coverage; fixture WER.
- Word and phrase unit counts; median words per unit.
- Empirical support for one-word RSVP.

The simulator did not run the engine. It consequently provides no evidence for
audible synchronization, phone performance, memory, thermal behavior, audio
routes, interruptions, or visual drift. Those physical-device checks remain
unrun.

## Verdict

`INCONCLUSIVE`. The exit-75 capacity guard is infrastructure evidence, not an
Apple transcription result. It cannot support either `APPLE_PROCEED` or
`PARAKEET_COMPARISON_REQUIRED`; no second integration attempt was made.

Ad classification, automatic skipping, production UI, and transcript
persistence remain out of scope.
