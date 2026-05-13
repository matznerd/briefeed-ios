# PocketTTS TestFlight Handoff

Date: 2026-05-13
Branch: `feature/processing-chamber`
Latest pushed commit: `4ade618`

## What Is Done

- FluidAudio is pinned to `0.14.5`.
- The app uses `PocketTtsManager` through the existing `FluidAudioTTSService` contract.
- `UnifiedAudioPlayer` uses on-device PocketTTS first when `preferOnDeviceTTS` is enabled, then falls back to cloud TTS if local initialization or synthesis fails.
- The Play Now article pipeline is wired as:
  - article URL/content
  - Firecrawl content fetch when content is missing
  - Gemini summary generation
  - PocketTTS local WAV generation
  - cache URL persisted back into `QueueCoordinator`
  - SwiftAudioEx playback
- Gemini and Firecrawl keys are injected through `Info.plist` build settings and read as bundled fallbacks after user overrides.
- The clean exported IPA excludes stale `.backup` and `.disabled` Swift files from the app bundle.

## Verified Artifacts

Clean IPA:

```bash
/tmp/briefeed-export-auth-clean/Briefeed.ipa
```

Clean archive:

```bash
/tmp/briefeed-pockettts-release-clean.xcarchive
```

Archive identity:

```text
Bundle ID: Matznerd.Briefeed
Version: 0.1.1.1
Build: 2
```

Secret packaging was checked without printing values:

```text
FirecrawlAPIKey length: 35
GeminiAPIKey length: 39
Info.plist placeholders present in archive: no
```

IPA resource cleanup was checked:

```text
stale_backup_entries=0
```

## Verified Tests

PocketTTS focused tests:

```bash
xcodebuild test \
  -project Briefeed/Briefeed.xcodeproj \
  -scheme Briefeed \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -derivedDataPath /tmp/briefeed-audit-test-dd \
  CODE_SIGNING_ALLOWED=NO \
  -skip-testing:BriefeedUITests \
  -only-testing:BriefeedTests/FluidAudioTTSServiceTests \
  -only-testing:BriefeedTests/KokoroTTSIntegrationTests
```

Result:

```text
/tmp/briefeed-audit-test-dd/Logs/Test/Test-Briefeed-2026.05.13_06-29-29--0700.xcresult
9 tests, 0 failures
```

Play Now / queue / audio-pipeline tests:

```bash
xcodebuild test \
  -project Briefeed/Briefeed.xcodeproj \
  -scheme Briefeed \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -derivedDataPath /tmp/briefeed-audit-test-dd \
  CODE_SIGNING_ALLOWED=NO \
  -skip-testing:BriefeedUITests \
  -only-testing:BriefeedTests/PipelineTimerTests \
  -only-testing:BriefeedTests/QueueOperationTests \
  -only-testing:BriefeedTests/PipelineErrorHandlingTests \
  -only-testing:BriefeedTests/GenerationStateTests \
  -only-testing:BriefeedTests/AudioPipelineFlowTests \
  -only-testing:BriefeedTests/ProcessingChamberTests
```

Result:

```text
/tmp/briefeed-audit-test-dd/Logs/Test/Test-Briefeed-2026.05.13_06-33-54--0700.xcresult
28 tests, 0 failures
```

## Current Blocker

TestFlight upload is blocked because App Store Connect has no app record for `Matznerd.Briefeed`.

Evidence:

```bash
asc apps list --bundle-id Matznerd.Briefeed --output json
```

Returned:

```json
{"data":[],"meta":{"paging":{"total":0,"limit":50}}}
```

The Developer Portal bundle ID does exist:

```text
ZDHZJA9SWH / Matznerd.Briefeed / UNIVERSAL / X273WR8MT2
```

The local unofficial web-session auth is not available:

```bash
asc web auth status
```

Returned:

```json
{"authenticated":false}
```

Apple's public App Store Connect API does not create new apps. Apple documents that new apps should be created in the App Store Connect website. The local CLI has `asc web apps create`, but it is marked experimental, unofficial, and discouraged because it uses private Apple web endpoints.

Tracking issue:

```text
https://github.com/matznerd/briefeed-ios/issues/7
```

## App Record Fields

Use these fields when creating the missing app record in the official App Store Connect web UI:

```text
Platform: iOS
Name: Briefeed
Primary language / locale: English (U.S.) / en-US
Bundle ID: Matznerd.Briefeed
SKU: Matznerd.Briefeed
Initial version: 0.1.1.1
```

## Upload Command After App Record Exists

Once the App Store Connect app record exists, find the app ID:

```bash
asc apps list --bundle-id Matznerd.Briefeed --output table
```

Then upload the clean IPA:

```bash
asc builds upload \
  --app "<APP_STORE_CONNECT_APP_ID>" \
  --ipa /tmp/briefeed-export-auth-clean/Briefeed.ipa \
  --test-notes "PocketTTS local briefing playback: Reddit story Play Now fetches content, summarizes with Gemini, generates local PocketTTS audio, caches it, and plays through the unified player." \
  --locale en-US \
  --verify-timeout 10m
```

If using `altool` instead:

```bash
xcrun altool --upload-app \
  -f /tmp/briefeed-export-auth-clean/Briefeed.ipa \
  --type ios \
  --api-key VR4TSYW58F \
  --api-issuer 1c456fce-f1bf-4674-8190-0499bcff46b2 \
  --p8-file-path /Users/me/ericode/apple_AuthKey_VR4TSYW58F.p8
```

Do not expect either upload command to work until the App Store Connect app record exists.
