import Foundation
import Testing
@testable import Briefeed

@Suite("SwiftAudioEx remote policy")
@MainActor
struct SwiftAudioExRemotePolicyTests {
    @Test func radioUsesCanonicalRatesTenSecondSkipsAndNoPrevious() {
        let policy = RemoteCommandAvailability.radio(canPlayNext: true)

        #expect(policy.skipBackwardInterval == 10)
        #expect(policy.skipForwardInterval == 10)
        #expect(policy.previousEnabled == false)
        #expect(policy.nextEnabled == true)
        #expect(policy.supportedRates == PlaybackSpeedPolicy.supported)
    }

    @Test func briefReflectsQueueNavigationAvailability() {
        let policy = RemoteCommandAvailability.brief(canPlayPrevious: true, canPlayNext: false)

        #expect(policy.previousEnabled)
        #expect(!policy.nextEnabled)
        #expect(policy.supportedRates == PlaybackSpeedPolicy.supported)
    }
}
