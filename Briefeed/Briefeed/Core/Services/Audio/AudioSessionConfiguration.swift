import AVFoundation

enum AudioSessionConfiguration {
    // Keep spoken news playing while the user browses apps that activate their
    // own audio session. The playback category provides output routing itself.
    static let playbackOptions: AVAudioSession.CategoryOptions = [.mixWithOthers]

    static func activatePlayback(on session: AVAudioSession = .sharedInstance()) throws {
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: playbackOptions
        )
        try session.setActive(true)
    }
}
