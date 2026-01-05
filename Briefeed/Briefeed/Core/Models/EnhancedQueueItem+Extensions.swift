//
//  EnhancedQueueItem+Extensions.swift
//  Briefeed
//
//  Conversion between UnifiedQueueItem and EnhancedQueueItem
//

import Foundation
import CoreData

// MARK: - UnifiedQueueItem to EnhancedQueueItem conversion
extension UnifiedQueueItem {
    /// Convert UnifiedQueueItem to EnhancedQueueItem for UI display
    @MainActor
    func toEnhancedQueueItem() -> EnhancedQueueItem {
        let source: QueueItemSource
        let articleID: UUID?
        let audioUrl: URL?

        switch type {
        case .article:
            source = .article(source: article?.feed?.name ?? "Unknown")
            articleID = article?.id
            audioUrl = nil
        case .rssEpisode:
            source = .rss(
                feedId: episode?.feed?.id ?? "",
                feedName: episode?.feed?.displayName ?? "Unknown"
            )
            articleID = nil
            audioUrl = self.audioURL
        }

        // Look up error state from QueueCoordinator
        let itemUUID = UUID(uuidString: id) ?? UUID()
        let queueItem = QueueCoordinator.shared.queue.first { $0.id == itemUUID }
        let errorMessage = queueItem?.errorMessage
        let retryCount = queueItem?.retryCount ?? 0

        return EnhancedQueueItem(
            id: itemUUID,
            title: title,
            source: source,
            addedDate: Date(),
            expiresAt: nil,
            articleID: articleID,
            audioUrl: audioUrl,
            duration: Int(duration),
            isListened: false,
            lastPosition: 0.0,
            errorMessage: errorMessage,
            retryCount: retryCount
        )
    }
    
    /// Computed property for convenience
    var articleID: UUID? {
        article?.id
    }
}

// MARK: - Enhanced Queue Item Extensions
extension EnhancedQueueItem {
    /// Create from Article
    init(from article: Article) {
        self.init(
            id: article.id ?? UUID(),
            title: article.title ?? "Untitled",
            source: .article(source: article.feed?.name ?? "Unknown"),
            addedDate: Date(),
            expiresAt: nil,
            articleID: article.id,
            audioUrl: nil,
            duration: nil,
            isListened: false,
            lastPosition: 0.0,
            errorMessage: nil,
            retryCount: 0
        )
    }

    /// Create from RSS Episode
    init(from episode: RSSEpisode) {
        self.init(
            id: UUID(uuidString: episode.id) ?? UUID(),
            title: episode.title,
            source: .rss(
                feedId: episode.feed?.id ?? "",
                feedName: episode.feed?.displayName ?? "Unknown"
            ),
            addedDate: Date(),
            expiresAt: nil,
            articleID: nil,
            audioUrl: URL(string: episode.audioUrl),
            duration: nil,
            isListened: episode.isListened,
            lastPosition: 0.0,
            errorMessage: nil,
            retryCount: 0
        )
    }
}

// MARK: - Collection Extension for Array Conversion
extension Array where Element == UnifiedQueueItem {
    /// Convert array of UnifiedQueueItems to EnhancedQueueItems
    @MainActor
    func toEnhancedQueueItems() -> [EnhancedQueueItem] {
        self.map { $0.toEnhancedQueueItem() }
    }
}
