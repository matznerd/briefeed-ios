//
//  BriefeedAudioItem.swift
//  Briefeed
//
//  Created by Briefeed Team on 1/8/25.
//

import Foundation
import AVFoundation
import SwiftAudioEx
import UIKit

// MARK: - Content Type
enum AudioContentType: String, Codable {
    case article
    case rssEpisode
}

// MARK: - Audio Content Protocol
protocol BriefeedAudioContent {
    var id: UUID { get }
    var title: String { get }
    var author: String? { get }
    var contentType: AudioContentType { get }
    var duration: TimeInterval? { get }
    var lastPlaybackPosition: TimeInterval { get }
    var dateAdded: Date { get }
    
    // For articles
    var articleContent: String? { get }
    var articleURL: URL? { get }
    
    // For RSS episodes
    var episodeURL: URL? { get }
    var feedTitle: String? { get }
    var pubDate: Date? { get }
}

// MARK: - Unified Audio Item
class BriefeedAudioItem {
    let content: BriefeedAudioContent
    var audioURL: URL?
    let isTemporary: Bool
    private(set) var generationState: GenerationState = .pending
    
    enum GenerationState {
        case pending
        case generating
        case ready
        case failed(Error)
    }
    
    init(content: BriefeedAudioContent, audioURL: URL? = nil, isTemporary: Bool = false) {
        self.content = content
        self.audioURL = audioURL
        self.isTemporary = isTemporary
        self.generationState = audioURL != nil ? .ready : .pending
    }
    
    // Update generation state
    func updateGenerationState(_ state: GenerationState) {
        generationState = state
    }
    
    // Update audio URL after TTS generation
    func setAudioURL(_ url: URL) {
        audioURL = url
        generationState = .ready
    }
}

// MARK: - Article Audio Content
struct ArticleAudioContent: BriefeedAudioContent {
    let id: UUID
    let title: String
    let author: String?
    let contentType: AudioContentType = .article
    var duration: TimeInterval?
    var lastPlaybackPosition: TimeInterval = 0
    let dateAdded: Date
    
    // Article specific
    let articleContent: String?
    let articleURL: URL?
    
    // Not used for articles
    let episodeURL: URL? = nil
    let feedTitle: String? = nil
    let pubDate: Date? = nil
    
    init(article: Article) {
        self.id = article.id ?? UUID()
        self.title = article.title ?? "Untitled Article"
        self.author = article.author
        self.dateAdded = article.createdAt ?? Date()
        self.articleContent = article.summary ?? article.content
        self.articleURL = article.url != nil ? URL(string: article.url!) : nil
        
        // Duration will be set after TTS generation
        self.duration = nil
        self.lastPlaybackPosition = 0
    }
}

// MARK: - RSS Episode Audio Content
struct RSSEpisodeAudioContent: BriefeedAudioContent {
    let id: UUID
    let title: String
    let author: String?
    let contentType: AudioContentType = .rssEpisode
    var duration: TimeInterval?
    var lastPlaybackPosition: TimeInterval
    let dateAdded: Date
    
    // RSS specific
    let episodeURL: URL?
    let feedTitle: String?
    let pubDate: Date?
    
    // Not used for RSS
    let articleContent: String? = nil
    let articleURL: URL? = nil
    
    init(episode: RSSEpisode) {
        self.id = UUID() // RSS episodes don't have UUIDs in Core Data
        self.title = episode.title
        self.author = episode.feed?.displayName  // Use feed name as author
        self.dateAdded = Date()
        self.episodeURL = URL(string: episode.audioUrl)
        self.feedTitle = episode.feed?.displayName
        self.pubDate = episode.pubDate
        self.duration = episode.duration > 0 ? TimeInterval(episode.duration) : nil
        self.lastPlaybackPosition = episode.lastPosition
    }
}

// MARK: - Minimal Content Structs for Queue Restoration
struct MinimalArticleContent: BriefeedAudioContent {
    let id: UUID
    let title: String
    let author: String?
    let contentType: AudioContentType = .article
    var duration: TimeInterval? = nil
    var lastPlaybackPosition: TimeInterval = 0
    let dateAdded: Date
    
    // Article specific
    let articleContent: String? = nil
    let articleURL: URL?
    
    // Not used for articles
    let episodeURL: URL? = nil
    let feedTitle: String? = nil
    let pubDate: Date? = nil
}

struct MinimalRSSContent: BriefeedAudioContent {
    let id: UUID
    let title: String
    let author: String?
    let contentType: AudioContentType = .rssEpisode
    var duration: TimeInterval? = nil
    var lastPlaybackPosition: TimeInterval = 0
    let dateAdded: Date
    
    // RSS specific
    let episodeURL: URL?
    let feedTitle: String?
    let pubDate: Date? = nil
    
    // Not used for RSS
    let articleContent: String? = nil
    let articleURL: URL? = nil
}

// MARK: - SwiftAudioEx AudioItem Extension
extension BriefeedAudioItem: AudioItem {
    func getSourceUrl() -> String {
        return audioURL?.absoluteString ?? ""
    }
    
    func getArtist() -> String? {
        switch content.contentType {
        case .article:
            return content.author
        case .rssEpisode:
            return content.feedTitle ?? content.author
        }
    }
    
    func getTitle() -> String? {
        return content.title
    }
    
    func getAlbumTitle() -> String? {
        switch content.contentType {
        case .article:
            return "Briefeed Articles"
        case .rssEpisode:
            return content.feedTitle ?? "Live News"
        }
    }
    
    func getSourceType() -> SourceType {
        // Check if URL is local or remote
        if let url = audioURL {
            if url.isFileURL {
                return .file
            } else {
                return .stream
            }
        }
        return .stream
    }
    
    func getArtwork(_ handler: @escaping (UIImage?) -> Void) {
        // For now, return a default icon based on content type
        DispatchQueue.main.async {
            let imageName = self.content.contentType == .article ? "doc.text" : "dot.radiowaves.left.and.right"
            handler(UIImage(systemName: imageName))
        }
    }
}

// Resume playback support
extension BriefeedAudioItem {
    func getInitialTime() -> TimeInterval? {
        return content.lastPlaybackPosition > 0 ? content.lastPlaybackPosition : nil
    }
}

