import Foundation
import AVFoundation
import MediaPlayer
import Combine

// MARK: - AudioServiceV2
// Fixed architecture: Plain singleton, no ObservableObject, no @MainActor

final class AudioServiceV2: NSObject {
    // MARK: - Singleton
    static let shared = AudioServiceV2()
    
    // MARK: - Properties (No @Published!)
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var currentUtterance: AVSpeechUtterance?
    private var fullText: String = ""
    private var currentRange: NSRange = NSRange(location: 0, length: 0)
    private var isPausedByUser = false
    private var playerTimer: Timer?
    
    // State management (plain properties, not @Published)
    private(set) var state: AudioPlayerState = .idle {
        didSet {
            // Notify delegate of state changes
            delegate?.audioStateChanged(to: state, from: oldValue)
        }
    }
    
    private(set) var progress: Float = 0.0
    private(set) var currentRate: Float = 1.0
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var volume: Float = 1.0
    
    // Current playback info
    private(set) var currentArticle: Article?
    private(set) var currentTitle: String?
    private(set) var currentAuthor: String?
    
    // Delegate for state changes (instead of @Published)
    weak var delegate: AudioServiceDelegate?
    
    // MARK: - Initialization (LIGHTWEIGHT!)
    private override init() {
        super.init()
        // Only lightweight setup in init
        synthesizer.delegate = self
        
        // Safety check from our monitor
        SafetyMonitor.shared.checkSingletonNotObservable(self)
        SafetyMonitor.shared.checkNoPublishedInService(self)
    }
    
    // MARK: - Async Initialization (HEAVY WORK HERE)
    func initialize() async {
        // Heavy work goes here, not in init
        SafetyMonitor.shared.assertNotMainThread()
        
        // Load saved playback speed
        currentRate = UserDefaultsManager.shared.playbackSpeed
        
        // Setup notifications
        await setupNotifications()
        
        // Configure audio session
        do {
            try await configureAudioSession()
        } catch {
            print("⚠️ Audio session configuration failed: \(error)")
        }
    }
    
    // MARK: - Audio Session Configuration
    private func configureAudioSession() async throws {
        let session = AVAudioSession.sharedInstance()
        
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.allowBluetooth, .allowAirPlay]
        )
        
        try session.setActive(true)
    }
    
    // MARK: - Public Methods (Async, no blocking)
    
    func speak(text: String, title: String? = nil, author: String? = nil) async throws {
        guard !text.isEmpty else {
            throw AudioServiceError.noTextToSpeak
        }
        
        // Stop any current speech
        await stop()
        
        // Update state
        state = .loading
        fullText = text
        currentTitle = title
        currentAuthor = author
        currentRange = NSRange(location: 0, length: 0)
        progress = 0.0
        
        // Try Gemini TTS first
        let ttsResult = await generateTTS(text: text)
        
        if let audioURL = ttsResult.audioURL {
            // Play generated audio
            try await playAudioFile(url: audioURL)
        } else {
            // Fallback to system TTS
            await playSystemTTS(text: text)
        }
        
        // Update Now Playing info
        await updateNowPlayingInfo(title: title, author: author)
        
        state = .playing
        isPausedByUser = false
    }
    
    func pause() {
        SafetyMonitor.shared.measureBlock(name: "AudioService.pause") {
            if let player = audioPlayer, player.isPlaying {
                player.pause()
                state = .paused
                isPausedByUser = true
            } else if synthesizer.isSpeaking {
                synthesizer.pauseSpeaking(at: .immediate)
                state = .paused
                isPausedByUser = true
            }
        }
    }
    
    func resume() {
        SafetyMonitor.shared.measureBlock(name: "AudioService.resume") {
            if let player = audioPlayer {
                player.play()
                state = .playing
                isPausedByUser = false
            } else if synthesizer.isPaused {
                synthesizer.continueSpeaking()
                state = .playing
                isPausedByUser = false
            }
        }
    }
    
    func stop() async {
        if let player = audioPlayer {
            player.stop()
            audioPlayer = nil
        }
        
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        playerTimer?.invalidate()
        playerTimer = nil
        
        state = .stopped
        progress = 0.0
        currentTime = 0
        duration = 0
        currentArticle = nil
        currentTitle = nil
        currentAuthor = nil
    }
    
    func setRate(_ rate: Float) {
        currentRate = max(0.5, min(rate, 2.0)) // System TTS limited to 2x
        
        // Save to UserDefaults for persistence
        UserDefaultsManager.shared.playbackSpeed = currentRate
        
        // Note: AVSpeechUtterance rate cannot be changed while speaking
        // The new rate will be applied to the next utterance
        // For immediate effect, user would need to stop and restart playback
        
        // Note: For speeds > 2x, we need AudioStreaming library
        delegate?.audioRateChanged(to: currentRate)
    }
    
    func setVolume(_ volume: Float) {
        self.volume = max(0.0, min(volume, 1.0))
        
        audioPlayer?.volume = self.volume
        currentUtterance?.volume = self.volume
    }
    
    // MARK: - Private Helper Methods
    
    private func generateTTS(text: String) async -> (audioURL: URL?, success: Bool) {
        // Call Gemini TTS service
        let result = await GeminiTTSService.shared.generateSpeech(
            text: text,
            voiceName: nil,
            useRandomVoice: true
        )
        
        return (result.audioURL, result.success)
    }
    
    private func playAudioFile(url: URL) async throws {
        audioPlayer?.stop()
        audioPlayer = nil
        
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()
        
        duration = audioPlayer?.duration ?? 0
        
        guard audioPlayer?.play() == true else {
            throw AudioServiceError.speechSynthesizerUnavailable
        }
        
        startProgressTimer()
    }
    
    private func playSystemTTS(text: String) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = currentRate
        utterance.volume = volume
        
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }
    
    private func startProgressTimer() {
        playerTimer?.invalidate()
        playerTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }
    
    private func updateProgress() {
        if let player = audioPlayer {
            currentTime = player.currentTime
            duration = player.duration
            
            if duration > 0 {
                progress = Float(currentTime / duration)
            }
            
            delegate?.audioProgressUpdated(progress: progress, currentTime: currentTime, duration: duration)
        }
    }
    
    private func setupNotifications() async {
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
    
    @objc private func handleInterruption(_ notification: Notification) {
        // Handle audio interruptions
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        // Handle route changes
    }
    
    private func updateNowPlayingInfo(title: String?, author: String?) async {
        await MainActor.run {
            var info = [String: Any]()
            info[MPMediaItemPropertyTitle] = title ?? "Unknown"
            info[MPMediaItemPropertyArtist] = author ?? "Briefeed"
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            info[MPNowPlayingInfoPropertyPlaybackRate] = state == .playing ? 1.0 : 0.0
            
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioServiceV2: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        state = .stopped
        delegate?.audioDidFinishPlaying(successfully: flag)
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let errorMessage = error?.localizedDescription ?? "Speech synthesizer unavailable"
        state = .error(errorMessage)
        delegate?.audioDecodeError(error)
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension AudioServiceV2: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        state = .playing
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        state = .paused
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        state = .playing
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        state = .stopped
        delegate?.audioDidFinishPlaying(successfully: true)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        currentRange = characterRange
        
        if fullText.count > 0 {
            let position = characterRange.location + characterRange.length
            progress = Float(position) / Float(fullText.count)
            
            delegate?.audioProgressUpdated(progress: progress, currentTime: 0, duration: 0)
        }
    }
}

// MARK: - Delegate Protocol
protocol AudioServiceDelegate: AnyObject {
    func audioStateChanged(to newState: AudioPlayerState, from oldState: AudioPlayerState)
    func audioProgressUpdated(progress: Float, currentTime: TimeInterval, duration: TimeInterval)
    func audioRateChanged(to rate: Float)
    func audioDidFinishPlaying(successfully: Bool)
    func audioDecodeError(_ error: Error?)
}