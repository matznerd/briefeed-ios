import AVFoundation

enum AudioSessionConfiguration {
    // The legacy MediaPlayer integration only becomes the system Now Playing
    // app when playback starts from a nonmixable audio session.
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
