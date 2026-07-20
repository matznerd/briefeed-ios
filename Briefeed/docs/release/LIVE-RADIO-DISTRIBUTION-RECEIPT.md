# Live Radio Distribution Readiness Receipt

Date: July 20, 2026
Branch: `codex/live-radio-mvp`
Implementation base commit: `2f260fa`
Verified implementation commit: `b3950b9`
Status: **simulator-verified and ready for approved phone testing; not yet a distribution candidate**

## Gate Summary

| Gate | Result | Evidence |
| --- | --- | --- |
| Build for testing | PASS | `make radio-compile`; `/tmp/briefeed-live-radio-final-compile.log`; `** TEST BUILD SUCCEEDED **` |
| Adapter fresh-claim regression | PASS | `bash skills/app-testing/scripts/run-radio-selftest.sh` |
| Deterministic Radio unit suites | PASS | Focused suites passed; final examples include Audio completion 6/6, Unified playback 11/11, and playback state 30/30 |
| Radio UI suite | PASS | `/tmp/briefeed-live-radio-final-ui.log`; 15/15 tests in 226.8 seconds |
| Headless Radio smoke behavior | PASS | `RadioUITests.testHeadlessRadioSmoke` passed inside the complete UI suite |
| Standalone smoke evidence bundle | BLOCKED | Fleet doctor returned critical swap pressure before new work; no override; no screenshot receipt created |
| Focused Brief regression | PASS | `/tmp/briefeed-live-radio-final-brief-selectors.log`; MiniPlayer navigation 13/13 plus focused isolation/state selectors |
| Analyze | PASS | `/tmp/briefeed-live-radio-final-analyze.log`; `** ANALYZE SUCCEEDED **` |
| Physical-device checklist | NOT RUN | No developer device was selected or modified |
| Signed archive/export | PASS | `/tmp/Briefeed-Live-Radio-b3950b9.xcarchive`; `/tmp/Briefeed-Live-Radio-b3950b9-export/Briefeed.ipa`; code-sign verification passed |
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
pressure, including reuse of an already booted claim. Its self-test proves that
the test command is never invoked in that state. No
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

## Automated Verification Detail

- Audio completion routing: 6/6 tests passed, including deterministic fixture
  media readability and callback ordering.
- Unified Radio playback: 11/11 tests passed.
- Radio playback state: 30/30 tests passed.
- Focused Brief navigation: 13/13 tests passed; additional Brief isolation and
  mini-player selectors also passed.
- Focused autoplay: passed in 26.3 seconds with Off producing zero bootstrap
  play intents and On producing exactly one per process launch.
- Complete `RadioUITests`: 15/15 passed, covering navigation, settings, source
  management, compact player ergonomics, speed/sleep controls, partial resume,
  completion, autoplay, state recovery, and headless smoke behavior.

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
| Implementation commit | `b3950b9` |
| Archive | `/tmp/Briefeed-Live-Radio-b3950b9.xcarchive` |
| Exported IPA | `/tmp/Briefeed-Live-Radio-b3950b9-export/Briefeed.ipa` |
| IPA size | 5.8 MB |
| IPA SHA-256 | `08f16472e1bf4dc598ff463e475cddbb43e5d9030ad52a40ef6769f70777aefd` |
| Export signature | `iPhone Distribution: Eric Matzner (X273WR8MT2)` |
| Export profile | `iOS Team Store Provisioning Profile: Matznerd.Briefeed` |
| Signature verification | `codesign --verify --deep --strict` passed |
| Background modes | `audio` |

The archived `Info.plist` contains nonempty packaged values for the configured
Firecrawl and Gemini keys; their contents were not printed. The IPA was exported
locally with destination `export`; it was not uploaded.

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

Current label: **simulator-verified and ready for an explicitly approved phone
test; not yet a distribution candidate**.

The deterministic simulator and signed archive/export gates pass, and the
artifact is tied to implementation commit `b3950b9`. The label can change to a
distribution candidate only after the complete physical-device checklist
passes.

## Human-Only Distribution Actions

1. Approve a physical developer iPhone and run the device checklist.
2. Create the App Store Connect app record for `Matznerd.Briefeed` through the
   official web interface as tracked by GitHub issue #7.
3. Confirm App Store Connect agreements, roles, certificates, provisioning
   profiles, privacy answers, and export-compliance answers.
4. Approve the marketing version and build number.
5. Approve and initiate upload of the validated IPA. No upload is performed by
   this verification task.
6. Select internal/external tester groups and complete beta review if needed.
7. Submit App Review only after explicit human approval.

Future on-device transcription and smart ad-boundary skipping remain outside
this MVP and are tracked by GitHub issue #10.
