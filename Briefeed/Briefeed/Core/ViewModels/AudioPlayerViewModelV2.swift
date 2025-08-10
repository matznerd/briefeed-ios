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
    
    @Published private(set) var lastError: Error?
    @Published private(set) var generationProgress: String = ""
    
    // Speed options supporting up to 20x
    let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0, 5.0, 8.0, 10.0, 15.0, 20.0]
    
    enum ItemType {
        case none
        case article
        case rssEpisode
    }
    
    // MARK: - Private Properties
    
    private let unifiedPlayer = UnifiedAudioPlayer.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
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
            .assign(to: &$queueItems)
        
        unifiedPlayer.$currentIndex
            .assign(to: &$currentQueueIndex)
        
        unifiedPlayer.$isGenerating
            .assign(to: &$isGenerating)
        
        unifiedPlayer.$generationProgress
            .assign(to: &$generationProgress)
        
        // Calculate progress
        Publishers.CombineLatest(unifiedPlayer.$currentTime, unifiedPlayer.$duration)
            .map { currentTime, duration in
                duration > 0 ? Float(currentTime / duration) : 0
            }
            .assign(to: &$progress)
        
        // Update current item info
        unifiedPlayer.$currentItem
            .sink { [weak self] item in
                self?.updateCurrentItemInfo(item)
            }
            .store(in: &cancellables)
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
    
    func play() {
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
        
        // Create queue with single article
        await unifiedPlayer.loadQueue(from: [article])
        
        // Play first (and only) item
        await unifiedPlayer.play(at: 0)
        
        isLoading = false
    }
    
    func play(episode: RSSEpisode) async {
        isLoading = true
        lastError = nil
        
        // Create queue with single episode
        await unifiedPlayer.loadQueue(from: [episode])
        
        // Play first (and only) item
        await unifiedPlayer.play(at: 0)
        
        isLoading = false
    }
    
    func playQueue(articles: [Article]) async {
        isLoading = true
        lastError = nil
        
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
        
        // Load mixed queue
        await unifiedPlayer.loadMixedQueue(items: items)
        
        // Start playing from beginning
        if !items.isEmpty {
            await unifiedPlayer.play(at: 0)
        }
        
        isLoading = false
    }
    
    // MARK: - Queue Management
    
    func playNext() async {
        await unifiedPlayer.playNext()
    }
    
    func playPrevious() async {
        await unifiedPlayer.playPrevious()
    }
    
    func playItemAt(index: Int) async {
        await unifiedPlayer.play(at: index)
    }
    
    func addToQueue(_ article: Article) async {
        await unifiedPlayer.addToQueue(article)
    }
    
    func addToQueue(_ episode: RSSEpisode) async {
        await unifiedPlayer.addToQueue(episode)
    }
    
    func removeFromQueue(at index: Int) {
        unifiedPlayer.removeFromQueue(at: index)
    }
    
    func clearQueue() {
        unifiedPlayer.clearQueue()
    }
    
    func reorderQueue(from source: IndexSet, to destination: Int) {
        // Convert IndexSet to array of items to move
        var newQueue = queueItems
        
        // Get items to move
        let itemsToMove = source.map { newQueue[$0] }
        
        // Remove items from their current positions
        for index in source.reversed() {
            newQueue.remove(at: index)
        }
        
        // Insert at new position
        let insertIndex = destination > source.first! ? destination - source.count : destination
        for (offset, item) in itemsToMove.enumerated() {
            newQueue.insert(item, at: insertIndex + offset)
        }
        
        // Update queue
        Task {
            await unifiedPlayer.loadMixedQueue(items: newQueue.compactMap { item in
                item.article ?? item.episode
            })
        }
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
    
    /// Play latest RSS episodes as "Live News"
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
        episodes.sort { ($0.pubDate ?? Date.distantPast) > ($1.pubDate ?? Date.distantPast) }
        
        // Load and play
        if !episodes.isEmpty {
            await playQueue(episodes: episodes)
        } else {
            lastError = NSError(
                domain: "AudioPlayer",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No new episodes available"]
            )
        }
        
        isLoading = false
    }
}

// MARK: - Testing Support

#if DEBUG
extension AudioPlayerViewModelV2 {
    func loadTestQueue() async {
        await unifiedPlayer.loadTestQueue()
        if !queueItems.isEmpty {
            await unifiedPlayer.play(at: 0)
        }
    }
}