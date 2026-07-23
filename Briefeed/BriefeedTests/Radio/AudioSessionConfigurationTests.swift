import AVFoundation
import Testing
@testable import Briefeed

@Suite("Audio session configuration")
struct AudioSessionConfigurationTests {
    @Test func playbackReliesOnSystemManagedOutputRouting() {
        let options = AudioSessionConfiguration.playbackOptions

        #expect(options.isEmpty)
        #expect(!options.contains(.allowAirPlay))
        #expect(!options.contains(.allowBluetoothA2DP))
        #expect(!options.contains(.allowBluetoothHFP))
    }
}
