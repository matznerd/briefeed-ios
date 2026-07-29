import AVFoundation
import Testing
@testable import Briefeed

@Suite("Audio session configuration")
struct AudioSessionConfigurationTests {
    @Test func playbackRemainsNonmixableForSystemNowPlayingEligibility() {
        let options = AudioSessionConfiguration.playbackOptions

        #expect(!options.contains(.mixWithOthers))
        #expect(!options.contains(.duckOthers))
        #expect(!options.contains(.interruptSpokenAudioAndMixWithOthers))
        #expect(!options.contains(.allowAirPlay))
        #expect(!options.contains(.allowBluetoothA2DP))
        #expect(!options.contains(.allowBluetoothHFP))
    }
}
