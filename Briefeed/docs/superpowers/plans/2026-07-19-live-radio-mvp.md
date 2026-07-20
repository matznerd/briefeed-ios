# Briefeed Live Radio MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a distribution-candidate iOS build whose default Radio tab restores and deterministically advances a persisted source-ordered podcast session, supports opt-in cold-launch autoplay, 10-second transport controls, persisted speed, sleep timing, accessible compact navigation, and reliable background and remote playback without depending on Reddit or article generation.

**Architecture:** Add a Radio-only domain beside the existing Brief `QueueCoordinator`: a pure queue builder, a versioned UserDefaults session store, a Core Data repository, and a `@MainActor` `RadioSessionCoordinator`. `UnifiedAudioPlayer` projects either Brief or Radio into one single-item `SwiftAudioExService`; only the active high-level coordinator owns navigation and completion. RSS refresh publishes per-source results into the Radio coordinator, while deterministic debug fixtures and a thin adapter use the shared simulator fleet without touching human-owned devices.

**Tech Stack:** Swift 6, SwiftUI, Combine, Core Data, Codable/UserDefaults, CryptoKit, Network/NWPathMonitor, AVFoundation, MediaPlayer, SwiftAudioEx, Swift Testing, XCTest/XCUITest, and `/Users/me/ericode/skills/app-testing`.

## Global Constraints

- Work from `/Users/me/ericode/briefeed-app/briefeed-ios/Briefeed` on the current feature branch; inspect `git status` before every commit and preserve unrelated changes.
- The deployment target remains iOS 18.2. Native Liquid Glass APIs are availability-gated to iOS 26 and later; iOS 18.2 through 25 use adaptive Material fallback.
- Radio remains independent of Reddit discovery, article summarization, Gemini TTS, and any future Supabase or Render backend.
- `QueueCoordinator` remains the single source of truth for Brief only. `RadioSessionCoordinator` is the single source of truth for Radio only.
- Core Data remains authoritative for RSS sources, episode metadata, normalized progress, and completion. `briefeed_radio_session_v1` remains authoritative for Radio order and seconds-based resume position.
- Autoplay uses the existing `autoPlayLiveNewsOnOpen` key, defaults Off, and runs once per process cold launch only. When no local episode exists, its deferred online-refresh opportunity lasts at most 60 foreground seconds and is canceled by inactive/background or any manual playback command.
- Playback speed uses the canonical `playbackSpeed` key and exactly `0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0`.
- In-app and remote skip intervals are exactly 10 seconds. Radio Previous is disabled.
- Manual Next defers the current partial episode; it never marks the episode complete.
- Completion is crash-consistent: save Core Data completion first, then remove and persist the Radio entry.
- Sleep timer values are Off, End of Episode, 10, 20, 30, 45, 60, and exact Custom 1 through 180 minutes. Sleep state does not survive process termination.
- Production behavior never depends on live publisher feeds in automated tests.
- All simulator commands use the repo adapter and an exact owned UUID. Never choose the first simulator, run `simctl shutdown all`, erase an unowned device, or open Simulator.app unless `SIMULATOR_GUI=1`.
- The shared `/Users/me/ericode/skills/app-testing` engine is authoritative for simulator lifecycle. A completed lane touches its lease and releases its use lock but leaves the owned simulator booted for warm reuse; only the engine's lease-aware GC shuts down or deletes it.
- An exit status of `75` from the simulator adapter is infrastructure capacity or routing failure, not a product failure.
- New Swift files are discovered by the existing file-system-synchronized Xcode groups; do not churn `project.pbxproj` unless Xcode proves an exception is required.
- Each task follows red, green, refactor and ends in its own reviewable commit.
- A red test that references a not-yet-created symbol must first use `make radio-compile`; it must not claim a simulator. Claim an owned simulator lane only after the test target compiles and a behavioral assertion can fail at runtime.
- Tasks 7 and 8 land back-to-back in one implementation session. Do not publish, release, or pause the migration with the temporary nonpersisted Live News compatibility commit as the branch endpoint.

## File Map

**Radio domain**

- Create `Briefeed/Core/Radio/RadioModels.swift`: value types, states, intents, failure and sleep models.
- Create `Briefeed/Core/Radio/RadioSessionStore.swift`: versioned Codable snapshot validation and debounced/forced persistence.
- Create `Briefeed/Core/Radio/RadioQueueBuilder.swift`: pure initial build, restore, partitioning, and reconciliation.
- Create `Briefeed/Core/Radio/RadioEpisodeRepository.swift`: protocol plus Core Data implementation and crash-consistent completion.
- Create `Briefeed/Core/Radio/RadioSessionCoordinator.swift`: Radio state machine and public commands.
- Create `Briefeed/Core/Radio/RadioNetworkMonitor.swift`: injectable connectivity protocol and NWPathMonitor implementation.
- Create `Briefeed/Core/Radio/RadioServiceContainer.swift`: one lazy production composition root plus pre-resolution DEBUG override seam.

**RSS and playback integration**

- Create `Briefeed/Core/Services/RSS/RSSEpisodeIdentity.swift`: canonical enclosure identity and deterministic fallback ID.
- Modify `Briefeed/Core/Services/RSS/RSSParser.swift`: reject malformed identity and dates instead of using `Date()`.
- Modify `Briefeed/Core/Services/RSS/RSSAudioService.swift`: one refresh schedule and structured per-source results.
- Modify `Briefeed/Core/Models/RSS/RSSFeed+CoreDataClass.swift`: exact staleness and candidate/retention policy.
- Modify `Briefeed/Core/Services/Audio/SwiftAudioExService.swift`: single-item transport and remote event ownership.
- Modify `Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift`: active playback mode router and Radio projection.
- Modify `Briefeed/Core/ViewModels/AudioPlayerViewModelV2.swift`: Radio presentation bindings and canonical controls.

**App and UI**

- Modify `Briefeed/BriefeedApp.swift` and `Briefeed/BriefeedApp+RSSV2.swift`: one startup owner, restore/autoplay, lifecycle persistence, one active refresh poll.
- Modify `Briefeed/Core/Utilities/UserDefaultsManager.swift` and `UserDefaultsManager+RSS.swift`: speed migration and Radio autoplay naming.
- Create `Briefeed/Features/Radio/RadioHomeView.swift`: primary Radio experience and state-specific recovery actions.
- Create `Briefeed/Features/Navigation/AppTab.swift`, `RadioTabRail.swift`, and `AppBottomChrome.swift`: default Radio navigation and bottom-most mini-player.
- Modify `Briefeed/ContentView.swift`: hidden native tab bar, top-right Settings sheet, safe-area chrome.
- Modify `Briefeed/Features/Audio/MiniAudioPlayerV4.swift` and `ExpandedAudioPlayerV2.swift`: approved compact layout, scrubber, speed, sleep, and accessible controls.
- Modify `Briefeed/Features/Settings/SettingsView.swift`: Radio settings at the top of Audio.
- Modify `Briefeed/Core/Utilities/AccessibilityIdentifiers.swift`: stable Radio UI test identifiers.

**Tests and operations**

- Create the exact `BriefeedTests/Radio/` test files named by Tasks 1 through 12: runtime, store, speed, identity, refresh, builder, repository, coordinator restore, empty state, playback state, sleep, remote policy, completion routing, unified playback, Brief isolation, lifecycle, presentation, and fixture seeding.
- Create `BriefeedUITests/RadioUITests.swift`: deterministic launch, playback, relaunch, and accessibility flows.
- Create `Briefeed/Core/Debug/RadioFixtureSeeder.swift`: debug-only Core Data and generated local audio fixtures.
- Extend `Briefeed/Core/Utilities/AppRuntime.swift` and `Persistence.swift`: isolated deterministic UI-test store.
- Create `skills/app-testing/{SKILL.md,config.sh}` and `skills/app-testing/scripts/{build-install.sh,radio-fixtures.sh,run-radio.sh,radio-smoke.sh}`: thin shared-fleet adapter.
- Modify `Makefile`: obvious `radio-*` targets.

---

### Task 1: Safe Simulator Lane and Deterministic Test Store

**Files:**
- Create: `skills/app-testing/config.sh`
- Create: `skills/app-testing/SKILL.md`
- Create: `skills/app-testing/scripts/build-install.sh`
- Create: `skills/app-testing/scripts/run-radio.sh`
- Modify: `Makefile`
- Modify: `Briefeed/Core/Utilities/AppRuntime.swift`
- Modify: `Briefeed/Persistence.swift`
- Test: `BriefeedTests/Radio/RadioRuntimeTests.swift`

**Interfaces:**
- Consumes: shared functions in `/Users/me/ericode/skills/app-testing/scripts/sim-lib.sh`.
- Produces: `AppRuntime.radioFixtureScenario: String?`, `AppRuntime.shouldResetRadioFixtureStore: Bool`, `PersistenceController.init(inMemory:storeURL:resetStore:)`, and `bash skills/app-testing/scripts/run-radio.sh <lane> <unit|ui|smoke>`.

- [ ] **Step 1: Write the failing runtime tests**

Create `RadioRuntimeTests.swift` with an injected environment seam rather than mutating process-global values:

```swift
import Foundation
import Testing
@testable import Briefeed

@Suite("Radio runtime")
struct RadioRuntimeTests {
    @Test func fixtureArgumentsSelectScenarioAndIsolatedStore() {
        let runtime = AppRuntime.Configuration(
            arguments: ["Briefeed", "-briefeed-radio-fixture", "partial"],
            environment: ["BRIEFEED_RADIO_RESET_STORE": "1"]
        )

        #expect(runtime.radioFixtureScenario == "partial")
        #expect(runtime.shouldResetRadioFixtureStore)
        #expect(runtime.shouldSkipAutomaticStartupWork)
        #expect(runtime.usesIsolatedRadioStore)
    }

    @Test func productionArgumentsUseProductionStore() {
        let runtime = AppRuntime.Configuration(arguments: ["Briefeed"], environment: [:])
        #expect(runtime.radioFixtureScenario == nil)
        #expect(!runtime.usesIsolatedRadioStore)
    }

    @Test func existingHostedTestOverrideStillSkipsStartup() {
        let runtime = AppRuntime.Configuration(
            arguments: ["Briefeed"],
            environment: ["BRIEFEED_FORCE_HOSTED_XCTEST": "1"]
        )
        #expect(runtime.shouldSkipAutomaticStartupWork)
    }

    @Test func resettingExplicitStoreRemovesPreviouslySavedObjects() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Briefeed-RadioRuntime-\(UUID().uuidString).sqlite")
        defer {
            for url in [
                storeURL,
                URL(fileURLWithPath: storeURL.path + "-wal"),
                URL(fileURLWithPath: storeURL.path + "-shm")
            ] {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let initial = PersistenceController(storeURL: storeURL)
        let feed = Feed(context: initial.container.viewContext)
        feed.id = UUID()
        feed.name = "sentinel"
        try initial.container.viewContext.save()

        let reset = PersistenceController(storeURL: storeURL, resetStore: true)
        let request = Feed.fetchRequest()
        #expect(try reset.container.viewContext.count(for: request) == 0)
    }
}
```

- [ ] **Step 2: Run a simulator-free compile gate and verify the new test fails to compile**

Run:

```bash
xcodebuild build-for-testing \
  -project Briefeed.xcodeproj \
  -scheme Briefeed \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/briefeed-radio-compile \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO
```

Expected: failure naming the missing `AppRuntime.Configuration` type. This command claims no simulator.

- [ ] **Step 3: Add the runtime and persistence seams**

Add to `AppRuntime.swift`:

```swift
extension AppRuntime {
    struct Configuration: Equatable {
        let arguments: [String]
        let environment: [String: String]

        init(
            arguments: [String] = ProcessInfo.processInfo.arguments,
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) {
            self.arguments = arguments
            self.environment = environment
        }

        var radioFixtureScenario: String? {
            guard let index = arguments.firstIndex(of: "-briefeed-radio-fixture"),
                  arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }

        var shouldResetRadioFixtureStore: Bool {
            environment["BRIEFEED_RADIO_RESET_STORE"] == "1"
        }

        var usesIsolatedRadioStore: Bool { radioFixtureScenario != nil }

        var isHostedXCTestEnvironment: Bool {
            environment["BRIEFEED_FORCE_HOSTED_XCTEST"] == "1"
                || environment["XCTestConfigurationFilePath"] != nil
        }

        var shouldSkipAutomaticStartupWork: Bool {
            usesIsolatedRadioStore
                || environment["BRIEFEED_DISABLE_AUTOMATIC_STARTUP"] == "1"
                || isHostedXCTestEnvironment
        }
    }

    static let configuration = Configuration()
    static var isHostedXCTest: Bool {
        configuration.isHostedXCTestEnvironment
            || Bundle.allBundles.contains { bundle in
                let path = bundle.bundlePath
                return path.hasSuffix(".xctest") && !path.contains("UITests")
            }
    }
    static var radioFixtureScenario: String? { configuration.radioFixtureScenario }
    static var shouldResetRadioFixtureStore: Bool { configuration.shouldResetRadioFixtureStore }
    static var shouldSkipAutomaticStartupWork: Bool {
        configuration.shouldSkipAutomaticStartupWork || isHostedXCTest
    }
}
```

Change `PersistenceController` to accept an explicit store URL and delete only that store plus its `-wal`/`-shm` siblings when `resetStore` is true. Initialize `shared` with `Briefeed-RadioUITests.sqlite` under Application Support only when `AppRuntime.radioFixtureScenario != nil`; production continues using `Briefeed.sqlite` unchanged. Preserve the existing loaded-unit-test-bundle fallback and `BRIEFEED_FORCE_HOSTED_XCTEST` behavior.

- [ ] **Step 4: Add the thin fleet adapter**

`config.sh` must export:

```bash
#!/usr/bin/env bash
BRIEFEED_APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export BRIEFEED_APP_ROOT
export AGENT_SIM_PREFIX="Briefeed-Codex"
export AGENT_SIM_BUNDLE_ID="Matznerd.Briefeed"
export AGENT_SIM_STABLE_MAX_MAJOR=18
export AGENT_SIM_GOLDEN_INSTALL_HOOK='SIM_UUID=$GOLDEN_UUID bash "$BRIEFEED_APP_ROOT/skills/app-testing/scripts/build-install.sh"'
```

`run-radio.sh` must source, not copy, the shared engine and implement this exact ownership flow:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENGINE="$HOME/ericode/skills/app-testing/scripts"
export AGENT_SIM_CONFIG="$ROOT/skills/app-testing/config.sh"
source "$ENGINE/sim-lib.sh"

lane="$(printf '%s' "${1:?lane key required}" | tr -cs '[:alnum:]_.-' '-' | sed 's/^-*//;s/-*$//')"
mode="${2:?mode unit, ui, or smoke required}"
[[ -n "$lane" ]] || exit 75
[[ "$mode" == unit || "$mode" == ui || "$mode" == smoke ]] || exit 64

state_dir="$(sim_state_dir)"
mkdir -p "$state_dir"
lane_lock="$state_dir/.adapter-$lane.lock"
if ! mkdir "$lane_lock" 2>/dev/null; then
    holder="$(sed -n 's/^pid=//p' "$lane_lock/holder" 2>/dev/null | head -1)"
    if [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null; then
        echo "Radio lane $lane is owned by pid $holder" >&2
        exit 75
    fi
    age=$(( $(date +%s) - $(stat -f %m "$lane_lock" 2>/dev/null || echo 0) ))
    (( age >= 10 )) || exit 75
    rm -rf "$lane_lock"
    mkdir "$lane_lock" || exit 75
fi
printf 'pid=%s\n' "$$" > "$lane_lock/holder"

sim_uuid=""
state_file="$state_dir/$lane.env"
use_locked=0
cleanup() {
    rc=$?
    trap - EXIT INT TERM
    if [[ "$use_locked" == 1 ]]; then
        sim_lease_touch "$state_file"
        sim_use_unlock "$sim_uuid"
    fi
    rm -rf "$lane_lock"
    exit "$rc"
}
trap cleanup EXIT INT TERM

doctor_rc=0
bash "$ENGINE/sim-doctor.sh" --gc || doctor_rc=$?
[[ "$doctor_rc" == 0 || "$doctor_rc" == 10 ]] || exit 75

sim_uuid="$(sed -n 's/^SIM_UUID=//p' "$state_file" 2>/dev/null | tail -1)"
recorded_name="$(sed -n 's/^SIM_NAME=//p' "$state_file" 2>/dev/null | tail -1)"
sim_name=""
valid_claim=0
claim_exists=0
[[ -e "$state_file" ]] && claim_exists=1
if [[ "$claim_exists" == 1 && -n "$sim_uuid" ]] && sim_uuid_exists "$sim_uuid"; then
    sim_name="$(sim_field "$sim_uuid" name)"
    claims="$(sim_claims_for_uuid "$sim_uuid")"
    if [[ -n "$recorded_name" && "$recorded_name" == "$sim_name" \
          && "$sim_name" == "$AGENT_SIM_PREFIX-"* \
          && "$claims" == "$state_file" ]] \
          && ! sim_is_protected "$sim_uuid"; then
        valid_claim=1
    fi
fi

if [[ "$claim_exists" == 1 && "$valid_claim" != 1 ]]; then
    echo "Radio lane claim is malformed or not uniquely owned: $state_file" >&2
    exit 75
fi

if [[ "$valid_claim" != 1 ]]; then
    [[ "$doctor_rc" != 10 ]] || exit 75
    clone_output="$(bash "$ENGINE/sim-golden.sh" clone "$lane")" || {
        exit 75
    }
    sim_uuid="$(printf '%s\n' "$clone_output" | sed -n 's/^SIM_UUID=//p' | tail -1)"
    [[ -n "$sim_uuid" ]] || exit 75
    state_file="$state_dir/$lane.env"
    sim_name="$(sim_field "$sim_uuid" name)"
    recorded_name="$(sed -n 's/^SIM_NAME=//p' "$state_file" 2>/dev/null | tail -1)"
    claims="$(sim_claims_for_uuid "$sim_uuid")"
    [[ -n "$recorded_name" && "$recorded_name" == "$sim_name" ]] || exit 75
    [[ "$sim_name" == "$AGENT_SIM_PREFIX-"* ]] || exit 75
    [[ "$claims" == "$state_file" ]] || exit 75
    sim_is_protected "$sim_uuid" && exit 75
    sim_use_lock "$sim_uuid" "$$" "briefeed-$mode-$lane" || exit 75
    use_locked=1
else
    sim_lease_touch "$state_file"
    sim_use_lock "$sim_uuid" "$$" "briefeed-$mode-$lane" || exit 75
    use_locked=1
    if [[ "$(sim_field "$sim_uuid" state)" != Booted ]]; then
        [[ "$doctor_rc" != 10 ]] || exit 75
        sim_acquire_boot_slot || exit 75
        boot_rc=0
        sim_boot_start "$sim_uuid" || boot_rc=$?
        sim_unlock
        [[ "$boot_rc" == 0 ]] || exit 75
        sim_boot_ready "$sim_uuid" || exit 75
    fi
fi

derived="/tmp/briefeed-radio-$lane-derived-data"
case "$mode" in
unit)
    selector="${RADIO_TEST_SELECTOR:-BriefeedTests}"
    xcodebuild test -project "$ROOT/Briefeed.xcodeproj" -scheme Briefeed \
      -destination "platform=iOS Simulator,id=$sim_uuid" \
      -derivedDataPath "$derived" -parallel-testing-enabled NO \
      -maximum-concurrent-test-simulator-destinations 1 \
      -only-testing:"$selector"
    ;;
ui)
    xcodebuild test -project "$ROOT/Briefeed.xcodeproj" -scheme Briefeed \
      -destination "platform=iOS Simulator,id=$sim_uuid" \
      -derivedDataPath "$derived" -parallel-testing-enabled NO \
      -maximum-concurrent-test-simulator-destinations 1 \
      -only-testing:BriefeedUITests/RadioUITests
    ;;
smoke)
    SIM_UUID="$sim_uuid" DERIVED_DATA_PATH="$derived" \
      bash "$ROOT/skills/app-testing/scripts/radio-smoke.sh"
    ;;
esac
```

`build-install.sh` is the golden provisioning hook and always targets its supplied UUID:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${SIM_UUID:?SIM_UUID is required}"
ENGINE="$HOME/ericode/skills/app-testing/scripts"
export AGENT_SIM_CONFIG="$ROOT/skills/app-testing/config.sh"
source "$ENGINE/sim-lib.sh"
derived="${DERIVED_DATA_PATH:-/tmp/briefeed-radio-golden-derived-data}"
xcodebuild build -project "$ROOT/Briefeed.xcodeproj" -scheme Briefeed \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UUID" \
  -derivedDataPath "$derived" COMPILER_INDEX_STORE_ENABLE=NO
app_path="$(find "$derived/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name 'Briefeed.app' -print -quit)"
[[ -d "$app_path" ]] || { echo "Briefeed.app not found" >&2; exit 1; }
sim_install_if_changed "$SIM_UUID" "$app_path" "$AGENT_SIM_BUNDLE_ID"
```

- [ ] **Step 5: Add Makefile entry points and the repo runbook**

Add these Makefile entry points:

```make
APP_TEST_ENGINE := $(HOME)/ericode/skills/app-testing/scripts
RADIO_SIM_CONFIG := $(CURDIR)/skills/app-testing/config.sh

.PHONY: radio-compile radio-golden radio-unit radio-ui radio-smoke sim-doctor sim-status
radio-compile:
	xcodebuild build-for-testing -project Briefeed.xcodeproj -scheme Briefeed -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/briefeed-radio-compile CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO

radio-golden:
	AGENT_SIM_CONFIG=$(RADIO_SIM_CONFIG) bash $(APP_TEST_ENGINE)/sim-doctor.sh --gc
	AGENT_SIM_CONFIG=$(RADIO_SIM_CONFIG) bash $(APP_TEST_ENGINE)/sim-golden.sh refresh

radio-unit:
	bash skills/app-testing/scripts/run-radio.sh radio-unit unit

radio-ui:
	bash skills/app-testing/scripts/run-radio.sh radio-ui ui

radio-smoke:
	bash skills/app-testing/scripts/run-radio.sh radio-smoke smoke

sim-doctor:
	AGENT_SIM_CONFIG=$(RADIO_SIM_CONFIG) bash $(APP_TEST_ENGINE)/sim-doctor.sh --gc

sim-status:
	bash $(APP_TEST_ENGINE)/sim-status.sh
```

`SKILL.md` must name the shared engine as authoritative, document exit `75`, headless default, lane keys, exact commands, and the prohibition on broad simulator actions.

- [ ] **Step 6: Verify the adapter and runtime test**

Run:

```bash
make radio-compile
make radio-golden
RADIO_TEST_SELECTOR=BriefeedTests/RadioRuntimeTests \
  bash skills/app-testing/scripts/run-radio.sh radio-runtime unit
```

Expected: compile succeeds, the golden reports a non-empty `GOLDEN_UUID=<owned UUID>`, and the test reports `RadioRuntimeTests` passed. The adapter releases the exact lane's use lock and leaves that owned simulator booted for warm reuse; lease-aware GC reaps it later. If capacity or pressure returns `75`, record infrastructure blocked and do not run a different unowned simulator.

- [ ] **Step 7: Commit**

```bash
git add Makefile skills/app-testing Briefeed/Core/Utilities/AppRuntime.swift Briefeed/Persistence.swift BriefeedTests/Radio/RadioRuntimeTests.swift
git commit -m "test: add safe Radio simulator lanes"
```

---

### Task 2: Radio Models, Snapshot Validation, and Speed Migration

**Files:**
- Create: `Briefeed/Core/Radio/RadioModels.swift`
- Create: `Briefeed/Core/Radio/RadioSessionStore.swift`
- Modify: `Briefeed/Core/Utilities/UserDefaultsManager.swift`
- Modify: `Briefeed/Core/Utilities/UserDefaultsManager+RSS.swift`
- Test: `BriefeedTests/Radio/RadioSessionStoreTests.swift`
- Test: `BriefeedTests/Radio/PlaybackSpeedSettingsTests.swift`

**Interfaces:**
- Produces: `RadioEpisodeKey`, `RadioQueueEntry`, `PersistedRadioSession`, `RadioSessionState`, `RadioSleepTimer`, `RadioPlaybackIntent`, `RadioSessionStoreProtocol`, `RadioSessionStore`, and `PlaybackSpeedPolicy`.

- [ ] **Step 1: Write failing snapshot and speed tests**

Cover exact schema acceptance, corrupt decode, more than 200 entries, duplicate repair, non-finite and negative position repair, known-duration clamping, persisted playing normalization, failed cold-launch reset, invalid current selection, legacy speed migration, non-finite normalization, clamping, nearest value, and lower tie behavior.

Representative tests:

```swift
@Test func restoreRepairsTransientStateAndCurrentKey() throws {
    let failed = RadioQueueEntry(
        key: .init(feedID: "bbc", episodeID: "b"),
        positionSeconds: .nan,
        disposition: .failedThisSession,
        playbackFailureCount: 2,
        lastPlaybackError: "timeout"
    )
    let snapshot = PersistedRadioSession(
        schemaVersion: 1,
        entries: [failed],
        currentKey: .init(feedID: "missing", episodeID: "x"),
        savedAt: .distantPast
    )

    let restored = try RadioSessionStore.validate(snapshot, durations: [failed.key: 300])
    #expect(restored.entries[0].positionSeconds == 0)
    #expect(restored.entries[0].disposition == .pending)
    #expect(restored.entries[0].playbackFailureCount == 0)
    #expect(restored.currentKey == failed.key)
}

@Test func speedMigrationUsesLegacyOnlyWhenCanonicalIsAbsent() {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.set(20.0, forKey: UserDefaultsKey.rssPlaybackSpeed.rawValue)
    let speed = PlaybackSpeedPolicy.loadAndMigrate(defaults: defaults)
    #expect(speed == 3.0)
    #expect(defaults.float(forKey: UserDefaultsKey.playbackSpeed.rawValue) == 3.0)
}
```

- [ ] **Step 2: Run and verify red**

Run `make radio-compile`.

Expected: compile failure naming `RadioEpisodeKey` and `PlaybackSpeedPolicy`.

- [ ] **Step 3: Implement focused value types**

Use these canonical declarations:

```swift
struct RadioEpisodeKey: Codable, Hashable, Sendable {
    let feedID: String
    let episodeID: String
}

enum RadioEntryDisposition: String, Codable, Sendable {
    case pending, playing, deferred, failedThisSession
}

struct RadioQueueEntry: Codable, Identifiable, Equatable, Sendable {
    var id: RadioEpisodeKey { key }
    let key: RadioEpisodeKey
    var positionSeconds: TimeInterval
    var disposition: RadioEntryDisposition
    var playbackFailureCount: Int
    var lastPlaybackError: String?
}

struct PersistedRadioSession: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    var entries: [RadioQueueEntry]
    var currentKey: RadioEpisodeKey?
    var savedAt: Date
}

enum RadioSessionState: Equatable, Sendable {
    case idle, restoring, refreshing, readyPaused, loading, playing
    case pausedByUser, waitingForNetwork, noSources, exhausted
    case failed(RadioFailure)
}

enum RadioSleepTimer: Equatable, Sendable {
    case off, deadline(Date), endOfEpisode
}

enum ConnectivityStatus: Equatable, Sendable {
    case unknown, online, offline
}

enum RSSUpdateFrequencyValue: String, Codable, Sendable {
    case hourly, daily
}

enum RadioFailure: Equatable, Sendable {
    case allSourcesUnavailable
    case playback(String)
    case persistence(String)
}

struct RadioPlaybackRequest: Equatable, Sendable {
    let key: RadioEpisodeKey
    let url: URL
    let title: String
    let source: String
    let positionSeconds: TimeInterval
}

enum RadioPlaybackIntent: Equatable, Sendable {
    case play(RadioPlaybackRequest)
    case pause

    var key: RadioEpisodeKey? {
        guard case .play(let request) = self else { return nil }
        return request.key
    }
}

@MainActor
protocol RadioSessionStoreProtocol: AnyObject {
    func load(durations: [RadioEpisodeKey: TimeInterval]) throws -> PersistedRadioSession?
    func saveDebounced(_ session: PersistedRadioSession)
    func saveNow(_ session: PersistedRadioSession) throws
    func clear()
}
```

`RadioSessionStore` uses key `briefeed_radio_session_v1`, a supplied `UserDefaults`, `JSONEncoder`, and `JSONDecoder`. Entry-level invalidity is repaired; only decoding, schema, or count corruption discards the entire snapshot. Serialize every write on the main actor with a monotonically increasing `writeGeneration`. A 10-second debounced save captures its generation and writes only if it is still current. `saveNow(_:)` and `clear()` increment the generation and cancel the pending Task before writing/removing, so an older progress debounce cannot overwrite a newer pause, Next, completion, or lifecycle snapshot.

Add this race test:

```swift
@MainActor
protocol RadioDebounceScheduling: AnyObject {
    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () -> Void)
    func cancel()
}

@Test func forcedSaveInvalidatesOlderDebounce() async throws {
    let scheduler = TestDebounceScheduler()
    let store = RadioSessionStore(defaults: defaults, scheduler: scheduler)
    store.saveDebounced(session(current: keyA, position: 10))
    try store.saveNow(session(current: keyB, position: 40))
    scheduler.fireCanceledActionAnyway()
    #expect(try store.load(durations: [:])?.currentKey == keyB)
    #expect(try store.load(durations: [:])?.entries.first?.positionSeconds == 40)
}
```

The production scheduler owns one cancellable `Task.sleep(for: .seconds(10))`. The adversarial test scheduler records cancellation but deliberately retains the old closure and exposes `fireCanceledActionAnyway()`; passing this test proves the generation guard, not merely successful cancellation.

- [ ] **Step 4: Implement one canonical speed policy**

```swift
enum PlaybackSpeedPolicy {
    static let supported: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    static func normalize(_ raw: Float) -> Float {
        guard raw.isFinite else { return 1.0 }
        let clamped = min(3.0, max(0.5, raw))
        return supported.min { lhs, rhs in
            let left = abs(lhs - clamped)
            let right = abs(rhs - clamped)
            return left == right ? lhs < rhs : left < right
        } ?? 1.0
    }

    static func loadAndMigrate(defaults: UserDefaults) -> Float {
        let canonical = UserDefaultsKey.playbackSpeed.rawValue
        let legacy = UserDefaultsKey.rssPlaybackSpeed.rawValue
        let raw: Float
        if defaults.object(forKey: canonical) != nil {
            raw = defaults.float(forKey: canonical)
        } else if defaults.object(forKey: legacy) != nil {
            raw = defaults.float(forKey: legacy)
        } else {
            raw = 1.0
        }
        let normalized = normalize(raw)
        defaults.set(normalized, forKey: canonical)
        return normalized
    }
}
```

Call `loadAndMigrate` before `registerDefaults()` so registration-domain values cannot masquerade as a persisted canonical value. Only when the canonical key is absent does it read and normalize `rssPlaybackSpeed`. Remove the published `rssPlaybackSpeed` source of truth after migration and make all audio UI read `playbackSpeed`.

- [ ] **Step 5: Run focused tests and compile**

Run:

```bash
bash skills/app-testing/scripts/run-radio.sh radio-models unit
make radio-compile
```

Expected: both Radio suites pass; the generic simulator compile succeeds.

- [ ] **Step 6: Commit**

```bash
git add Briefeed/Core/Radio Briefeed/Core/Utilities/UserDefaultsManager.swift Briefeed/Core/Utilities/UserDefaultsManager+RSS.swift BriefeedTests/Radio
git commit -m "feat: add persisted Radio session model"
```

---

### Task 3: Deterministic RSS Identity and Structured Refresh Results

**Files:**
- Create: `Briefeed/Core/Services/RSS/RSSEpisodeIdentity.swift`
- Modify: `Briefeed/Core/Services/RSS/RSSParser.swift`
- Modify: `Briefeed/Core/Services/RSS/RSSAudioService.swift`
- Modify: `Briefeed/Core/Models/RSS/RSSFeed+CoreDataClass.swift`
- Modify: `Briefeed/BriefeedApp+RSSV2.swift`
- Test: `BriefeedTests/Radio/RSSEpisodeIdentityTests.swift`
- Test: `BriefeedTests/Radio/RSSRefreshPolicyTests.swift`

**Interfaces:**
- Produces: `RSSEpisodeIdentity.episodeID(guid:enclosureURL:publicationDate:)`, `RSSFeedRefreshResult`, `RSSRefreshBatchResult`, `RSSAudioService.refreshIfStale(now:)`, and `RSSAudioService.refreshAll(now:)`.

- [ ] **Step 1: Write identity and cadence tests**

```swift
@Test func fallbackIdentityCanonicalizesWithoutChangingPlaybackURL() throws {
    let original = "HTTPS://Example.COM:443/show/one.mp3?b=2&a=1#frag"
    let date = Date(timeIntervalSince1970: 1_720_000_000.9)
    let id1 = try RSSEpisodeIdentity.episodeID(guid: "", enclosureURL: original, publicationDate: date)
    let id2 = try RSSEpisodeIdentity.episodeID(
        guid: nil,
        enclosureURL: "https://example.com/show/one.mp3?a=1&b=2",
        publicationDate: Date(timeIntervalSince1970: 1_720_000_000.1)
    )
    #expect(id1 == id2)
}

@Test func missingGuidAndPublicationDateIsRejected() {
    #expect(throws: RSSEpisodeIdentity.Error.missingStableIdentity) {
        try RSSEpisodeIdentity.episodeID(
            guid: nil,
            enclosureURL: "https://example.com/audio.mp3",
            publicationDate: nil
        )
    }
}

@Test func shiftedPublicationDateReusesCanonicalEnclosureRecord() async throws {
    let original = try await ingestFallbackEpisode(url: "https://example.com/hourly.mp3", date: now)
    original.isListened = true
    original.listenedDate = now
    try context.save()
    let corrected = try await ingestFallbackEpisode(
        url: "https://example.com/hourly.mp3",
        date: now.addingTimeInterval(300)
    )
    #expect(corrected.objectID == original.objectID)
    #expect(corrected.isListened)
}

@Test func stalenessUsesThirtyMinutesAndSixHours() {
    let now = Date(timeIntervalSince1970: 10_000_000)
    #expect(RSSRefreshPolicy.isStale(.hourly, lastSuccess: now.addingTimeInterval(-1_801), now: now))
    #expect(!RSSRefreshPolicy.isStale(.hourly, lastSuccess: now.addingTimeInterval(-1_799), now: now))
    #expect(RSSRefreshPolicy.isStale(.daily, lastSuccess: now.addingTimeInterval(-21_601), now: now))
}
```

- [ ] **Step 2: Verify red**

Run `make radio-compile`.

Expected: compile failure naming the new identity and refresh types.

- [ ] **Step 3: Implement identity and parser rejection**

Use `URLComponents` and CryptoKit SHA-256. Require HTTP or HTTPS, lowercase scheme/host, remove fragment/default port, preserve normalized path, sort query items by name then value, and hash `canonicalURL + "|" + Int(publicationDate.timeIntervalSince1970)`. Return trimmed GUID unchanged when present. Keep the original `audioUrl` in `ParsedRSSEpisode`. In `RSSParser`, replace the current synthesized GUID and `parseDate(...) ?? Date()` with a throwing construction that drops malformed items and records their parse rejection count. Before inserting a fallback-ID episode, fetch the same feed plus canonical enclosure. Reuse the existing durable ID and completion/progress state when a publisher merely shifts `pubDate`; update only safe metadata. The canonical-enclosure uniqueness check therefore protects history even though the deterministic fallback hash includes publication time.

- [ ] **Step 4: Return per-source refresh outcomes**

Add:

```swift
enum RSSFeedRefreshOutcome: Equatable, Sendable {
    case success(insertedEpisodeIDs: [String])
    case failed(message: String)
    case skippedFresh(lastSuccessfulRefresh: Date)
    case skippedOffline
}

struct RSSFeedRefreshResult: Equatable, Sendable {
    let feedID: String
    let outcome: RSSFeedRefreshOutcome
}

struct RSSRefreshBatchResult: Equatable, Sendable {
    let results: [RSSFeedRefreshResult]
    var successfulSourceEvidenceCount: Int {
        results.reduce(into: 0) { count, result in
            switch result.outcome {
            case .success, .skippedFresh:
                count += 1
            case .failed, .skippedOffline:
                break
            }
        }
    }
    var attemptedFailureCount: Int {
        results.reduce(into: 0) { count, result in
            if case .failed = result.outcome { count += 1 }
        }
    }
}
```

Make `refreshFeed` return a result. Update `lastFetchDate` only after parse and Core Data save succeed. Keep `lastError` only as a compatibility projection of the newest failure; Radio consumes the result array. Sort feeds by priority then ID before refreshing.

Keep a source-compatible `@discardableResult refreshAllFeeds() async -> RSSRefreshBatchResult` adapter for existing manual Brief and Live News refresh callers; it delegates once to `refreshAll(now: Date())` and owns no timer. The startup caller is removed in Task 9. This avoids forcing unrelated view migration into Task 3 while every commit remains buildable.

Change `initializeDefaultFeedsIfNeeded()` into local-only `ensureDefaultFeedsExist()`: it inserts and saves missing default feed rows but never refreshes them. In this same task, update every production caller in `BriefeedApp+RSSV2.swift` to the local-only name so Task 3 compiles; do not leave a wrapper that still performs a network request. Network refresh occurs only through the structured refresh methods after Radio restoration. `refreshIfStale` returns `.skippedFresh(lastSuccessfulRefresh:)` only when the feed has a non-nil prior successful `lastFetchDate`; this counts as successful-source evidence for a truly exhausted session.

- [ ] **Step 5: Remove duplicate timers and establish one poll owner**

Remove `RSSAudioService.refreshTimer`, `setupAutoRefresh()`, and the timer in `BriefeedApp+RSSV2`. Add `refreshIfStale(now:)` and have the app own one cancellable 15-minute active-scene poll in Task 9. Change hourly `RSSUpdateFrequency.checkInterval` to 1,800 seconds and daily to 21,600 seconds; make `RSSFeed.isStale` call the same policy.

- [ ] **Step 6: Run tests and compile**

Run the focused identity/refresh suites and `make radio-compile`. Include a relaunch test where every enabled source is skipped fresh and no eligible episode remains; the result must be `exhausted`, not an unresolved or failed state.

Expected: malformed items are rejected, canonical duplicates match, cadence boundaries pass, no `Timer.scheduledTimer` remains in `RSSAudioService` or `BriefeedApp+RSSV2`, and `rg -n 'initializeDefaultFeedsIfNeeded|setupAutoRefresh' Briefeed` returns no production matches.

- [ ] **Step 7: Commit**

```bash
git add Briefeed/Core/Services/RSS Briefeed/Core/Models/RSS/RSSFeed+CoreDataClass.swift Briefeed/BriefeedApp+RSSV2.swift BriefeedTests/Radio
git commit -m "fix: make Radio feed refresh deterministic"
```

---

### Task 4: Core Data Radio Repository and Pure Queue Builder

**Files:**
- Create: `Briefeed/Core/Radio/RadioEpisodeRepository.swift`
- Create: `Briefeed/Core/Radio/RadioQueueBuilder.swift`
- Test: `BriefeedTests/Radio/RadioQueueBuilderTests.swift`
- Test: `BriefeedTests/Radio/CoreDataRadioEpisodeRepositoryTests.swift`

**Interfaces:**
- Consumes: model and identity types from Tasks 2 and 3.
- Produces: `RadioEpisodeCandidate`, `RadioEpisodeRepository`, `CoreDataRadioEpisodeRepository`, `RadioQueueBuilder.buildInitial`, `restore`, and `reconcile`.

- [ ] **Step 1: Write pure ordering and reconciliation tests**

Cover: feed priority then feed ID; per-feed publication descending then episode ID; one newest per source; 2-hour/24-hour candidate freshness; 24-hour/7-day retention; no older backfill when newest is completed; duplicate key and canonical enclosure; restored current preservation; partition order; source reorder affecting pending only; append without insertion before current; manual-deferred order; failed entries ineligible; 200-entry cap supplied by the store.

```swift
@Test func reconcilePreservesCurrentAndPartitionsNewPendingBeforeDeferred() {
    let current = candidate("npr", "1", priority: 1, date: now)
    let deferred = candidate("bbc", "old", priority: 2, date: now.addingTimeInterval(-60))
    let fresh = candidate("bbc", "new", priority: 2, date: now)
    let snapshot = session(entries: [
        entry(current.key, .playing),
        entry(deferred.key, .deferred)
    ], current: current.key)

    let result = RadioQueueBuilder(now: now).reconcile(snapshot: snapshot, candidates: [current, deferred, fresh])
    #expect(result.entries.map(\.key) == [current.key, fresh.key, deferred.key])
    #expect(result.currentKey == current.key)
}
```

- [ ] **Step 2: Verify red**

Run `make radio-compile`; expect missing `RadioEpisodeCandidate` and builder symbols. Claim the `radio-builder` lane only after the target compiles.

- [ ] **Step 3: Implement the pure candidate boundary**

```swift
struct RadioEpisodeCandidate: Equatable, Sendable {
    let key: RadioEpisodeKey
    let originalPlaybackURL: URL
    let canonicalEnclosureURL: String
    let title: String
    let sourceName: String
    let publicationDate: Date
    let durationSeconds: TimeInterval?
    let normalizedCoreDataProgress: Double
    let isCompleted: Bool
    let sourcePriority: Int
    let sourceFrequency: RSSUpdateFrequencyValue
}

@MainActor
protocol RadioEpisodeRepository: AnyObject {
    func candidates() throws -> [RadioEpisodeCandidate]
    func candidate(for key: RadioEpisodeKey) throws -> RadioEpisodeCandidate?
    func saveProgress(key: RadioEpisodeKey, seconds: TimeInterval, duration: TimeInterval?) throws
    func markCompleted(key: RadioEpisodeKey, at date: Date) throws
}
```

Use a Sendable value enum rather than exposing Core Data managed objects outside the repository. Fetch exact `(feedId, id)`. Save normalized Core Data progress only when duration is finite and greater than zero.

- [ ] **Step 4: Implement the builder partitions**

The builder returns a repaired `PersistedRadioSession`. It keeps current, recomputes pending order, preserves deferred order, preserves failed order, selects pending before deferred, and never selects failed. Every comparison has the spec tie-breaker. No builder method reads `Date()`; inject `now`.

- [ ] **Step 5: Prove crash-consistent repository completion**

Use an in-memory `PersistenceController` test with an injected `NSManagedObjectContext`. Assert that `markCompleted` sets all three fields and saves. Inject a context-save failure using a test repository wrapper; this test becomes the coordinator safety gate in Task 6.

- [ ] **Step 6: Run focused tests and commit**

```bash
bash skills/app-testing/scripts/run-radio.sh radio-builder unit
git add Briefeed/Core/Radio BriefeedTests/Radio
git commit -m "feat: add deterministic Radio queue builder"
```

Expected: pure and hosted repository suites pass.

---

### Task 5: Radio Session Coordinator Restore, Autoplay, and Empty-State Precedence

**Files:**
- Create: `Briefeed/Core/Radio/RadioSessionCoordinator.swift`
- Test: `BriefeedTests/Radio/RadioSessionCoordinatorRestoreTests.swift`
- Test: `BriefeedTests/Radio/RadioEmptyStateTests.swift`

**Interfaces:**
- Consumes: `RadioSessionStoreProtocol`, `RadioEpisodeRepository`, `RadioQueueBuilder`, `RSSRefreshBatchResult`.
- Produces: `RadioSessionCoordinator.restore(autoplayEnabled:)`, intent-returning `applyRefresh(_:)`, `beginCurrent()`, published `state`, `entries`, `currentKey`, `currentEpisode`, `sourceFailures`, and `canPlayNext`.

- [ ] **Step 1: Write coordinator tests with fakes**

Use deterministic `FakeRadioSessionStore`, `FakeRadioEpisodeRepository`, and injected `now`. Cover paused restore, autoplay resume intent, autoplay once per process, deferred autoplay still eligible at 59 seconds and expired at 60 seconds, manual playback canceling the opportunity, invalid current repair, local playback before refresh, and exact empty precedence: active playback, no sources, offline, unknown connectivity, refreshing, all attempted failed, then exhausted only after at least one successful or prior-success-backed skipped-fresh result.

Also cover explicit episode selection: selecting an eligible repository candidate defers the prior partial current entry, inserts or moves the selected key to current without duplication, force-saves, and returns its restored-position play request. An ineligible, completed, missing, or expired key is a no-op.

```swift
@Test func allSourcesFailedIsNotCaughtUp() async {
    let coordinator = makeCoordinator(candidates: [], online: true)
    await coordinator.restore(autoplayEnabled: true)
    coordinator.refreshStarted(enabledSourceCount: 2)
    coordinator.applyRefresh(.init(results: [
        .init(feedID: "npr", outcome: .failed(message: "503")),
        .init(feedID: "bbc", outcome: .failed(message: "timeout"))
    ]))
    #expect(coordinator.state == .failed(.allSourcesUnavailable))
    #expect(coordinator.state != .exhausted)
}
```

- [ ] **Step 2: Verify red**

Run `make radio-compile`; expect the missing `RadioSessionCoordinator` failure. Claim a simulator only after the coordinator surface compiles and the behavioral assertions are red.

- [ ] **Step 3: Implement coordinator dependency injection and restore**

```swift
@MainActor
protocol RadioSessionCoordinating: AnyObject {
    var state: RadioSessionState { get }
    var entries: [RadioQueueEntry] { get }
    var currentKey: RadioEpisodeKey? { get }
    var currentEpisode: RadioEpisodeCandidate? { get }
    var sourceFailures: [String: String] { get }
    var sleepTimer: RadioSleepTimer { get }
    var hasPendingColdLaunchAutoplay: Bool { get }
    var canPlayNext: Bool { get }
    var statePublisher: AnyPublisher<RadioSessionState, Never> { get }
    var entriesPublisher: AnyPublisher<[RadioQueueEntry], Never> { get }
    var currentEpisodePublisher: AnyPublisher<RadioEpisodeCandidate?, Never> { get }
    var sourceFailuresPublisher: AnyPublisher<[String: String], Never> { get }
    var sleepTimerPublisher: AnyPublisher<RadioSleepTimer, Never> { get }
    var canPlayNextPublisher: AnyPublisher<Bool, Never> { get }

    func restore(autoplayEnabled: Bool) async -> RadioPlaybackIntent?
    func refreshStarted(enabledSourceCount: Int)
    func applyRefresh(_ result: RSSRefreshBatchResult) -> RadioPlaybackIntent?
    func beginCurrent() -> RadioPlaybackIntent?
    func selectEpisode(_ key: RadioEpisodeKey) -> RadioPlaybackIntent?
    func cancelPendingColdLaunchAutoplay()
}
```

Implement `RadioSessionCoordinator` as an `ObservableObject` conforming to this surface, with each property `@Published private(set)` and the cold-launch opportunity flag `private(set)`.

`restore` reads local candidates and snapshot without awaiting network. It emits `.play` with a `RadioPlaybackRequest` built from the selected candidate and restored seconds position once only when autoplay is enabled and an eligible current item exists. If autoplay is enabled but no local entry exists, record an injected-clock deadline exactly 60 seconds after restore and keep one cold-launch opportunity pending only while the scene remains active. `applyRefresh` may return one play intent only before that deadline when the initial refresh appends an eligible entry; it then consumes the opportunity. The deadline, a terminal initial refresh with no entry, inactive/background, or any manual playback command consumes it. Later foreground, timer, and manual refreshes never autoplay. A refresh can append entries but cannot replace or interrupt current playback.

Implement `selectEpisode(_:)` in this task using the same eligibility and persistence rules covered by Step 1. `beginCurrent`, `selectEpisode`, and the explicit cancellation command consume the deferred autoplay opportunity before returning. Expose the six explicit publishers by erasing the matching `@Published` projections so injected consumers and test fakes never depend on concrete coordinator storage.

- [ ] **Step 4: Encode empty precedence as one tested function**

Create this private function and implement its ordered guards exactly as the spec states:

```swift
private func resolveNoPlayableEntry(
    enabledSourceCount: Int,
    connectivityStatus: ConnectivityStatus,
    isRefreshing: Bool,
    successfulSourceEvidenceCount: Int,
    attemptedFailureCount: Int
) -> RadioSessionState
```

The failed branch requires `attemptedFailureCount == enabledSourceCount` with no success evidence; one source failure among several enabled sources is not `allSourcesUnavailable`. The `exhausted` branch requires `successfulSourceEvidenceCount > 0`; a `.skippedFresh(lastSuccessfulRefresh:)` result supplies this evidence. With no local playable entry, `.unknown` connectivity resolves to the nonterminal `.refreshing`/checking-connection presentation and can never resolve to `.exhausted` or consume an attempt. `sourceFailures` is orthogonal; non-empty failures during playback set the degraded UI flag but leave `.playing` primary.

- [ ] **Step 5: Run tests and commit**

```bash
bash skills/app-testing/scripts/run-radio.sh radio-coordinator unit
git add Briefeed/Core/Radio/RadioSessionCoordinator.swift BriefeedTests/Radio
git commit -m "feat: restore persistent Radio sessions"
```

---

### Task 6: Progress, Next, Completion, Failures, Connectivity, and Sleep

**Files:**
- Create: `Briefeed/Core/Radio/RadioNetworkMonitor.swift`
- Create: `Briefeed/Core/Radio/RadioServiceContainer.swift`
- Modify: `Briefeed/Core/Radio/RadioSessionCoordinator.swift`
- Test: `BriefeedTests/Radio/RadioPlaybackStateTests.swift`
- Test: `BriefeedTests/Radio/RadioSleepTimerTests.swift`
- Test: `BriefeedTests/Radio/RadioServiceContainerTests.swift`

**Interfaces:**
- Produces: `ConnectivityMonitoring`, `RadioNetworkMonitor`, the explicit `RadioServiceContainer` composition root, and an extended `RadioSessionCoordinating` surface for `recordProgress`, `pauseByUser`, `seekEnded`, `manualNext`, `playbackCompleted`, `playbackFailed`, `retry`, `setSleepTimer`, `evaluateSleepTimer`, `handleInterruptionBegan`, `handleInterruptionEnded`, and `handleRouteRemoval`.

- [ ] **Step 1: Write failing transition tests**

Cover every force-save event; Next deferral; 95 percent completion on advance; natural completion; Core Data save failure retaining entry; one initial online attempt plus one retry; offline consuming no attempt; remaining retry on reconnection; reset only on explicit Retry, successful source refresh, or cold launch; only-failed session; end-of-episode suppression; manual Next canceling end-of-episode; deadline pause without completion; timer replacement and cancel.

Add a container test built without the static singleton: create a fake monitor, store, repository, and `RadioServiceContainer(connectivity:coordinator:)`; assert `container.connectivity === fake`, drive the fake from unknown to offline, and prove `container.coordinator` observes that same transition. The lifecycle test in Task 9 receives `container.connectivity`, completing the same-instance contract. Hosted tests never install a process override or resolve `RadioServiceContainer.shared`.

```swift
@Test func completionSaveFailureRetainsCurrentEntry() async {
    let repository = FailingCompletionRepository(candidate: episode)
    let coordinator = restoredCoordinator(repository: repository, current: episode.key)
    let intent = await coordinator.playbackCompleted(at: now)
    #expect(intent == nil)
    #expect(coordinator.currentKey == episode.key)
    #expect(coordinator.entries.contains { $0.key == episode.key })
    #expect(coordinator.state == .failed(.persistence("save failed")))
}

@Test func nextCancelsEndOfEpisodeAndDefersCurrent() async {
    coordinator.setSleepTimer(.endOfEpisode)
    let intent = await coordinator.manualNext(positionSeconds: 42, duration: 300)
    #expect(coordinator.sleepTimer == .off)
    #expect(coordinator.entries.last?.disposition == .deferred)
    #expect(intent?.key == next.key)
}
```

- [ ] **Step 2: Verify red**

Run `make radio-compile` and expect missing transition methods. After the transition surface compiles, run the focused suites in the owned `radio-state` lane and require behavioral failures before implementation.

- [ ] **Step 3: Implement connectivity as an injected publisher**

```swift
@MainActor
protocol ConnectivityMonitoring: AnyObject {
    var status: ConnectivityStatus { get }
    var statusPublisher: AnyPublisher<ConnectivityStatus, Never> { get }
}

@MainActor
final class RadioNetworkMonitor: ConnectivityMonitoring {
    private let monitor = NWPathMonitor()
    private let subject = CurrentValueSubject<ConnectivityStatus, Never>(.unknown)
    var status: ConnectivityStatus { subject.value }
    var statusPublisher: AnyPublisher<ConnectivityStatus, Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }
}
```

Deliver NWPath callbacks onto the main queue. Start and cancel one monitor with coordinator lifetime. While status is unknown, readable local files remain immediately playable, but no remote feed refresh or remote enclosure load starts and no failure attempt is consumed. The first `.online` or `.offline` event resolves the pending network action. Tests use a `CurrentValueSubject` fake and prove offline cold launch never consumes an online attempt.

Create `RadioServiceContainer` as the sole production composition root for Radio. It owns the one `ConnectivityMonitoring` instance and one concrete `RadioSessionCoordinator`; the coordinator receives that same monitor in its initializer. Do not add `RadioSessionCoordinator.shared`. The container exposes a main-actor, process-local factory override that can be installed only before its lazy `shared` instance is first resolved:

```swift
@MainActor
final class RadioServiceContainer {
    typealias Factory = @MainActor () -> RadioServiceContainer
    private static var instance: RadioServiceContainer?
    private static var factory: Factory = makeProduction

    let connectivity: ConnectivityMonitoring
    let coordinator: RadioSessionCoordinator

    static var shared: RadioServiceContainer {
        if let instance { return instance }
        let created = factory()
        instance = created
        return created
    }

    #if DEBUG
    static func installProcessOverride(_ override: @escaping Factory) {
        precondition(instance == nil, "Install Radio override before resolving shared services")
        factory = override
    }
    #endif
}
```

`makeProduction` constructs the Core Data repository, versioned store, `RadioNetworkMonitor`, and coordinator once. Hosted unit tests continue to construct their dependencies directly and never resolve this container.

- [ ] **Step 4: Implement transition methods and persistence points**

Extend `RadioSessionCoordinating` with the Task 6 commands before adding their concrete implementations. Keep identity, seconds position, duration, connectivity, and `shouldResume` explicit in method arguments; do not make the transport or view model reach into concrete coordinator internals.

Every user-initiated `pauseByUser`, `seekEnded`, `manualNext`, `retry`, or sleep/playback selection command begins by consuming the pending cold-launch autoplay opportunity. System-driven progress and connectivity events do not consume it before the 60-second deadline.

Save seconds at most once per 5-second bucket during progress. Force `store.saveNow` on pause, seek end, Next, completion, background, interruption, route removal, and termination. Manual Next moves current to deferred tail and chooses pending then deferred. On successful completion, call `repository.markCompleted` before removing the entry. If that throws, preserve the entry and stop advancement.

Add a crash-window test for both persistence boundaries: a crash before the Core Data save leaves the snapshot entry resumable; a crash after the Core Data save but before snapshot removal leaves a stale snapshot entry that restore deterministically drops because Core Data is completed. This is the recovery contract for the unavoidable two-store window.

Failure accounting is per entry. Increment only for online load attempts. After attempt two fails, mark `failedThisSession` and select next. An offline transition sets `waitingForNetwork` and does not mutate the count. Explicit Retry resets the current failure cycle; successful source refresh resets only entries from that source.

- [ ] **Step 5: Implement non-persisted sleep state**

`setSleepTimer(.deadline(now + minutes * 60))` replaces the prior timer. `evaluateSleepTimer(at:)` returns `.pause` exactly once after the deadline, clears the timer, force-saves position, and does not complete. Natural completion under `.endOfEpisode` completes crash-consistently, selects the next cursor in paused readiness, clears the timer, and returns no play intent.

- [ ] **Step 6: Run tests and commit**

```bash
bash skills/app-testing/scripts/run-radio.sh radio-state unit
git add Briefeed/Core/Radio BriefeedTests/Radio
git commit -m "feat: complete Radio playback state machine"
```

---

### Task 7: Atomic Single-Item Transport and Unified Delegate Migration

**Files:**
- Modify: `Briefeed/Core/Services/Audio/SwiftAudioExService.swift`
- Modify: `Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift`
- Create: `Briefeed/Core/Services/Audio/BriefQueueCoordinating.swift`
- Test: `BriefeedTests/Radio/SwiftAudioExRemotePolicyTests.swift`
- Test: `BriefeedTests/Radio/AudioCompletionRoutingTests.swift`

**Interfaces:**
- Consumes: canonical speed list plus the existing Brief and temporary Live News routing in `UnifiedAudioPlayer`.
- Produces: `BriefQueueCoordinating`, `AudioPlaybackTransporting`, a single-item `SwiftAudioExService`, `TransportPlaybackID`, `RemoteCommandAvailability`, and an atomically migrated `UnifiedAudioPlayer` delegate for identity-bound state, progress, terminal, interruption, route, play, pause, seek, skip, Next, and rate events. Task 8 replaces temporary routing with the formal active-mode router.

- [ ] **Step 1: Write policy tests before touching the player**

Extract this pure configuration so tests can assert it without touching the process-global command center:

```swift
struct RemoteCommandAvailability: Equatable, Sendable {
    let previousEnabled: Bool
    let nextEnabled: Bool
    let skipBackwardInterval: TimeInterval
    let skipForwardInterval: TimeInterval
    let supportedRates: [Float]

    static func radio(canPlayNext: Bool) -> Self {
        .init(
            previousEnabled: false,
            nextEnabled: canPlayNext,
            skipBackwardInterval: 10,
            skipForwardInterval: 10,
            supportedRates: PlaybackSpeedPolicy.supported
        )
    }

    static func brief(canPlayPrevious: Bool, canPlayNext: Bool) -> Self {
        .init(
            previousEnabled: canPlayPrevious,
            nextEnabled: canPlayNext,
            skipBackwardInterval: 10,
            skipForwardInterval: 10,
            supportedRates: PlaybackSpeedPolicy.supported
        )
    }
}

@Test func radioRemotePolicyUsesTenSecondsAndNoPrevious() {
    let policy = RemoteCommandAvailability.radio(canPlayNext: true)
    #expect(policy.skipBackwardInterval == 10)
    #expect(policy.skipForwardInterval == 10)
    #expect(policy.previousEnabled == false)
    #expect(policy.nextEnabled == true)
    #expect(policy.supportedRates == PlaybackSpeedPolicy.supported)
}
```

Add a spy-delegate test proving one low-level `.playedUntilEnd` event emits exactly one `audioDidFinishPlaying(id: expectedID, successfully: true)` and never invokes another URL load.

- [ ] **Step 2: Verify red**

Run `make radio-compile` and expect missing `RemoteCommandAvailability`. Do not claim a simulator until the new policy, transport identity, delegate surface, and Brief protocol compile.

- [ ] **Step 3: Extract the Brief queue dependency before changing the delegate**

Create `BriefQueueCoordinating.swift` before migrating `UnifiedAudioPlayer` so the Task 7 commit is atomic and hosted tests never need the production singleton:

```swift
@MainActor
protocol BriefQueueCoordinating: AnyObject {
    var queue: [QueueItem] { get }
    var currentIndex: Int { get }
    var currentPosition: TimeInterval { get }
    var currentItem: QueueItem? { get }
    var itemCount: Int { get }
    var queuePublisher: AnyPublisher<[QueueItem], Never> { get }
    var currentIndexPublisher: AnyPublisher<Int, Never> { get }

    func addArticle(_ article: Article, playNow: Bool, playNext: Bool)
    func addEpisode(_ episode: RSSEpisode, playNow: Bool, playNext: Bool)
    func removeItem(at index: Int)
    func clearQueue()
    func setCurrentIndex(_ index: Int)
    func updateCurrentPosition(_ position: TimeInterval)
    func markCurrentAsListened()
    func updateCachedAudioURL(for itemID: UUID, url: URL?)
    func markItemFailed(for itemID: UUID, error: String)
    func autoRemoveIfListened(at index: Int) -> UUID?
}

extension QueueCoordinator: BriefQueueCoordinating {
    var queuePublisher: AnyPublisher<[QueueItem], Never> { $queue.eraseToAnyPublisher() }
    var currentIndexPublisher: AnyPublisher<Int, Never> { $currentIndex.eraseToAnyPublisher() }
}
```

Make default arguments explicit at every protocol call site. Add a Task 7 internal initializer that accepts `BriefQueueCoordinating`; production still supplies `QueueCoordinator.shared`. All hosted Radio audio tests use a fresh fake and never read, clear, persist, or subscribe to the singleton.

- [ ] **Step 4: Remove the private transport queue**

Delete `queue`, `currentIndex`, `loadQueue`, `playNext`, `playPrevious`, and completion-time auto-advance from `SwiftAudioExService`. `play(id:url:title:artist:)` loads exactly one item. `handlePlaybackEnd(.playedUntilEnd)` notifies the delegate once and stops.

Give every load an identity so late callbacks from a replaced item cannot advance the new one:

```swift
struct TransportPlaybackID: Hashable, Sendable {
    let rawValue: UUID
}

@MainActor
protocol AudioPlaybackTransporting: AnyObject {
    var delegate: SwiftAudioExServiceDelegate? { get set }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    func play(id: TransportPlaybackID, url: URL, title: String?, artist: String?) async throws
    func pause()
    func resume()
    func stop()
    func seek(to time: TimeInterval)
    func setRate(_ rate: Float)
    func applyRemoteCommandAvailability(_ availability: RemoteCommandAvailability)
}
```

Do not label library callbacks with a mutable current ID. Create a fresh SwiftAudioEx `AudioPlayer` for each load and register its listeners with closures that capture that load's immutable `TransportPlaybackID`. Stop and detach the previous player before publishing the new player as active. Maintain `consumedTerminalIDs`; the first failure or end callback consumes the ID, and later failure/end duplicates are ignored. A deliberate stop used for replacement is recorded in `expectedStopIDs` and never becomes a completion/failure. This makes delayed callbacks retain the old ID so Unified can reject them.

- [ ] **Step 5: Route every remote command as a semantic event**

Declare both `SwiftAudioExService` and `SwiftAudioExServiceDelegate` `@MainActor`, then extend the delegate with:

```swift
@MainActor
protocol SwiftAudioExServiceDelegate: AnyObject {
func audioItemReady(id: TransportPlaybackID, duration: TimeInterval)
func audioStateChanged(id: TransportPlaybackID, to newState: SwiftAudioPlayerState, from oldState: SwiftAudioPlayerState)
func audioProgressUpdated(id: TransportPlaybackID, progress: Float, currentTime: TimeInterval, duration: TimeInterval)
func audioDidFinishPlaying(id: TransportPlaybackID, successfully: Bool)
func audioInterruptionBegan(id: TransportPlaybackID?)
func audioInterruptionEnded(id: TransportPlaybackID?, shouldResume: Bool)
func audioRouteWasRemoved(id: TransportPlaybackID?)
func audioRequestPlay()
func audioRequestPause()
func audioRequestSeek(to seconds: TimeInterval)
func audioRequestSkipBackward(seconds: TimeInterval)
func audioRequestSkipForward(seconds: TimeInterval)
func audioRequestNextTrack()
func audioRequestRate(_ rate: Float)
}
```

Remote handlers only emit these events. AVAudioSession interruption and old-device-unavailable route handlers also only emit their identity-bound events. They do not directly call `resume`, `pause`, `seek`, `setRate`, or private navigation. SwiftAudioEx listener closures may arrive off-main; each closure captures the immutable playback ID and hops through `Task { @MainActor in ... }` before reading service state or invoking the delegate. `audioItemReady` is emitted exactly once for the matching load after duration is known. Add `applyRemoteCommandAvailability(_:)` to enable/disable commands and set 10-second preferred intervals and the exact supported rate list.

In the same step, mark `UnifiedAudioPlayer` `@MainActor` and conform it to the new delegate surface so Task 7 remains buildable. Migrate every current call to the removed transport queue API: Brief and the temporary Live News compatibility path select their next item at the Unified layer, create a playback ID, and call single-item `play`; no production caller may invoke low-level `loadQueue`, `playNext`, or `playPrevious`. Brief interruption/route handling force-saves through `BriefQueueCoordinating` before it changes playback state. The temporary Live News compatibility path remains deliberately nonpersisted in this intermediate task: it snapshots current time in memory, pauses, and resumes only when `shouldResume` is true and the user had not paused; it never writes Brief state. Keep those temporary properties only until Task 8 replaces them with persistent Radio and moves their view-model callers.

- [ ] **Step 6: Clamp transport speed and update Now Playing**

Make `setRate` call `PlaybackSpeedPolicy.normalize`. Update command availability and Now Playing after current item, mode, queue eligibility, state, route, or rate changes. Preserve the spoken-audio session while removing direct interruption/route state changes from the transport.

Add tests for stop-then-load, a delayed old completion after a replacement, failure followed by playback-end, duplicate terminal callbacks, an off-main library callback hopping to the main actor, a stale ready callback being rejected by ID, and interruption `shouldResume` when the active semantic owner reports user-paused.

- [ ] **Step 7: Run focused tests and compile**

```bash
bash skills/app-testing/scripts/run-radio.sh radio-transport unit
make radio-compile
```

Expected: remote policy and one-completion tests pass; `rg -n 'private var queue|func loadQueue|func playNext|func playPrevious' Briefeed/Core/Services/Audio/SwiftAudioExService.swift` and `rg -n 'audioPlayer\.(loadQueue|playNext|playPrevious)' Briefeed` return no matches.

- [ ] **Step 8: Commit**

```bash
git add Briefeed/Core/Services/Audio/SwiftAudioExService.swift Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift Briefeed/Core/Services/Audio/BriefQueueCoordinating.swift BriefeedTests/Radio
git commit -m "fix: make audio transport single item"
```

---

### Task 8: Unified Player Radio Projection and Brief Isolation

**Files:**
- Modify: `Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift`
- Modify: `Briefeed/Core/ViewModels/AudioPlayerViewModelV2.swift`
- Modify: `Briefeed/Core/ViewModels/AppViewModel.swift`
- Modify: `Briefeed/Features/LiveNews/LiveNewsViewV2.swift`
- Test: `BriefeedTests/Radio/UnifiedRadioPlaybackTests.swift`
- Test: `BriefeedTests/Radio/BriefIsolationTests.swift`

**Interfaces:**
- Consumes: coordinator playback intents and single-item transport.
- Produces: `ActivePlaybackMode`, an injectable internal `UnifiedAudioPlayer` initializer, `UnifiedAudioPlayer.playRadio`, Radio-aware identity-checked control routing, `AudioPlayerViewModelV2.radioState`, `radioEntries`, `sleepTimer`, and `sourceFailures`.

- [ ] **Step 1: Write integration tests with a transport spy**

Cover restoring at seconds position; progress sent only to Radio while Radio is active; Brief state untouched; manual Next defers; natural completion once; stream failure uses coordinator budget; remote event routing; and switching from Radio to Brief without deleting either persisted session. Add a persistence-order spy proving Radio pause, seek, Next, interruption, route removal, and mode switch each force-save the semantic owner before the transport state change. This is the Task 8 proof that closes Task 7's one-commit compatibility gap.

```swift
@Test func radioProgressDoesNotMutateBriefCoordinator() async throws {
    let brief = FakeBriefQueueCoordinator(currentPosition: 17)
    let radio = makeRadioCoordinator(position: 42)
    let transport = SpyTransport()
    let player = makeUnifiedPlayer(brief: brief, radio: radio, transport: transport)
    await player.activateRadioAndPlay()
    player.audioProgressUpdated(
        id: try #require(transport.lastPlaybackID),
        progress: 0.2,
        currentTime: 60,
        duration: 300
    )
    #expect(radio.entries.first?.positionSeconds == 60)
    #expect(brief.currentPosition == 17)
}
```

- [ ] **Step 2: Verify red**

Run `make radio-compile`; expect missing active-mode injection seams. After those seams compile, run both suites in the owned `radio-unified` lane and require behavioral failures.

- [ ] **Step 3: Replace temporary Live News state with Radio projection**

Introduce:

```swift
enum ActivePlaybackMode: Equatable { case none, brief, radio }

@Published private(set) var activeMode: ActivePlaybackMode = .none
@Published private(set) var radioQueue: [UnifiedQueueItem] = []
@Published private(set) var radioIndex: Int = -1
```

Keep `shared` as the production singleton, but add an internal initializer used by hosted tests:

```swift
init(
    audioPlayer: AudioPlaybackTransporting,
    queueCoordinator: BriefQueueCoordinating,
    radioCoordinator: RadioSessionCoordinating,
    context: NSManagedObjectContext
)
```

The production convenience initializer supplies `SwiftAudioExService`, `QueueCoordinator.shared`, `RadioServiceContainer.shared.coordinator`, and the production view context. Tests supply a transport spy, fresh Brief fake, and isolated repository/coordinator. This is the only production resolution point for the Radio container inside the playback graph.

Delete `liveNewsStreamQueue`, `liveNewsStreamIndex`, `isStreamingLiveNews`, and their temporary navigation methods after callers move to Radio. Hydrate exact `(feedID, episodeID)` through `RadioEpisodeRepository`, not the old ID-only fetch.

- [ ] **Step 4: Execute coordinator intents in one method**

Add `execute(_ intent: RadioPlaybackIntent?) async`. For `.play`, persist and deliberately stop any prior active item, create a new `TransportPlaybackID`, make it the sole `activePlaybackID`, set Radio active, load the original or readable downloaded URL, apply canonical speed, call transport play, and seek after the matching ready callback. The expected replacement stop must not complete or fail the prior item. For `.pause`, pause transport. For nil, update presentation without loading. Ignore every state, progress, failure, and completion callback whose ID does not equal `activePlaybackID`. Do not mark episodes listened at playback start.

- [ ] **Step 5: Route UI and remote controls by active mode**

Play/pause, seek, 10-second skip, Next, rate, completion, interruption, and route removal switch on `activeMode`. Any user or remote playback command first cancels a pending deferred autoplay opportunity. Radio calls `RadioSessionCoordinator`; Brief preserves current `QueueCoordinator` behavior. Radio Previous remains disabled. Update remote availability after every transition.

- [ ] **Step 6: Bind the view model to Radio**

Replace 20x options with `PlaybackSpeedPolicy.supported`. Subscribe only to the explicit `RadioSessionCoordinating` publishers and publish current metadata from the active projection. Add `playRadio()`, `playRadioEpisode(_ key: RadioEpisodeKey)`, `retryRadio()`, `refreshRadio()`, `setSleepTimer(_:)`, and `cancelSleepTimer()`. `playRadioEpisode` uses the already-tested `selectEpisode(_:)` command from Task 5. Keep `queueEpisode` for explicit future Brief playlist actions.

Update `LiveNewsViewV2`: Play Live News calls `playRadio()`, and per-episode Play Now calls `playRadioEpisode(RadioEpisodeKey(feedID: episode.feedId, episodeID: episode.id))`. Remove no view call site until `rg -n 'playLiveNewsStream|isStreamingLiveNews|liveNewsStream' Briefeed` returns no production matches.

- [ ] **Step 7: Run focused tests and commit**

```bash
bash skills/app-testing/scripts/run-radio.sh radio-unified unit
git add Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift Briefeed/Core/ViewModels/AudioPlayerViewModelV2.swift Briefeed/Core/ViewModels/AppViewModel.swift Briefeed/Features/LiveNews/LiveNewsViewV2.swift BriefeedTests/Radio
git commit -m "feat: route Radio through unified playback"
```

Expected: Radio playback tests and Brief isolation tests pass; no temporary Live News queue fields remain.

---

### Task 9: Startup, Lifecycle, Refresh Poll, and Autoplay

**Files:**
- Modify: `Briefeed/BriefeedApp.swift`
- Modify: `Briefeed/BriefeedApp+RSSV2.swift`
- Modify: `Briefeed/Core/Services/RSS/RSSAudioService.swift`
- Test: `BriefeedTests/Radio/RadioAppLifecycleTests.swift`

**Interfaces:**
- Consumes: Radio coordinator restore/intents, the shared `ConnectivityMonitoring` instance, structured refresh results, and existing autoplay key.
- Produces: one startup task, one connectivity-gated active 15-minute stale-check poll, `handleScenePhase(_:)`, and cold-launch-only autoplay.

- [ ] **Step 1: Write lifecycle tests around an extracted driver**

Create `RadioAppLifecycleDriver` in `BriefeedApp+RSSV2.swift` with fakeable closures and an injected `ConnectivityMonitoring`. Test that cold launch restores before refresh, autoplay evaluates once, unknown and offline connectivity defer rather than start refresh, online at 59 seconds may consume the opportunity while online at 60 seconds only replenishes paused state, the first timely online event starts the single pending stale refresh, foreground refreshes stale only, background cancels pending refresh/autoplay and force-saves, and active-background-active-background cycles re-arm exactly one poll without autoplay or duplication.

- [ ] **Step 2: Verify red**

Run `make radio-compile`; expect the missing lifecycle driver. Claim the `radio-lifecycle` lane only after the driver surface compiles and the ordering assertions can fail behaviorally.

- [ ] **Step 3: Consolidate startup**

Replace `initializeRSSFeatures`, `playLiveNewsRadio`, `scheduleRSSRefresh`, and arbitrary 0.5-second delay with:

```swift
@MainActor
func startRadioServices() async {
    let radioServices = RadioServiceContainer.shared
    await RSSAudioService.shared.ensureDefaultFeedsExist()
    let intent = await radioServices.coordinator.restore(
        autoplayEnabled: UserDefaultsManager.shared.autoPlayLiveNewsOnOpen
    )
    await UnifiedAudioPlayer.shared.execute(intent)
    radioLifecycleDriver.requestStaleRefreshWhenOnline(now: Date()) {
        radioServices.coordinator.refreshStarted(
            enabledSourceCount: RSSAudioService.shared.enabledFeedCount
        )
        let result = await RSSAudioService.shared.refreshIfStale(now: Date())
        // Only this first connectivity-gated refresh can consume the bounded
        // cold-launch autoplay opportunity.
        let postRefreshIntent = radioServices.coordinator.applyInitialRefresh(result)
        await UnifiedAudioPlayer.shared.execute(postRefreshIntent)
    }
}
```

Construct `radioLifecycleDriver` with `RadioServiceContainer.shared.connectivity`, which is the exact monitor already injected into its coordinator. `requestStaleRefreshWhenOnline` retains at most one pending request while status is `.unknown` or `.offline` without polling or consuming source/episode attempts; `.online` invokes its operation exactly once. The cold-launch request applies its result through `applyInitialRefresh` exactly once, including when connectivity delays it. Foreground and 15-minute poll requests apply results through `applyRefresh`; they can replenish paused state but never create or consume another autoplay opportunity. An offline transition is already reflected in the coordinator's connectivity-driven `waitingForNetwork` state, so it does not fabricate a terminal refresh result. The coordinator independently enforces the 60-second active autoplay deadline. Cancellation on inactive/background removes the pending request and calls `cancelPendingColdLaunchAutoplay()` so a later network callback cannot start background work or audio; the next foreground creates a new stale-check request without creating a new autoplay opportunity.

Skip production startup only in hosted unit tests or deterministic Radio fixture mode. Fixture seeding gets its own Task 12 path.

- [ ] **Step 4: Own one active poll and scene lifecycle**

Use `scenePhase` plus a cancellable `Task` that sleeps 15 minutes while active and calls only `requestStaleRefreshWhenOnline` with a stale-refresh operation. Cancel both poll and pending connectivity wait on inactive/background. Every transition to active idempotently creates exactly one new poll when none exists; repeated active notifications leave the existing poll unchanged. On every foreground, evaluate stale refresh but never create a new autoplay opportunity. On background and termination, cancel deferred autoplay and force-save both Radio and Brief state. Let playing audio continue.

- [ ] **Step 5: Run tests and inspect timer ownership**

```bash
bash skills/app-testing/scripts/run-radio.sh radio-lifecycle unit
rg -n 'Timer\.scheduledTimer|1_800|1800' Briefeed/BriefeedApp+RSSV2.swift Briefeed/Core/Services/RSS/RSSAudioService.swift
```

Expected: lifecycle suite passes; no refresh timer matches remain in either file.

- [ ] **Step 6: Commit**

```bash
git add Briefeed/BriefeedApp.swift Briefeed/BriefeedApp+RSSV2.swift Briefeed/Core/Services/RSS/RSSAudioService.swift BriefeedTests/Radio/RadioAppLifecycleTests.swift
git commit -m "feat: restore and refresh Radio on lifecycle"
```

---

### Task 10: Default Radio Navigation and Settings Placement

**Files:**
- Create: `Briefeed/Features/Navigation/AppTab.swift`
- Create: `Briefeed/Features/Navigation/RadioTabRail.swift`
- Create: `Briefeed/Features/Navigation/AppBottomChrome.swift`
- Create: `Briefeed/Features/Radio/RadioHomeView.swift`
- Modify: `Briefeed/ContentView.swift`
- Modify: `Briefeed/Features/Settings/SettingsView.swift`
- Modify: `Briefeed/Core/Utilities/AccessibilityIdentifiers.swift`
- Test: `BriefeedUITests/RadioUITests.swift`

**Interfaces:**
- Produces: `AppTab.radio|brief|feed`, icon-only accessible tab rail, top-right Settings sheet, and state-driven Radio home.

- [ ] **Step 1: Write failing launch and navigation XCUITests**

Launch with `-briefeed-radio-fixture partial` and reset environment. Assert Radio selected by default; three 44-point controls with labels Radio, Brief, Feed; Settings opens from a top-right gear; switching tabs preserves Radio title; native tab-bar labels do not appear as a second navigation row.

```swift
func testLaunchesIntoRadioAndSwitchesAccessibleRail() {
    let app = XCUIApplication()
    app.launchArguments += ["-briefeed-radio-fixture", "partial"]
    app.launchEnvironment["BRIEFEED_RADIO_RESET_STORE"] = "1"
    app.launch()

    XCTAssertTrue(app.buttons["Radio"].isSelected)
    app.buttons["Brief"].tap()
    XCTAssertTrue(app.buttons["Brief"].isSelected)
    app.buttons["Radio"].tap()
    XCTAssertTrue(app.staticTexts["Morning Update"].exists)
}
```

- [ ] **Step 2: Verify red**

Run `bash skills/app-testing/scripts/run-radio.sh radio-nav ui` and expect the default Radio assertion to fail.

- [ ] **Step 3: Implement root navigation with safe-area chrome**

```swift
enum AppTab: Hashable { case radio, brief, feed }
```

`ContentView` defaults to `.radio`. Keep a `TabView(selection:)`, apply `.toolbar(.hidden, for: .tabBar)`, and present custom chrome with `safeAreaInset(edge: .bottom, spacing: 0)`. Remove the fixed `49`-point padding. The inset order is `RadioTabRail` above `MiniAudioPlayerV4`, making the mini-player the bottom-most app control above the home indicator.

- [ ] **Step 4: Implement the compact rail and Settings**

Use SF Symbols `dot.radiowaves.left.and.right`, `text.page`, and `newspaper`; no visible text. Keep each hit target 44 by 44 points. On iOS 26 use an availability-gated glass container; on iOS 18.2 fallback to `.ultraThinMaterial`, semantic stroke, and restrained shadow. Reduce Transparency gets an opaque semantic background. A gear in each root screen's top-right toolbar presents `SettingsView` as a full-height sheet.

- [ ] **Step 5: Implement Radio state surfaces**

`RadioHomeView` renders current metadata and source management plus explicit `refreshing`, `waitingForNetwork`, `noSources`, `failed`, and true `exhausted` actions. Only exhausted uses `You're caught up`. Active playback stays primary while `sourceFailures` appear in a nonblocking degraded banner.

- [ ] **Step 6: Run navigation UI tests and visual captures**

Run the UI lane at default iPhone and then with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge`. Capture screenshots for Radio, Brief, Feed, Settings, dark mode, Reduce Transparency, and large type.

Expected: one compact rail, no overlap, stable tab selection, and all controls hittable.

- [ ] **Step 7: Commit**

```bash
git add Briefeed/Features/Navigation Briefeed/Features/Radio Briefeed/ContentView.swift Briefeed/Features/Settings/SettingsView.swift Briefeed/Core/Utilities/AccessibilityIdentifiers.swift BriefeedUITests/RadioUITests.swift
git commit -m "feat: make Radio the primary app surface"
```

---

### Task 11: Compact Mini Player, Scrubber, Speed, Sleep, and Expanded Player

**Files:**
- Modify: `Briefeed/Features/Audio/MiniAudioPlayerV4.swift`
- Modify: `Briefeed/Features/Audio/ExpandedAudioPlayerV2.swift`
- Modify: `Briefeed/Core/ViewModels/AudioPlayerViewModelV2.swift`
- Modify: `Briefeed/Core/Utilities/AccessibilityIdentifiers.swift`
- Test: `BriefeedTests/MiniPlayer/MiniPlayerSeekTests.swift`
- Test: `BriefeedTests/Radio/RadioPlayerPresentationTests.swift`
- Test: `BriefeedUITests/RadioUITests.swift`

**Interfaces:**
- Consumes: active mode metadata, `PlaybackSpeedPolicy`, Radio sleep state, and exact transport actions.
- Produces: approved asymmetric mini-player and consistent expanded controls.

- [ ] **Step 1: Extend failing presentation and seek tests**

Assert seek clamping, 44-point scrubber lane, back/forward 10, Next availability, no Radio Previous, speed option list and persistence, all sleep presets, custom 1/180 bounds, remaining-time accessibility value, and stable control identifiers.

- [ ] **Step 2: Verify red**

Run `make radio-compile` first. When the presentation tests compile, run them in an owned lane and expect interval, speed, and sleep assertion failures.

- [ ] **Step 3: Implement the approved compact layout**

Use a constrained two-column grid: flexible metadata on the left and fixed transport cluster on the elevated right. Left shows artwork, one-line title, source, speed, and sleep. Right shows Back 10, dominant Play/Pause, Forward 10, and Next. A bottom row shows elapsed, thin scrubber, and remaining. Do not render a decorative waveform. Truncate metadata before shrinking transport.

- [ ] **Step 4: Make the scrubber usable and accessible**

Render a thin visible progress rail inside a 44-point-high `contentShape(Rectangle())`. Support tap and drag with stable geometry; clamp 0 through duration. Add `.accessibilityAdjustableAction` with 10-second increments and an elapsed/remaining value.

- [ ] **Step 5: Add speed and sleep menus**

Speed uses one Menu over the canonical discrete list. Sleep uses Off, End of Episode, presets, and a Custom sheet with a minute Stepper from 1 through 180 initialized to 20. Use icons and concise values; do not add instructional copy to the player surface.

- [ ] **Step 6: Align expanded and remote semantics**

Change expanded player 15/30 controls to 10/10, use the same speed and sleep source, display Radio session position, and hide Brief queue affordances while Radio is active.

- [ ] **Step 7: Run tests and screenshot matrix**

Run focused unit and UI lanes. Capture small iPhone, large iPhone, iPad landscape, dark mode, XXXL, and accessibility type. Inspect for text/control overlap, clipped speed values, transport movement, and safe-area mistakes.

- [ ] **Step 8: Commit**

```bash
git add Briefeed/Features/Audio Briefeed/Core/ViewModels/AudioPlayerViewModelV2.swift Briefeed/Core/Utilities/AccessibilityIdentifiers.swift BriefeedTests/MiniPlayer BriefeedTests/Radio BriefeedUITests/RadioUITests.swift
git commit -m "feat: finish compact Radio player controls"
```

---

### Task 12: Generated Audio Fixtures, Relaunch Tests, and Headless Smoke

**Files:**
- Create: `Briefeed/Core/Debug/RadioFixtureSeeder.swift`
- Create: `skills/app-testing/scripts/radio-fixtures.sh`
- Create: `skills/app-testing/scripts/radio-smoke.sh`
- Modify: `Briefeed/BriefeedApp.swift`
- Modify: `Briefeed/Core/Radio/RadioServiceContainer.swift`
- Modify: `BriefeedUITests/RadioUITests.swift`
- Test: `BriefeedTests/Radio/RadioFixtureSeederTests.swift`

**Interfaces:**
- Produces: fixture scenarios `partial`, `completed`, `offline`, `all-failed`, `degraded`, `no-sources`, `refreshing`, and `exhausted`; a debug-only fixture dependency/transition definition; generated local WAV files; evidence directory and `.xcresult` receipt.

- [ ] **Step 1: Write fixture seed tests**

Verify three deterministic feeds, priorities, fresh/partial/completed/stale/malformed/duplicate cases, and a readable local audio URL with duration greater than 60 seconds. Assert reseeding with reset is idempotent and without reset preserves partial session data. For every scenario, assert its initial connectivity and scripted coordinator transition: `offline` begins offline with a remote-only eligible item; `refreshing` calls `refreshStarted` and withholds a terminal result; `all-failed` applies one failure for every enabled source; `degraded` keeps a playable local current item while another source fails; `exhausted` applies prior-success-backed skipped-fresh results with no eligible entries; `no-sources` has zero enabled feeds. No scenario invokes a real RSS request.

Also add one cross-scenario reuse test. Seed `partial` with reset, mutate its Radio snapshot and preferences, then seed `completed` with reset in the same app container. Assert the old snapshot, current key, position, autoplay override, speed override, and legacy last-played key do not leak. Relaunch `completed` without reset and assert its newly mutated session remains intact.

- [ ] **Step 2: Verify red**

Run `make radio-compile`; expect the missing fixture seeder. Claim a simulator only after the seeder and fixture branch compile.

- [ ] **Step 3: Generate local audio in DEBUG code**

Use `AVAudioFile` to write a 90-second mono 44.1 kHz PCM WAV into Application Support with a low-volume alternating 440/660 Hz tone. Do not commit binary audio. Seed Core Data with fixed feed IDs, episode IDs, publication dates relative to an injected clock, and local file URLs. In fixture mode, bypass production feed creation and network refresh.

Reset has an exact, narrow meaning. When `reset` is true, delete and recreate only the isolated `Briefeed-RadioUITests.sqlite` store and its WAL/SHM, remove `briefeed_radio_session_v1`, `playbackSpeed`, `rssPlaybackSpeed`, `autoPlayLiveNewsOnOpen`, and `rssLastPlayedEpisodeId` from `UserDefaults.standard`, then establish scenario defaults of autoplay Off and speed `1.0`. Do not call `removePersistentDomain` or clear unrelated user settings. Run the preference reset from a fixture bootstrap in `BriefeedApp.init` before first access to `UserDefaultsManager.shared`, `RadioSessionStore`, or either playback coordinator; the Core Data reset remains inside the isolated `PersistenceController` initializer. When `reset` is false, preserve both the isolated store and these Radio preferences so relaunch assertions exercise real restoration.

The current app has eager stored-property initializers, so calling preflight in the existing init body is too late. Remove the eager initial values for `persistenceController`, `userDefaultsManager`, `audioPlayerViewModel`, and `appViewModel`. At the first line of `BriefeedApp.init`, call `AppRuntime.prepareRadioFixturePreferencesIfNeeded()`. When a fixture scenario exists, next install the `RadioServiceContainer` process override described below. Only then initialize `PersistenceController.shared`, `UserDefaultsManager.shared`, the single audio view model, and the app view model in that order. No settings, persistence, Radio container, Unified player, or playback view-model singleton may be referenced from a property default initializer.

Add a DEBUG-only `RadioFixtureScenarioDefinition` that provides `initialConnectivity` and a scripted post-restore action. Extend `RadioServiceContainer` under `#if DEBUG` with `installFixtureOverride(definition:)`; it calls the Task 6 `installProcessOverride` API with a closure that constructs the fixture monitor, isolated Core Data repository, defaults-backed Radio store, and coordinator using that same monitor. `BriefeedApp.init` installs it after preference preflight and before `PersistenceController.shared`, `AudioPlayerViewModelV2`, or `UnifiedAudioPlayer.shared` can resolve the lazy container. The scripted action uses the same public coordinator methods as production to enter refreshing, apply structured failures/skipped-fresh evidence, or preserve a degraded active session. It may not assign private state directly, start the production lifecycle driver, or call the RSS network client.

In `BriefeedApp`, order launch branches explicitly:

```swift
if let scenario = AppRuntime.radioFixtureScenario {
    Task { @MainActor in
        try RadioFixtureSeeder(context: persistenceController.container.viewContext)
            .seed(scenario: scenario, reset: AppRuntime.shouldResetRadioFixtureStore)
        await startRadioFixtureSession()
    }
} else if AppRuntime.shouldSkipAutomaticStartupWork {
    print("Skipping automatic startup services for hosted XCTest")
} else {
    Task { @MainActor in await startRadioServices() }
}
```

`startRadioFixtureSession()` restores the Radio coordinator, applies the selected definition's scripted post-restore action, and executes any returned autoplay intent using only seeded local state. It starts neither default-feed creation nor refresh polling. The offline definition is injected before coordinator construction; every other definition drives the exact production transition method after restore.

`radio-fixtures.sh` is the bounded manual-launch wrapper:

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${BRIEFEED_APP_ROOT:?BRIEFEED_APP_ROOT is required}"
: "${SIM_UUID:?SIM_UUID is required}"
ENGINE="$HOME/ericode/skills/app-testing/scripts"
export AGENT_SIM_CONFIG="$BRIEFEED_APP_ROOT/skills/app-testing/config.sh"
source "$ENGINE/sim-lib.sh"
scenario="${1:?fixture scenario is required}"
reset="${2:-0}"
case "$scenario" in
  partial|completed|offline|all-failed|degraded|no-sources|refreshing|exhausted) ;;
  *) exit 64 ;;
esac
SIMCTL_CHILD_BRIEFEED_RADIO_RESET_STORE="$reset" \
  with_timeout 30 xcrun simctl launch --terminate-running-process "$SIM_UUID" Matznerd.Briefeed \
  -briefeed-radio-fixture "$scenario"
```

- [ ] **Step 4: Add relaunch UI tests**

Test: start partial with `BRIEFEED_RADIO_RESET_STORE=1`, play until time advances, pause, terminate, construct a new `XCUIApplication` with the same scenario and `BRIEFEED_RADIO_RESET_STORE=0`, relaunch, and assert same episode plus position tolerance. Complete an episode, relaunch without reset in the same simulated hour, and assert it is absent/current advances. Test autoplay Off stays silent and On starts once on cold relaunch. Assert the distinct offline, refreshing, all-failed, degraded, no-sources, and exhausted presentation plus each recovery action. Reuse one claimed lane for `partial -> completed -> partial`; reset boundaries must prevent cross-scenario state bleed, while the no-reset relaunch inside each scenario must preserve state.

- [ ] **Step 5: Implement the headless smoke script**

`radio-smoke.sh` must build/install to `$SIM_UUID`, call `radio-fixtures.sh partial 1`, wait with the shared `with_timeout` helper, capture `simctl io screenshot`, collect a bounded `log stream` predicate for `Matznerd.Briefeed`, run the Radio XCUITest selector into `$DERIVED_DATA_PATH/RadioSmoke.xcresult`, and write a receipt containing simulator UUID, git SHA, app path, screenshot path, log path, and xcresult path. It must never open Simulator.app or select another device.

- [ ] **Step 6: Run the full deterministic proof**

```bash
bash skills/app-testing/scripts/run-radio.sh radio-all unit
bash skills/app-testing/scripts/run-radio.sh radio-ui ui
bash skills/app-testing/scripts/run-radio.sh radio-smoke smoke
```

Expected: unit, UI, and smoke lanes pass; each reports exact evidence paths, releases its exact use lock, and leaves only its owned lane device booted for warm reuse.

- [ ] **Step 7: Commit**

```bash
git add Briefeed/Core/Debug/RadioFixtureSeeder.swift Briefeed/Core/Radio/RadioServiceContainer.swift Briefeed/BriefeedApp.swift BriefeedTests/Radio BriefeedUITests/RadioUITests.swift skills/app-testing/scripts
git commit -m "test: add deterministic Radio playback proof"
```

---

### Task 13: Regression, Device Gate, and Distribution Candidate

**Files:**
- Modify: `docs/PRD-REFACTOR-V2.md`
- Create: `docs/release/LIVE-RADIO-DEVICE-CHECKLIST.md`
- Create: `docs/release/LIVE-RADIO-DISTRIBUTION-RECEIPT.md`
- Modify: `Scripts/upload-testflight.sh` only if dry-run inspection finds unsafe defaults.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: a verified physical-device and signed archive receipt, or an explicitly blocked implementation-only receipt that is not called a distribution candidate; plus human-only distribution actions.

- [ ] **Step 1: Run static and focused regression gates**

```bash
make radio-compile
bash skills/app-testing/scripts/run-radio.sh radio-all unit
bash skills/app-testing/scripts/run-radio.sh radio-ui ui
bash skills/app-testing/scripts/run-radio.sh radio-smoke smoke
xcodebuild analyze -project Briefeed.xcodeproj -scheme Briefeed \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/briefeed-radio-analyze \
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO
```

Expected: all focused gates pass and Analyze reports no new warnings in touched files.

- [ ] **Step 2: Run the existing Brief regression subset**

Use an owned lane and run `MiniPlayerNavigationTests`, `MiniPlayerSeekTests`, `AudioPipelineFlowTests`, and `PlayNowPipelineTests`. Expected: Brief queue, TTS playback, and existing mini-player behaviors remain green. Do not treat unrelated disabled legacy suites as Radio failures; record their existing status explicitly.

- [ ] **Step 3: Complete the physical-device checklist**

On an explicitly selected developer device, verify audible streaming; partial resume after force quit; screen-lock background continuation; Lock Screen and Control Center play/pause, 10-second back/forward and Next; Bluetooth/AirPlay/headphone removal; call/Siri interruption; online/offline recovery; all sleep modes while locked; speed persistence; and no Brief state mutation. Record device model, iOS version, build SHA, and pass/fail per row.

- [ ] **Step 4: Build and validate a fresh archive without uploading**

```bash
xcodebuild archive \
  -project Briefeed.xcodeproj \
  -scheme Briefeed \
  -configuration Release \
  -archivePath /tmp/Briefeed-Live-Radio.xcarchive \
  -destination 'generic/platform=iOS'
xcodebuild -exportArchive \
  -archivePath /tmp/Briefeed-Live-Radio.xcarchive \
  -exportPath /tmp/Briefeed-Live-Radio-export \
  -exportOptionsPlist ExportOptions.plist
```

Inspect bundle ID, version/build, `UIBackgroundModes`, signing identity, entitlements, packaged resources, and any Info.plist-substituted API values. Do not upload. A successful physical-device checklist and a validated signed archive/export are mandatory before labeling this work a distribution candidate. If a device, certificate, profile, or export configuration is unavailable, record the exact blocker and preserve the green implementation evidence, but leave Task 13 open and label the result `implementation verified; distribution candidate blocked`. An unsigned generic build is useful evidence but cannot satisfy this gate.

- [ ] **Step 5: Update product and release documentation**

Mark only actually implemented Radio requirements and test evidence in `PRD-REFACTOR-V2.md`. `LIVE-RADIO-DISTRIBUTION-RECEIPT.md` must include commands, results, evidence paths, device checklist, archive SHA, gate status, known limitations, and human-only actions: create App Store Connect record for `Matznerd.Briefeed` per GitHub issue #7, confirm agreements/roles/certificates/profiles/privacy/export compliance, approve version/build, initiate upload, select tester groups, and submit beta/App Review. Do not mark the implementation goal complete as a distribution candidate while either the physical-device or signed-archive gate is blocked.

- [ ] **Step 6: File GitHub issues for remaining work**

From `/Users/me/ericode/briefeed-app/briefeed-ios`, create narrowly scoped issues for every deferred or failed device/release item. Keep ad transcription and smart skip linked to existing issue #10 and explicitly outside the MVP.

- [ ] **Step 7: Final commit, rebase, push, and verify**

```bash
git add docs/PRD-REFACTOR-V2.md docs/release Scripts/upload-testflight.sh
git commit -m "docs: record Live Radio release readiness"
git pull --rebase
git push
git status --short --branch
```

Expected: the branch is clean and reports up to date with its origin. Work is not complete until push succeeds.

## Planning Review Record

- The first architecture gate returned REVISE with stable findings covering task atomicity, interruption ownership, fresh-source evidence, simulator claims, local-only startup, persistence generations, tri-state connectivity, callback identity, singleton-free tests, fixture reset, and release labeling. Every listed correction is incorporated into this revision.
- Two historical Fabled Orca High transport attempts failed before the final revision: the first review timed out without a verdict, and the first debate exited 86 without a valid envelope. Neither is treated as review evidence.
- A fresh independent Fable High review of `radio-plan-82e80e6-v2` completed with observed Anthropic/Fable routing and returned `PLAN_APPROVED`. Result SHA-256: `0d9968be7de072fbea6ab786590c1cf4503af75210bb05bf3139b20bdd880ebc`. It found no critical/high issue and raised two medium plus three low hardening items.
- Revision `68c2b94` bounded deferred autoplay to 60 active seconds, made canonical-enclosure ingestion preserve durable identity across shifted publication dates, specified exact foreground poll re-arming, strengthened the Task 7/8 adjacency gate, and carried the already-existing crash-window proof into the review evidence.
- A fresh Fable High debate round reviewed every finding disposition and declared the plan converged with no remaining critical, high, or material medium disagreement. Result SHA-256: `7da462e6eb40d51107cc571214a56db4106ca6f9bf75c93fbd8c9d8dff5f3e1d`; round: `debate-round-1`; remaining disagreements: none.
- Before implementation on July 20, 2026, Task 1 and Task 12 were reconciled with the current shared `app-testing` engine: content-addressed bounded install, doctor preflight, bounded manual fixture launch, and warm owned-simulator reuse now replace raw install/launch and eager lane shutdown. These are simulator-infrastructure updates and do not alter the approved Radio product behavior.
- The independent review and debate approve implementation readiness only. Product implementation, simulator evidence, physical-device checks, signing, archive validation, and distribution remain undone.

## Final Acceptance Matrix

- Fresh install defaults to Radio with autoplay Off.
- Cold-launch autoplay On resumes the exact partial current episode once.
- Deferred cold-launch autoplay expires after 60 active seconds, inactive/background, or any manual playback command; a late online refresh replenishes paused state only.
- Reopening in the same hour never replays a completed episode.
- Source priority, publication date, and episode ID deterministically order pending entries.
- Manual Next preserves seconds position, defers current, and selects pending before deferred.
- Refresh appends without duplicates and never replaces active playback.
- Offline, no-sources, refreshing, all-failed, degraded, and truly exhausted states are distinct.
- Core Data completion saves before snapshot removal; save failure retains a recoverable entry.
- Radio failure budget is one initial online load plus one online retry and resets only under the specified events.
- Mini and expanded players provide Back 10, Play/Pause, Forward 10, Next, precise scrubber, 0.5x through 3.0x speed, and complete sleep timing.
- Manual Next cancels End of Episode sleep.
- Lock Screen and Control Center route every command through the active mode; Radio Previous is disabled.
- Each foreground transition re-arms exactly one active 15-minute stale-refresh poll.
- Brief queue, index, playback position, and persistence are unchanged by Radio.
- Custom navigation is safe-area correct and accessible across the required size, contrast, motion, and transparency matrix.
- Automated proof uses only deterministic fixtures and owned simulator UUIDs.
- Physical-device background, route, interruption, remote-control, and sleep gates pass.
- A fresh signed archive/export is validated and the physical-device checklist passes before the build is called a distribution candidate. A documented signing/device blocker leaves the release gate open.
- No irreversible publication occurs; upload, tester-group selection, and App Review submission remain human-approved actions.
