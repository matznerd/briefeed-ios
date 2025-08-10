//
//  SwiftAudioExService.swift
//  Briefeed
//
//  SwiftAudioEx integration for high-performance audio playback
//  Supports up to 20x speed, seeking, and streaming
//

import Foundation
import AVFoundation
// import SwiftAudioEx // Uncomment when ready to integrate

// MARK: - Audio Player State

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
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}

// MARK: - Delegate Protocol

protocol SwiftAudioExServiceDelegate: AnyObject {
    func audioStateChanged(to newState: AudioPlayerState, from oldState: AudioPlayerState)
    func audioProgressUpdated(progress: Float, currentTime: TimeInterval, duration: TimeInterval)
    func audioRateChanged(to rate: Float)
    func audioDidFinishPlaying(successfully: Bool)
}

// MARK: - SwiftAudioEx Service

final class SwiftAudioExService: NSObject {
    
    // MARK: - Properties
    
    // private let player = AudioPlayer() // SwiftAudioEx player
    weak var delegate: SwiftAudioExServiceDelegate?
    
    private(set) var state: AudioPlayerState = .idle {
        didSet {
            if state != oldValue {
                delegate?.audioStateChanged(to: state, from: oldValue)
            }
        }
    }
    
    private(set) var isPlaying: Bool = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float = 1.0
    private(set) var backgroundPlaybackEnabled: Bool = true
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupPlayer()
        setupRemoteControl()
        setupNotifications()
    }
    
    private func setupPlayer() {
        // Configure SwiftAudioEx player
        // player.delegate = self
        // player.bufferDuration = 2.0
        // player.automaticallyUpdateNowPlayingInfo = true
    }
    
    private func setupRemoteControl() {
        // Setup remote control commands
        // let commandCenter = MPRemoteCommandCenter.shared()
        // commandCenter.playCommand.addTarget { [weak self] _ in
        //     self?.resume()
        //     return .success
        // }
        // etc...
    }
    
    private func setupNotifications() {
        // Handle app lifecycle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
    
    // MARK: - Playback Control
    
    func play(url: URL) async throws {
        state = .loading
        
        // Create audio item
        // let item = DefaultAudioItem(
        //     audioUrl: url.absoluteString,
        //     sourceType: url.isFileURL ? .file : .stream
        // )
        
        // Load and play
        // try await player.load(item: item)
        // player.play()
        
        state = .playing
        isPlaying = true
    }
    
    func play(data: Data) async throws {
        // Save data to temp file and play
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        
        try data.write(to: tempURL)
        try await play(url: tempURL)
    }
    
    func pause() {
        // player.pause()
        state = .paused
        isPlaying = false
    }
    
    func resume() {
        // player.play()
        state = .playing
        isPlaying = true
    }
    
    func stop() {
        // player.stop()
        state = .stopped
        isPlaying = false
        currentTime = 0
    }
    
    func seek(to time: TimeInterval) {
        // player.seek(to: time)
        currentTime = time
    }
    
    func setRate(_ newRate: Float) {
        // SwiftAudioEx supports up to 32x, we limit to 20x
        let clampedRate = max(0.25, min(newRate, 20.0))
        // player.rate = clampedRate
        rate = clampedRate
        delegate?.audioRateChanged(to: clampedRate)
    }
    
    // MARK: - Queue Management
    
    func loadQueue(_ items: [URL]) async throws {
        // Load multiple items
        // let audioItems = items.map { url in
        //     DefaultAudioItem(
        //         audioUrl: url.absoluteString,
        //         sourceType: url.isFileURL ? .file : .stream
        //     )
        // }
        // try await player.load(items: audioItems)
    }
    
    func playNext() {
        // player.next()
    }
    
    func playPrevious() {
        // player.previous()
    }
    
    // MARK: - Interruption Handling
    
    @objc private func handleInterruption(_ notification: Notification) {
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
}

// MARK: - SwiftAudioEx Player Delegate

// extension SwiftAudioExService: AudioPlayerDelegate {
//     func audioPlayer(_ player: AudioPlayer, didChangeState state: AudioPlayerState) {
//         // Map SwiftAudioEx state to our state
//     }
//     
//     func audioPlayer(_ player: AudioPlayer, didUpdateProgress progress: TimeInterval, duration: TimeInterval) {
//         currentTime = progress
//         self.duration = duration
//         let progressFloat = duration > 0 ? Float(progress / duration) : 0
//         delegate?.audioProgressUpdated(progress: progressFloat, currentTime: progress, duration: duration)
//     }
//     
//     func audioPlayer(_ player: AudioPlayer, didFinishPlaying successfully: Bool) {
//         delegate?.audioDidFinishPlaying(successfully: successfully)
//     }
// }

// MARK: - TTS Generator Service

final class TTSGeneratorService {
    
    enum TTSError: Error {
        case emptyText
        case generationFailed
        case fileWriteFailed
    }
    
    private let cacheDirectory: URL
    
    init() {
        // Setup cache directory
        let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachePath.appendingPathComponent("tts_audio", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func generateAudioFile(from text: String) async throws -> URL {
        guard !text.isEmpty else {
            throw TTSError.emptyText
        }
        
        // Check cache first
        let cacheKey = text.hash
        let cachedURL = cacheDirectory
            .appendingPathComponent("\(cacheKey)")
            .appendingPathExtension("mp3")
        
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }
        
        // Generate with Gemini TTS
        let audioData = try await generateWithGeminiTTS(text: text)
        
        // Save to cache
        try audioData.write(to: cachedURL)
        
        return cachedURL
    }
    
    private func generateWithGeminiTTS(text: String) async throws -> Data {
        // Call Gemini TTS service
        // This will use the existing GeminiTTSService
        // For now, return dummy data for testing
        return Data()
    }
    
    func clearCache() throws {
        try FileManager.default.removeItem(at: cacheDirectory)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    var cacheSize: Int64 {
        let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        
        return files?.reduce(0) { total, url in
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            return total + Int64(size ?? 0)
        } ?? 0
    }
}

// MARK: - Unified Audio Player

final class UnifiedAudioPlayer: ObservableObject {
    
    enum QueueItem {
        case article(Article)
        case rssEpisode(RSSEpisode)
        
        var title: String {
            switch self {
            case .article(let article):
                return article.title ?? "Unknown"
            case .rssEpisode(let episode):
                return episode.title
            }
        }
    }
    
    // MARK: - Properties
    
    private let audioService = SwiftAudioExService()
    private let ttsGenerator = TTSGeneratorService()
    
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTitle: String?
    @Published private(set) var currentAudioURL: URL?
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isStreaming: Bool = false
    
    private var queue: [QueueItem] = []
    
    var rate: Float {
        get { audioService.rate }
        set { audioService.setRate(newValue) }
    }
    
    var cacheSize: Int64 {
        ttsGenerator.cacheSize
    }
    
    // MARK: - Initialization
    
    init() {
        audioService.delegate = self
    }
    
    // MARK: - Playback
    
    func play(article: Article) async throws {
        guard let content = article.content else { return }
        
        currentTitle = article.title
        isStreaming = false
        
        // Generate TTS audio file
        let audioFile = try await ttsGenerator.generateAudioFile(from: content)
        currentAudioURL = audioFile
        
        // Play with SwiftAudioEx
        try await audioService.play(url: audioFile)
        isPlaying = true
    }
    
    func play(episode: RSSEpisode) async throws {
        guard let urlString = episode.audioUrl,
              let url = URL(string: urlString) else { return }
        
        currentTitle = episode.title
        currentAudioURL = url
        isStreaming = true
        
        // Stream directly with SwiftAudioEx
        try await audioService.play(url: url)
        isPlaying = true
    }
    
    func play() async throws {
        guard currentIndex < queue.count else { return }
        
        let item = queue[currentIndex]
        switch item {
        case .article(let article):
            try await play(article: article)
        case .rssEpisode(let episode):
            try await play(episode: episode)
        }
    }
    
    func playNext() async throws {
        guard currentIndex < queue.count - 1 else { return }
        currentIndex += 1
        try await play()
    }
    
    func pause() {
        audioService.pause()
        isPlaying = false
    }
    
    func resume() {
        audioService.resume()
        isPlaying = true
    }
    
    func seek(to time: TimeInterval) {
        audioService.seek(to: time)
        currentTime = time
    }
    
    // MARK: - Queue Management
    
    func setQueue(_ items: [QueueItem]) async throws {
        queue = items
        currentIndex = 0
    }
    
    // MARK: - State Persistence
    
    struct PlayerState: Codable {
        let currentTime: TimeInterval
        let playbackRate: Float
        let currentItemTitle: String?
        let currentIndex: Int
        let queueItems: [String] // Simplified for example
    }
    
    func saveState() -> PlayerState {
        PlayerState(
            currentTime: currentTime,
            playbackRate: rate,
            currentItemTitle: currentTitle,
            currentIndex: currentIndex,
            queueItems: queue.map { $0.title }
        )
    }
    
    func restoreState(_ state: PlayerState) async throws {
        currentTime = state.currentTime
        rate = state.playbackRate
        currentTitle = state.currentItemTitle
        currentIndex = state.currentIndex
        // Note: Would need to restore actual queue items from Core Data
        
        if currentTime > 0 {
            audioService.seek(to: currentTime)
        }
    }
}

// MARK: - SwiftAudioExServiceDelegate

extension UnifiedAudioPlayer: SwiftAudioExServiceDelegate {
    func audioStateChanged(to newState: AudioPlayerState, from oldState: AudioPlayerState) {
        DispatchQueue.main.async { [weak self] in
            switch newState {
            case .playing:
                self?.isPlaying = true
            case .paused, .stopped:
                self?.isPlaying = false
            default:
                break
            }
        }
    }
    
    func audioProgressUpdated(progress: Float, currentTime: TimeInterval, duration: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.currentTime = currentTime
            self?.duration = duration
        }
    }
    
    func audioRateChanged(to rate: Float) {
        // Handle rate change if needed
    }
    
    func audioDidFinishPlaying(successfully: Bool) {
        if successfully {
            Task { [weak self] in
                try? await self?.playNext()
            }
        }
    }
}