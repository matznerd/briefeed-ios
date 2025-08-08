//
//  EnhancedQueueItem+Extensions.swift
//  Briefeed
//
//  Extensions to properly create EnhancedQueueItem from various sources
//

import Foundation

// MARK: - Item Type for New Architecture
extension EnhancedQueueItem {
    enum ItemType: String, Codable {
        case article
        case rssEpisode
    }
}

// MARK: - Convenience Initializers
extension EnhancedQueueItem {
    
    /// Create from Article
    init(from article: Article) {
        self.init(
            id: UUID(),
            title: article.title ?? "Untitled Article",
            source: .article(source: article.feed?.name ?? "Unknown"),
            addedDate: Date(),
            expiresAt: nil, // Articles don't expire
            articleID: article.id,
            audioUrl: nil, // Will be set after TTS generation
            duration: nil, // Will be set after TTS generation
            isListened: false,
            lastPosition: 0.0
        )
    }
    
    /// Create from RSS Episode
    init(from episode: RSSEpisode) {
        // Calculate expiration (7 days for RSS episodes)
        let expiresAt = Date().addingTimeInterval(7 * 24 * 60 * 60)
        
        self.init(
            id: UUID(),
            title: episode.title,
            source: .rss(
                feedId: episode.feedId,
                feedName: episode.feed?.displayName ?? "Unknown Feed"
            ),
            addedDate: Date(),
            expiresAt: expiresAt,
            articleID: nil,
            audioUrl: URL(string: episode.audioUrl),
            duration: episode.duration > 0 ? Int(episode.duration) : nil,
            isListened: episode.isListened,
            lastPosition: Double(episode.lastPosition) / 100.0 // Convert percentage to 0-1
        )
    }
    
    /// Create a minimal version for persistence
    init(
        id: UUID,
        type: ItemType,
        title: String?,
        author: String? = nil,
        dateAdded addedDate: Date,
        articleID: UUID? = nil,
        audioUrl: URL? = nil,
        feedTitle: String? = nil
    ) {
        let source: QueueItemSource
        if type == .article {
            source = .article(source: feedTitle ?? "Unknown")
        } else {
            source = .rss(feedId: "", feedName: feedTitle ?? "RSS")
        }
        
        self.init(
            id: id,
            title: title ?? "Untitled",
            source: source,
            addedDate: addedDate,
            expiresAt: nil,
            articleID: articleID,
            audioUrl: audioUrl,
            duration: nil,
            isListened: false,
            lastPosition: 0.0
        )
    }
}

// MARK: - Computed Properties for New Architecture
extension EnhancedQueueItem {
    
    /// Get the item type for serialization
    var type: ItemType {
        switch source {
        case .article:
            return .article
        case .rss:
            return .rssEpisode
        }
    }
    
    /// Get author name (for UI display)
    var author: String? {
        switch source {
        case .article(let sourceName):
            return sourceName
        case .rss(_, let feedName):
            return feedName
        }
    }
    
    /// Get feed title (for Now Playing info)
    var feedTitle: String? {
        source.displayName
    }
    
    /// Check if this is a Live News item
    var isLiveNews: Bool {
        source.isLiveNews
    }
    
    /// Get appropriate skip interval (15s for articles, 30s for RSS)
    var skipInterval: TimeInterval {
        switch source {
        case .article:
            return 15.0
        case .rss:
            return 30.0
        }
    }
    
    /// Get icon for UI display
    var iconName: String {
        source.iconName
    }
    
    /// Get formatted time remaining if expires
    var formattedTimeRemaining: String? {
        guard let remainingTime = remainingTime else { return nil }
        
        let hours = Int(remainingTime) / 3600
        let minutes = Int(remainingTime) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    /// Check if ready for playback
    var isPlayable: Bool {
        // RSS episodes are always playable (have URL)
        if audioUrl != nil { return true }
        
        // Articles need TTS generation first
        if articleID != nil {
            // Check if TTS has been generated (would need cache check)
            return false // Will be updated when TTS completes
        }
        
        return false
    }
}

// MARK: - Conversion to BriefeedAudioItem
extension EnhancedQueueItem {
    
    /// Convert to BriefeedAudioItem for playback
    func toBriefeedAudioItem(with article: Article? = nil, episode: RSSEpisode? = nil) -> BriefeedAudioItem? {
        switch source {
        case .article:
            guard let article = article else { return nil }
            let content = ArticleAudioContent(article: article)
            return BriefeedAudioItem(
                content: content,
                audioURL: audioUrl, // May be nil until TTS generated
                isTemporary: false
            )
            
        case .rss:
            if let episode = episode {
                let content = RSSEpisodeAudioContent(episode: episode)
                return BriefeedAudioItem(
                    content: content,
                    audioURL: audioUrl,
                    isTemporary: false
                )
            } else if let audioUrl = audioUrl {
                // Create minimal RSS content for URL-only playback
                let content = MinimalRSSContent(
                    id: id,
                    title: title ?? "Unknown",
                    author: author,
                    dateAdded: addedDate,
                    episodeURL: audioUrl,
                    feedTitle: feedTitle
                )
                return BriefeedAudioItem(
                    content: content,
                    audioURL: audioUrl,
                    isTemporary: true
                )
            }
            return nil
        }
    }
}

// MARK: - Persistence Support
extension EnhancedQueueItem {
    
    /// Convert to dictionary for UserDefaults storage
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "type": type.rawValue,
            "title": title ?? "",
            "dateAdded": addedDate,
            "isListened": isListened,
            "lastPosition": lastPosition
        ]
        
        if let author = author {
            dict["author"] = author
        }
        
        if let articleID = articleID {
            dict["articleID"] = articleID.uuidString
        }
        
        if let audioUrl = audioUrl {
            dict["audioUrl"] = audioUrl.absoluteString
        }
        
        if let feedTitle = feedTitle {
            dict["feedTitle"] = feedTitle
        }
        
        if let duration = duration {
            dict["duration"] = duration
        }
        
        if let expiresAt = expiresAt {
            dict["expiresAt"] = expiresAt
        }
        
        return dict
    }
    
    /// Create from dictionary (UserDefaults restoration)
    static func fromDictionary(_ dict: [String: Any]) -> EnhancedQueueItem? {
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let typeString = dict["type"] as? String,
              let type = ItemType(rawValue: typeString),
              let title = dict["title"] as? String,
              let dateAdded = dict["dateAdded"] as? Date else {
            return nil
        }
        
        let author = dict["author"] as? String
        let articleID = (dict["articleID"] as? String).flatMap { UUID(uuidString: $0) }
        let audioUrl = (dict["audioUrl"] as? String).flatMap { URL(string: $0) }
        let feedTitle = dict["feedTitle"] as? String
        let duration = dict["duration"] as? Int
        let expiresAt = dict["expiresAt"] as? Date
        let isListened = dict["isListened"] as? Bool ?? false
        let lastPosition = dict["lastPosition"] as? Double ?? 0.0
        
        // Reconstruct source
        let source: QueueItemSource
        if type == .article {
            source = .article(source: feedTitle ?? "Unknown")
        } else {
            source = .rss(feedId: "", feedName: feedTitle ?? "RSS")
        }
        
        return EnhancedQueueItem(
            id: id,
            title: title,
            source: source,
            addedDate: dateAdded,
            expiresAt: expiresAt,
            articleID: articleID,
            audioUrl: audioUrl,
            duration: duration,
            isListened: isListened,
            lastPosition: lastPosition
        )
    }
}

// MARK: - Equatable & Hashable
extension EnhancedQueueItem: Equatable {
    static func == (lhs: EnhancedQueueItem, rhs: EnhancedQueueItem) -> Bool {
        lhs.id == rhs.id
    }
}

extension EnhancedQueueItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}