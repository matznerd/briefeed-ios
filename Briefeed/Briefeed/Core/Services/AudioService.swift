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
import CoreData
import UIKit

// MARK: - Audio Service Types

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

// MARK: - Associated Keys for RSS Extension
internal enum AssociatedKeys {
    static var currentRSSEpisode: UInt8 = 0
    static var rssAudioPlayer: UInt8 = 1
    static var progressObserver: UInt8 = 2
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
    
    // Audio player for Gemini TTS - keep strong reference
    internal var audioPlayer: AVAudioPlayer? {
        didSet {
            if audioPlayer != nil {
                print("📱 Audio player created (setter called)")
                print("📱 Stack trace: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))")
            } else {
                print("📱 Audio player released (setter called)")
                print("📱 Stack trace: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))")
            }
        }
    }
    private var playerTimer: Timer?
    internal var isUsingGeminiTTS = false
    
    // Published properties
    let state = CurrentValueSubject<AudioPlayerState, Never>(.idle)
    let progress = CurrentValueSubject<Float, Never>(0.0)
    let currentRate = CurrentValueSubject<Float, Never>(Constants.Audio.defaultSpeechRate)
    
    // New published properties for queue and progress tracking
    @Published var currentArticle: Article?
    @Published var currentPlaybackItem: CurrentPlaybackItem?
    @Published var playbackContext: PlaybackContext = .direct
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
    internal var nowPlayingInfo: [String: Any] = [:]
    
    // MARK: - Initialization
    override init() {
        super.init()
        synthesizer.delegate = self
        setupNotifications()
        
        // Don't restore queue here - it causes race conditions
        // Queue will be restored by QueueService's own init
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
        
        // Configure audio session - don't let failures stop playback
        try? configureBackgroundAudio()
        
        // Try Gemini TTS first
        print("🎤 Attempting Gemini TTS generation...")
        await ProcessingStatusService.shared.updateGeneratingAudio()
        
        let ttsResult = await GeminiTTSService.shared.generateSpeech(
            text: text,
            voiceName: nil, // Let it use random voice
            useRandomVoice: true
        )
        
        if ttsResult.success, let audioURL = ttsResult.audioURL {
            print("✅ Gemini TTS successful, using voice: \(ttsResult.voiceUsed ?? "unknown")")
            await ProcessingStatusService.shared.updateGeneratingAudio(voiceName: ttsResult.voiceUsed)
            isUsingGeminiTTS = true
            
            do {
                // Stop any existing player first
                audioPlayer?.stop()
                audioPlayer = nil
                
                // Create new player
                audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
                audioPlayer?.delegate = self
                
                print("📱 Audio player created with URL: \(audioURL)")
                print("📱 Audio player duration: \(audioPlayer?.duration ?? 0) seconds")
                print("📱 Audio player isPlaying before prepare: \(audioPlayer?.isPlaying ?? false)")
                
                audioPlayer?.prepareToPlay()
                
                // Configure audio session for playback
                try AVAudioSession.sharedInstance().setActive(true)
                
                // Start playback
                let didPlay = audioPlayer?.play() ?? false
                print("📱 Audio player play() returned: \(didPlay)")
                print("📱 Audio player isPlaying after play: \(audioPlayer?.isPlaying ?? false)")
                
                guard didPlay else {
                    print("❌ Failed to start audio playback")
                    throw AudioServiceError.speechSynthesizerUnavailable
                }
                
                // Update Now Playing info
                updateNowPlayingInfo(title: title, author: author)
                
                // Start progress timer
                startProgressTimer()
                
                state.send(.playing)
                isPausedByUser = false
                
                // Store duration
                duration = audioPlayer?.duration ?? 0
                currentTime = 0
                
                await ProcessingStatusService.shared.updateAudioReady()
                await ProcessingStatusService.shared.completeProcessing()
                
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
        if objc_getAssociatedObject(self, &AssociatedKeys.rssAudioPlayer) != nil {
            playWithRSSSupport()
        } else if isUsingGeminiTTS {
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
        if objc_getAssociatedObject(self, &AssociatedKeys.rssAudioPlayer) != nil {
            pauseWithRSSSupport()
        } else if isUsingGeminiTTS {
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
        currentPlaybackItem = nil
        currentArticle = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    func skipForward(seconds: TimeInterval = 15) {
        if objc_getAssociatedObject(self, &AssociatedKeys.rssAudioPlayer) != nil {
            skipForwardWithRSSSupport(seconds: seconds)
        } else if isUsingGeminiTTS {
            // For Gemini TTS audio player
            guard let player = audioPlayer else { return }
            let newTime = min(player.currentTime + seconds, player.duration)
            player.currentTime = newTime
            updateNowPlayingInfo(title: currentArticle?.title, author: currentArticle?.author)
        } else {
            // AVSpeechSynthesizer doesn't support direct seeking
            guard currentUtterance != nil else { return }
            let newTime = min(currentTime + seconds, duration)
            seek(to: newTime)
        }
    }
    
    func skipBackward(seconds: TimeInterval = 15) {
        if objc_getAssociatedObject(self, &AssociatedKeys.rssAudioPlayer) != nil {
            skipBackwardWithRSSSupport(seconds: seconds)
        } else if isUsingGeminiTTS {
            // For Gemini TTS audio player
            guard let player = audioPlayer else { return }
            let newTime = max(player.currentTime - seconds, 0)
            player.currentTime = newTime
            updateNowPlayingInfo(title: currentArticle?.title, author: currentArticle?.author)
        } else {
            // AVSpeechSynthesizer doesn't support direct seeking
            guard currentUtterance != nil else { return }
            let newTime = max(currentTime - seconds, 0)
            seek(to: newTime)
        }
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
        
        // Update UserDefaults
        UserDefaultsManager.shared.playbackSpeed = clampedRate
        
        // Update RSS player if playing
        if objc_getAssociatedObject(self, &AssociatedKeys.rssAudioPlayer) != nil {
            if let player = objc_getAssociatedObject(self, &AssociatedKeys.rssAudioPlayer) as? AVPlayer {
                player.rate = clampedRate
            }
        } else if isUsingGeminiTTS {
            // For Gemini TTS, we can't change the rate of already generated audio
            // but we'll use the new rate for future generations
        } else if let utterance = currentUtterance {
            // Update current utterance if speaking
            utterance.rate = clampedRate
        }
    }
    
    func configureBackgroundAudio() throws {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // Check if audio session is already configured properly
            let currentCategory = session.category
            let currentMode = session.mode
            let currentOptions = session.categoryOptions
            
            // Only reconfigure if necessary
            if currentCategory != .playback || 
               currentMode != .spokenAudio || 
               !currentOptions.contains([.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]) {
                
                // First deactivate if needed
                if session.isOtherAudioPlaying {
                    try session.setActive(false, options: .notifyOthersOnDeactivation)
                }
                
                // Use playback category with mixWithOthers for non-intrusive playback
                try session.setCategory(
                    .playback,
                    mode: .spokenAudio,
                    options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
                )
                
                print("✅ Audio session category configured")
            }
            
            // Always try to activate the session
            if !session.isOtherAudioPlaying {
                try session.setActive(true)
            } else {
                // If other audio is playing, try with options
                try session.setActive(true, options: [])
            }
            
            print("✅ Audio session activated successfully")
            print("📱 Category: \(session.category.rawValue)")
            print("📱 Mode: \(session.mode.rawValue)")
            print("📱 Options: mixWithOthers, Bluetooth, AirPlay enabled")
        } catch {
            print("❌ Failed to configure audio session: \(error)")
            print("📱 Error code: \((error as NSError).code)")
            print("📱 Error domain: \((error as NSError).domain)")
            
            // Don't throw error - let playback continue anyway
            // Some audio session errors are recoverable
        }
    }
    
    // MARK: - Queue Management
    
    func playArticle(_ article: Article) async throws {
        currentArticle = article
        currentPlaybackItem = CurrentPlaybackItem(from: article)
        
        // Start processing status
        await ProcessingStatusService.shared.startProcessing(articleTitle: article.title ?? "Article")
        
        // If article is already in queue, just jump to it
        if let index = queue.firstIndex(where: { $0.id == article.id }) {
            queueIndex = index
        } else {
            // Add to queue and play
            queue = [article]
            queueIndex = 0
        }
        
        // Check if article needs summary generation
        let needsSummary = (article.summary == nil || article.summary?.isEmpty == true)
        let hasURL = article.url != nil
        
        if needsSummary && hasURL {
            // Show loading state
            state.send(.loading)
            
            // Generate summary first
            if let url = article.url {
                let summary = await GeminiService().generateSummary(from: url)
                
                // Update article with summary if we got one
                if let summary = summary, !summary.isEmpty {
                    await MainActor.run {
                        article.summary = summary
                        do {
                            try article.managedObjectContext?.save()
                        } catch {
                            print("Failed to save article summary: \(error)")
                        }
                    }
                } else {
                    // Firecrawl failed or timed out, create a simple fallback summary
                    print("AudioService: Failed to generate summary, using fallback")
                    await ProcessingStatusService.shared.updateError("Could not fetch article content")
                    
                    await MainActor.run {
                        // Use a more informative fallback that includes the title
                        let fallbackSummary = """
                        Unable to retrieve the full article content at this time. \
                        The website may be slow, blocking automated access, or experiencing issues. \
                        Article title: \(article.title ?? "Unknown"). \
                        You may want to try again later or visit the website directly.
                        """
                        
                        article.summary = fallbackSummary
                        do {
                            try article.managedObjectContext?.save()
                        } catch {
                            print("Failed to save fallback summary: \(error)")
                        }
                    }
                }
            }
        } else if needsSummary && article.content != nil && !article.content!.isEmpty {
            // For articles with content but no URL, generate summary from content
            print("AudioService: Generating summary from existing content")
            do {
                let summary = try await GeminiService().summarize(text: article.content!, length: .standard)
                
                await MainActor.run {
                    article.summary = summary
                    do {
                        try article.managedObjectContext?.save()
                    } catch {
                        print("Failed to save content-based summary: \(error)")
                    }
                }
            } catch {
                print("AudioService: Failed to generate summary from content: \(error)")
                await MainActor.run {
                    article.summary = "Unable to generate summary from content."
                    do {
                        try article.managedObjectContext?.save()
                    } catch {
                        print("Failed to save fallback summary: \(error)")
                    }
                }
            }
        }
        
        // Format the text for speech using the same logic as Capacitor app
        let textToSpeak = GeminiTTSService.shared.formatStoryForSpeech(article)
        
        let title = article.title ?? "Untitled"
        let author = article.author ?? "Unknown"
        
        try await speak(text: textToSpeak, title: title, author: author)
        saveQueueState()
    }
    
    func addToQueue(_ article: Article) {
        // Ensure article has an ID
        if article.id == nil {
            article.id = UUID()
        }
        
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
        print("🎵 playNext() called, context: \(playbackContext)")
        
        // Stop current playback
        stop()
        
        // Handle different contexts
        switch playbackContext {
        case .liveNews:
            // Play next from Live News
            await playNextLiveNews()
            return
            
        case .brief, .direct:
            // Play next from enhanced queue
            break
        }
        
        // Check if QueueService has items to play
        let enhancedQueue = QueueService.shared.enhancedQueue
        print("🎵 Enhanced queue has \(enhancedQueue.count) items")
        
        if !enhancedQueue.isEmpty {
            // Find the currently playing item
            var currentIndex = -1
            if let currentArticle = currentArticle {
                // Check by article ID
                if let articleID = currentArticle.id {
                    currentIndex = enhancedQueue.firstIndex { $0.articleID == articleID } ?? -1
                }
                // Check by audio URL for RSS
                if currentIndex == -1, let url = currentArticle.url {
                    currentIndex = enhancedQueue.firstIndex { $0.audioUrl?.absoluteString == url } ?? -1
                }
            }
            
            print("🎵 Current index in enhanced queue: \(currentIndex)")
            
            // If we found the current item and there's a next item
            if currentIndex >= 0 && currentIndex + 1 < enhancedQueue.count {
                // Play the next item
                let nextItem = enhancedQueue[currentIndex + 1]
                print("🎵 Playing next item: \(nextItem.title)")
                
                await MainActor.run {
                    if let audioUrl = nextItem.audioUrl {
                        // Play RSS episode
                        Task {
                            let fetchRequest: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
                            fetchRequest.predicate = NSPredicate(format: "audioUrl == %@", audioUrl.absoluteString)
                            fetchRequest.fetchLimit = 1
                            
                            if let episode = try? PersistenceController.shared.container.viewContext.fetch(fetchRequest).first {
                                await self.playRSSEpisode(url: audioUrl, title: nextItem.title ?? "Unknown", episode: episode)
                            } else {
                                await self.playRSSEpisode(url: audioUrl, title: nextItem.title ?? "Unknown")
                            }
                        }
                    } else if let articleID = nextItem.articleID {
                        // Play article
                        let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
                        fetchRequest.predicate = NSPredicate(format: "id == %@", articleID as CVarArg)
                        if let article = try? PersistenceController.shared.container.viewContext.fetch(fetchRequest).first {
                            Task {
                                try? await self.playArticle(article)
                            }
                        }
                    }
                }
                return
            } else if currentIndex == -1 && !enhancedQueue.isEmpty {
                // If we couldn't find current item, just play the first item
                await MainActor.run {
                    QueueService.shared.playNext()
                }
                return
            }
        }
        
        // Fallback to regular queue
        guard queueIndex + 1 < queue.count else { 
            print("🎵 No more items in queue")
            return 
        }
        queueIndex += 1
        currentArticle = queue[queueIndex]
        
        if let article = currentArticle {
            try await playArticle(article)
        }
    }
    
    func playPrevious() async throws {
        print("🎵 playPrevious() called")
        
        // Stop current playback
        stop()
        
        // Check if QueueService has items to play
        let enhancedQueue = QueueService.shared.enhancedQueue
        print("🎵 Enhanced queue has \(enhancedQueue.count) items")
        
        if !enhancedQueue.isEmpty {
            // Find the currently playing item
            var currentIndex = -1
            if let currentArticle = currentArticle {
                // Check by article ID
                if let articleID = currentArticle.id {
                    currentIndex = enhancedQueue.firstIndex { $0.articleID == articleID } ?? -1
                }
                // Check by audio URL for RSS
                if currentIndex == -1, let url = currentArticle.url {
                    currentIndex = enhancedQueue.firstIndex { $0.audioUrl?.absoluteString == url } ?? -1
                }
            }
            
            print("🎵 Current index in enhanced queue: \(currentIndex)")
            
            // If we found the current item and there's a previous item
            if currentIndex > 0 {
                // Play the previous item
                let previousItem = enhancedQueue[currentIndex - 1]
                print("🎵 Playing previous item: \(previousItem.title)")
                
                await MainActor.run {
                    if let audioUrl = previousItem.audioUrl {
                        // Play RSS episode
                        Task {
                            let fetchRequest: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
                            fetchRequest.predicate = NSPredicate(format: "audioUrl == %@", audioUrl.absoluteString)
                            fetchRequest.fetchLimit = 1
                            
                            if let episode = try? PersistenceController.shared.container.viewContext.fetch(fetchRequest).first {
                                await self.playRSSEpisode(url: audioUrl, title: previousItem.title ?? "Unknown", episode: episode)
                            } else {
                                await self.playRSSEpisode(url: audioUrl, title: previousItem.title ?? "Unknown")
                            }
                        }
                    } else if let articleID = previousItem.articleID {
                        // Play article
                        let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
                        fetchRequest.predicate = NSPredicate(format: "id == %@", articleID as CVarArg)
                        if let article = try? PersistenceController.shared.container.viewContext.fetch(fetchRequest).first {
                            Task {
                                try? await self.playArticle(article)
                            }
                        }
                    }
                }
                return
            }
        }
        
        // Fallback to regular queue
        guard queueIndex > 0 else { 
            print("🎵 No previous items in queue")
            return 
        }
        queueIndex -= 1
        currentArticle = queue[queueIndex]
        
        if let article = currentArticle {
            try await playArticle(article)
        }
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
    
    // MARK: - Live News Navigation
    
    private func playNextLiveNews() async {
        print("🎵 Playing next Live News episode")
        
        // Get RSS service
        guard let rssService = try? QueueService.shared.getRSSService() else { return }
        
        // Get all feeds sorted by priority
        let feeds = rssService.feeds.filter { $0.isEnabled }
        
        // Find current episode and feed
        var currentFeedIndex = -1
        var currentEpisodeFound = false
        
        if let currentItem = currentPlaybackItem,
           let currentURL = currentItem.audioUrl?.absoluteString {
            
            // Find which feed and episode is currently playing
            for (feedIndex, feed) in feeds.enumerated() {
                if let episodes = feed.episodes?.allObjects as? [RSSEpisode] {
                    let sortedEpisodes = episodes.sorted { $0.pubDate > $1.pubDate }
                    
                    for episode in sortedEpisodes {
                        if episode.audioUrl == currentURL {
                            currentFeedIndex = feedIndex
                            currentEpisodeFound = true
                            break
                        }
                    }
                }
                if currentEpisodeFound { break }
            }
        }
        
        // Find next unlistened episode
        let startIndex = currentEpisodeFound ? currentFeedIndex + 1 : 0
        
        for i in startIndex..<feeds.count {
            let feed = feeds[i]
            if let episodes = feed.episodes?.allObjects as? [RSSEpisode] {
                // Get the most recent unlistened episode
                if let nextEpisode = episodes
                    .filter({ !$0.isListened })
                    .sorted(by: { $0.pubDate > $1.pubDate })
                    .first {
                    
                    // Play the next episode
                    if let audioUrl = URL(string: nextEpisode.audioUrl) {
                        await playRSSEpisode(url: audioUrl, title: nextEpisode.title ?? "Unknown", episode: nextEpisode)
                        return
                    }
                }
            }
        }
        
        print("🎵 No more Live News episodes to play")
        state.send(.stopped)
    }
    
    // MARK: - Private Methods
    
    private func startProgressTimer() {
        playerTimer?.invalidate()
        playerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
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
        
        // Next/Previous track commands
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task {
                try? await self?.playNext()
            }
            return .success
        }
        
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task {
                try? await self?.playPrevious()
            }
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
    
    internal func updateNowPlayingPlaybackState() {
        // Check if RSS is playing
        if let rssPlayer = objc_getAssociatedObject(self, &AssociatedKeys.rssAudioPlayer) as? AVPlayer {
            if rssPlayer.rate > 0 {
                MPNowPlayingInfoCenter.default().playbackState = .playing
            } else {
                MPNowPlayingInfoCenter.default().playbackState = .paused
            }
        } else if synthesizer.isSpeaking && !synthesizer.isPaused {
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
        print("🎵 audioPlayerDidFinishPlaying called - successfully: \(flag)")
        print("🎵 Player duration was: \(player.duration)")
        print("🎵 Player current time: \(player.currentTime)")
        
        Task { @MainActor in
            playerTimer?.invalidate()
            state.send(.stopped)
            progress.send(1.0)
            updateNowPlayingPlaybackState()
            
            // Don't clean up cached audio files
            // Audio files are now cached in AudioCache directory
            
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