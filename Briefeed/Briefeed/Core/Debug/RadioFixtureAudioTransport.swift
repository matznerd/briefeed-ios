#if DEBUG
import Foundation

/// Deterministic transport for UI fixtures. Headless Simulator audio devices can
/// block AVAudioSession activation for minutes, which is unrelated to app state.
/// This transport still requires the seeded local file and exercises the real
/// UnifiedAudioPlayer and RadioSessionCoordinator callback path.
@MainActor
final class RadioFixtureAudioTransport: AudioPlaybackTransporting {
    weak var delegate: SwiftAudioExServiceDelegate?

    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval
    private var activeID: TransportPlaybackID?
    private var state: SwiftAudioPlayerState = .idle

    init(duration: TimeInterval = 90) {
        self.duration = duration
    }

    func play(id: TransportPlaybackID, url: URL, title: String?, artist: String?) async throws {
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
            throw RadioFixtureTransportError.unreadableLocalAudio
        }

        activeID = id
        currentTime = 0
        publish(.loading, id: id)
        delegate?.audioItemReady(id: id, duration: duration)
        publish(.playing, id: id)
    }

    func pause() {
        guard let activeID else { return }
        publish(.paused, id: activeID)
    }

    func resume() {
        guard let activeID else { return }
        publish(.playing, id: activeID)
    }

    func stop() {
        guard let activeID else { return }
        publish(.stopped, id: activeID)
        self.activeID = nil
    }

    func seek(to time: TimeInterval) {
        currentTime = max(0, min(time, duration))
        guard let activeID else { return }
        delegate?.audioProgressUpdated(
            id: activeID,
            progress: duration > 0 ? Float(currentTime / duration) : 0,
            currentTime: currentTime,
            duration: duration
        )
    }

    func setRate(_ rate: Float) {}
    func applyRemoteCommandAvailability(_ availability: RemoteCommandAvailability) {}

    private func publish(_ newState: SwiftAudioPlayerState, id: TransportPlaybackID) {
        let oldState = state
        state = newState
        guard newState != oldState else { return }
        delegate?.audioStateChanged(id: id, to: newState, from: oldState)
    }
}

enum RadioFixtureTransportError: LocalizedError {
    case unreadableLocalAudio

    var errorDescription: String? {
        "Radio fixture audio must be a readable local file"
    }
}
#endif
