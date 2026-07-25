# Radio Refresh Verification Receipt

**Date:** July 25, 2026  
**Branch:** `codex/live-radio-mvp`

## Verified Behavior

- Cold launch and every foreground return force one enabled-source refresh.
- Reopening Radio Home after the 60-second opening debounce forces one refresh.
- Active foreground polling remains stale-only and runs on the existing 15-minute cadence.
- A best-effort iOS background app-refresh request is registered and re-armed with a 45-minute earliest begin date.
- Background refresh applies feed changes without issuing a playback or autoplay command.
- If an older NPR bulletin is already playing when a newer one arrives, the active episode, playback state, and transport identity remain unchanged.

## Automated Evidence

`make radio-compile`

- Result: `TEST BUILD SUCCEEDED`
- Destination: generic iOS Simulator
- Coverage: application, unit-test, and UI-test targets compile.

Focused physical-device unit run:

```text
RadioAppLifecycleTests
RadioFeedBackgroundRefreshTests
RadioSessionCoordinatorRestoreTests
```

- Result: 37 tests in 3 suites passed.
- Device: `Eric's iPhone (2)`
- Includes the active-old-NPR/new-NPR refresh regression.

## Remaining Human Proof

iOS decides whether and when a `BGAppRefreshTask` runs. Registration, scheduling,
expiration, and completion are covered deterministically, but opportunistic
background delivery still belongs in the physical-device release matrix tracked
by GitHub issue #13.
