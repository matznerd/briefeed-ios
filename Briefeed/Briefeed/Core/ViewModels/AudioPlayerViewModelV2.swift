//
//  AudioPlayerViewModelV2.swift
//  Briefeed
//
//  Updated ViewModel using UnifiedAudioPlayer with SwiftAudioEx
//  Supports up to 20x speed playback
//

import Foundation
import SwiftUI
import Combine
import CoreData

@MainActor
final class AudioPlayerViewModelV2: ObservableObject {
    
    // MARK: - Published Properties (For UI Binding)
    
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isGenerating: Bool = false
    
    @Published private(set) var currentTitle: String?
    @Published private(set) var currentArtist: String?
    @Published private(set) var currentItemType: ItemType = .none
    
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var progress: Float = 0
    
    @Published var playbackSpeed: Float = 1.0 {
        didSet {
            unifiedPlayer.setRate(playbackSpeed)
        }
    }
    
    @Published private(set) var queueItems: [UnifiedQueueItem] = []
    @Published private(set) var currentQueueIndex: Int = -1

    // Live News streaming state (temporary, not persisted to Brief)
    @Published private(set) var isStreamingLiveNews: Bool = false
    @Published private(set) var liveNewsStreamQueue: [UnifiedQueueItem] = []
    @Published private(set) var liveNewsStreamIndex: Int = -1
    
    @Published private(set) var lastError: Error?
    @Published private(set) var generationPhase: GenerationPhase = .idle

    /// Display string for generation progress (derived from generationPhase)
    var generationProgress: String {
        generationPhase.displayMessage
    }
    
    // Speed options supporting up to 20x
    let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0, 5.0, 8.0, 10.0, 15.0, 20.0]
    
    enum ItemType {
        case none
        case article
        case rssEpisode
    }
    
    // MARK: - Private Properties

    private let unifiedPlayer = UnifiedAudioPlayer.shared
    private let queueCoordinator = QueueCoordinator.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        setupBindings()
        loadSavedState()
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Bind to UnifiedAudioPlayer state
        unifiedPlayer.$isPlaying
            .assign(to: &$isPlaying)
        
        unifiedPlayer.$currentTime
            .assign(to: &$currentTime)
        
        unifiedPlayer.$duration
            .assign(to: &$duration)
        
        unifiedPlayer.$playbackRate
            .assign(to: &$playbackSpeed)

        unifiedPlayer.$queue
            .sink { [weak self] queue in
                self?.queueItems = queue
                self?.refreshNowPlaying()
            }
            .store(in: &cancellables)

        unifiedPlayer.$currentIndex
            .sink { [weak self] index in
                self?.currentQueueIndex = index
                self?.refreshNowPlaying()
            }
            .store(in: &cancellables)

        unifiedPlayer.$isStreamingLiveNews
            .sink { [weak self] isStreaming in
                self?.isStreamingLiveNews = isStreaming
                self?.refreshNowPlaying()
            }
            .store(in: &cancellables)

        unifiedPlayer.$liveNewsStreamQueue
            .sink { [weak self] queue in
                self?.liveNewsStreamQueue = queue
                self?.refreshNowPlaying()
            }
            .store(in: &cancellables)

        unifiedPlayer.$liveNewsStreamIndex
            .sink { [weak self] index in
                self?.liveNewsStreamIndex = index
                self?.refreshNowPlaying()
            }
            .store(in: &cancellables)
        
        unifiedPlayer.$isGenerating
            .assign(to: &$isGenerating)

        unifiedPlayer.$generationPhase
            .assign(to: &$generationPhase)
        
        // Calculate progress
        Publishers.CombineLatest(unifiedPlayer.$currentTime, unifiedPlayer.$duration)
            .map { currentTime, duration in
                duration > 0 ? Float(currentTime / duration) : 0
            }
            .assign(to: &$progress)
    }

    private func refreshNowPlaying() {
        updateCurrentItemInfo(unifiedPlayer.currentItem)
    }
    
    private func loadSavedState() {
        // Load saved playback speed
        playbackSpeed = UserDefaultsManager.shared.playbackSpeed
        
        // Load saved queue if any
        // This would be implemented with persistence
    }
    
    // MARK: - Computed Properties
    
    var canPlayPrevious: Bool {
        unifiedPlayer.canPlayPrevious
    }
    
    var canPlayNext: Bool {
        unifiedPlayer.canPlayNext
    }
    
    var formattedCurrentTime: String {
        unifiedPlayer.formattedCurrentTime
    }
    
    var formattedDuration: String {
        unifiedPlayer.formattedDuration
    }
    
    var formattedRemainingTime: String {
        unifiedPlayer.formattedRemainingTime
    }
    
    var progressPercentage: Double {
        unifiedPlayer.progressPercentage
    }
    
    // MARK: - Playback Control
    
    func togglePlayPause() {
        unifiedPlayer.togglePlayPause()
    }
    
    func play() async {
        unifiedPlayer.resume()
    }
    
    func pause() {
        unifiedPlayer.pause()
    }
    
    func stop() {
        unifiedPlayer.stop()
    }
    
    func skipForward(_ seconds: TimeInterval = 30) {
        unifiedPlayer.skipForward(seconds)
    }
    
    func skipBackward(_ seconds: TimeInterval = 15) {
        unifiedPlayer.skipBackward(seconds)
    }
    
    func seek(to progress: Float) {
        let time = TimeInterval(progress) * duration
        unifiedPlayer.seek(to: time)
    }
    
    // MARK: - Navigation Methods for Mini Player
    
    func playNext() async {
        guard canPlayNext else { return }
        isLoading = true

        // CRITICAL: Yield to allow SwiftUI to update UI before heavy work
        await Task.yield()

        defer { isLoading = false }
        await unifiedPlayer.playNext()
    }
    
    func playPrevious() async {
        // If we're more than 3 seconds into playback, restart current item
        if currentTime > 3 {
            unifiedPlayer.seek(to: 0)
            return
        }

        // Otherwise go to previous item if possible
        guard canPlayPrevious else {
            unifiedPlayer.seek(to: 0)
            return
        }

        isLoading = true

        // CRITICAL: Yield to allow SwiftUI to update UI before heavy work
        await Task.yield()

        defer { isLoading = false }
        await unifiedPlayer.playPrevious()
    }
    
    // MARK: - Seek Methods for Mini Player
    
    func seekForward() {
        // Seek forward 10 seconds
        skipForward(10)
    }
    
    func seekBackward() {
        // Seek backward 10 seconds
        skipBackward(10)
    }
    
    func seek(to time: TimeInterval) {
        unifiedPlayer.seek(to: time)
    }
    
    // MARK: - Speed Control
    
    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        UserDefaultsManager.shared.playbackSpeed = speed
    }
    
    func increaseSpeed() {
        if let currentIndex = speedOptions.firstIndex(where: { $0 >= playbackSpeed }),
           currentIndex < speedOptions.count - 1 {
            setSpeed(speedOptions[currentIndex + 1])
        }
    }
    
    func decreaseSpeed() {
        if let currentIndex = speedOptions.firstIndex(where: { $0 >= playbackSpeed }),
           currentIndex > 0 {
            setSpeed(speedOptions[currentIndex - 1])
        }
    }
    
    // MARK: - Play Specific Content
    
    func play(article: Article) async {
        isLoading = true
        lastError = nil

        // CRITICAL: Yield to allow SwiftUI to update UI before heavy work
        await Task.yield()

        // Check if article is already in the queue
        if let existingIndex = queueItems.firstIndex(where: { $0.article?.id == article.id }) {
            // Article already in queue, just play it at its current position
            await unifiedPlayer.play(at: existingIndex)
        } else {
            // Article not in queue: add to Brief queue and play immediately.
            await addToQueue(article, playNow: true)
        }
        
        isLoading = false
    }
    
    func play(episode: RSSEpisode) async {
        isLoading = true
        lastError = nil

        // CRITICAL: Yield to allow SwiftUI to update UI before heavy work
        await Task.yield()

        // Check if episode is already in the queue
        if let existingIndex = queueItems.firstIndex(where: { 
            $0.audioURL?.absoluteString == episode.audioUrl 
        }) {
            // Episode already in queue, just play it at its current position
            await unifiedPlayer.play(at: existingIndex)
        } else {
            // Episode not in queue: add to Brief queue and play immediately.
            await addToQueue(episode, playNow: true)
        }
        
        isLoading = false
    }
    
    func playQueue(articles: [Article]) async {
        isLoading = true
        lastError = nil

        // CRITICAL: Yield to allow SwiftUI to update UI before heavy work
        await Task.yield()

        // Load full queue
        await unifiedPlayer.loadQueue(from: articles)
        
        // Start playing from beginning
        if !articles.isEmpty {
            await unifiedPlayer.play(at: 0)
        }
        
        isLoading = false
    }
    
    func playQueue(episodes: [RSSEpisode]) async {
        isLoading = true
        lastError = nil

        // CRITICAL: Yield to allow SwiftUI to update UI before heavy work
        await Task.yield()

        // Load full queue
        await unifiedPlayer.loadQueue(from: episodes)
        
        // Start playing from beginning
        if !episodes.isEmpty {
            await unifiedPlayer.play(at: 0)
        }
        
        isLoading = false
    }
    
    func playMixedQueue(items: [Any]) async {
        isLoading = true
        lastError = nil

        // CRITICAL: Yield to allow SwiftUI to update UI before heavy work
        await Task.yield()

        // Load mixed queue
        await unifiedPlayer.loadMixedQueue(items: items)
        
        // Start playing from beginning
        if !items.isEmpty {
            await unifiedPlayer.play(at: 0)
        }
        
        isLoading = false
    }
    
    // MARK: - Queue Management
    
    func playItemAt(index: Int) async {
        await unifiedPlayer.play(at: index)
    }
    
    func addToQueue(_ article: Article, playNow: Bool = false, playNext: Bool = false) async {
        await unifiedPlayer.addToQueue(article, playNow: playNow, playNext: playNext)

        // If playNow, start playback immediately
        if playNow {
            await unifiedPlayer.play(at: unifiedPlayer.currentIndex >= 0 ? unifiedPlayer.currentIndex : 0)
        }
    }

    func addToQueue(_ episode: RSSEpisode, playNow: Bool = false, playNext: Bool = false) async {
        await unifiedPlayer.addToQueue(episode, playNow: playNow, playNext: playNext)

        // If playNow, start playback immediately
        if playNow {
            await unifiedPlayer.play(at: unifiedPlayer.currentIndex >= 0 ? unifiedPlayer.currentIndex : 0)
        }
    }

    func queueArticle(_ article: Article, playNow: Bool = false, playNext: Bool = false) async {
        await addToQueue(article, playNow: playNow, playNext: playNext)
    }

    func queueEpisode(_ episode: RSSEpisode, playNow: Bool = false, playNext: Bool = false) async {
        await addToQueue(episode, playNow: playNow, playNext: playNext)
    }
    
    func removeFromQueue(at index: Int) async {
        unifiedPlayer.removeFromQueue(at: index)
    }
    
    func clearQueue() async {
        unifiedPlayer.clearQueue()
    }
    
    func saveQueueState() async {
        // Save current queue to UserDefaults for persistence
        let queueData = queueItems.compactMap { item -> [String: Any]? in
            if let article = item.article {
                return [
                    "type": "article",
                    "id": article.id?.uuidString ?? "",
                    "title": article.title ?? ""
                ]
            } else if let episode = item.episode {
                return [
                    "type": "episode", 
                    "id": episode.id,
                    "title": episode.title
                ]
            }
            return nil
        }
        
        UserDefaults.standard.set(queueData, forKey: "audioQueueState")
        UserDefaults.standard.set(currentQueueIndex, forKey: "audioQueueIndex")
    }
    
    func playNextInQueue() {
        Task {
            await playNext()
        }
    }
    
    func playPreviousInQueue() {
        Task {
            await playPrevious()
        }
    }
    
    func reorderQueue(from source: IndexSet, to destination: Int) async {
        // Delegate to QueueCoordinator (source of truth)
        // Local queue (queueItems) syncs automatically via Combine subscription
        queueCoordinator.moveItems(from: source, to: destination)
    }
    
    // MARK: - Private Methods
    
    private func updateCurrentItemInfo(_ item: UnifiedQueueItem?) {
        guard let item = item else {
            currentTitle = nil
            currentArtist = nil
            currentItemType = .none
            return
        }
        
        currentTitle = item.title
        
        switch item.type {
        case .article:
            currentArtist = item.article?.author ?? "Unknown Author"
            currentItemType = .article
        case .rssEpisode:
            currentArtist = item.episode?.feed?.displayName ?? "Unknown Podcast"
            currentItemType = .rssEpisode
        }
    }
    
    // MARK: - Error Handling
    
    func handleError(_ error: Error) {
        lastError = error
        isLoading = false
        isGenerating = false
        
        // Log error
        print("[AudioPlayerViewModel] Error: \(error)")
    }
    
    // MARK: - State Persistence
    
    func saveQueueState() {
        // Save current queue to UserDefaults or Core Data
        // This would include queue items and current index
    }
    
    func restoreQueueState() async {
        // Restore saved queue from persistence
        // This would reload the queue and position
    }
}

// MARK: - Live News Support

extension AudioPlayerViewModelV2 {
    /// Play Live News episodes immediately WITHOUT queuing to Brief
    /// Per PRD: "Play Live News" streams immediately without adding to Brief queue
    func playLiveNewsStream(episodes: [RSSEpisode]) async {
        isLoading = true
        lastError = nil

        // CRITICAL: Yield to allow SwiftUI to update UI before heavy work
        await Task.yield()

        if !episodes.isEmpty {
            await unifiedPlayer.playLiveNewsStream(episodes: episodes)
        } else {
            lastError = NSError(
                domain: "AudioPlayer",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No new episodes available"]
            )
        }

        isLoading = false
    }

    /// Stop Live News streaming and return to Brief queue mode
    func stopLiveNewsStream() {
        unifiedPlayer.stopLiveNewsStream()
    }

    /// Stream a single episode immediately WITHOUT queuing to Brief
    /// Per PRD: Per-episode "Play Now" in Live News also streams immediately
    func streamEpisode(_ episode: RSSEpisode) async {
        await playLiveNewsStream(episodes: [episode])
    }

    /// Play latest RSS episodes as "Live News" (legacy - queues to Brief)
    /// NOTE: Use playLiveNewsStream for immediate streaming per PRD
    func playLiveNews(from feeds: [RSSFeed]) async {
        isLoading = true
        lastError = nil

        let context = PersistenceController.shared.container.viewContext
        var episodes: [RSSEpisode] = []

        // Get latest unlistened episode from each feed
        for feed in feeds {
            let request: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
            request.predicate = NSPredicate(
                format: "feed == %@ AND isListened == NO",
                feed
            )
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \RSSEpisode.pubDate, ascending: false)
            ]
            request.fetchLimit = 1

            if let latestEpisode = try? context.fetch(request).first {
                episodes.append(latestEpisode)
            }
        }

        // Sort by publication date (newest first)
        episodes.sort { $0.pubDate > $1.pubDate }

        // Stream immediately without queuing (per PRD)
        await playLiveNewsStream(episodes: episodes)

        isLoading = false
    }
}

// MARK: - Testing Support

#if DEBUG
extension AudioPlayerViewModelV2 {
    func loadTestQueue() async {
        // Create test items for debugging
        let testArticles = [
            "Test Article 1",
            "Test Article 2",
            "Test Article 3"
        ]
        
        // For now, just set up test items
        // This would need actual Article objects in a real implementation
        print("[AudioPlayerViewModelV2] Test queue loading not fully implemented")
    }
}
#endif
