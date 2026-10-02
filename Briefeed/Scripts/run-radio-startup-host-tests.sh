#!/usr/bin/env bash
set -euo pipefail

# Compile the real state machine/lifecycle on macOS, without Xcode or a simulator.
# App composition, Core Data adapters, and platform background/speech execution
# remain iOS gates. Pipeline tests inject synthetic assets/engines, never live ASR.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/briefeed-startup.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT

awk '
    /^final class CoreDataRadioEpisodeRepository/ { exit }
    /^protocol RadioEpisodeRepository/ { protocol_body = 1 }
    /    @MainActor/ { skip_adapter_init = 1; next }
    skip_adapter_init && /^    init\(/ { skip_adapter_init = 0 }
    !skip_adapter_init { print }
    protocol_body && /^}/ { exit }
' "$ROOT/Briefeed/Core/Radio/RadioEpisodeRepository.swift" > "$BUILD/RadioEpisodeRepository.swift"
sed '/^\/\/ MARK: - Radio App Initialization/,$d' \
    "$ROOT/Briefeed/BriefeedApp+RSSV2.swift" > "$BUILD/RadioAppLifecycleDriver.swift"
awk '/^import Foundation/ { print } /^enum RSSFeedRefreshOutcome/ { result_types = 1 } result_types { print }' \
    "$ROOT/Briefeed/Core/Services/RSS/RSSAudioService.swift" > "$BUILD/RSSRefreshResult.swift"

xcrun swiftc -parse-as-library -D DEBUG \
    "$ROOT/Briefeed/Core/Radio/RadioModels.swift" \
    "$BUILD/RadioEpisodeRepository.swift" \
    "$ROOT/Briefeed/Core/Radio/RadioQueueBuilder.swift" \
    "$ROOT/Briefeed/Core/Radio/RadioSessionStore.swift" \
    "$ROOT/Briefeed/Core/Radio/RadioNetworkMonitor.swift" \
    "$ROOT/Briefeed/Core/Radio/RadioSessionCoordinator.swift" \
    "$BUILD/RSSRefreshResult.swift" \
    "$BUILD/RadioAppLifecycleDriver.swift" \
    "$ROOT/Scripts/radio-startup-host-tests.swift" \
    -o "$BUILD/radio-startup-tests"
"$BUILD/radio-startup-tests"

# Run the portable XCTest-independent suites against the same production code.
mkdir -p "$BUILD/Sources" "$BUILD/Tests"
cp "$ROOT/Scripts/radio-startup-host-package.swift" "$BUILD/Package.swift"
cp "$BUILD/RadioEpisodeRepository.swift" "$BUILD/RadioAppLifecycleDriver.swift" \
    "$BUILD/RSSRefreshResult.swift" "$BUILD/Sources/"
for file in RadioModels RadioQueueBuilder RadioSessionStore RadioNetworkMonitor RadioSessionCoordinator; do
    cp "$ROOT/Briefeed/Core/Radio/$file.swift" "$BUILD/Sources/"
done
for file in TimedTranscript TimedTranscriptEngine RadioTranscriptModels RadioTranscriptStore RadioTranscriptAssetService RadioFeedSpeechMetadataStore RadioTranscriptCoordinator; do
    cp "$ROOT/Briefeed/Core/Transcription/$file.swift" "$BUILD/Sources/"
done
cp "$ROOT/Briefeed/Core/Transcription/RadioTranscriptPreparationPipeline.swift" \
    "$ROOT/Briefeed/Core/Transcription/AppleSpeechAnalyzerEngine.swift" "$BUILD/Sources/"
awk '
    /^import BackgroundTasks/ { next }
    /^final class RadioTranscriptBackgroundTaskDriver/ { exit }
    { print }
' "$ROOT/Briefeed/Core/Transcription/RadioTranscriptBackgroundTaskDriver.swift" \
    | sed '$d' > "$BUILD/Sources/RadioTranscriptBackgroundContracts.swift"
for file in RadioSessionCoordinatorRestoreTests RadioQueueBuilderTests RadioPlaybackStateTests RadioEmptyStateTests RadioSleepTimerTests RadioSessionStoreTests; do
    cp "$ROOT/BriefeedTests/Radio/$file.swift" "$BUILD/Tests/"
done
# The add-feed workflow is SwiftUI/Core Data composition, not portable state.
awk '
    /^    @Test func successfulAddWorkflowReconcilesFirstSourceWithoutAnotherRefresh/ { skip_workflow = 1 }
    /^    private func makeCoordinator/ { skip_workflow = 0 }
    !skip_workflow { print }
' "$ROOT/BriefeedTests/Radio/RadioSourceConfigurationTests.swift" > "$BUILD/Tests/RadioSourceConfigurationTests.swift"
awk '
    /^    @Test func backgroundForceSavesActiveRadioTransportPositionAndBriefWithoutStoppingAudio/ { skip_transport = 1 }
    /^    private func delayedInitialRefresh/ { skip_transport = 0 }
    !skip_transport { print }
' "$ROOT/BriefeedTests/Radio/RadioAppLifecycleTests.swift" > "$BUILD/Tests/RadioAppLifecycleTests.swift"
cp "$ROOT/BriefeedTests/Transcription/RadioTranscriptCoordinatorTests.swift" "$BUILD/Tests/"
for file in "$ROOT"/Briefeed/Core/AdDetection/*.swift; do
    if [ -f "$file" ]; then cp "$file" "$BUILD/Sources/"; fi
done
for file in "$ROOT"/BriefeedTests/AdDetection/*.swift; do
    if [ -f "$file" ]; then cp "$file" "$BUILD/Tests/"; fi
done
xcrun swift test --package-path "$BUILD" \
    --scratch-path "${RADIO_HOST_BUILD_PATH:-${TMPDIR:-/tmp}/briefeed-radio-startup-host-build}" \
    --build-system native --disable-index-store --disable-keychain --disable-netrc --jobs 2 "$@"
