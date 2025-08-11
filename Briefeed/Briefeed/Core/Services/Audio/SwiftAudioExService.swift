//
//  SwiftAudioExService.swift
//  Briefeed
//
//  SwiftAudioEx integration for high-performance audio playback
//  Supports up to 20x speed, seeking, and streaming
//

import Foundation
import AVFoundation
import SwiftAudioEx
import MediaPlayer

// MARK: - Audio Player State

enum SwiftAudioPlayerState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case error(Error)
    
    static func == (lhs: SwiftAudioPlayerState, rhs: SwiftAudioPlayerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.playing, .playing),
             (.paused, .paused), (.stopped, .stopped):
            return true
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}

// MARK: - Delegate Protocol

protocol SwiftAudioExServiceDelegate: AnyObject {
    func audioStateChanged(to newState: SwiftAudioPlayerState, from oldState: SwiftAudioPlayerState)
    func audioProgressUpdated(progress: Float, currentTime: TimeInterval, duration: TimeInterval)
    func audioRateChanged(to rate: Float)
    func audioDidFinishPlaying(successfully: Bool)
}

// MARK: - SwiftAudioEx Service

final class SwiftAudioExService: NSObject {
    
    // MARK: - Properties
    
    /// The SwiftAudioEx player instance
    private let player = AudioPlayer()
    
    /// Delegate for state updates
    weak var delegate: SwiftAudioExServiceDelegate?
    
    /// Current state
    private(set) var state: SwiftAudioPlayerState = .idle {
        didSet {
            if state != oldValue {
                delegate?.audioStateChanged(to: state, from: oldValue)
            }
        }
    }
    
    /// Playback properties
    var currentTime: TimeInterval {
        return player.currentTime
    }
    
    var duration: TimeInterval {
        return player.duration
    }
    
    var rate: Float {
        return player.rate
    }
    
    var isPlaying: Bool {
        return player.playerState == .playing
    }
    
    /// Queue management
    private var queue: [URL] = []
    private var currentIndex: Int = -1
    
    /// Progress timer
    private var progressTimer: Timer?
    
    /// Background playback support
    private(set) var backgroundPlaybackEnabled: Bool = true
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupAudioSession()
        setupPlayer()
        setupRemoteCommands()
        setupNotifications()
    }
    
    deinit {
        progressTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Setup
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetooth, .allowAirPlay])
            try session.setActive(true)
        } catch {
            print("[SwiftAudioEx] Failed to setup audio session: \(error)")
        }
    }
    
    private func setupPlayer() {
        // Configure player events
        player.event.stateChange.addListener(self) { [weak self] state in
            self?.handleStateChange(state: state)
        }
        player.event.playbackEnd.addListener(self) { [weak self] reason in
            self?.handlePlaybackEnd(reason: reason)
        }
        player.event.fail.addListener(self) { [weak self] error in
            self?.handlePlaybackFailure(error: error)
        }
        
        // Enable remote control
        player.remoteCommands = [
            .play,
            .pause,
            .skipForward(preferredIntervals: [30]),
            .skipBackward(preferredIntervals: [15]),
            .changePlaybackPosition
        ]
        
        // Configure buffer
        player.bufferDuration = 2.0
        player.automaticallyUpdateNowPlayingInfo = false // We'll manage this ourselves
    }
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward()
            return .success
        }
        
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward()
            return .success
        }
        
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 1.0, 1.5, 2.0, 4.0, 8.0, 16.0, 20.0]
        commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
            if let rateEvent = event as? MPChangePlaybackRateCommandEvent {
                self?.setRate(rateEvent.playbackRate)
            }
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: positionEvent.positionTime)
            }
            return .success
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    // MARK: - Playback Control
    
    func play(url: URL) async throws {
        print("[SwiftAudioEx] play() called with URL: \(url)")
        state = .loading
        
        // Check if file exists for local files
        if url.isFileURL {
            if !FileManager.default.fileExists(atPath: url.path) {
                print("[SwiftAudioEx] ERROR: File does not exist at path: \(url.path)")
                throw NSError(domain: "SwiftAudioEx", code: 404, userInfo: [NSLocalizedDescriptionKey: "Audio file not found"])
            }
            print("[SwiftAudioEx] File exists, loading local file: \(url.path)")
            
            // Try to verify the file is playable
            do {
                let testPlayer = try AVAudioPlayer(contentsOf: url)
                print("[SwiftAudioEx] File is playable, duration: \(testPlayer.duration) seconds")
            } catch {
                print("[SwiftAudioEx] WARNING: File may not be playable: \(error)")
            }
        } else {
            print("[SwiftAudioEx] Loading remote URL: \(url.absoluteString)")
        }
        
        // Create audio item with metadata
        // IMPORTANT: For file source type, SwiftAudioEx expects a file path, not a file:// URL
        let audioUrl = url.isFileURL ? url.path : url.absoluteString
        let audioItem = DefaultAudioItem(
            audioUrl: audioUrl,
            artist: "TTS",
            title: url.lastPathComponent,
            albumTitle: "Briefeed",
            sourceType: url.isFileURL ? .file : .stream,
            artwork: nil
        )
        
        print("[SwiftAudioEx] Creating DefaultAudioItem:")
        print("[SwiftAudioEx]   - audioUrl: \(audioUrl)")
        print("[SwiftAudioEx]   - sourceType: \(url.isFileURL ? ".file" : ".stream")")
        print("[SwiftAudioEx]   - title: \(url.lastPathComponent)")
        
        // Load and play
        print("[SwiftAudioEx] Loading item into player with playWhenReady: true")
        player.load(item: audioItem, playWhenReady: true)
        
        // Store in queue
        if !queue.contains(url) {
            queue.append(url)
            currentIndex = queue.count - 1
        }
        
        // Start progress timer
        startProgressTimer()
        print("[SwiftAudioEx] play() completed, waiting for player state changes...")
    }
    
    func pause() {
        player.pause()
        progressTimer?.invalidate()
    }
    
    func resume() {
        player.play()
        startProgressTimer()
    }
    
    func stop() {
        player.stop()
        progressTimer?.invalidate()
        state = .stopped
    }
    
    // MARK: - Speed Control
    
    func setRate(_ newRate: Float) {
        // SwiftAudioEx supports rates from 0.25 to 32.0
        // We limit to 0.5 to 20.0 for TTS clarity
        let clampedRate = max(0.5, min(20.0, newRate))
        player.rate = clampedRate
        delegate?.audioRateChanged(to: clampedRate)
        
        // Update Now Playing info
        updateNowPlayingInfo()
    }
    
    // MARK: - Seeking
    
    func seek(to time: TimeInterval) {
        player.seek(to: time)
    }
    
    func skipForward(_ seconds: TimeInterval = 30) {
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
    }
    
    func skipBackward(_ seconds: TimeInterval = 15) {
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }
    
    // MARK: - Queue Management
    
    func loadQueue(_ urls: [URL]) async throws {
        queue = urls
        currentIndex = -1
        
        // For SwiftAudioEx, we'll manage the queue ourselves
        // and load items individually when needed
    }
    
    func playNext() {
        if currentIndex < queue.count - 1 {
            currentIndex += 1
            let url = queue[currentIndex]
            
            // Create and load next item
            // IMPORTANT: For file source type, SwiftAudioEx expects a file path, not a file:// URL
            let audioUrl = url.isFileURL ? url.path : url.absoluteString
            let audioItem = DefaultAudioItem(
                audioUrl: audioUrl,
                artist: "TTS",
                title: url.lastPathComponent,
                albumTitle: "Briefeed",
                sourceType: url.isFileURL ? .file : .stream,
                artwork: nil
            )
            player.load(item: audioItem, playWhenReady: true)
            startProgressTimer()
        }
    }
    
    func playPrevious() {
        if currentIndex > 0 {
            currentIndex -= 1
            let url = queue[currentIndex]
            
            // Create and load previous item
            // IMPORTANT: For file source type, SwiftAudioEx expects a file path, not a file:// URL
            let audioUrl = url.isFileURL ? url.path : url.absoluteString
            let audioItem = DefaultAudioItem(
                audioUrl: audioUrl,
                artist: "TTS",
                title: url.lastPathComponent,
                albumTitle: "Briefeed",
                sourceType: url.isFileURL ? .file : .stream,
                artwork: nil
            )
            player.load(item: audioItem, playWhenReady: true)
            startProgressTimer()
        }
    }
    
    // MARK: - Private Methods
    
    private func handleStateChange(state: AVPlayerWrapperState) {
        switch state {
        case .idle:
            self.state = .idle
        case .loading:
            self.state = .loading
        case .playing:
            self.state = .playing
        case .paused:
            self.state = .paused
        case .stopped:
            self.state = .stopped
        case .failed:
            self.state = .error(TTSError.generationFailed)
        case .ended:
            self.state = .stopped
        case .buffering:
            self.state = .loading
        case .ready:
            self.state = .idle
        }
    }
    
    private func handlePlaybackEnd(reason: PlaybackEndedReason) {
        progressTimer?.invalidate()
        
        switch reason {
        case .playedUntilEnd:
            delegate?.audioDidFinishPlaying(successfully: true)
            // Auto-play next if in queue
            if currentIndex < queue.count - 1 {
                playNext()
            }
        case .playerStopped:
            delegate?.audioDidFinishPlaying(successfully: false)
        case .skippedToNext, .skippedToPrevious:
            // Continue playing
            break
        case .jumpedToIndex:
            // Continue playing
            break
        case .cleared:
            // Queue was cleared
            state = .stopped
            delegate?.audioDidFinishPlaying(successfully: false)
        case .failed:
            // Playback failed
            state = .error(TTSError.generationFailed)
            delegate?.audioDidFinishPlaying(successfully: false)
        @unknown default:
            break
        }
    }
    
    private func handlePlaybackFailure(error: Error?) {
        progressTimer?.invalidate()
        
        // Log detailed error information
        if let error = error {
            print("[SwiftAudioEx] ⚠️ Playback failed with error: \(error)")
            print("[SwiftAudioEx] Error description: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("[SwiftAudioEx] Error code: \(nsError.code)")
                print("[SwiftAudioEx] Error domain: \(nsError.domain)")
                print("[SwiftAudioEx] Error userInfo: \(nsError.userInfo)")
            }
            
            // Check if it's a specific SwiftAudioEx error
            if let playbackError = error as? AudioPlayerError.PlaybackError {
                print("[SwiftAudioEx] Playback error type: \(playbackError)")
            }
        } else {
            print("[SwiftAudioEx] ⚠️ Playback failed with unknown error")
        }
        
        state = .error(error ?? TTSError.generationFailed)
        delegate?.audioDidFinishPlaying(successfully: false)
    }
    
    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }
    
    private func updateProgress() {
        let progress = duration > 0 ? Float(currentTime / duration) : 0
        delegate?.audioProgressUpdated(
            progress: progress,
            currentTime: currentTime,
            duration: duration
        )
        updateNowPlayingInfo()
    }
    
    private func updateNowPlayingInfo() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        info[MPMediaItemPropertyTitle] = queue.isEmpty ? "Briefeed" : queue[max(0, currentIndex)].lastPathComponent
        info[MPMediaItemPropertyAlbumTitle] = "Briefeed"
        info[MPMediaItemPropertyArtist] = "TTS"
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            pause()
        case .ended:
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    resume()
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones were unplugged
            pause()
        default:
            break
        }
    }
}

// MARK: - Unified Audio Player (moved to separate file for clarity)
// This should be in UnifiedAudioPlayer.swift