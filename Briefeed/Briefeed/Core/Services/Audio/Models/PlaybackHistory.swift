//
//  PlaybackHistory.swift
//  Briefeed
//
//  Created by Briefeed Team on 1/8/25.
//

import Foundation

// MARK: - Playback History Item
struct PlaybackHistoryItem: Codable, Identifiable {
    let id: UUID
    let contentType: AudioContentType
    let title: String
    let author: String?
    let feedTitle: String? // For RSS episodes
    var duration: TimeInterval
    var lastPlaybackPosition: TimeInterval
    var lastPlayedDate: Date
    var playbackProgress: Double // 0.0 to 1.0
    var isCompleted: Bool
    
    // Reference IDs
    let articleID: UUID? // For articles
    let episodeURL: String? // For RSS episodes
    
    init(from audioItem: BriefeedAudioItem) {
        self.id = UUID()
        self.contentType = audioItem.content.contentType
        self.title = audioItem.content.title
        self.author = audioItem.content.author
        self.feedTitle = audioItem.content.feedTitle
        self.duration = audioItem.content.duration ?? 0
        self.lastPlaybackPosition = audioItem.content.lastPlaybackPosition
        self.lastPlayedDate = Date()
        
        // Calculate progress
        let progress = duration > 0 ? lastPlaybackPosition / duration : 0
        self.playbackProgress = min(max(progress, 0), 1.0)
        self.isCompleted = progress >= 0.95 // 95% or more is considered completed
        
        // Set reference IDs
        switch audioItem.content.contentType {
        case .article:
            self.articleID = audioItem.content.id
            self.episodeURL = nil
        case .rssEpisode:
            self.articleID = nil
            self.episodeURL = audioItem.content.episodeURL?.absoluteString
        }
    }
    
    // Update playback position
    mutating func updatePlaybackPosition(_ position: TimeInterval, duration: TimeInterval? = nil) {
        self.lastPlaybackPosition = position
        if let duration = duration {
            self.duration = duration
        }
        
        let progress = self.duration > 0 ? position / self.duration : 0
        self.playbackProgress = min(max(progress, 0), 1.0)
        self.isCompleted = progress >= 0.95
        self.lastPlayedDate = Date()
    }
}

// MARK: - Playback History Manager
final class PlaybackHistoryManager {
    static let shared = PlaybackHistoryManager()
    
    // Configuration
    private let maxHistoryItems = 100
    private let historyKey = "BriefeedPlaybackHistory"
    
    // History storage
    private(set) var history: [PlaybackHistoryItem] = []
    private let queue = DispatchQueue(label: "com.briefeed.playbackhistory", attributes: .concurrent)
    
    private init() {
        loadHistory()
    }
    
    // MARK: - Public Methods
    
    /// Add or update item in history
    func addToHistory(_ audioItem: BriefeedAudioItem, position: TimeInterval, duration: TimeInterval) {
        queue.async(flags: .barrier) {
            // Check if item already exists
            if let existingIndex = self.findExistingItemIndex(for: audioItem) {
                // Update existing item
                self.history[existingIndex].updatePlaybackPosition(position, duration: duration)
                
                // Move to front if significant progress was made
                if existingIndex != 0 {
                    let item = self.history.remove(at: existingIndex)
                    self.history.insert(item, at: 0)
                }
            } else {
                // Add new item
                var newItem = PlaybackHistoryItem(from: audioItem)
                newItem.updatePlaybackPosition(position, duration: duration)
                self.history.insert(newItem, at: 0)
                
                // Enforce max items limit
                if self.history.count > self.maxHistoryItems {
                    self.history = Array(self.history.prefix(self.maxHistoryItems))
                }
            }
            
            self.saveHistory()
        }
    }
    
    /// Get history items (thread-safe)
    func getHistory() -> [PlaybackHistoryItem] {
        return queue.sync {
            history
        }
    }
    
    /// Get history for a specific article
    func getHistory(for articleID: UUID) -> PlaybackHistoryItem? {
        return queue.sync {
            history.first { $0.articleID == articleID }
        }
    }
    
    /// Get history for a specific RSS episode
    func getHistory(for episodeURL: String) -> PlaybackHistoryItem? {
        return queue.sync {
            history.first { $0.episodeURL == episodeURL }
        }
    }
    
    /// Clear all history
    func clearHistory() {
        queue.async(flags: .barrier) {
            self.history.removeAll()
            self.saveHistory()
        }
    }
    
    /// Remove specific item from history
    func removeFromHistory(itemID: UUID) {
        queue.async(flags: .barrier) {
            self.history.removeAll { $0.id == itemID }
            self.saveHistory()
        }
    }
    
    // MARK: - Search & Filter
    
    func searchHistory(query: String) -> [PlaybackHistoryItem] {
        let lowercasedQuery = query.lowercased()
        
        return queue.sync {
            history.filter { item in
                item.title.lowercased().contains(lowercasedQuery) ||
                (item.author?.lowercased().contains(lowercasedQuery) ?? false) ||
                (item.feedTitle?.lowercased().contains(lowercasedQuery) ?? false)
            }
        }
    }
    
    func getIncompleteItems() -> [PlaybackHistoryItem] {
        return queue.sync {
            history.filter { !$0.isCompleted && $0.playbackProgress > 0.05 }
        }
    }
    
    func getRecentItems(limit: Int = 10) -> [PlaybackHistoryItem] {
        return queue.sync {
            Array(history.prefix(limit))
        }
    }
    
    // MARK: - Private Methods
    
    private func findExistingItemIndex(for audioItem: BriefeedAudioItem) -> Int? {
        switch audioItem.content.contentType {
        case .article:
            return history.firstIndex { $0.articleID == audioItem.content.id }
        case .rssEpisode:
            if let episodeURL = audioItem.content.episodeURL?.absoluteString {
                return history.firstIndex { $0.episodeURL == episodeURL }
            }
        }
        return nil
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([PlaybackHistoryItem].self, from: data) else {
            history = []
            return
        }
        
        history = decoded
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }
}

// MARK: - History Statistics
extension PlaybackHistoryManager {
    struct Statistics {
        let totalItems: Int
        let completedItems: Int
        let totalListeningTime: TimeInterval
        let averageCompletion: Double
        let itemsByType: [AudioContentType: Int]
    }
    
    func getStatistics() -> Statistics {
        return queue.sync {
            let totalItems = history.count
            let completedItems = history.filter { $0.isCompleted }.count
            let totalListeningTime = history.reduce(0) { $0 + $1.lastPlaybackPosition }
            
            let totalProgress = history.reduce(0.0) { $0 + $1.playbackProgress }
            let averageCompletion = totalItems > 0 ? totalProgress / Double(totalItems) : 0
            
            var itemsByType: [AudioContentType: Int] = [:]
            for item in history {
                itemsByType[item.contentType, default: 0] += 1
            }
            
            return Statistics(
                totalItems: totalItems,
                completedItems: completedItems,
                totalListeningTime: totalListeningTime,
                averageCompletion: averageCompletion,
                itemsByType: itemsByType
            )
        }
    }
}