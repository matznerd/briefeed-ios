# Live Radio Distribution Readiness Receipt

Date: July 20, 2026
Branch: `codex/live-radio-mvp`
Implementation base commit: `2f260fa`
Verified implementation commit: `12ec494`
Status: **focused simulator verification complete; exported IPA approved for authorized local phone testing only; public distribution blocked**

## Gate Summary

| Gate | Result | Evidence |
| --- | --- | --- |
| Build for testing | PASS | `make radio-compile`; `/tmp/briefeed-live-radio-12ec494-compile.log`; `** TEST BUILD SUCCEEDED **` |
| Adapter safety regression | PASS | `bash skills/app-testing/scripts/run-radio-selftest.sh`; `/tmp/briefeed-live-radio-cb04d12-adapter-selftest.log`; covers fresh/ownerless claims and critical-pressure refusal |
| Deterministic Radio unit suites | PASS | Exact-commit suites: restore 17/17, lifecycle 11/11, empty state 4/4, RSS refresh 8/8, Unified playback 11/11, playback state 30/30 |
| Radio UI suite | PASS | `/tmp/briefeed-live-radio-12ec494-ui.log`; 15/15 tests in 226.6 seconds |
| Headless Radio smoke behavior | PASS | `RadioUITests.testHeadlessRadioSmoke` passed inside the complete UI suite |
| Standalone smoke evidence bundle | NOT RUN | An earlier attempt was refused at critical pressure; pressure later recovered for focused/UI suites, but the separate script was not retried and no screenshot receipt was created |
| Focused Brief regression | PASS ON PRIOR BASELINE | `/tmp/briefeed-live-radio-final-brief-selectors.log`; MiniPlayer navigation 13/13 plus focused isolation/state selectors passed at `b3950b9`; not rerun after the scoped Radio/RSS repairs in `12ec494` |
| Analyze | PASS | `/tmp/briefeed-live-radio-12ec494-analyze.log`; `** ANALYZE SUCCEEDED **` |
| Physical-device checklist | NOT RUN | No developer device was selected or modified |
| Signed archive/export | PASS | `/tmp/Briefeed-Live-Radio-12ec494.xcarchive`; `/tmp/Briefeed-Live-Radio-12ec494-export/Briefeed.ipa`; code-sign verification passed |
| Packaged credential audit | BLOCKED | Exported IPA contains nonempty Firecrawl and Gemini values. Do not upload or share it. Remediation is tracked in GitHub #16 |
| Visual size/appearance matrix | NOT RUN | One iPhone 15 Pro / iOS 18.6 runtime verified; follow-up GitHub #15 |
| App Store Connect upload | BLOCKED / NOT ATTEMPTED | No app record for `Matznerd.Briefeed`; GitHub #7 |

## Simulator Identity and Safety

- Owned lane: `live-radio-mvp-final`
- Simulator UUID: `BC59FDE1-AEB1-413C-A988-8494357A7A3D`
- Device/runtime: iPhone 15 Pro, iOS 18.6
- Mode: headless; `Simulator.app` was not opened
- No foreign simulator was borrowed, shut down, erased, or modified.
- The owned simulator remains warm as required by the shared fleet contract.

The first fresh-lane attempt exposed an adapter defect: `run-radio.sh` exited
under `set -e` when its state file did not exist. The original trace is
`/tmp/briefeed-adapter-trace.log`. The state-file read is now tolerant of a
missing first-use claim, and `run-radio-selftest.sh` proves that a fresh claim
is created and reaches the test command.

The adapter also now refuses **all** new simulator work at critical host
pressure, including when the doctor reports `PRESSURE=critical` with exit zero
and when reusing an already booted claim. Its self-test proves that an active
lane cannot be stolen, an ownerless claim-lock can recover after a bounded
wait, and the test command is never invoked at critical pressure. No
`AGENT_SIM_PRESSURE_OVERRIDE` was used.

## CoreSimulator Audio Limitation

The fixture seeder installed a readable, valid 90-second mono 44.1 kHz WAVE
file in the app data container. CoreSimulator loaded the file through AVPlayer,
but the headless audio backend could not start and logged:

```text
AQME ... timed out after 15.000s
CA_UISoundClientBase::StartPlaying: AddRunningClient failed (status = -66681)
```

This could stall UI automation for minutes and is not evidence that physical
audio works. The app previously entered `playing` optimistically before the
transport confirmed it; that product bug is fixed. Radio now enters `loading`
and becomes `playing` only after the transport callback.

DEBUG fixture launches use `RadioFixtureAudioTransport`, which requires the
readable seeded local file and emits through the real
`UnifiedAudioPlayer`/`RadioSessionCoordinator` callback path. Production and the
Release archive always use `SwiftAudioExService`. Focused tests prove fixture
callback order, missing-media failure, and transport-driven state promotion.
Audible playback, background audio, Lock Screen, and Control Center therefore
remain mandatory physical-device checks.

## Broad Legacy Suite Attempt

The exact requested unit adapter was attempted once:

```bash
bash skills/app-testing/scripts/run-radio.sh live-radio-mvp-final unit
```

Log: `/tmp/briefeed-live-radio-final-unit.log`

This default selector runs all `BriefeedTests`, not only the deterministic Radio
suites. It initiated live Firecrawl requests (HTTP 402), downloaded 77 PocketTTS
model files, emitted existing Core Data duplicate-entity warnings, and failed
five `InfiniteScrollTests` assertions. One assertion is labeled in source as
expected to fail until implemented. A later `MiniPlayerNavigationTests` case
also inherited persisted singleton queue state and initiated more network/audio
work. The run was stopped rather than permitting additional external traffic.
These are legacy test-harness defects, not a claim that the Radio suites failed.
They are tracked in GitHub #12, #14, and the existing Core Data warning issue
#9. The broad selector was not rerun for this release receipt.

Immediately afterward the shared doctor reported:

```text
PRESSURE=critical ... load=262/10cores
NEXT: host pressure critical: new boots will wedge. Free memory (stale agent sessions, browser), run --gc, or reboot to drain swap
```

No pressure override or simulator recovery action was used. The doctor later
permitted the focused unit and full UI runs, which passed. After those runs it
again reported critical swap pressure (`swap_free` approximately 786-794 MB),
so the redundant standalone smoke/screenshot bundle was not started. The owned
simulator remained warm.

## Focused Automated Verification Detail

- Coordinator restore/autoplay state: 17/17 tests passed. Cold-launch restore
  and initial-refresh autoplay remain `loading` until transport start promotes
  them to `playing`.
- App lifecycle: 11/11 tests passed.
- Empty-state precedence: 4/4 tests passed.
- RSS refresh policy: 8/8 tests passed, including failed-save recovery that
  preserves an unrelated unsaved draft and pre-existing Core Data undo history.
- Unified Radio playback: 11/11 tests passed.
- Radio playback state: 30/30 tests passed.
- Focused Brief navigation: 13/13 tests passed at `b3950b9`; additional Brief
  isolation and mini-player selectors passed on that prior baseline. They were
  not rerun after the final scoped Radio/RSS repairs.
- Focused autoplay UI: passed in 26.9 seconds with Off producing zero bootstrap
  play intents and On producing exactly one per process launch.
- Complete `RadioUITests`: 15/15 passed, covering navigation, settings, source
  management, compact player ergonomics, speed/sleep controls, partial resume,
  completion, autoplay, state recovery, and headless smoke behavior.

This is focused release verification, not an all-tests claim. The broad hosted
`BriefeedTests` target is not green for the independent reasons recorded above,
and a separate standalone smoke evidence bundle with screenshots was not
captured. Those gaps remain tracked in GitHub #11, #12, #14, and #15.

## Signing and Package Inventory

| Item | Observed value |
| --- | --- |
| Product bundle ID | `Matznerd.Briefeed` |
| Marketing version | `0.1.1.1` |
| Build number | `2` |
| Development team | `X273WR8MT2` |
| Signing style | Automatic |
| Background modes | `audio` |
| App entitlements file | None in the project |
| Matching distribution identity | `iPhone Distribution: Eric Matzner (X273WR8MT2)` |
| Matching App Store profile | `iOS Team Store Provisioning Profile: Matznerd.Briefeed`, expires 2027-04-25 |
| App Store Connect record | Absent (`asc apps list --bundle-id Matznerd.Briefeed` returned zero apps) |
| Repository ExportOptions.plist | Absent |
| Tracked credential/profile files | None found by filename scan |

Archive/export result:

| Artifact | Value |
| --- | --- |
| Implementation commit | `12ec494` |
| Archive | `/tmp/Briefeed-Live-Radio-12ec494.xcarchive` |
| Exported IPA | `/tmp/Briefeed-Live-Radio-12ec494-export/Briefeed.ipa` |
| IPA size | 5.8 MB |
| IPA SHA-256 | `514e336ebd3d6d128ed54622f1dc7dee8516b9760a723c772d26cf92f03b640f` |
| Export signature | `iPhone Distribution: Eric Matzner (X273WR8MT2)` |
| Export profile | `iOS Team Store Provisioning Profile: Matznerd.Briefeed` |
| Signature verification | `codesign --verify --deep --strict` passed |
| Background modes | `audio` |

The archived `Info.plist` contains nonempty packaged values for the configured
Firecrawl and Gemini keys; their contents were not printed. The IPA was exported
locally with destination `export`; it was not uploaded. This credential finding
is a release blocker, not an accepted client-configuration decision. The current
IPA must not be uploaded to TestFlight/App Store Connect or shared externally.
GitHub issue #16 requires rotation/revocation, provider restrictions, a
server-owned Firecrawl boundary, and a packaging gate before a new distribution
artifact is produced.

`Info.plist` declares `FirecrawlAPIKey` and `GeminiAPIKey` through build-setting
substitution. Their packaged values were checked without printing secrets. The
correct Gemini TTS model remains
`gemini-2.5-flash-preview-tts`.

## Physical Device

Read-only discovery found `Eric's iPhone (2)`, an available paired iPhone 13 Pro
with identifier `2E288699-F8E0-5B18-A2D9-DE8B1384C33A`. It was not selected,
installed to, or changed. See `LIVE-RADIO-DEVICE-CHECKLIST.md`; every physical
row remains open.

## Distribution Decision

Current label: **focused simulator verification complete; signed IPA approved
only for an explicitly authorized local phone test; public distribution
blocked**.

The deterministic simulator and signed archive/export gates pass, and the
artifact is tied to implementation commit `12ec494`. The label can change to a
distribution candidate only after the complete physical-device checklist
passes, GitHub #16 is cleared by a newly inspected clean artifact, and the
App Store Connect blocker in GitHub #7 is resolved.

## Human-Only Distribution Actions

1. Rotate/revoke the packaged credentials, move privileged Firecrawl access off
   device, decide and enforce the Gemini trust boundary, and pass the clean IPA
   packaging gate in GitHub #16.
2. Approve a physical developer iPhone and run the device checklist with this
   local-only artifact or a newer clean artifact.
3. Create the App Store Connect app record for `Matznerd.Briefeed` through the
   official web interface as tracked by GitHub issue #7.
4. Confirm App Store Connect agreements, roles, certificates, provisioning
   profiles, privacy answers, and export-compliance answers.
5. Approve the marketing version and build number.
6. Approve and initiate upload of a newly validated, credential-clean IPA. No
   upload is performed by this verification task.
7. Select internal/external tester groups and complete beta review if needed.
8. Submit App Review only after explicit human approval.

Future on-device transcription and smart ad-boundary skipping remain outside
this MVP and are tracked by GitHub issue #10.
