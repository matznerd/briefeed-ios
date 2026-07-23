import AVFoundation

enum AudioSessionConfiguration {
    // The playback category provides AirPlay and A2DP output routing itself.
    // Input-oriented route options are invalid here and make setCategory fail.
    static let playbackOptions: AVAudioSession.CategoryOptions = []

    static func activatePlayback(on session: AVAudioSession = .sharedInstance()) throws {
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: playbackOptions
        )
        try session.setActive(true)
    }
}
