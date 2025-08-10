//
//  UnifiedAudioPlayer.swift
//  Briefeed
//
//  Bridge between TTS generation and SwiftAudioEx playback
//  Orchestrates the complete audio pipeline
//

import Foundation
import SwiftUI
import AVFoundation
import CoreData
import Combine

// MARK: - Unified Queue Item

/// Unified representation of a queue item (Article or RSS Episode)
@MainActor
class UnifiedQueueItem: ObservableObject, Identifiable {
    let id: String
    let type: QueueItemType
    let title: String
    let content: String?
    let audioURL: URL?
    let article: Article?
    let episode: RSSEpisode?
    
    @Published var generationState: GenerationState = .pending
    @Published var cachedAudioURL: URL?
    @Published var duration: TimeInterval = 0
    
    enum QueueItemType {
        case article
        case rssEpisode
    }
    
    enum GenerationState: Equatable {
        case pending
        case generating
        case ready
        case failed(Error)
        
        static func == (lhs: GenerationState, rhs: GenerationState) -> Bool {
            switch (lhs, rhs) {
            case (.pending, .pending), 
                 (.generating, .generating), 
                 (.ready, .ready):
                return true
            case (.failed(_), .failed(_)):
                return true
            default:
                return false
            }
        }
    }
    
    init(article: Article) {
        self.id = article.objectID.uriRepresentation().absoluteString
        self.type = .article
        self.title = article.title ?? "Untitled"
        self.content = article.summary ?? article.content
        self.audioURL = nil
        self.article = article
        self.episode = nil
    }
    
    init(episode: RSSEpisode) {
        self.id = episode.id ?? UUID().uuidString
        self.type = .rssEpisode
        self.title = episode.title ?? "Untitled Episode"
        self.content = episode.episodeDescription
        if let audioUrlString = episode.audioUrl {
            self.audioURL = URL(string: audioUrlString)
        } else {
            self.audioURL = nil
        }
        self.article = nil
        self.episode = episode
    }
}

// MARK: - Unified Audio Player

@MainActor
final class UnifiedAudioPlayer: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = UnifiedAudioPlayer()
    
    // MARK: - Services
    
    private let ttsGenerator = TTSGeneratorService.shared
    private let audioPlayer = SwiftAudioExService()
    private let cacheManager = AudioCacheManager.shared
    
    // MARK: - Published Properties
    
    @Published var queue: [UnifiedQueueItem] = []
    @Published var currentIndex: Int = -1
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var isGenerating: Bool = false
    @Published var generationProgress: String = ""
    
    // MARK: - Current Item
    
    var currentItem: UnifiedQueueItem? {
        guard currentIndex >= 0 && currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }
    
    // MARK: - Private Properties
    
    private var preGenerationTask: Task<Void, Never>?
    private var playbackProgressTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let context = PersistenceController.shared.container.viewContext
    
    // MARK: - Initialization
    
    private init() {
        setupAudioPlayer()
        setupNotifications()
    }
    
    // MARK: - Setup
    
    private func setupAudioPlayer() {
        audioPlayer.delegate = self
    }
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.handleEnterBackground()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.handleEnterForeground()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Queue Management
    
    /// Load queue from articles
    func loadQueue(from articles: [Article]) async {
        queue = articles.map { UnifiedQueueItem(article: $0) }
        currentIndex = -1
        
        // Start pre-generation for first items
        await preGenerateNextItems()
    }
    
    /// Load queue from RSS episodes
    func loadQueue(from episodes: [RSSEpisode]) async {
        queue = episodes.map { UnifiedQueueItem(episode: $0) }
        currentIndex = -1
        
        // RSS episodes don't need TTS generation
        for item in queue {
            if item.audioURL != nil {
                item.generationState = .ready
                item.cachedAudioURL = item.audioURL
            }
        }
    }
    
    /// Load mixed queue
    func loadMixedQueue(items: [Any]) async {
        queue = items.compactMap { item in
            if let article = item as? Article {
                return UnifiedQueueItem(article: article)
            } else if let episode = item as? RSSEpisode {
                return UnifiedQueueItem(episode: episode)
            }
            return nil
        }
        currentIndex = -1
        
        await preGenerateNextItems()
    }
    
    /// Add item to queue
    func addToQueue(_ item: Any) async {
        if let article = item as? Article {
            let queueItem = UnifiedQueueItem(article: article)
            queue.append(queueItem)
            
            // Pre-generate if it's one of the next items
            if queue.count <= 3 {
                await generateAudioForItem(queueItem)
            }
        } else if let episode = item as? RSSEpisode {
            let queueItem = UnifiedQueueItem(episode: episode)
            if queueItem.audioURL != nil {
                queueItem.generationState = .ready
                queueItem.cachedAudioURL = queueItem.audioURL
            }
            queue.append(queueItem)
        }
    }
    
    /// Remove item from queue
    func removeFromQueue(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        
        queue.remove(at: index)
        
        // Adjust current index if needed
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            // Current item was removed, stop playback
            stop()
        }
    }
    
    /// Clear queue
    func clearQueue() {
        stop()
        queue.removeAll()
        currentIndex = -1
    }
    
    // MARK: - Playback Control
    
    /// Play item at index
    func play(at index: Int) async {
        guard index >= 0 && index < queue.count else { return }
        
        currentIndex = index
        let item = queue[index]
        
        // Ensure audio is ready
        if item.generationState != .ready {
            await generateAudioForItem(item)
        }
        
        // Play if generation succeeded
        if let audioURL = item.cachedAudioURL {
            do {
                try await audioPlayer.play(url: audioURL)
                isPlaying = true
                
                // Start pre-generation for next items
                await preGenerateNextItems()
                
                // Update Core Data if it's an article
                if let article = item.article {
                    await markArticleAsListened(article)
                }
                
                // Update RSS episode if needed
                if let episode = item.episode {
                    await markEpisodeAsListened(episode)
                }
            } catch {
                print("[UnifiedPlayer] Failed to play audio: \(error)")
                item.generationState = .failed(error)
            }
        }
    }
    
    /// Play next item
    func playNext() async {
        if currentIndex < queue.count - 1 {
            await play(at: currentIndex + 1)
        }
    }
    
    /// Play previous item
    func playPrevious() async {
        if currentIndex > 0 {
            await play(at: currentIndex - 1)
        }
    }
    
    /// Toggle play/pause
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }
    
    /// Pause playback
    func pause() {
        audioPlayer.pause()
        isPlaying = false
    }
    
    /// Resume playback
    func resume() {
        audioPlayer.resume()
        isPlaying = true
    }
    
    /// Stop playback
    func stop() {
        audioPlayer.stop()
        isPlaying = false
        currentTime = 0
        duration = 0
    }
    
    /// Set playback rate
    func setRate(_ rate: Float) {
        playbackRate = rate
        audioPlayer.setRate(rate)
        
        // Save preference
        UserDefaultsManager.shared.playbackSpeed = rate
    }
    
    /// Seek to time
    func seek(to time: TimeInterval) {
        audioPlayer.seek(to: time)
        currentTime = time
    }
    
    /// Skip forward
    func skipForward(_ seconds: TimeInterval = 30) {
        audioPlayer.skipForward(seconds)
    }
    
    /// Skip backward
    func skipBackward(_ seconds: TimeInterval = 15) {
        audioPlayer.skipBackward(seconds)
    }
    
    // MARK: - TTS Generation
    
    /// Generate audio for a queue item
    private func generateAudioForItem(_ item: UnifiedQueueItem) async {
        // Skip if already ready or generating
        guard item.generationState == .pending else { return }
        
        // RSS episodes don't need generation
        if item.type == .rssEpisode && item.audioURL != nil {
            item.generationState = .ready
            item.cachedAudioURL = item.audioURL
            return
        }
        
        // Generate TTS for articles
        if let article = item.article {
            item.generationState = .generating
            isGenerating = true
            generationProgress = "Generating audio for \(item.title)..."
            
            do {
                // Format text for TTS
                let text = formatArticleForTTS(article)
                
                // Generate audio file
                let audioURL = try await ttsGenerator.generateAudioFile(
                    from: text,
                    trackingIn: context,
                    for: article
                )
                
                item.cachedAudioURL = audioURL
                item.generationState = .ready
                
                // Get duration if possible
                if let player = try? AVAudioPlayer(contentsOf: audioURL) {
                    item.duration = player.duration
                }
                
                print("[UnifiedPlayer] Generated audio for: \(item.title)")
            } catch {
                print("[UnifiedPlayer] Failed to generate audio: \(error)")
                item.generationState = .failed(error)
            }
            
            isGenerating = false
            generationProgress = ""
        }
    }
    
    /// Pre-generate audio for next items
    private func preGenerateNextItems() async {
        // Cancel existing pre-generation
        preGenerationTask?.cancel()
        
        preGenerationTask = Task {
            // Generate for current + next 2 items
            let indicesToGenerate = [
                currentIndex,
                currentIndex + 1,
                currentIndex + 2
            ].filter { $0 >= 0 && $0 < queue.count }
            
            for index in indicesToGenerate {
                guard !Task.isCancelled else { break }
                
                let item = queue[index]
                if item.generationState == .pending {
                    await generateAudioForItem(item)
                }
            }
        }
    }
    
    /// Format article for TTS
    private func formatArticleForTTS(_ article: Article) -> String {
        var text = ""
        
        // Add title
        if let title = article.title {
            text += "\(title). "
        }
        
        // Prefer summary over content
        if let summary = article.summary, !summary.isEmpty {
            text += summary
        } else if let content = article.content {
            // Clean HTML from content
            let cleanContent = content.stripHTML
                .replacingOccurrences(of: "\n\n", with: ". ")
                .replacingOccurrences(of: "\n", with: " ")
            
            // Limit length for TTS
            if cleanContent.count > 5000 {
                text += String(cleanContent.prefix(5000)) + "... Content truncated."
            } else {
                text += cleanContent
            }
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Core Data Updates
    
    private func markArticleAsListened(_ article: Article) async {
        await context.perform {
            article.isRead = true
            try? self.context.save()
        }
    }
    
    private func markEpisodeAsListened(_ episode: RSSEpisode) async {
        await context.perform {
            episode.isListened = true
            episode.listenedDate = Date()
            try? self.context.save()
        }
    }
    
    // MARK: - Background Handling
    
    private func handleEnterBackground() {
        // Continue playback in background
        if isPlaying {
            // Audio session is already configured for background
        }
    }
    
    private func handleEnterForeground() {
        // Resume UI updates
        if isPlaying {
            startProgressTimer()
        }
    }
    
    private func startProgressTimer() {
        playbackProgressTimer?.invalidate()
        playbackProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                self.updateProgress()
            }
        }
    }
    
    private func updateProgress() {
        currentTime = audioPlayer.currentTime
        duration = audioPlayer.duration
    }
}

// MARK: - SwiftAudioExService Delegate

extension UnifiedAudioPlayer: SwiftAudioExServiceDelegate {
    
    func audioStateChanged(to newState: SwiftAudioPlayerState, from oldState: SwiftAudioPlayerState) {
        switch newState {
        case .playing:
            isPlaying = true
            startProgressTimer()
        case .paused:
            isPlaying = false
            playbackProgressTimer?.invalidate()
        case .stopped:
            isPlaying = false
            playbackProgressTimer?.invalidate()
        case .error(let error):
            isPlaying = false
            playbackProgressTimer?.invalidate()
            print("[UnifiedPlayer] Audio error: \(error)")
        default:
            break
        }
    }
    
    func audioProgressUpdated(progress: Float, currentTime: TimeInterval, duration: TimeInterval) {
        self.currentTime = currentTime
        self.duration = duration
    }
    
    func audioRateChanged(to rate: Float) {
        self.playbackRate = rate
    }
    
    func audioDidFinishPlaying(successfully: Bool) {
        if successfully {
            // Auto-play next item
            Task {
                await playNext()
            }
        }
    }
}

// MARK: - Convenience Methods

extension UnifiedAudioPlayer {
    
    /// Get progress percentage
    var progressPercentage: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    /// Get formatted current time
    var formattedCurrentTime: String {
        formatTime(currentTime)
    }
    
    /// Get formatted duration
    var formattedDuration: String {
        formatTime(duration)
    }
    
    /// Get formatted remaining time
    var formattedRemainingTime: String {
        formatTime(duration - currentTime)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Check if can play next
    var canPlayNext: Bool {
        currentIndex < queue.count - 1
    }
    
    /// Check if can play previous
    var canPlayPrevious: Bool {
        currentIndex > 0
    }
}

// MARK: - Testing Support

#if DEBUG
extension UnifiedAudioPlayer {
    /// Reset for testing
    func resetForTesting() {
        stop()
        clearQueue()
        preGenerationTask?.cancel()
        playbackProgressTimer?.invalidate()
    }
    
    /// Load test queue
    func loadTestQueue() async {
        // Create test articles
        let testArticles = (1...5).map { index in
            let article = Article(context: context)
            article.title = "Test Article \(index)"
            article.summary = "This is test article number \(index). It contains sample content for testing the audio player."
            article.id = UUID()
            return article
        }
        
        await loadQueue(from: testArticles)
    }
}
#endif