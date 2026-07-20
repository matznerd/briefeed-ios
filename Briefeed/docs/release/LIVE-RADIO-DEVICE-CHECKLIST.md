# Live Radio Physical Device Checklist

This checklist is the release gate for the Live Radio MVP. Simulator success does
not satisfy any row below. Run it on one explicitly selected developer iPhone
using the exact commit and archive recorded in
`LIVE-RADIO-DISTRIBUTION-RECEIPT.md`.

> **Local test only:** The current IPA contains nonempty packaged Firecrawl and
> Gemini values. It may be installed only on an explicitly approved local test
> phone. Do not upload it to TestFlight/App Store Connect or share it externally.
> GitHub #16 must be cleared before distribution.

## Test Identity

| Field | Value |
| --- | --- |
| Verified implementation commit | `12ec494` |
| Installed development build | `9621d1f` |
| Archive | `/tmp/Briefeed-Live-Radio-12ec494.xcarchive` |
| IPA | `/tmp/Briefeed-Live-Radio-12ec494-export/Briefeed.ipa` |
| IPA SHA-256 | `514e336ebd3d6d128ed54622f1dc7dee8516b9760a723c772d26cf92f03b640f` |
| Device | `Eric's iPhone (2)`, iPhone 13 Pro |
| iOS version | 26.5.2 (23F84) |
| Tester | Eric, owner-approved local test |
| Date | July 20, 2026 |

The owner explicitly requested installation on `Eric's iPhone (2)`, iPhone 13
Pro (`2E288699-F8E0-5B18-A2D9-DE8B1384C33A`). A Debug device build from
repository HEAD `9621d1f` was signed with Apple Development, installed, and
launched successfully. The process remained alive after a follow-up check. No
functional, audio, lifecycle, route, or isolation row below was executed.

## Preconditions

- [x] Confirm the device owner approves installing this exact build.
- [x] Confirm this is an authorized local test only and that the IPA will not
  be uploaded or shared while GitHub #16 remains open.
- [x] Record device model, iOS version, build commit, archive checksum, tester,
  and test date above.
- [ ] Start with Radio autoplay Off and at least two enabled sources.
- [ ] Confirm the test includes one remote episode and one locally available
  episode.
- [ ] Capture failures with reproduction steps and attach console evidence where
  useful.

## Functional Gate

| Check | Status | Evidence / Notes |
| --- | --- | --- |
| Fresh launch opens Radio and remains paused when autoplay is Off | NOT RUN | Physical device required |
| Autoplay On starts the eligible partial/current episode once | NOT RUN | Physical device required |
| Audible remote episode playback | NOT RUN | Physical device required |
| Pause, leave or force quit, relaunch, and resume the same episode near the saved position | NOT RUN | Physical device required |
| A completed episode is not replayed after relaunch in the same hour | NOT RUN | Physical device required |
| Next selects the next eligible episode without rebuilding from the first item | NOT RUN | Physical device required |
| Refresh appends new episodes without duplicating existing episode identity | NOT RUN | Physical device required |
| Offline state skips remote-only media but keeps locally available media usable | NOT RUN | Physical device required |
| Reconnection replenishes the queue without auto-starting after autoplay intent expires | NOT RUN | Physical device required |
| Back 10, Forward 10, Next, scrub, and 0.5x through 3.0x speed work audibly | NOT RUN | Physical device required |
| Playback speed persists after terminate and relaunch | NOT RUN | Physical device required |
| Sleep Off cancels an active timer | NOT RUN | Physical device required |
| Sleep at End of Episode stops after the current episode | NOT RUN | Physical device required |
| Sleep 10/20/30/45/60 and one custom value stop while the screen is locked | NOT RUN | Physical device required |
| Manual Next cancels End of Episode sleep | NOT RUN | Physical device required |

## Lifecycle, Route, and Remote Gate

| Check | Status | Evidence / Notes |
| --- | --- | --- |
| Playback continues after screen lock and while the app is backgrounded | NOT RUN | Physical device required |
| Lock Screen play/pause works | NOT RUN | Physical device required |
| Lock Screen Back 10 and Forward 10 work | NOT RUN | Physical device required |
| Lock Screen Next works and Previous is unavailable for Radio | NOT RUN | Physical device required |
| Control Center commands match Lock Screen behavior | NOT RUN | Physical device required |
| Wired or Bluetooth headphone removal pauses safely | NOT RUN | Route hardware required |
| Bluetooth output and AirPlay route changes preserve position and ownership | NOT RUN | Route hardware required |
| Incoming call interruption pauses and resumes according to iOS audio-session policy | NOT RUN | Physical device required |
| Siri interruption does not duplicate, complete, or lose the episode | NOT RUN | Physical device required |

## Isolation Gate

| Check | Status | Evidence / Notes |
| --- | --- | --- |
| Capture Brief queue, current index, and position before Radio playback | NOT RUN | Physical device required |
| Exercise Radio play, seek, Next, sleep, background, and relaunch | NOT RUN | Physical device required |
| Confirm Brief queue, current index, and position are unchanged afterward | NOT RUN | Physical device required |

## Gate Result

Status: **OPEN - development build installed and launched; physical checks not run**

Do not call the build a distribution candidate until every required row passes
on the selected device, GitHub #16 is cleared by a newly inspected
credential-clean artifact, and the signed archive/export gate also passes.
