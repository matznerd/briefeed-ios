# Task 9 Receipt

## RED

- Added `RadioAppLifecycleTests` before the lifecycle driver existed. `make radio-compile` failed on the missing `RadioAppLifecycleDriver` surface.
- Added lifecycle-owned Unified persistence tests before its narrow app lifecycle methods existed. The compile failed on missing `handleAppBackground()` and `handleAppTermination()`.
- Added regressions for nonactive-before-active startup, background during async restore, and cancellation-ignoring refresh work. The compile failed against the older restore/cancellation API before the race repairs were implemented.

## Implementation

- Replaced `initializeRSSFeatures` with one `RadioAppLifecycleDriver` that receives the exact `RadioServiceContainer` connectivity monitor, injected clock/sleep seams, structured refresh work, and cancellation/save callbacks.
- Cold launch restores once, gates its returned playback intent on the current active generation, and reserves `applyInitialRefresh` exclusively for the bounded first refresh. Foreground and 15-minute active polling use `applyRefresh` only.
- Unknown/offline connectivity retains at most one pending request without beginning source attempts. Online consumes it once. Background clears pending/in-flight ownership immediately, cancels the active poll, rejects late results by identity and generation, revokes autoplay even before the first active phase, and allows a fresh foreground stale check.
- Consolidated app startup into one SwiftUI task while preserving unrelated service startup. Stored app dependencies are initialized explicitly once, leaving a preflight boundary before singleton resolution for Task 12 fixture injection.
- Removed duplicate app/Unified background and foreground observers. `scenePhase` is the lifecycle owner; the sole termination notification force-saves both Brief and Radio.
- Unified lifecycle saves use the live transport position only when Radio owns that exact current episode; otherwise they preserve Radio's persisted entry position. Brief and Radio snapshots are always forced without pausing or stopping background audio.
- Added `RSSAudioService.enabledFeedCount`; no service-owned refresh timer was introduced.

## Verification

- Final `make radio-compile` passed with `TEST BUILD SUCCEEDED`.
- `rg -n 'Timer\.scheduledTimer|1_800|1800' Briefeed/BriefeedApp+RSSV2.swift Briefeed/Core/Services/RSS/RSSAudioService.swift` returned no matches.
- Legacy startup and duplicate lifecycle subscriber search returned no matches in app startup or Unified playback.
- The owned `radio-lifecycle` unit lane was attempted twice through the shared fleet adapter. Fleet preflight refused to create a claim because `Simulator.app` remained open, even after the prescribed `sim-gui.sh hide`; the adapter returned `1`. No pressure override, foreign simulator UUID, GUI launch, or CoreSimulator recovery was used. Runtime execution remains deferred to the final simulator pass.
