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
    func addRSSEpisode(_ episode: RSSEpisode, isLiveNews: Bool = false, playNext: Bool = false) {
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
        
        // Add to enhanced queue
        if playNext && !enhancedQueue.isEmpty {
            // Find the current playing index
            var insertIndex = 1 // Default to second position
            if let currentItem = audioService.currentPlaybackItem {
                // Find where the current item is in the queue
                if let currentArticleID = currentItem.articleID {
                    if let index = enhancedQueue.firstIndex(where: { $0.articleID == currentArticleID }) {
                        insertIndex = index + 1
                    }
                } else if let currentURL = currentItem.audioUrl {
                    if let index = enhancedQueue.firstIndex(where: { $0.audioUrl == currentURL }) {
                        insertIndex = index + 1
                    }
                }
            }
            insertIntoEnhancedQueue(queueItem, at: min(insertIndex, enhancedQueue.count))
        } else {
            appendToEnhancedQueue(queueItem)
        }
        saveEnhancedQueue()
        
        // Add to audio service
        if let article = createPlaceholderArticle(for: episode) {
            if playNext && audioService.queue.count > 1 {
                audioService.queue.insert(article, at: min(1, audioService.queue.count))
            } else {
                audioService.addToQueue(article)
            }
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
            if audioService.state.value != .playing && !enhancedQueue.isEmpty {
                playNext()
            }
        }
    }
    
    /// Clean up expired items from queue
    func cleanupExpiredItems() {
        let now = Date()
        
        // Remove expired items that aren't currently playing
        removeFromEnhancedQueue { item in
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
        modifyEnhancedQueueItem(at: index) { item in
            let newItem = EnhancedQueueItem(
                id: item.id,
                title: item.title,
                source: item.source,
                addedDate: item.addedDate,
                expiresAt: item.expiresAt,
                articleID: item.articleID,
                audioUrl: item.audioUrl,
                duration: item.duration,
                isListened: item.isListened,
                lastPosition: progress
            )
            item = newItem
        }
        saveEnhancedQueue()
    }
    
    /// Mark RSS episode as listened
    func markRSSListened(itemId: UUID) {
        guard let index = enhancedQueue.firstIndex(where: { $0.id == itemId }) else { return }
        modifyEnhancedQueueItem(at: index) { item in
            let newItem = EnhancedQueueItem(
                id: item.id,
                title: item.title,
                source: item.source,
                addedDate: item.addedDate,
                expiresAt: item.expiresAt,
                articleID: item.articleID,
                audioUrl: item.audioUrl,
                duration: item.duration,
                isListened: true,
                lastPosition: 1.0
            )
            item = newItem
        }
        
        // Remove from queue after playing (unless saved)
        if index < enhancedQueue.count && enhancedQueue[index].source.isLiveNews {
            var updatedQueue = enhancedQueue
            updatedQueue.remove(at: index)
            updateEnhancedQueue(updatedQueue)
            
            // Auto-populate with next episode
            Task {
                await autoPopulateNextEpisode()
            }
        }
        
        saveEnhancedQueue()
    }
    
    /// Auto-populate with the next episode from available feeds
    private func autoPopulateNextEpisode() async {
        // Check if we should auto-populate
        guard UserDefaultsManager.shared.autoPlayLiveNewsOnOpen else { return }
        
        // Get fresh episodes from RSS service
        if let rssService = try? getRSSService() {
            let freshEpisodes = await rssService.getFreshEpisodes()
            
            // Find an episode that's not already in queue
            for episode in freshEpisodes {
                if !enhancedQueue.contains(where: { $0.audioUrl?.absoluteString == episode.audioUrl }) && !episode.isListened {
                    await MainActor.run {
                        addRSSEpisode(episode)
                    }
                    break
                }
            }
        }
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
    internal func getRSSService() throws -> RSSAudioService {
        return RSSAudioService.shared
    }
    
    /// Save enhanced queue to UserDefaults
    internal func saveEnhancedQueue() {
        guard let encoded = try? JSONEncoder().encode(enhancedQueue) else { return }
        userDefaults.set(encoded, forKey: getEnhancedQueueKey())
    }
    
    /// Load enhanced queue from UserDefaults
    func loadEnhancedQueue() {
        guard let data = userDefaults.data(forKey: getEnhancedQueueKey()),
              let decoded = try? JSONDecoder().decode([EnhancedQueueItem].self, from: data) else {
            return
        }
        updateEnhancedQueue(decoded)
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
                appendToEnhancedQueue(enhancedItem)
            }
        }
        
        saveEnhancedQueue()
    }
    
    /// Play next item in queue
    func playNext() {
        print("📻 QueueService.playNext() called")
        print("📻 Enhanced queue has \(enhancedQueue.count) items")
        
        guard let nextItem = enhancedQueue.first else { 
            print("📻 No items in enhanced queue")
            return 
        }
        
        print("📻 Next item: \(nextItem.title ?? "Unknown") - Type: \(nextItem.audioUrl != nil ? "RSS" : "Article")")
        
        if let audioUrl = nextItem.audioUrl {
            // Play RSS episode
            print("📻 Playing RSS episode from URL: \(audioUrl)")
            Task {
                // Find the actual RSS episode for full data
                if case let .rss(feedId, _) = nextItem.source {
                    let fetchRequest: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "audioUrl == %@", audioUrl.absoluteString)
                    fetchRequest.fetchLimit = 1
                    
                    if let episode = try? PersistenceController.shared.container.viewContext.fetch(fetchRequest).first {
                        print("📻 Found full episode data, playing...")
                        await audioService.playRSSEpisode(url: audioUrl, title: nextItem.title ?? "Unknown", episode: episode)
                    } else {
                        print("📻 No episode data found, playing URL only...")
                        await audioService.playRSSEpisode(url: audioUrl, title: nextItem.title ?? "Unknown")
                    }
                } else {
                    print("📻 Playing RSS URL without episode data...")
                    await audioService.playRSSEpisode(url: audioUrl, title: nextItem.title ?? "Unknown")
                }
            }
        } else if let articleID = nextItem.articleID {
            // Play article TTS
            print("📻 Playing article TTS: \(articleID)")
            // Fetch article and play as usual
            let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", articleID as CVarArg)
            if let article = try? PersistenceController.shared.container.viewContext.fetch(fetchRequest).first {
                print("📻 Found article, adding to queue...")
                audioService.addToQueue(article)
            } else {
                print("❌ Article not found in Core Data")
            }
        }
    }
}