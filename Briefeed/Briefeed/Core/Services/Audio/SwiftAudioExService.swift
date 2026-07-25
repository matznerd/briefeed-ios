import AVFoundation
import Foundation
import MediaPlayer
import SwiftAudioEx
import UIKit

enum SwiftAudioPlayerState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case error(Error)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.playing, .playing),
             (.paused, .paused), (.stopped, .stopped), (.error, .error):
            true
        default:
            false
        }
    }
}

struct TransportPlaybackID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct RemotePlaybackAssetIdentity: Equatable, Sendable {
    let playbackID: TransportPlaybackID
    let requestedURL: URL
    let finalURL: URL
    let etag: String?
    let lastModified: String?
    let responseContentLength: Int64?
    let duration: TimeInterval
}

struct RemoteCommandAvailability: Equatable, Sendable {
    let previousEnabled: Bool
    let nextEnabled: Bool
    let skipBackwardInterval: TimeInterval
    let skipForwardInterval: TimeInterval
    let supportedRates: [Float]

    static func radio(canPlayNext: Bool) -> Self {
        .init(
            previousEnabled: false,
            nextEnabled: canPlayNext,
            skipBackwardInterval: 10,
            skipForwardInterval: 10,
            supportedRates: PlaybackSpeedPolicy.supported
        )
    }

    static func brief(canPlayPrevious: Bool, canPlayNext: Bool) -> Self {
        .init(
            previousEnabled: canPlayPrevious,
            nextEnabled: canPlayNext,
            skipBackwardInterval: 10,
            skipForwardInterval: 10,
            supportedRates: PlaybackSpeedPolicy.supported
        )
    }
}

@MainActor
protocol SwiftAudioExServiceDelegate: AnyObject {
    func audioItemReady(id: TransportPlaybackID, duration: TimeInterval)
    func audioStateChanged(id: TransportPlaybackID, to newState: SwiftAudioPlayerState, from oldState: SwiftAudioPlayerState)
    func audioProgressUpdated(id: TransportPlaybackID, progress: Float, currentTime: TimeInterval, duration: TimeInterval)
    func audioDidFinishPlaying(id: TransportPlaybackID, successfully: Bool)
    func audioInterruptionBegan(id: TransportPlaybackID?)
    func audioInterruptionEnded(id: TransportPlaybackID?, shouldResume: Bool)
    func audioRouteWasRemoved(id: TransportPlaybackID?)
    func audioRequestPlay()
    func audioRequestPause()
    func audioRequestSeek(to seconds: TimeInterval)
    func audioRequestSkipBackward(seconds: TimeInterval)
    func audioRequestSkipForward(seconds: TimeInterval)
    func audioRequestNextTrack()
    func audioRequestRate(_ rate: Float)
}

@MainActor
protocol AudioPlaybackTransporting: AnyObject {
    var delegate: SwiftAudioExServiceDelegate? { get set }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var activeRemotePlaybackIdentity: RemotePlaybackAssetIdentity? { get }
    func play(id: TransportPlaybackID, url: URL, title: String?, artist: String?) async throws
    func play(
        id: TransportPlaybackID,
        url: URL,
        title: String?,
        artist: String?,
        startingAt time: TimeInterval
    ) async throws
    func pause()
    func resume()
    func stop()
    func seek(to time: TimeInterval)
    func setRate(_ rate: Float)
    func applyRemoteCommandAvailability(_ availability: RemoteCommandAvailability)
}

extension AudioPlaybackTransporting {
    var activeRemotePlaybackIdentity: RemotePlaybackAssetIdentity? { nil }

    func play(
        id: TransportPlaybackID,
        url: URL,
        title: String?,
        artist: String?,
        startingAt time: TimeInterval
    ) async throws {
        try await play(id: id, url: url, title: title, artist: artist)
        if time.isFinite, time > 0 {
            seek(to: time)
        }
    }
}

@MainActor
final class SwiftAudioExService: NSObject, AudioPlaybackTransporting {
    weak var delegate: SwiftAudioExServiceDelegate?

    private var player: AudioPlayer?
    private var activePlaybackID: TransportPlaybackID?
    private var expectedStopIDs = Set<TransportPlaybackID>()
    private var consumedTerminalIDs = Set<TransportPlaybackID>()
    private var readyIDs = Set<TransportPlaybackID>()
    private var progressTimer: Timer?
    private var state: SwiftAudioPlayerState = .idle
    private var currentTitle: String?
    private var currentArtist: String?
    private var lastNowPlayingUpdateTime: TimeInterval = 0

    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var duration: TimeInterval { player?.duration ?? 0 }

    override convenience init() {
        self.init(systemIntegrationEnabled: true)
    }

    init(systemIntegrationEnabled: Bool) {
        super.init()
        if systemIntegrationEnabled {
            setupAudioSession()
            setupRemoteCommands()
            setupNotifications()
        }
    }

    deinit {
        progressTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    func play(id: TransportPlaybackID, url: URL, title: String?, artist: String?) async throws {
        try await loadPlayback(
            id: id,
            url: url,
            title: title,
            artist: artist,
            startingAt: nil
        )
    }

    func play(
        id: TransportPlaybackID,
        url: URL,
        title: String?,
        artist: String?,
        startingAt time: TimeInterval
    ) async throws {
        try await loadPlayback(
            id: id,
            url: url,
            title: title,
            artist: artist,
            startingAt: time.isFinite ? max(0, time) : 0
        )
    }

    private func loadPlayback(
        id: TransportPlaybackID,
        url: URL,
        title: String?,
        artist: String?,
        startingAt time: TimeInterval?
    ) async throws {
        detachActivePlayer(expectStop: true)

        if url.isFileURL, !FileManager.default.fileExists(atPath: url.path) {
            throw NSError(
                domain: "SwiftAudioEx",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Audio file not found"]
            )
        }

        consumedTerminalIDs.remove(id)
        expectedStopIDs.remove(id)
        readyIDs.remove(id)

        let nextPlayer = AudioPlayer()
        configure(nextPlayer, id: id)
        player = nextPlayer
        activePlaybackID = id
        currentTitle = title ?? url.lastPathComponent
        currentArtist = artist ?? "Briefeed"
        publishState(.loading, id: id)

        let audioURL = url.isFileURL ? url.path : url.absoluteString
        let sourceType: SourceType = url.isFileURL ? .file : .stream
        let item: AudioItem
        if let time, time > 0 {
            item = DefaultAudioItemInitialTime(
                audioUrl: audioURL,
                artist: currentArtist ?? "Briefeed",
                title: currentTitle ?? url.lastPathComponent,
                albumTitle: "Briefeed",
                sourceType: sourceType,
                artwork: nil,
                initialTime: time
            )
        } else {
            item = DefaultAudioItem(
                audioUrl: audioURL,
                artist: currentArtist ?? "Briefeed",
                title: currentTitle ?? url.lastPathComponent,
                albumTitle: "Briefeed",
                sourceType: sourceType,
                artwork: nil
            )
        }
        try AVAudioSession.sharedInstance().setActive(true)
        UIApplication.shared.beginReceivingRemoteControlEvents()
        nextPlayer.load(item: item, playWhenReady: true)
        updateNowPlayingInfo()
        startProgressTimer()
    }

    func pause() {
        player?.pause()
        progressTimer?.invalidate()
        updateNowPlayingInfo()
    }

    func resume() {
        player?.play()
        startProgressTimer()
        updateNowPlayingInfo()
    }

    func stop() {
        detachActivePlayer(expectStop: true)
        state = .stopped
        progressTimer?.invalidate()
        updateNowPlayingInfo(clear: true)
    }

    func seek(to time: TimeInterval) {
        player?.seek(to: max(0, min(time, duration > 0 ? duration : time)))
        updateNowPlayingInfo()
    }

    func setRate(_ rate: Float) {
        player?.rate = PlaybackSpeedPolicy.normalize(rate)
        updateNowPlayingInfo()
    }

    func applyRemoteCommandAvailability(_ availability: RemoteCommandAvailability) {
        let commands = MPRemoteCommandCenter.shared()
        commands.previousTrackCommand.isEnabled = availability.previousEnabled
        commands.nextTrackCommand.isEnabled = availability.nextEnabled
        commands.skipBackwardCommand.preferredIntervals = [NSNumber(value: availability.skipBackwardInterval)]
        commands.skipForwardCommand.preferredIntervals = [NSNumber(value: availability.skipForwardInterval)]
        commands.changePlaybackRateCommand.supportedPlaybackRates = availability.supportedRates.map(NSNumber.init(value:))
    }

    private func configure(_ player: AudioPlayer, id: TransportPlaybackID) {
        player.remoteCommands = []
        player.bufferDuration = 2
        player.automaticallyUpdateNowPlayingInfo = false
        player.event.stateChange.addListener(self) { [weak self] state in
            Task { @MainActor [weak self] in self?.receiveState(state, id: id) }
        }
        player.event.updateDuration.addListener(self) { [weak self] duration in
            Task { @MainActor [weak self] in self?.receiveReady(id: id, duration: duration) }
        }
        player.event.playbackEnd.addListener(self) { [weak self] reason in
            Task { @MainActor [weak self] in self?.receivePlaybackEnd(id: id, reason: reason) }
        }
        player.event.fail.addListener(self) { [weak self] error in
            Task { @MainActor [weak self] in self?.receiveFailure(id: id, error: error) }
        }
    }

    private func detachActivePlayer(expectStop: Bool) {
        guard let oldPlayer = player else { return }
        if expectStop, let id = activePlaybackID { recordExpectedStop(id: id) }
        oldPlayer.event.stateChange.removeListener(self)
        oldPlayer.event.updateDuration.removeListener(self)
        oldPlayer.event.playbackEnd.removeListener(self)
        oldPlayer.event.fail.removeListener(self)
        oldPlayer.stop()
        player = nil
        activePlaybackID = nil
    }

    private func receiveState(_ rawState: AVPlayerWrapperState, id: TransportPlaybackID) {
        guard id == activePlaybackID else { return }
        let mapped: SwiftAudioPlayerState
        switch rawState {
        case .idle: mapped = .idle
        case .loading, .buffering: mapped = .loading
        case .ready: mapped = .idle
        case .playing: mapped = .playing
        case .paused: mapped = .paused
        case .stopped, .ended: mapped = .stopped
        case .failed: mapped = .error(TTSError.generationFailed)
        }
        publishState(mapped, id: id)
        if rawState == .ready { receiveReady(id: id, duration: duration) }
        if rawState == .playing || rawState == .paused { updateNowPlayingInfo() }
    }

    private func publishState(_ newState: SwiftAudioPlayerState, id: TransportPlaybackID) {
        let oldState = state
        state = newState
        guard newState != oldState else { return }
        delegate?.audioStateChanged(id: id, to: newState, from: oldState)
    }

    private func receiveReady(id: TransportPlaybackID, duration: TimeInterval) {
        guard id == activePlaybackID, duration.isFinite, duration >= 0, readyIDs.insert(id).inserted else { return }
        delegate?.audioItemReady(id: id, duration: duration)
    }

    func receivePlaybackEnd(id: TransportPlaybackID, reason: PlaybackEndedReason) {
        switch reason {
        case .playedUntilEnd:
            consumeTerminal(id: id, successfully: true, error: nil)
        case .failed:
            consumeTerminal(id: id, successfully: false, error: TTSError.generationFailed)
        case .playerStopped, .cleared:
            guard !expectedStopIDs.contains(id) else {
                consumedTerminalIDs.insert(id)
                return
            }
            consumeTerminal(id: id, successfully: false, error: nil)
        case .skippedToNext, .skippedToPrevious, .jumpedToIndex:
            break
        @unknown default:
            break
        }
    }

    func receiveFailure(id: TransportPlaybackID, error: Error?) {
        consumeTerminal(id: id, successfully: false, error: error ?? TTSError.generationFailed)
    }

    func recordExpectedStop(id: TransportPlaybackID) {
        expectedStopIDs.insert(id)
    }

    func installActivePlaybackForTesting(id: TransportPlaybackID) {
        detachActivePlayer(expectStop: true)
        player = AudioPlayer()
        activePlaybackID = id
    }

    private func consumeTerminal(id: TransportPlaybackID, successfully: Bool, error: Error?) {
        guard !expectedStopIDs.contains(id) else {
            consumedTerminalIDs.insert(id)
            return
        }
        guard consumedTerminalIDs.insert(id).inserted else { return }
        progressTimer?.invalidate()
        if id == activePlaybackID {
            publishState(error.map(SwiftAudioPlayerState.error) ?? .stopped, id: id)
        }
        delegate?.audioDidFinishPlaying(id: id, successfully: successfully)
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.publishProgress() }
        }
    }

    private func publishProgress() {
        guard let id = activePlaybackID else { return }
        let currentTime = currentTime
        let duration = duration
        let progress = duration > 0 ? Float(currentTime / duration) : 0
        delegate?.audioProgressUpdated(id: id, progress: progress, currentTime: currentTime, duration: duration)
        if abs(currentTime - lastNowPlayingUpdateTime) >= 5 {
            updateNowPlayingInfo()
            lastNowPlayingUpdateTime = currentTime
        }
    }

    private func setupAudioSession() {
        do {
            try AudioSessionConfiguration.activatePlayback()
        } catch {
            print("[SwiftAudioEx] Audio session setup failed: \(error)")
        }
    }

    private func setupRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.delegate?.audioRequestPlay() }
            return .success
        }
        commands.pauseCommand.isEnabled = true
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.delegate?.audioRequestPause() }
            return .success
        }
        commands.skipBackwardCommand.isEnabled = true
        commands.skipBackwardCommand.addTarget { [weak self] event in
            let seconds = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            Task { @MainActor [weak self] in self?.delegate?.audioRequestSkipBackward(seconds: seconds) }
            return .success
        }
        commands.skipForwardCommand.isEnabled = true
        commands.skipForwardCommand.addTarget { [weak self] event in
            let seconds = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            Task { @MainActor [weak self] in self?.delegate?.audioRequestSkipForward(seconds: seconds) }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.delegate?.audioRequestNextTrack() }
            return .success
        }
        commands.changePlaybackPositionCommand.isEnabled = true
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let seconds = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return .commandFailed }
            Task { @MainActor [weak self] in self?.delegate?.audioRequestSeek(to: seconds) }
            return .success
        }
        commands.changePlaybackRateCommand.isEnabled = true
        commands.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let rate = (event as? MPChangePlaybackRateCommandEvent)?.playbackRate else { return .commandFailed }
            Task { @MainActor [weak self] in self?.delegate?.audioRequestRate(rate) }
            return .success
        }
        commands.seekForwardCommand.isEnabled = false
        commands.seekBackwardCommand.isEnabled = false
        applyRemoteCommandAvailability(.brief(canPlayPrevious: false, canPlayNext: false))
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }

    @objc nonisolated private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        switch type {
        case .began:
            enqueueInterruption(began: true, shouldResume: false)
        case .ended:
            enqueueInterruption(
                began: false,
                shouldResume: AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            )
        @unknown default:
            break
        }
    }

    @objc nonisolated private func handleRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
        enqueueRouteRemoval()
    }

    nonisolated func deliverInterruptionForTesting(began: Bool, shouldResume: Bool) {
        enqueueInterruption(began: began, shouldResume: shouldResume)
    }

    nonisolated func deliverRouteRemovalForTesting() {
        enqueueRouteRemoval()
    }

    nonisolated private func enqueueInterruption(began: Bool, shouldResume: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if began {
                delegate?.audioInterruptionBegan(id: activePlaybackID)
            } else {
                delegate?.audioInterruptionEnded(id: activePlaybackID, shouldResume: shouldResume)
            }
        }
    }

    nonisolated private func enqueueRouteRemoval() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            delegate?.audioRouteWasRemoved(id: activePlaybackID)
        }
    }

    private func updateNowPlayingInfo(clear: Bool = false) {
        guard !clear else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        guard currentTitle != nil || duration > 0 else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyArtist: currentArtist ?? "Briefeed",
            MPMediaItemPropertyAlbumTitle: "Briefeed",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? (player?.rate ?? 1) : 0
        ]
        if let currentTitle { info[MPMediaItemPropertyTitle] = currentTitle }
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
