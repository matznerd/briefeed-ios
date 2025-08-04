//
//  AudioServiceAdapter.swift
//  Briefeed
//
//  Created by Briefeed Team on 1/8/25.
//

import Foundation
import AVFoundation
import Combine
import CoreData

/// Adapter that bridges the old AudioService API to the new BriefeedAudioService
/// This allows gradual migration of UI components without breaking existing functionality
@MainActor
final class AudioServiceAdapter: ObservableObject {
    
    // MARK: - Published Properties (matching old AudioService)
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var isGeneratingAudio = false
    @Published var currentPlaybackItem: PlaybackItem?
    @Published var queue: [Article] = []
    @Published var enhancedQueue: [EnhancedQueueItem] = []
    @Published var progress = PlaybackProgress()
    @Published var playbackSpeed: Float = 1.0
    @Published var volume: Float = 1.0
    @Published var lastError: Error?
    
    // MARK: - Private Properties
    private let briefeedAudioService = BriefeedAudioService.shared
    private var cancellables = Set<AnyCancellable>()
    private var articleQueueMap: [UUID: Article] = [:] // Maps BriefeedAudioItem IDs to Articles
    private var episodeQueueMap: [String: RSSEpisode] = [:] // Maps episode URLs to RSSEpisodes
    
    // Feature flag
    var isUsingNewService: Bool {
        UserDefaults.standard.bool(forKey: "useNewAudioService")
    }
    
    // MARK: - Initialization
    init() {
        setupBindings()
        restoreState()
    }
    
    // MARK: - Setup
    private func setupBindings() {
        // Bind playback state
        briefeedAudioService.$isPlaying
            .assign(to: &$isPlaying)
        
        briefeedAudioService.$isLoading
            .assign(to: &$isLoading)
        
        // Convert currentItem to PlaybackItem
        briefeedAudioService.$currentPlaybackItem
            .map { [weak self] item -> PlaybackItem? in
                guard let item = item else { return nil }
                return self?.convertToPlaybackItem(item)
            }
            .assign(to: &$currentPlaybackItem)
        
        // Convert queue to Article array
        briefeedAudioService.$queue
            .map { [weak self] items -> [Article] in
                self?.convertQueueToArticles(items) ?? []
            }
            .assign(to: &$queue)
        
        // Update enhanced queue
        briefeedAudioService.$queue
            .map { [weak self] items -> [EnhancedQueueItem] in
                self?.convertToEnhancedQueue(items) ?? []
            }
            .assign(to: &$enhancedQueue)
        
        // Update progress
        Publishers.CombineLatest(
            briefeedAudioService.$currentTime,
            briefeedAudioService.$duration
        )
        .sink { [weak self] currentTime, duration in
            self?.updateProgress(currentTime: currentTime, duration: duration)
        }
        .store(in: &cancellables)
        
        // Sync playback speed
        briefeedAudioService.$playbackRate
            .assign(to: &$playbackSpeed)
        
        // Handle errors
        briefeedAudioService.$lastError
            .assign(to: &$lastError)
    }
    
    private func restoreState() {
        // Restore playback speed
        playbackSpeed = UserDefaultsManager.shared.playbackSpeed
        briefeedAudioService.setPlaybackRate(playbackSpeed)
    }
    
    // MARK: - Playback Control
    
    func playArticle(_ article: Article) async {
        articleQueueMap[article.id ?? UUID()] = article
        isGeneratingAudio = true
        
        await briefeedAudioService.playArticle(article)
        isGeneratingAudio = false
    }
    
    func playRSSEpisode(_ episode: RSSEpisode) async {
        episodeQueueMap[episode.audioUrl] = episode
        
        await briefeedAudioService.playRSSEpisode(episode)
    }
    
    func togglePlayPause() {
        briefeedAudioService.togglePlayPause()
    }
    
    func play() {
        briefeedAudioService.play()
    }
    
    func pause() {
        briefeedAudioService.pause()
    }
    
    func stop() {
        briefeedAudioService.stop()
    }
    
    func skipForward() {
        briefeedAudioService.skipForward()
    }
    
    func skipBackward() {
        briefeedAudioService.skipBackward()
    }
    
    func seek(to position: TimeInterval) {
        briefeedAudioService.seek(to: position)
    }
    
    func setPlaybackSpeed(_ speed: Float) {
        briefeedAudioService.setPlaybackRate(speed)
        playbackSpeed = speed
    }
    
    // MARK: - Queue Management
    
    func addToQueue(_ article: Article) async {
        articleQueueMap[article.id ?? UUID()] = article
        await briefeedAudioService.addToQueue(article)
    }
    
    func addToRSSQueue(_ episode: RSSEpisode) {
        episodeQueueMap[episode.audioUrl] = episode
        briefeedAudioService.addToQueue(episode)
    }
    
    func removeFromQueue(at index: Int) {
        briefeedAudioService.removeFromQueue(at: index)
    }
    
    func clearQueue() {
        articleQueueMap.removeAll()
        episodeQueueMap.removeAll()
        briefeedAudioService.clearQueue()
    }
    
    func moveQueueItem(from sourceIndex: Int, to destinationIndex: Int) {
        // Note: This would need implementation in BriefeedAudioService
        // For now, we can reorder locally and rebuild the queue
        var newQueue = briefeedAudioService.queue
        guard sourceIndex < newQueue.count && destinationIndex <= newQueue.count else { return }
        
        let item = newQueue.remove(at: sourceIndex)
        newQueue.insert(item, at: destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex)
        
        // Rebuild queue in new service
        briefeedAudioService.clearQueue()
        Task {
            for item in newQueue {
                if item.content.contentType == .article,
                   let article = articleQueueMap[item.content.id] {
                    await briefeedAudioService.addToQueue(article)
                } else if item.content.contentType == .rssEpisode,
                          let episodeURL = item.content.episodeURL?.absoluteString,
                          let episode = episodeQueueMap[episodeURL] {
                    briefeedAudioService.addToQueue(episode)
                }
            }
        }
    }
    
    func playNext() async {
        await briefeedAudioService.playNext()
    }
    
    func playPrevious() async {
        await briefeedAudioService.playPrevious()
    }
    
    // MARK: - Private Helpers
    
    private func convertToPlaybackItem(_ item: CurrentPlaybackItem) -> PlaybackItem {
        PlaybackItem(
            id: UUID(),
            title: item.title,
            author: item.author,
            feedTitle: item.author, // Use author as feed title for backward compatibility
            contentType: item.isRSS ? "episode" : "article",
            duration: briefeedAudioService.duration,
            audioURL: item.audioUrl?.absoluteString,
            isRSS: item.isRSS
        )
    }
    
    private func convertQueueToArticles(_ items: [BriefeedAudioItem]) -> [Article] {
        items.compactMap { item in
            guard item.content.contentType == .article else { return nil }
            return articleQueueMap[item.content.id]
        }
    }
    
    private func convertToEnhancedQueue(_ items: [BriefeedAudioItem]) -> [EnhancedQueueItem] {
        items.map { item in
            let source: QueueItemSource
            if item.content.contentType == .article {
                source = .article(source: item.content.feedTitle ?? "Briefeed")
            } else {
                source = .rss(feedId: UUID().uuidString, feedName: item.content.feedTitle ?? "RSS")
            }
            
            return EnhancedQueueItem(
                id: UUID(),
                title: item.content.title,
                source: source,
                addedDate: item.content.dateAdded,
                expiresAt: nil,
                articleID: item.content.contentType == .article ? item.content.id : nil,
                audioUrl: item.content.episodeURL ?? item.audioURL,
                duration: item.content.duration != nil ? Int(item.content.duration!) : nil
            )
        }
    }
    
    private func updateProgress(currentTime: TimeInterval, duration: TimeInterval) {
        let value = duration > 0 ? currentTime / duration : 0
        let remaining = max(0, duration - currentTime)
        
        progress = PlaybackProgress(
            value: value,
            currentTime: Int(currentTime),
            remainingTime: Int(remaining),
            currentTimeFormatted: formatTime(currentTime),
            remainingTimeFormatted: formatTime(remaining),
            durationFormatted: formatTime(duration)
        )
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Legacy Models for Backward Compatibility

struct PlaybackItem: Identifiable {
    let id: UUID
    let title: String
    let author: String?
    let feedTitle: String?
    let contentType: String
    let duration: TimeInterval
    let audioURL: String?
    let isRSS: Bool
}

struct PlaybackProgress {
    var value: Double = 0
    var currentTime: Int = 0
    var remainingTime: Int = 0
    var currentTimeFormatted: String = "0:00"
    var remainingTimeFormatted: String = "0:00"
    var durationFormatted: String = "0:00"
}