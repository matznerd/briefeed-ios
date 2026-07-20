import Foundation
import Testing
@testable import Briefeed

@Suite("Radio player presentation")
struct RadioPlayerPresentationTests {
    @Test func radioTransportIsRightHandedAndHasNoPreviousControl() {
        #expect(PlayerPresentationPolicy.transportControls(for: .radio) == [
            .backTen,
            .playPause,
            .forwardTen,
            .next
        ])
        #expect(!PlayerPresentationPolicy.showsPrevious(for: .radio))
        #expect(PlayerPresentationPolicy.showsPrevious(for: .brief))
    }

    @Test func speedMenuUsesCanonicalOptionsAndPersistsSelection() {
        #expect(PlayerPresentationPolicy.speedOptions == PlaybackSpeedPolicy.supported)
        #expect(PlayerPresentationPolicy.speedOptions == [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3])

        let suite = "RadioPlayerPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        PlaybackSpeedPolicy.persist(1.75, defaults: defaults)
        #expect(PlaybackSpeedPolicy.loadAndMigrate(defaults: defaults) == 1.75)
    }

    @Test func sleepMenuContainsExactPresetsAndCustomBounds() {
        #expect(RadioSleepMenuOption.all == [
            .off,
            .endOfEpisode,
            .minutes(10),
            .minutes(20),
            .minutes(30),
            .minutes(45),
            .minutes(60),
            .custom
        ])
        #expect(RadioSleepMenuOption.customBounds == 1...180)
        #expect(RadioSleepMenuOption.defaultCustomMinutes == 20)
        #expect(RadioSleepMenuOption.clampedCustomMinutes(0) == 1)
        #expect(RadioSleepMenuOption.clampedCustomMinutes(181) == 180)
    }

    @Test func sleepSelectionMapsToReplaceableCoordinatorState() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(RadioSleepMenuOption.off.timer(now: now) == .off)
        #expect(RadioSleepMenuOption.endOfEpisode.timer(now: now) == .endOfEpisode)
        #expect(RadioSleepMenuOption.minutes(20).timer(now: now) == .deadline(now.addingTimeInterval(1_200)))
        #expect(RadioSleepMenuOption.custom.timer(now: now, customMinutes: 37) == .deadline(now.addingTimeInterval(2_220)))
    }

    @Test func displayFormattingExposesElapsedRemainingAndTimerValues() {
        #expect(PlayerPresentationFormat.elapsed(134) == "2:14")
        #expect(PlayerPresentationFormat.remaining(position: 134, duration: 360) == "-3:46")
        #expect(PlayerPresentationFormat.scrubberAccessibilityValue(position: 134, duration: 360) == "2 minutes, 14 seconds elapsed, 3 minutes, 46 seconds remaining")

        let now = Date(timeIntervalSince1970: 1_000)
        #expect(PlayerPresentationFormat.sleepTimer(.off, now: now) == "Off")
        #expect(PlayerPresentationFormat.sleepTimer(.endOfEpisode, now: now) == "End of Episode")
        #expect(PlayerPresentationFormat.sleepTimer(.deadline(now.addingTimeInterval(1_201)), now: now) == "21 min")
    }

    @Test func playerControlsKeepStableAccessibilityIdentifiers() {
        #expect(AccessibilityID.MiniPlayer.rewind == "miniPlayer.rewind")
        #expect(AccessibilityID.MiniPlayer.playPause == "miniPlayer.playPause")
        #expect(AccessibilityID.MiniPlayer.forward == "miniPlayer.forward")
        #expect(AccessibilityID.MiniPlayer.next == "miniPlayer.next")
        #expect(AccessibilityID.MiniPlayer.scrubber == "miniPlayer.scrubber")
        #expect(AccessibilityID.MiniPlayer.speed == "miniPlayer.speed")
        #expect(AccessibilityID.MiniPlayer.sleep == "miniPlayer.sleep")
    }
}
