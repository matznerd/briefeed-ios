# Queue-Ahead Ad Preparation Checkpoint

Date: October 2, 2026. Source base: `4acbbcb70f2958de14bd557d727cc89fa0dc17ad`.
Integration checkout: `.worktrees/live-radio-mvp`. This is a draft source/test
checkpoint, not an automatic-skipping release or physical-device receipt.

## Implemented Contract

- Preparation defaults off. Automatic skipping defaults off, is disabled in
  settings, and is independently blocked by `RadioAdSkipPolicy.isReleaseQualified`.
  Imported preferences cannot enable an unqualified release. No automatic ad
  seek handler has been enabled.
- While audio is already playing, opt-in preparation orders next one, next two,
  then current. Setting-off preserves existing transcript ordering and limits.
  Normal automatic work stops on background; background audio does not grant
  continuous ML execution. Existing explicit batches prepare transcripts only.
- Reuse the existing audio download/cache owner, deduplication and pins. Hash
  the complete committed rendition. Speech and ad records refer to this SHA-256
  and the original source clock. Local playback uses this same file. Uncached
  opening playback can still stream immediately; remote URL/ETag equality is
  insufficient for skips. A read-only player getter refuses remote playback.
- Streaming manifests/playlists are rejected as owned audio, including recognized
  playlist content disguised under an audio-file URL. Hashing a manifest would
  not prove the identity of mutable remote segments.
- Known durations up to 90 minutes are eligible for opt-in lookahead, with a
  100 MiB file cap and 256 semantic-window cap. Default transcript lookahead
  keeps its 45-minute limit. These limits do not expand automatic qualification.
  Ad lookahead downloads use a 120-second request inactivity timeout; classifier timeout
  is cooperative, not a guaranteed hard process deadline. Thermal pressure
  defers classification. Cancellation or model refusal does not stop audio.
- Transcript/audio readiness is published before semantic classification.
  Cached speech can be reused for ad analysis. Failed semantic work cannot
  delete a valid transcript or label total refusal as a successful no-ad result.
- Apple SpeechAnalyzer performs existing on-device ASR. Apple's default
  Foundation Models language model produces bounded, untrusted nominations in
  fresh sessions. Host code maps supplied unit IDs to source times. Availability
  is checked; no cloud fallback, relaxed safeguards, new weights or dependencies.
  Experimental output has no human approval and cannot authorize a seek.
- Local revision-checked reviews support category/boundary corrections, listening
  around boundaries, an explicit manual skip, and undo to the original source
  position. Listening/boundary confirmation/manual skip require exact owned
  playing-file identity. Reviewed editorial conflicts block sponsor skips.
- Settings show model availability, actual queue state and an hour estimate
  only after successful measured ASR plus classifier work on this device.
  Download time is additional. No physical-iPhone speed has been established.

## Owned Source And Test Changes

Paths below are relative to the `Briefeed` directory containing the Xcode project.

New files:

- `Briefeed/Core/AdDetection/RadioAdModels.swift`
- `Briefeed/Core/AdDetection/RadioAdStore.swift`
- `Briefeed/Core/AdDetection/AdTranscriptWindows.swift`
- `Briefeed/Core/AdDetection/RadioAdPreparationService.swift`
- `Briefeed/Features/Settings/RadioAdSettingsView.swift`
- `Briefeed/Features/Radio/RadioAdReviewView.swift`
- `BriefeedTests/AdDetection/RadioAdDetectionTests.swift`
- `BriefeedTests/AdDetection/RadioAdPipelineIntegrationTests.swift`
- `BriefeedTests/AdDetection/RadioAdAssetIntegrationTests.swift`
- This checkpoint document.

Modified, fully owned for this phase:

- `Briefeed/Core/Radio/RadioServiceContainer.swift`
- `Briefeed/Core/Transcription/RadioTranscriptAssetService.swift`
- `Briefeed/Core/Transcription/RadioTranscriptCoordinator.swift`
- `Briefeed/Core/Transcription/RadioTranscriptPreparationPipeline.swift`
- `Briefeed/Core/Utilities/UserDefaultsManager.swift`
- `Briefeed/Core/Utilities/AccessibilityIdentifiers.swift`
- `Briefeed/Core/ViewModels/AudioPlayerViewModelV2.swift`
- `Briefeed/Features/Settings/SettingsView.swift`
- `Briefeed/Features/Radio/RadioHomeView.swift`
- `BriefeedTests/Transcription/RadioTranscriptCoordinatorTests.swift`
- `Scripts/run-radio-startup-host-tests.sh`

Mixed ownership:

- `Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift`: only the new eight-line
  `activeOwnedRadioAssetFingerprint` getter near line 266 belongs to ad preparation.
  Do not include the pre-existing `audioRequestTogglePlayPause()` method hunk.

Excluded, untouched pre-existing remote-toggle edits:

- `Briefeed/Core/Services/Audio/SwiftAudioExService.swift`
- `BriefeedTests/Radio/AudioCompletionRoutingTests.swift`
- `BriefeedTests/Radio/UnifiedRadioPlaybackTests.swift`
- The mixed player method above.

The primary checkout contains separate local research/prototypes and the original
implementation ledger. They are not required for this app-source checkpoint.
Do not include downloaded audio, real transcripts, private rendition URLs,
review labels, corpus/probe output, `/tmp` logs, DerivedData or credentials in Git.

## Verification

All host runtime inputs are disposable synthetic fixtures. Pipeline integration
tests compile the actual production actor and inject speech/classifier/download
adapters; they do not call Apple inference or remote endpoints. Owned-file tests
validate commit/hash/reuse/prepared URL and resource cleanup, not decoded playback.

```sh
bash Scripts/run-radio-startup-host-tests.sh --filter 'RadioAdDetectionTests|RadioAdPipelineIntegrationTests|RadioAdAssetIntegrationTests|RadioTranscriptCoordinatorTests'
bash Scripts/run-radio-startup-host-tests.sh
xcodebuild -project Briefeed.xcodeproj -scheme Briefeed \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/briefeed-ad-integration-build \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  -jobs 2 build CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
git diff --check
```

Build phases, wrappers and pinned declared package manifests were reviewed before
execution. No new package or model was added. Existing concurrency/unused-code
warnings remain outside this scope.

- Focused suite before the final manifest guard: 42 tests in four suites pass,
  including 19 ad tests and the coordinator suite. Final full-suite execution
  includes all 20 ad tests and 23 coordinator tests passing. Covered: exact cache mismatch, review revisions, manual
  source-time identity/review prerequisites, imported settings gate, one-hour
  source-window coverage, next-first ordering, cached ASR reuse, semantic failure,
  cancellation, unknown/misreported duration, byte limit, staged-file cleanup and
  rejection of a streaming playlist disguised as an MP3.
- Final full portable suite: 166 of 167 tests pass. The sole failure is the previously
  reproduced baseline `directPauseNextCompletionInterruptionAndRouteSaveBeforeReturningIntent`
  at `RadioPlaybackStateTests.swift:629`. No baseline repair was mixed into this
  work. Baseline before integration was 145 of 146 passing.
- Generic arm64 iOS Simulator source build passes with signing disabled.
- Diff whitespace check passes.
- No app/simulator launch, iPhone installation, commit, push, deployment, release
  or remote business-data mutation was performed by this chat.

## Remaining Gates

- Isolated synthetic iOS interactive/visual QA of settings, review, exact local
  playback, seek/undo and queue changes. Source compilation is not runtime proof.
- Physical-device end-to-end hour timing, supported-device availability, speech
  asset installation policy, memory, battery/thermal, interruption, lock-screen,
  Control Center/Bluetooth and cancellation/readiness tests. No continuous locked
  analysis or speed guarantee is established.
- Detector accuracy is unqualified. Human-reviewed category/boundary labels,
  hard editorial negatives, independently frozen provider/position holdouts and
  the existing `briefeed-sl8` acceptance gates remain outstanding. Model refusals
  and editorial/boundary mistakes observed during local research are reasons to
  keep this nomination-only. Near-production auto-skip is not claimed.
- Before qualification: independent acoustic boundary/fingerprint evidence,
  wider eligible positions/providers, append-only correction history, aggregate
  metadata retention/quotas and acquisition timing/remaining-work ETA. Current
  corrections persist their latest revision; they are not an audit journal.
- A future transport-clock auto-skip implementation must independently satisfy
  bypass-on-user-seek and reversible undo/suppression tests. Enabling a setting
  or changing one release constant is not a substitute for that work.

The active integration/evaluation goal remains open. This checkpoint can be
reviewed as preparation/tag/review source with automatic skipping disabled.
