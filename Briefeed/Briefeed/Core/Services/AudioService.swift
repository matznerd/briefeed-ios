//
//  AudioService.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit

// MARK: - Audio Service Types
enum AudioPlayerState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case error(Error)
    
    static func == (lhs: AudioPlayerState, rhs: AudioPlayerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.playing, .playing),
             (.paused, .paused), (.stopped, .stopped):
            return true
        case (.error(_), .error(_)):
            return true
        default:
            return false
        }
    }
}

enum AudioServiceError: LocalizedError {
    case speechSynthesizerUnavailable
    case audioSessionError
    case noTextToSpeak
    case interruptedBySystem
    
    var errorDescription: String? {
        switch self {
        case .speechSynthesizerUnavailable:
            return "Text-to-speech is not available"
        case .audioSessionError:
            return "Failed to configure audio session"
        case .noTextToSpeak:
            return "No text provided for speech"
        case .interruptedBySystem:
            return "Audio was interrupted by the system"
        }
    }
}

// MARK: - Audio Service Protocol
@MainActor
protocol AudioServiceProtocol: AnyObject {
    var state: CurrentValueSubject<AudioPlayerState, Never> { get }
    var progress: CurrentValueSubject<Float, Never> { get }
    var currentRate: CurrentValueSubject<Float, Never> { get }
    
    func speak(text: String, title: String?, author: String?) async throws
    func play()
    func pause()
    func stop()
    func skipForward(seconds: TimeInterval)
    func skipBackward(seconds: TimeInterval)
    func setSpeechRate(_ rate: Float)
    func configureBackgroundAudio() throws
}

// MARK: - Audio Service Implementation
@MainActor
class AudioService: NSObject, AudioServiceProtocol, ObservableObject {
    // MARK: - Singleton
    static let shared = AudioService()
    
    // MARK: - Properties
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var fullText: String = ""
    private var currentRange: NSRange = NSRange(location: 0, length: 0)
    private var isPausedByUser = false
    
    // Audio player for Gemini TTS
    private var audioPlayer: AVAudioPlayer?
    private var playerTimer: Timer?
    private var isUsingGeminiTTS = false
    
    // Published properties
    let state = CurrentValueSubject<AudioPlayerState, Never>(.idle)
    let progress = CurrentValueSubject<Float, Never>(0.0)
    let currentRate = CurrentValueSubject<Float, Never>(Constants.Audio.defaultSpeechRate)
    
    // New published properties for queue and progress tracking
    @Published var currentArticle: Article?
    @Published var queue: [Article] = []
    @Published var queueIndex: Int = 0
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 1.0 {
        didSet {
            currentUtterance?.volume = volume
        }
    }
    
    // Queue state persistence
    private let queueKey = "audioQueueArticleIDs"
    private let currentIndexKey = "audioQueueCurrentIndex"
    
    // Now Playing Info
    private var nowPlayingInfo: [String: Any] = [:]
    
    // MARK: - Initialization
    override init() {
        super.init()
        synthesizer.delegate = self
        setupNotifications()
        
        // Restore queue on init
        Task {
            QueueService.shared.restoreQueueOnAppLaunch()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    func speak(text: String, title: String? = nil, author: String? = nil) async throws {
        print("🎤 speak() called with text length: \(text.count)")
        
        guard !text.isEmpty else {
            print("❌ No text to speak")
            throw AudioServiceError.noTextToSpeak
        }
        
        // Stop any current speech
        stop()
        
        // Update state
        state.send(.loading)
        
        // Store the full text
        fullText = text
        currentRange = NSRange(location: 0, length: 0)
        progress.send(0.0)
        
        // Configure audio session
        do {
            try configureBackgroundAudio()
        } catch {
            print("⚠️ Audio session configuration failed, continuing anyway: \(error)")
        }
        
        // Try Gemini TTS first
        print("🎤 Attempting Gemini TTS generation...")
        let ttsResult = await GeminiTTSService.shared.generateSpeech(
            text: text,
            voiceName: nil, // Let it use random voice
            useRandomVoice: true
        )
        
        if ttsResult.success, let audioURL = ttsResult.audioURL {
            print("✅ Gemini TTS successful, using voice: \(ttsResult.voiceUsed ?? "unknown")")
            isUsingGeminiTTS = true
            
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
                audioPlayer?.delegate = self
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                
                // Update Now Playing info
                updateNowPlayingInfo(title: title, author: author)
                
                // Start progress timer
                startProgressTimer()
                
                state.send(.playing)
                isPausedByUser = false
                
                // Store duration
                duration = audioPlayer?.duration ?? 0
                currentTime = 0
                
                print("✅ Audio playback started with Gemini TTS")
            } catch {
                print("❌ Failed to play Gemini audio: \(error)")
                // Fall back to device TTS
                try await speakWithDeviceTTS(text: text, title: title, author: author)
            }
        } else {
            print("⚠️ Gemini TTS failed: \(ttsResult.error ?? "Unknown error"), falling back to device TTS")
            // Fall back to device TTS
            try await speakWithDeviceTTS(text: text, title: title, author: author)
        }
    }
    
    private func speakWithDeviceTTS(text: String, title: String?, author: String?) async throws {
        isUsingGeminiTTS = false
        
        print("📝 Creating utterance for device TTS...")
        
        // Create utterance with clean text
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        currentUtterance = AVSpeechUtterance(string: cleanText)
        
        // Use default settings for better compatibility
        if let utterance = currentUtterance {
            utterance.rate = UserDefaultsManager.shared.playbackSpeed
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1.0
            
            // Use default voice
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            
            print("✅ Utterance created with rate: \(utterance.rate), volume: \(utterance.volume)")
        }
        
        // Update Now Playing info
        updateNowPlayingInfo(title: title, author: author)
        
        // Start speaking
        guard let utterance = currentUtterance else {
            state.send(.idle)
            throw AudioServiceError.noTextToSpeak
        }
        
        print("🎤 Starting device speech synthesis with text length: \(text.count)")
        print("📱 Synthesizer state - isPaused: \(synthesizer.isPaused), isSpeaking: \(synthesizer.isSpeaking)")
        
        // Ensure synthesizer is ready
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        // Start speech synthesis (already on main thread due to @MainActor)
        print("🎯 Speaking utterance with device TTS")
        synthesizer.speak(utterance)
        isPausedByUser = false
        state.send(.playing)
        
        print("✅ Device speech synthesis started")
    }
    
    func play() {
        if isUsingGeminiTTS {
            audioPlayer?.play()
            startProgressTimer()
            isPausedByUser = false
            state.send(.playing)
            updateNowPlayingPlaybackState()
        } else {
            if synthesizer.isPaused {
                synthesizer.continueSpeaking()
                isPausedByUser = false
                state.send(.playing)
                updateNowPlayingPlaybackState()
            } else if let utterance = currentUtterance, !synthesizer.isSpeaking {
                // Restart from beginning if stopped
                synthesizer.speak(utterance)
                isPausedByUser = false
            }
        }
    }
    
    func pause() {
        if isUsingGeminiTTS {
            audioPlayer?.pause()
            playerTimer?.invalidate()
            isPausedByUser = true
            state.send(.paused)
            updateNowPlayingPlaybackState()
        } else {
            if synthesizer.isSpeaking && !synthesizer.isPaused {
                synthesizer.pauseSpeaking(at: .immediate)
                isPausedByUser = true
                state.send(.paused)
                updateNowPlayingPlaybackState()
            }
        }
    }
    
    func stop() {
        if isUsingGeminiTTS {
            audioPlayer?.stop()
            audioPlayer = nil
            playerTimer?.invalidate()
            isUsingGeminiTTS = false
        }
        
        synthesizer.stopSpeaking(at: .immediate)
        currentUtterance = nil
        fullText = ""
        currentRange = NSRange(location: 0, length: 0)
        progress.send(0.0)
        state.send(.stopped)
        currentTime = 0
        duration = 0
        currentArticle = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    func skipForward(seconds: TimeInterval = 15) {
        // AVSpeechSynthesizer doesn't support direct seeking, but we can simulate it
        // by calculating the new position and restarting from there
        guard currentUtterance != nil else { return }
        
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
    }
    
    func skipBackward(seconds: TimeInterval = 15) {
        // AVSpeechSynthesizer doesn't support direct seeking, but we can simulate it
        // by calculating the new position and restarting from there
        guard currentUtterance != nil else { return }
        
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }
    
    func skip(by seconds: TimeInterval) {
        if seconds > 0 {
            skipForward(seconds: seconds)
        } else {
            skipBackward(seconds: abs(seconds))
        }
    }
    
    func seek(to time: TimeInterval) {
        // AVSpeechSynthesizer doesn't support direct seeking
        // For a production app, you might want to use a different TTS engine that supports seeking
        // For now, we'll update the current time and notify UI
        currentTime = min(max(time, 0), duration)
        
        // Update progress
        if duration > 0 {
            let progressValue = Float(currentTime / duration)
            progress.send(progressValue)
        }
        
        // Update Now Playing info
        if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
    
    func setSpeechRate(_ rate: Float) {
        let clampedRate = max(Constants.Audio.minSpeechRate, min(rate, Constants.Audio.maxSpeechRate))
        currentRate.send(clampedRate)
        
        // Update current utterance if speaking
        if let utterance = currentUtterance {
            utterance.rate = clampedRate
        }
    }
    
    func configureBackgroundAudio() throws {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // Use playback category for TTS
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            
            print("✅ Audio session configured successfully")
            print("📱 Category: \(session.category.rawValue)")
            print("📱 Mode: \(session.mode.rawValue)")
        } catch {
            print("❌ Failed to configure audio session: \(error)")
            throw AudioServiceError.audioSessionError
        }
    }
    
    // MARK: - Queue Management
    
    func playArticle(_ article: Article) async throws {
        currentArticle = article
        
        // If article is already in queue, just jump to it
        if let index = queue.firstIndex(where: { $0.id == article.id }) {
            queueIndex = index
        } else {
            // Add to queue and play
            queue = [article]
            queueIndex = 0
        }
        
        // Format the text for speech using the same logic as Capacitor app
        let textToSpeak = GeminiTTSService.shared.formatStoryForSpeech(article)
        
        let title = article.title ?? "Untitled"
        let author = article.author ?? "Unknown"
        
        try await speak(text: textToSpeak, title: title, author: author)
        saveQueueState()
    }
    
    func addToQueue(_ article: Article) {
        // Don't add duplicates
        guard !queue.contains(where: { $0.id == article.id }) else { return }
        queue.append(article)
        saveQueueState()
    }
    
    func removeFromQueue(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        
        // If removing the currently playing item, stop playback
        if index == queueIndex {
            stop()
        }
        
        queue.remove(at: index)
        
        // Adjust queue index if necessary
        if index < queueIndex {
            queueIndex -= 1
        } else if index == queueIndex && queueIndex >= queue.count {
            queueIndex = max(0, queue.count - 1)
        }
    }
    
    func reorderQueue(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        
        // Adjust current index if needed
        if let sourceIndex = source.first {
            let currentIndex = queueIndex
            
            if sourceIndex == currentIndex {
                // Moving the currently playing item
                queueIndex = destination > sourceIndex ? destination - 1 : destination
            } else if sourceIndex < currentIndex && destination > currentIndex {
                // Moving an item from before current to after current
                queueIndex -= 1
            } else if sourceIndex > currentIndex && destination <= currentIndex {
                // Moving an item from after current to before/at current
                queueIndex += 1
            }
        }
    }
    
    func playNext() async throws {
        guard queueIndex + 1 < queue.count else { return }
        queueIndex += 1
        currentArticle = queue[queueIndex]
        
        let content = currentArticle?.content ?? ""
        let title = currentArticle?.title ?? "Untitled"
        let author = currentArticle?.author ?? "Unknown"
        
        // Strip HTML from content
        let textToSpeak = content.stripHTML
        
        try await speak(text: textToSpeak, title: title, author: author)
    }
    
    func playPrevious() async throws {
        guard queueIndex > 0 else { return }
        queueIndex -= 1
        currentArticle = queue[queueIndex]
        
        let content = currentArticle?.content ?? ""
        let title = currentArticle?.title ?? "Untitled"
        let author = currentArticle?.author ?? "Unknown"
        
        // Strip HTML from content
        let textToSpeak = content.stripHTML
        
        try await speak(text: textToSpeak, title: title, author: author)
    }
    
    func clearQueue() {
        queue.removeAll()
        queueIndex = 0
        currentArticle = nil
        stop()
        clearQueueState()
        
        // Notify QueueService
        Task {
            QueueService.shared.clearQueue()
        }
    }
    
    // MARK: - Queue Persistence
    
    private func saveQueueState() {
        let queueIDs = queue.compactMap { $0.id?.uuidString }
        UserDefaults.standard.set(queueIDs, forKey: queueKey)
        UserDefaults.standard.set(queueIndex, forKey: currentIndexKey)
    }
    
    private func clearQueueState() {
        UserDefaults.standard.removeObject(forKey: queueKey)
        UserDefaults.standard.removeObject(forKey: currentIndexKey)
    }
    
    func restoreQueueState(articles: [Article]) {
        guard let queueIDs = UserDefaults.standard.stringArray(forKey: queueKey) else { return }
        let savedIndex = UserDefaults.standard.integer(forKey: currentIndexKey)
        
        // Rebuild queue from saved IDs
        let restoredQueue: [Article] = queueIDs.compactMap { idString -> Article? in
            guard let uuid = UUID(uuidString: idString) else { return nil }
            return articles.first { $0.id == uuid }
        }
        
        if !restoredQueue.isEmpty {
            queue = restoredQueue
            queueIndex = min(savedIndex, restoredQueue.count - 1)
            currentArticle = queueIndex >= 0 && queueIndex < restoredQueue.count ? restoredQueue[queueIndex] : nil
        }
    }
    
    // Play Next (like "Play Now" in Capacitor app)
    func playNow(_ article: Article) async throws {
        // Stop current playback
        stop()
        
        // Play immediately
        try await playArticle(article)
    }
    
    // Add as next in queue (like "Play Next" in Capacitor app)
    func playAfterCurrent(_ article: Article) {
        // Don't add duplicates
        guard !queue.contains(where: { $0.id == article.id }) else { return }
        
        // Insert after current index
        let insertIndex = min(queueIndex + 1, queue.count)
        queue.insert(article, at: insertIndex)
        saveQueueState()
    }
    
    // MARK: - Private Methods
    
    private func startProgressTimer() {
        playerTimer?.invalidate()
        playerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            
            self.currentTime = player.currentTime
            
            if self.duration > 0 {
                let progressValue = Float(self.currentTime / self.duration)
                self.progress.send(progressValue)
                
                // Update Now Playing info
                if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.currentTime
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        }
    }
    
    private func setupNotifications() {
        // Audio interruption handling
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        // Route change handling
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        // Remote control events
        setupRemoteCommandCenter()
    }
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        
        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        // Stop command
        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { [weak self] _ in
            self?.stop()
            return .success
        }
        
        // Skip forward/backward commands
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward()
            return .success
        }
        
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward()
            return .success
        }
        
        // Playback rate command
        commandCenter.changePlaybackRateCommand.isEnabled = true
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let rateEvent = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            self?.setSpeechRate(rateEvent.playbackRate)
            return .success
        }
    }
    
    private func updateNowPlayingInfo(title: String?, author: String?) {
        nowPlayingInfo[MPMediaItemPropertyTitle] = title ?? "Briefeed Article"
        nowPlayingInfo[MPMediaItemPropertyArtist] = author ?? "Unknown Author"
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "Briefeed"
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = currentRate.value
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        
        // Estimate duration based on text length and speech rate
        let wordsPerMinute = 150.0 * Double(currentRate.value)
        let wordCount = Double(fullText.split(separator: " ").count)
        let estimatedDuration = (wordCount / wordsPerMinute) * 60.0
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = estimatedDuration
        
        // Update our duration property
        self.duration = estimatedDuration
        self.currentTime = 0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func updateNowPlayingPlaybackState() {
        if synthesizer.isSpeaking && !synthesizer.isPaused {
            MPNowPlayingInfoCenter.default().playbackState = .playing
        } else if synthesizer.isPaused {
            MPNowPlayingInfoCenter.default().playbackState = .paused
        } else {
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
    }
    
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            // Interruption began - pause if playing
            if synthesizer.isSpeaking && !synthesizer.isPaused {
                pause()
            }
        case .ended:
            // Interruption ended - resume if not paused by user
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && !isPausedByUser {
                    play()
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones were unplugged - pause playback
            if synthesizer.isSpeaking && !synthesizer.isPaused {
                pause()
            }
        default:
            break
        }
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            playerTimer?.invalidate()
            state.send(.stopped)
            progress.send(1.0)
            updateNowPlayingPlaybackState()
            
            // Clean up temporary audio file
            if let url = player.url {
                try? FileManager.default.removeItem(at: url)
            }
            
            // Play next if auto-play is enabled
            if UserDefaultsManager.shared.autoPlayNext && queueIndex + 1 < queue.count {
                try? await playNext()
            }
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            playerTimer?.invalidate()
            state.send(.error(error ?? AudioServiceError.speechSynthesizerUnavailable))
            print("❌ Audio player decode error: \(error?.localizedDescription ?? "Unknown error")")
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension AudioService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            state.send(.playing)
            updateNowPlayingPlaybackState()
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            state.send(.paused)
            updateNowPlayingPlaybackState()
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            state.send(.playing)
            updateNowPlayingPlaybackState()
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            state.send(.stopped)
            progress.send(1.0)
            updateNowPlayingPlaybackState()
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            state.send(.stopped)
            progress.send(0.0)
            updateNowPlayingPlaybackState()
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            currentRange = characterRange
            
            // Calculate progress
            let currentLocation = characterRange.location + characterRange.length
            let totalLength = utterance.speechString.count
            let progressValue = Float(currentLocation) / Float(totalLength)
            progress.send(progressValue)
            
            // Update elapsed time in Now Playing
            if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo,
               let duration = info[MPMediaItemPropertyPlaybackDuration] as? TimeInterval {
                let elapsedTime = duration * Double(progressValue)
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                
                // Update our currentTime property
                self.currentTime = elapsedTime
            }
        }
    }
}

// MARK: - Time Formatting Helpers
extension AudioService {
    static func formatTime(_ timeInterval: TimeInterval) -> String {
        guard !timeInterval.isNaN && !timeInterval.isInfinite else {
            return "0:00"
        }
        
        let totalSeconds = Int(timeInterval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    static func formatTimeRemaining(_ current: TimeInterval, _ total: TimeInterval) -> String {
        let remaining = max(0, total - current)
        return "-\(formatTime(remaining))"
    }
}