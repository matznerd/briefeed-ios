import AVFoundation
import Testing
@testable import Briefeed

@Suite("Audio session configuration")
struct AudioSessionConfigurationTests {
    @Test func playbackRemainsNonmixableForSystemNowPlayingEligibility() {
        // A mixable session can still produce sound, which makes this regression
        // deceptively easy to miss without explicitly checking the category.
        let options = AudioSessionConfiguration.playbackOptions

        #expect(!options.contains(.mixWithOthers))
        #expect(!options.contains(.duckOthers))
        #expect(!options.contains(.interruptSpokenAudioAndMixWithOthers))
        #expect(!options.contains(.allowAirPlay))
        #expect(!options.contains(.allowBluetoothA2DP))
        #expect(!options.contains(.allowBluetoothHFP))
    }
}
