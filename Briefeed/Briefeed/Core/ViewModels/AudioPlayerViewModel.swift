//
//  AudioPlayerViewModel.swift
//  Briefeed
//
//  ViewModel layer with ObservableObject for UI binding
//

import Foundation
import SwiftUI
import Combine
import CoreData

// MARK: - AudioPlayerViewModel
// Proper architecture: ObservableObject for UI, delegates to services

@MainActor
final class AudioPlayerViewModel: ObservableObject {
    
    // MARK: - Published Properties (For UI Binding)
    
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isConnected: Bool = false
    
    @Published private(set) var currentTitle: String?
    @Published private(set) var currentArtist: String?
    @Published private(set) var currentURL: URL?
    
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var progress: Float = 0
    
    @Published private(set) var playbackSpeed: Float = 1.0
    @Published private(set) var volume: Float = 1.0
    
    @Published private(set) var queueItems: [EnhancedQueueItem] = []
    @Published private(set) var currentQueueIndex: Int = 0
    
    @Published private(set) var lastError: Error?
    
    // MARK: - Private Properties
    
    private var audioService: AudioServiceV2?
    // private var streamingService: AudioStreamingService? // Disabled until SwiftAudioEx available
    private var queueService: QueueServiceV2?
    private var stateManager: ArticleStateManagerV2?
    
    private var cancellables = Set<AnyCancellable>()
    private var useStreaming: Bool = false
    
    // MARK: - Initialization (LIGHTWEIGHT!)
    
    init() {
        // Lightweight init - no service access here!
        // ViewModels can be ObservableObject but need lightweight init
    }
    
    // MARK: - Computed Properties
    
    var canPlayPrevious: Bool {
        currentQueueIndex > 0
    }
    
    var canPlayNext: Bool {
        currentQueueIndex < queueItems.count - 1
    }
    
    // MARK: - Connection (HEAVY WORK HERE)
    
    func connect() async {
        guard !isConnected else { return }
        
        // Initialize services
        audioService = AudioServiceV2.shared
        // streamingService = AudioStreamingService.shared // Disabled
        queueService = QueueServiceV2.shared
        stateManager = ArticleStateManagerV2.shared
        
        // Set delegates
        audioService?.delegate = self
        // streamingService?.delegate = self // Disabled
        queueService?.delegate = self
        stateManager?.delegate = self
        
        // Initialize services
        await audioService?.initialize()
        // await streamingService?.initialize() // Disabled
        await queueService?.initialize()
        await stateManager?.initialize()
        
        // Load initial state
        loadQueueState()
        
        isConnected = true
    }
    
    // MARK: - Playback Control
    
    func play() {
        if useStreaming {
            // streamingService?.play() // Disabled
            // For now, RSS will use TTS limited to 2x speed
            audioService?.resume()
        } else {
            audioService?.resume()
        }
        // Don't set isPlaying here - let the delegate update it
    }
    
    func pause() {
        if useStreaming {
            // streamingService?.pause() // Disabled
            audioService?.pause()
        } else {
            audioService?.pause()
        }
        // Don't set isPlaying here - let the delegate update it
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func stop() {
        Task {
            if useStreaming {
                // streamingService?.stop() // Disabled
                await audioService?.stop()
            } else {
                await audioService?.stop()
            }
            isPlaying = false
            currentTitle = nil
            currentArtist = nil
            currentURL = nil
            progress = 0
            currentTime = 0
            duration = 0
        }
    }
    
    // MARK: - Play Specific Content
    
    func play(article: Article) async {
        isLoading = true
        lastError = nil
        
        // Update UI immediately with article info
        currentTitle = article.title
        currentArtist = article.author
        
        do {
            // Update state manager
            let articleID = article.objectID.uriRepresentation().absoluteString.components(separatedBy: "/").last.flatMap { UUID(uuidString: $0) } ?? UUID()
            stateManager?.setCurrentlyPlaying(articleID: articleID)
            
            // Generate or get audio
            if let content = article.content {
                // Use TTS for article
                useStreaming = false
                try await audioService?.speak(
                    text: content,
                    title: article.title,
                    author: article.author
                )
                // State will be updated by delegate callback
            }
        } catch {
            lastError = error
            isPlaying = false
        }
        
        isLoading = false
    }
    
    func play(episode: RSSEpisode) async {
        isLoading = true
        lastError = nil
        
        do {
            if let audioURL = URL(string: episode.audioUrl) {
                
                // Would use streaming for RSS episodes (supports 4x speed)
                // But for now, fall back to TTS with 2x limit
                useStreaming = false // Changed: was true, now false due to missing SwiftAudioEx
                
                // TODO: When SwiftAudioEx is available, use streaming:
                // try await streamingService?.load(url: audioURL, title: episode.title, artist: episode.feed?.title)
                // streamingService?.play()
                
                // For now, speak the episode description if available
                if let description = episode.episodeDescription {
                    try await audioService?.speak(
                        text: description,
                        title: episode.title,
                        author: episode.feed?.displayName
                    )
                }
                
                currentTitle = episode.title
                currentArtist = episode.feed?.displayName
                currentURL = audioURL
                isPlaying = true
            }
        } catch {
            lastError = error
            isPlaying = false
        }
        
        isLoading = false
    }
    
    // MARK: - Queue Management
    
    func queueArticle(_ article: Article) async {
        await queueService?.addToQueue(article: article)
    }
    
    func queueEpisode(_ episode: RSSEpisode) async {
        await queueService?.addToQueue(episode: episode)
    }
    
    func removeFromQueue(at index: Int) async {
        await queueService?.removeFromQueue(at: index)
    }
    
    func reorderQueue(from source: IndexSet, to destination: Int) async {
        await queueService?.reorderQueue(from: source, to: destination)
    }
    
    func clearQueue() async {
        await queueService?.clearQueue()
    }
    
    func playNextInQueue() {
        guard currentQueueIndex < queueItems.count - 1 else { return }
        
        currentQueueIndex += 1
        
        Task {
            // Use the existing playItemAt method which properly handles playing
            await playItemAt(index: currentQueueIndex)
        }
    }
    
    func playItemAt(index: Int) async {
        guard index >= 0 && index < queueItems.count else { return }
        
        currentQueueIndex = index
        let item = queueItems[index]
        
        // Update UI immediately
        currentTitle = item.title
        currentArtist = item.source.displayName
        
        if let audioUrl = item.audioUrl {
            // RSS Episode - direct playback
            currentURL = audioUrl
            
            if useStreaming {
                // Future: streamingService?.play(url: audioUrl)
            } else {
                // For RSS episodes, we'll need to handle URL playback differently
                // This might need a different audio service or player
                isPlaying = false
            }
        } else if let articleID = item.articleID {
            // Article - needs processing
            currentURL = nil
            
            // Fetch article from Core Data and play
            let context = PersistenceController.shared.container.viewContext
            let request: NSFetchRequest<Article> = Article.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", articleID as CVarArg)
            request.fetchLimit = 1
            
            if let article = try? context.fetch(request).first {
                // Generate audio for article
                if let summary = article.summary {
                    // Play the summary using TTS
                    do {
                        try await audioService?.speak(text: summary, title: article.title, author: article.author)
                        isPlaying = true
                    } catch {
                        lastError = error
                        isPlaying = false
                    }
                }
            }
        }
    }
    
    func playPreviousInQueue() {
        guard currentQueueIndex > 0 else { return }
        
        currentQueueIndex -= 1
        
        Task {
            // Use the existing playItemAt method which properly handles playing
            await playItemAt(index: currentQueueIndex)
        }
    }
    
    // MARK: - Speed Control
    
    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        
        if useStreaming {
            // Streaming would support up to 4x
            // streamingService?.setRate(speed) // Disabled
            // Fall back to TTS limited to 2x
            audioService?.setRate(min(speed, 2.0))
        } else {
            // TTS limited to 2x
            audioService?.setRate(min(speed, 2.0))
        }
    }
    
    func increaseSpeed() {
        if useStreaming {
            // streamingService?.increaseSpeed() // Disabled
            let newSpeed = min(playbackSpeed + 0.25, 2.0)
            setSpeed(newSpeed)
        } else {
            let newSpeed = min(playbackSpeed + 0.25, 2.0)
            setSpeed(newSpeed)
        }
    }
    
    func decreaseSpeed() {
        if useStreaming {
            // streamingService?.decreaseSpeed() // Disabled
            let newSpeed = max(playbackSpeed - 0.25, 0.5)
            setSpeed(newSpeed)
        } else {
            let newSpeed = max(playbackSpeed - 0.25, 0.5)
            setSpeed(newSpeed)
        }
    }
    
    // MARK: - Volume Control
    
    func setVolume(_ volume: Float) {
        self.volume = volume
        
        if useStreaming {
            // streamingService?.setVolume(volume) // Disabled
            audioService?.setVolume(volume)
        } else {
            audioService?.setVolume(volume)
        }
    }
    
    // MARK: - Seeking
    
    func seek(to time: TimeInterval) {
        if useStreaming {
            // streamingService?.seek(to: time) // Disabled
        }
        // TTS doesn't support seeking
    }
    
    func skipForward() {
        if useStreaming {
            // streamingService?.skipForward() // Disabled
        }
    }
    
    func skipBackward() {
        if useStreaming {
            // streamingService?.skipBackward() // Disabled
        } else {
            // For TTS, restart the current item (since seeking isn't supported)
            // This provides a reasonable "skip backward" experience
            Task {
                if currentQueueIndex >= 0 && currentQueueIndex < queueItems.count {
                    await playItemAt(index: currentQueueIndex)
                }
            }
        }
    }
    
    // MARK: - Error Handling
    
    func handleError(_ error: Error) {
        lastError = error
        isPlaying = false
        isLoading = false
    }
    
    func retry() async {
        guard let error = lastError else { return }
        lastError = nil
        
        // Retry based on last action
        if currentQueueIndex > 0 {
            currentQueueIndex -= 1
            playNextInQueue()
        }
    }
    
    // MARK: - Internal Helpers
    
    func updateCurrentTime(_ time: TimeInterval) {
        currentTime = time
    }
    
    private func loadQueueState() {
        queueItems = queueService?.enhancedQueue ?? []
        // Load saved playback speed
        playbackSpeed = UserDefaultsManager.shared.playbackSpeed
    }
}

// MARK: - AudioServiceDelegate

extension AudioPlayerViewModel: AudioServiceDelegate {
    
    nonisolated func audioStateChanged(to newState: AudioPlayerState, from oldState: AudioPlayerState) {
        Task { @MainActor in
            switch newState {
            case .playing:
                isPlaying = true
                isLoading = false
            case .paused:
                isPlaying = false
            case .stopped:
                isPlaying = false
                progress = 0
            case .loading:
                isLoading = true
            case .error(let error):
                handleError(error)
            default:
                break
            }
        }
    }
    
    nonisolated func audioProgressUpdated(progress: Float, currentTime: TimeInterval, duration: TimeInterval) {
        Task { @MainActor in
            self.progress = progress
            self.currentTime = currentTime
            self.duration = duration
        }
    }
    
    nonisolated func audioRateChanged(to rate: Float) {
        Task { @MainActor in
            self.playbackSpeed = rate
        }
    }
    
    nonisolated func audioDidFinishPlaying(successfully: Bool) {
        Task { @MainActor in
            if successfully {
                // Auto-play next in queue
                playNextInQueue()
            }
        }
    }
    
    nonisolated func audioDecodeError(_ error: Error?) {
        Task { @MainActor in
            if let error = error {
                handleError(error)
            }
        }
    }
}

// MARK: - AudioStreamingServiceDelegate
// Disabled until SwiftAudioEx is available
/*
extension AudioPlayerViewModel: AudioStreamingServiceDelegate {
    
    nonisolated func streamingStateChanged(to newState: AudioPlayerState, from oldState: AudioPlayerState) {
        Task { @MainActor in
            audioStateChanged(to: newState, from: oldState)
        }
    }
    
    nonisolated func streamingProgressUpdated(progress: Float, currentTime: TimeInterval, duration: TimeInterval) {
        Task { @MainActor in
            audioProgressUpdated(progress: progress, currentTime: currentTime, duration: duration)
        }
    }
    
    nonisolated func streamingRateChanged(to rate: Float) {
        Task { @MainActor in
            audioRateChanged(to: rate)
        }
    }
    
    nonisolated func streamingDidFinishPlaying(successfully: Bool) {
        Task { @MainActor in
            audioDidFinishPlaying(successfully: successfully)
        }
    }
    
    nonisolated func streamingDecodeError(_ error: Error?) {
        Task { @MainActor in
            audioDecodeError(error)
        }
    }
}
*/

// MARK: - QueueServiceDelegate

extension AudioPlayerViewModel: QueueServiceDelegate {
    
    nonisolated func queueItemsChanged(_ items: [QueueServiceV2.QueuedItem]) {
        // Legacy queue items - ignore
    }
    
    nonisolated func enhancedQueueChanged(_ items: [EnhancedQueueItem]) {
        Task { @MainActor in
            queueItems = items
        }
    }
}

// MARK: - ArticleStateManagerDelegate

extension AudioPlayerViewModel: ArticleStateManagerDelegate {
    
    nonisolated func currentlyPlayingArticleChanged(_ articleID: UUID?) {
        // Update UI if needed
    }
    
    nonisolated func archivedArticlesChanged(_ articleIDs: Set<UUID>) {
        // Update UI if needed
    }
    
    nonisolated func queuedArticlesChanged(_ articleIDs: [UUID]) {
        // Update UI if needed
    }
}