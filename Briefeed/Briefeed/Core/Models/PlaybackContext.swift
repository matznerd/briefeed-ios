//
//  PlaybackContext.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/17/25.
//

import Foundation

// MARK: - Playback Context
enum PlaybackContext {
    case liveNews       // Playing from Live News list (radio mode)
    case brief          // Playing from Brief queue
    case direct         // Single item play
    
    var displayName: String {
        switch self {
        case .liveNews:
            return "Live News"
        case .brief:
            return "Brief"
        case .direct:
            return "Now Playing"
        }
    }
}

// MARK: - Playable Item Protocol
protocol PlayableItem {
    var id: UUID { get }
    var title: String { get }
    var author: String? { get }
    var audioUrl: URL? { get }
    var isRSS: Bool { get }
}

// MARK: - Current Playback Item
struct CurrentPlaybackItem: PlayableItem {
    let id: UUID
    let title: String
    let author: String?
    let audioUrl: URL?
    let isRSS: Bool
    
    // Additional properties
    let articleID: UUID?        // For article-based items
    let rssEpisode: RSSEpisode? // For RSS episodes
    let source: String          // Feed name or source
    
    // Create from Article
    init(from article: Article) {
        self.id = article.id ?? UUID()
        self.title = article.title ?? "Untitled"
        self.author = article.author
        self.audioUrl = nil
        self.isRSS = false
        self.articleID = article.id
        self.rssEpisode = nil
        self.source = article.feed?.name ?? "Unknown"
    }
    
    // Create from RSS Episode
    init(from episode: RSSEpisode) {
        self.id = UUID() // Generate new ID for playback session
        self.title = episode.title ?? "Untitled Episode"
        self.author = episode.feed?.displayName
        self.audioUrl = URL(string: episode.audioUrl)
        self.isRSS = true
        self.articleID = nil
        self.rssEpisode = episode
        self.source = episode.feed?.displayName ?? "RSS"
    }
}