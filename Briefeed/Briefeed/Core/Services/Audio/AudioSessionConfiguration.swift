import AVFoundation

enum AudioSessionConfiguration {
    // Do not add .mixWithOthers here. Briefeed's MPNowPlayingInfoCenter and
    // MPRemoteCommandCenter integration is promoted to system Now Playing only
    // when playback starts from a nonmixable session. The regression test locks
    // this down because audio can keep playing while lock-screen controls vanish.
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
