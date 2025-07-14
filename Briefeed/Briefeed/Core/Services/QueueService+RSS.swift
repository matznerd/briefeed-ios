//
//  QueueService+RSS.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import Foundation
import CoreData

// MARK: - RSS Queue Extension
extension QueueService {
    
    // MARK: - RSS Methods
    
    /// Add an RSS episode to the queue
    func addRSSEpisode(_ episode: RSSEpisode) {
        // Check if already in queue
        if enhancedQueue.contains(where: { $0.audioUrl?.absoluteString == episode.audioUrl }) {
            return
        }
        
        // Calculate expiration based on update frequency
        let expirationHours = episode.updateFrequency == "hourly" ? 24 : 168 // 7 days for daily
        let expiresAt = Date().addingTimeInterval(TimeInterval(expirationHours * 3600))
        
        // Create enhanced queue item
        let queueItem = EnhancedQueueItem(
            id: UUID(),
            title: episode.title,
            source: .rss(feedId: episode.feedId, feedName: episode.feed?.displayName ?? "Unknown Feed"),
            addedDate: Date(),
            expiresAt: expiresAt,
            articleID: nil,
            audioUrl: URL(string: episode.audioUrl),
            duration: Int(episode.duration),
            isListened: false,
            lastPosition: 0.0
        )
        
        enhancedQueue.append(queueItem)
        saveEnhancedQueue()
        
        // Add to audio service
        if let article = createPlaceholderArticle(for: episode) {
            audioService.addToQueue(article)
        }
    }
    
    /// Auto-populate queue with fresh RSS episodes
    func autoPopulateWithLiveNews() async {
        guard UserDefaultsManager.shared.autoPlayLiveNewsOnOpen else { return }
        
        // Get fresh episodes from RSS service
        if let rssService = try? getRSSService() {
            let freshEpisodes = await rssService.getFreshEpisodes()
            
            // Add up to 10 fresh episodes
            for episode in freshEpisodes.prefix(10) {
                // Check if already queued
                if !episode.hasBeenQueued {
                    addRSSEpisode(episode)
                    episode.hasBeenQueued = true
                    try? episode.managedObjectContext?.save()
                }
            }
            
            // Start playing if nothing is playing
            if !audioService.isPlaying && !enhancedQueue.isEmpty {
                playNext()
            }
        }
    }
    
    /// Clean up expired items from queue
    func cleanupExpiredItems() {
        let now = Date()
        
        // Remove expired items that aren't currently playing
        enhancedQueue.removeAll { item in
            guard let expiresAt = item.expiresAt else { return false }
            let isExpired = now > expiresAt
            let isPlaying = audioService.currentArticle?.id?.uuidString == item.id.uuidString
            return isExpired && !isPlaying && !item.isListened
        }
        
        saveEnhancedQueue()
    }
    
    /// Filter queue by type
    func getFilteredQueue(filter: QueueFilter) -> [EnhancedQueueItem] {
        return enhancedQueue.filter { filter.matches($0) }
    }
    
    /// Update progress for RSS episode
    func updateRSSProgress(itemId: UUID, progress: Double) {
        guard let index = enhancedQueue.firstIndex(where: { $0.id == itemId }) else { return }
        enhancedQueue[index].lastPosition = progress
        saveEnhancedQueue()
    }
    
    /// Mark RSS episode as listened
    func markRSSListened(itemId: UUID) {
        guard let index = enhancedQueue.firstIndex(where: { $0.id == itemId }) else { return }
        enhancedQueue[index].isListened = true
        enhancedQueue[index].lastPosition = 1.0
        
        // Remove from queue after playing (unless saved)
        if enhancedQueue[index].source.isLiveNews {
            enhancedQueue.remove(at: index)
        }
        
        saveEnhancedQueue()
    }
    
    // MARK: - Private Methods
    
    /// Create a placeholder Article for RSS episode to work with AudioService
    private func createPlaceholderArticle(for episode: RSSEpisode) -> Article? {
        let context = PersistenceController.shared.container.viewContext
        let article = Article(context: context)
        
        article.id = UUID()
        article.title = episode.title
        article.summary = episode.episodeDescription ?? "RSS Episode"
        article.url = episode.audioUrl
        // Note: sourceFeed and publishedDate are not part of Article model
        // These are tracked in EnhancedQueueItem instead
        
        // Don't save to Core Data - this is temporary
        return article
    }
    
    /// Get RSS Audio Service instance
    private func getRSSService() throws -> RSSAudioService {
        return RSSAudioService.shared
    }
    
    /// Save enhanced queue to UserDefaults
    private func saveEnhancedQueue() {
        guard let encoded = try? JSONEncoder().encode(enhancedQueue) else { return }
        userDefaults.set(encoded, forKey: enhancedQueueKey)
    }
    
    /// Load enhanced queue from UserDefaults
    func loadEnhancedQueue() {
        guard let data = userDefaults.data(forKey: enhancedQueueKey),
              let decoded = try? JSONDecoder().decode([EnhancedQueueItem].self, from: data) else {
            return
        }
        enhancedQueue = decoded
    }
    
    /// Migrate legacy queue items to enhanced format
    func migrateLegacyQueue() {
        // Convert existing queue items to enhanced format
        for legacyItem in queuedItems {
            // Fetch article from Core Data
            let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", legacyItem.articleID as CVarArg)
            fetchRequest.fetchLimit = 1
            
            if let article = try? PersistenceController.shared.container.viewContext.fetch(fetchRequest).first,
               let enhancedItem = legacyItem.toEnhancedItem(with: article) {
                enhancedQueue.append(enhancedItem)
            }
        }
        
        saveEnhancedQueue()
    }
    
    /// Play next item in queue
    func playNext() {
        guard let nextItem = enhancedQueue.first else { return }
        
        if let audioUrl = nextItem.audioUrl {
            // Play RSS episode
            Task {
                await audioService.playRSSEpisode(url: audioUrl, title: nextItem.title)
            }
        } else if let articleID = nextItem.articleID {
            // Play article TTS
            // Fetch article and play as usual
            let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", articleID as CVarArg)
            if let article = try? PersistenceController.shared.container.viewContext.fetch(fetchRequest).first {
                audioService.addToQueue(article)
            }
        }
    }
}