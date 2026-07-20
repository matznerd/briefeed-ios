# Task 9 Receipt

## RED

- Added `RadioAppLifecycleTests` before the lifecycle driver existed. `make radio-compile` failed on the missing `RadioAppLifecycleDriver` surface.
- Added lifecycle-owned Unified persistence tests before its narrow app lifecycle methods existed. The compile failed on missing `handleAppBackground()` and `handleAppTermination()`.
- Added regressions for nonactive-before-active startup, background during async restore, and cancellation-ignoring refresh work. The compile failed against the older restore/cancellation API before the first race repairs were implemented.
- Added the two review regressions before their production repair: an active return while restore is still suspended, and a shared physical single-flight loader that ignores task cancellation. The fleet-safe runtime lane stopped at preflight (`Simulator.app` open), so these behavior tests could not produce a hosted semantic RED.

## Implementation

- Replaced `initializeRSSFeatures` with one `RadioAppLifecycleDriver` that receives the exact `RadioServiceContainer` connectivity monitor, injected clock/sleep seams, structured refresh work, and cancellation/save callbacks.
- Cold launch restores once, gates its returned playback intent on the current active generation, and reserves `applyInitialRefresh` exclusively for the bounded first refresh. Foreground and 15-minute active polling use `applyRefresh` only.
- Unknown/offline connectivity retains at most one pending request without beginning source attempts. Online consumes it once. Background clears queued logical work but retains physical refresh ownership until cancellation-ignoring RSS work actually completes. A foreground return queues exactly one replacement behind that work; the old result is rejected by generation, ownership is then released, and only the replacement result can apply.
- If the app returns active before a suspended restore completes, the stale restore intent is rejected and completion recovers through the foreground-only refresh path. It cannot consume the initial/autoplay refresh opportunity, and it arms exactly one active poll.
- Consolidated app startup into one SwiftUI task while preserving unrelated service startup. Stored app dependencies are initialized explicitly once, leaving a preflight boundary before singleton resolution for Task 12 fixture injection.
- Removed duplicate app/Unified background and foreground observers. `scenePhase` is the lifecycle owner; the sole termination notification force-saves both Brief and Radio.
- Unified lifecycle saves use the live transport position only when Radio owns that exact current episode; otherwise they preserve Radio's persisted entry position. Brief and Radio snapshots are always forced without pausing or stopping background audio.
- Added `RSSAudioService.enabledFeedCount`; no service-owned refresh timer was introduced.

## Verification

- The focused Task 9 build-for-testing passed with `TEST BUILD SUCCEEDED`, compiling `RadioAppLifecycleTests` while excluding Task 11's intentionally RED `MiniPlayerSeekTests.swift` and `RadioPlayerPresentationTests.swift` files.
- The global `make radio-compile` currently stops only on Task 11's expected missing player-presentation symbols; no Task 9 production or lifecycle-test compile errors were reported.
- `rg -n 'Timer\.scheduledTimer|1_800|1800' Briefeed/BriefeedApp+RSSV2.swift Briefeed/Core/Services/RSS/RSSAudioService.swift` returned no matches.
- Legacy startup and duplicate lifecycle subscriber search returned no matches in app startup or Unified playback.
- The owned `radio-lifecycle` unit lane was attempted again through the shared fleet adapter. Fleet preflight refused to create a claim because `Simulator.app` remained open (`PRESSURE=warn`, one booted simulator). No pressure override, foreign simulator UUID, GUI launch, or CoreSimulator recovery was used. Runtime execution remains deferred to the final simulator pass.
