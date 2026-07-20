# Task 8 Receipt

## RED

- Added transport-spy integration tests against the planned injected unified initializer before the initializer, `ActivePlaybackMode`, or Radio playback methods existed.
- `make radio-compile` failed on those missing mode and injection seams plus the deliberately incompatible old delegate/call sites.

## Implementation

- Added `ActivePlaybackMode` plus injected transport, Brief coordinator, Radio coordinator, and Core Data context dependencies. `RadioServiceContainer.shared` is resolved only by the production unified playback graph.
- Removed the temporary Live News stream queue, index, flag, navigation methods, and every production caller. Radio projection is rebuilt from coordinator entries and exact composite `(feedID, episodeID)` Core Data hydration.
- Centralized `.play`, `.pause`, and nil intent execution. Radio uses a readable downloaded file when present, applies canonical speed, seeks only after a matching ready callback, subscribes pending network intents, and rejects every stale state/progress/terminal callback by transport ID.
- Routed pause, seek, 10-second skip, Next, completion, failure, interruption, route removal, rate, and mode switching through the active semantic owner. Radio persistence happens before transport mutations; Brief state is isolated while Radio is active, and both queues survive mode switches.
- Bound explicit Radio state, entries, current episode, sleep timer, failures, and active mode through `AudioPlayerViewModelV2` and `AppViewModel`. Live News actions now call `playRadio()` or exact-key `playRadioEpisode(_:)`.

## Tests

- Added restore-at-seconds, Radio-only progress, stale/double completion, bounded duplicate failure, ready-ID, pending seek, manual Next, natural completion, Brief isolation, and mode-preservation coverage.
- Added ordering spies for Radio pause, seek, Next, interruption, route removal, and Radio-to-Brief switching, requiring forced persistence before pause, seek, stop, or load.

## Verification

- Final `make radio-compile` passed with `TEST BUILD SUCCEEDED` and compiled all new hosted suites.
- `bash skills/app-testing/scripts/run-radio.sh radio-unified unit` stopped at the fleet safety preflight because host pressure remained critical (`swap_free=818MB`, load 80) and Simulator.app was open. No override or foreign simulator was used.
- `rg -n 'playLiveNewsStream|isStreamingLiveNews|liveNewsStream' Briefeed` returned no production matches.
- `RadioServiceContainer.shared` has one production occurrence, in `UnifiedAudioPlayer` composition.
- `git diff --check` passed.
