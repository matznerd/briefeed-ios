import Foundation
import Testing
@testable import Briefeed

@Suite("Playback speed settings")
struct PlaybackSpeedSettingsTests {
    @Test func speedMigrationUsesLegacyOnlyWhenCanonicalIsAbsent() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(20.0, forKey: UserDefaultsKey.rssPlaybackSpeed.rawValue)

        let speed = PlaybackSpeedPolicy.loadAndMigrate(defaults: defaults)

        #expect(speed == 3.0)
        #expect(defaults.float(forKey: UserDefaultsKey.playbackSpeed.rawValue) == 3.0)
    }

    @Test func canonicalWinsOverLegacy() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(1.25, forKey: UserDefaultsKey.playbackSpeed.rawValue)
        defaults.set(3.0, forKey: UserDefaultsKey.rssPlaybackSpeed.rawValue)

        #expect(PlaybackSpeedPolicy.loadAndMigrate(defaults: defaults) == 1.25)
    }

    @Test func normalizeHandlesNonFiniteBoundsNearestAndLowerTie() {
        #expect(PlaybackSpeedPolicy.normalize(.nan) == 1.0)
        #expect(PlaybackSpeedPolicy.normalize(.infinity) == 1.0)
        #expect(PlaybackSpeedPolicy.normalize(-1) == 0.5)
        #expect(PlaybackSpeedPolicy.normalize(20) == 3.0)
        #expect(PlaybackSpeedPolicy.normalize(1.6) == 1.5)
        #expect(PlaybackSpeedPolicy.normalize(1.125) == 1.0)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "PlaybackSpeedSettingsTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
