//
//  QueueModels.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import Foundation

// MARK: - Queue Item Source
enum QueueItemSource: Codable {
    case article(source: String) // reddit, custom, etc.
    case rss(feedId: String, feedName: String)
    
    var displayName: String {
        switch self {
        case .article(let source):
            return source
        case .rss(_, let feedName):
            return feedName
        }
    }
    
    var isLiveNews: Bool {
        switch self {
        case .rss:
            return true
        case .article:
            return false
        }
    }
    
    var iconName: String {
        switch self {
        case .article:
            return "doc.text"
        case .rss:
            return "dot.radiowaves.left.and.right"
        }
    }
}

// MARK: - Enhanced Queue Item
struct EnhancedQueueItem: Codable {
    let id: UUID
    let title: String
    let source: QueueItemSource
    let addedDate: Date
    let expiresAt: Date?
    
    // Content
    let articleID: UUID? // For article-based items
    let audioUrl: URL? // For RSS episodes
    let duration: Int? // Duration in seconds
    
    // State
    var isListened: Bool = false
    var lastPosition: Double = 0.0 // 0.0 to 1.0 progress
    
    // Computed properties
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
    
    var remainingTime: TimeInterval? {
        guard let expiresAt = expiresAt else { return nil }
        return expiresAt.timeIntervalSinceNow
    }
    
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Queue Filter
enum QueueFilter: String, CaseIterable {
    case all = "all"
    case liveNews = "liveNews"
    case articles = "articles"
    
    var displayName: String {
        switch self {
        case .all:
            return "All"
        case .liveNews:
            return "Live News"
        case .articles:
            return "Articles"
        }
    }
    
    var icon: String {
        switch self {
        case .all:
            return "list.bullet"
        case .liveNews:
            return "dot.radiowaves.left.and.right"
        case .articles:
            return "doc.text"
        }
    }
    
    func matches(_ item: EnhancedQueueItem) -> Bool {
        switch self {
        case .all:
            return true
        case .liveNews:
            return item.source.isLiveNews
        case .articles:
            return !item.source.isLiveNews
        }
    }
}

// MIGRATION: QueueService.QueuedItem migration helper removed - no longer needed