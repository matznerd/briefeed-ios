//
//  RSSAudioService.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import Foundation
import CoreData
import Combine

// MARK: - RSS Audio Service
@MainActor
class RSSAudioService: NSObject, ObservableObject {
    
    // MARK: - Singleton
    static let shared = RSSAudioService()
    
    // MARK: - Published Properties
    @Published private(set) var feeds: [RSSFeed] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: Error?
    
    // MARK: - Private Properties
    private lazy var networkService = NetworkService.shared
    private lazy var viewContext = PersistenceController.shared.container.viewContext
    private var refreshTimer: Timer?
    
    // MARK: - Default Feeds Configuration
    private let defaultFeedsConfig = [
        ("npr-news-now", "https://feeds.npr.org/500005/podcast.xml", "NPR News Now", "hourly", 1),
        ("bbc-global-news", "https://podcasts.files.bbci.co.uk/p02nq0gn.rss", "BBC Global News Podcast", "daily", 2),
        ("abc-news-update", "https://feeds.megaphone.fm/ESP9792844572", "ABC News Update", "hourly", 3),
        ("cbs-on-the-hour", "https://rss.cbsradionewsfeed.com/254f5d63-d75a-44a2-b727-1ed9b51f03d4/90259cbd-993c-4ca1-afb4-aa23294369ac?feedFormat=all&itemFormat=latest", "CBS News: On The Hour", "hourly", 4),
        ("marketplace-morning", "https://feeds.publicradio.org/public_feeds/marketplace-morning-report/rss/rss", "Marketplace Morning Report", "daily", 5),
        ("marketplace-tech", "https://feeds.publicradio.org/public_feeds/marketplace-tech/rss/rss", "Marketplace Tech", "daily", 6),
        ("nyt-the-daily", "https://feeds.simplecast.com/Sl5CSM3S", "The Daily", "daily", 7),
        ("wsj-minute-briefing", "https://video-api.wsj.com/podcast/rss/wsj/minute-briefing", "WSJ Minute Briefing", "daily", 8),
        ("cbc-world-this-hour", "https://www.cbc.ca/podcasting/includes/hourlynews.xml", "CBC World This Hour", "hourly", 9)
    ]
    
    // MARK: - Initialization
    private var hasInitialized = false
    
    private override init() {
        super.init()
        // Defer heavy work until actually needed
    }
    
    /// Initialize the service (call this after app is ready)
    func initialize() {
        guard !hasInitialized else { return }
        hasInitialized = true
        loadFeeds()
        setupAutoRefresh()
    }
    
    deinit {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - Public Methods
    
    /// Initialize default feeds if needed
    func initializeDefaultFeedsIfNeeded() async {
        let fetchRequest: NSFetchRequest<RSSFeed> = RSSFeed.fetchRequest()
        let count = (try? viewContext.count(for: fetchRequest)) ?? 0
        
        print("🎙️ RSSAudioService: Checking for RSS feeds, found: \(count)")
        
        if count == 0 {  // swiftlint:disable:this empty_count
            print("🎙️ Creating default RSS feeds...")
            for (id, url, name, frequency, priority) in defaultFeedsConfig {
                createFeed(id: id, url: url, displayName: name, updateFrequency: frequency, priority: priority)
            }
            
            do {
                try viewContext.save()
                print("✅ Successfully created \(defaultFeedsConfig.count) default RSS feeds")
                loadFeeds()
                await refreshAllFeeds()
            } catch {
                print("❌ Error creating default feeds: \(error)")
            }
        } else {
            print("✅ RSS feeds already exist, loading...")
            loadFeeds()
        }
    }
    
    /// Refresh all enabled feeds
    func refreshAllFeeds() async {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        lastError = nil
        
        // Refresh each enabled feed
        for feed in feeds.filter({ $0.isEnabled }) {
            await refreshFeed(feed)
        }
        
        isRefreshing = false
        
        // Clean up old episodes
        cleanupOldEpisodes()
    }
    
    /// Refresh a specific feed
    func refreshFeed(_ feed: RSSFeed) async {
        do {
            // Fetch RSS data
            guard let url = URL(string: feed.url) else { return }
            let data = try await networkService.requestData(url.absoluteString, method: .get, parameters: nil, headers: nil, timeout: nil)
            
            // Parse RSS
            let parser = RSSParser()
            let episodes = try await parser.parse(data: data, feedId: feed.id)
            
            // Update feed in Core Data
            feed.lastFetchDate = Date()
            
            // Add new episodes
            for episodeData in episodes {
                // Check if episode already exists
                if !episodeExists(guid: episodeData.guid, feedId: feed.id) {
                    createEpisode(from: episodeData, for: feed)
                }
            }
            
            try viewContext.save()
            
        } catch {
            print("Error refreshing feed \(feed.displayName): \(error)")
            lastError = error
        }
    }
    
    /// Get all fresh episodes sorted by priority and date
    func getFreshEpisodes() -> [RSSEpisode] {
        let allEpisodes = feeds
            .filter { $0.isEnabled }
            .sorted { $0.priority < $1.priority }
            .flatMap { $0.getFreshEpisodes() }
        
        return allEpisodes
    }
    
    /// Get episodes filtered by criteria
    func getEpisodes(filter: EpisodeFilter = .all, limit: Int? = nil) -> [RSSEpisode] {
        let fetchRequest: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
        
        switch filter {
        case .all:
            fetchRequest.predicate = nil
        case .unlistened:
            fetchRequest.predicate = NSPredicate(format: "isListened == false")
        case .fresh:
            let cutoffDate = Date().addingTimeInterval(-7200) // 2 hours
            fetchRequest.predicate = NSPredicate(format: "isListened == false AND pubDate > %@", cutoffDate as CVarArg)
        case .partial:
            fetchRequest.predicate = NSPredicate(format: "lastPosition > 0.0 AND lastPosition < 0.95")
        }
        
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "pubDate", ascending: false)
        ]
        
        if let limit = limit {
            fetchRequest.fetchLimit = limit
        }
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            print("Error fetching episodes: \(error)")
            return []
        }
    }
    
    /// Update feed priority order
    func updateFeedPriorities(_ feedIds: [String]) {
        for (index, feedId) in feedIds.enumerated() {
            if let feed = feeds.first(where: { $0.id == feedId }) {
                feed.priority = Int16(index + 1)
            }
        }
        
        do {
            try viewContext.save()
            loadFeeds()
        } catch {
            print("Error updating feed priorities: \(error)")
        }
    }
    
    /// Parse Player.fm URL to extract RSS feed
    func extractFeedFromPlayerFM(_ urlString: String) async -> String? {
        guard URL(string: urlString) != nil else { return nil }
        
        do {
            // Use Firecrawl to get the page content
            let firecrawlService = FirecrawlService()
            let scraped = try await firecrawlService.scrapeURL(urlString)
            
            // Look for RSS feed link in the content
            let content = scraped.markdown ?? scraped.content
            if !content.isEmpty {
                // Player.fm includes RSS links in the page
                let pattern = #"(https?://[^"\s]+\.rss|https?://[^"\s]+/rss|https?://[^"\s]+/feed)"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) {
                    let range = Range(match.range, in: content)!
                    return String(content[range])
                }
            }
        } catch {
            print("Error extracting feed from Player.fm: \(error)")
        }
        
        return nil
    }
    
    /// Add a new RSS feed
    func addFeed(from urlString: String) async throws {
        // Check if it's a Player.fm URL
        var feedURL = urlString
        if urlString.contains("player.fm") {
            if let extractedURL = await extractFeedFromPlayerFM(urlString) {
                feedURL = extractedURL
            } else {
                throw NSError(domain: "RSSAudioService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not extract RSS feed from Player.fm URL"])
            }
        }
        
        // Validate URL
        guard let url = URL(string: feedURL) else {
            throw NSError(domain: "RSSAudioService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        // Check if feed already exists
        if feeds.first(where: { $0.url == feedURL }) != nil {
            throw NSError(domain: "RSSAudioService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Feed already exists"])
        }
        
        // Fetch and parse feed to get title
        let data = try await URLSession.shared.data(from: url).0
        let parser = RSSParser()
        let episodes = try await parser.parse(data: data, feedId: UUID().uuidString)
        
        // Extract feed title from first episode or use URL
        let feedTitle = episodes.first?.title.components(separatedBy: " - ").first ?? url.host ?? "Unknown Feed"
        
        // Create new feed
        let feed = RSSFeed(context: viewContext)
        feed.id = UUID().uuidString
        feed.url = feedURL
        feed.displayName = feedTitle
        feed.updateFrequency = "daily"
        feed.priority = Int16(feeds.count + 1)
        feed.isEnabled = true
        feed.createdDate = Date()
        
        try viewContext.save()
        loadFeeds()
        
        // Refresh the new feed
        await refreshFeed(feed)
    }
    
    /// Delete a feed
    func deleteFeed(_ feed: RSSFeed) {
        viewContext.delete(feed)
        
        do {
            try viewContext.save()
            loadFeeds()
        } catch {
            print("Error deleting feed: \(error)")
        }
    }
    
    /// Save changes to a feed
    func saveFeed(_ feed: RSSFeed) {
        do {
            try viewContext.save()
            loadFeeds()
        } catch {
            print("Error saving feed: \(error)")
        }
    }
    
    /// Check if an episode is fresh (unlistened and recent)
    func isEpisodeFresh(_ episode: RSSEpisode) -> Bool {
        guard !episode.isListened else { return false }
        
        let maxAge: TimeInterval = episode.updateFrequency == "hourly" ? 7200 : 86400 // 2 hours or 24 hours
        let age = Date().timeIntervalSince(episode.pubDate)
        
        return age <= maxAge
    }
    
    // MARK: - Private Methods
    
    private func loadFeeds() {
        let fetchRequest: NSFetchRequest<RSSFeed> = RSSFeed.fetchRequest()
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "priority", ascending: true)
        ]
        
        do {
            feeds = try viewContext.fetch(fetchRequest)
            print("📻 Loaded \(feeds.count) RSS feeds:")
            for feed in feeds {
                print("  - \(feed.displayName): \(feed.url) (enabled: \(feed.isEnabled))")
            }
        } catch {
            print("❌ Error loading feeds: \(error)")
        }
    }
    
    private func createFeed(id: String, url: String, displayName: String, updateFrequency: String, priority: Int) {
        let feed = RSSFeed(context: viewContext)
        feed.id = id
        feed.url = url
        feed.displayName = displayName
        feed.updateFrequency = updateFrequency
        feed.priority = Int16(priority)
        feed.isEnabled = true
        feed.createdDate = Date()
    }
    
    private func createEpisode(from data: ParsedRSSEpisode, for feed: RSSFeed) {
        let episode = RSSEpisode(context: viewContext)
        episode.id = data.guid
        episode.feedId = feed.id
        episode.title = data.title
        episode.audioUrl = data.audioUrl
        episode.pubDate = data.pubDate
        episode.duration = Int32(data.duration ?? 0)
        episode.episodeDescription = data.description
        episode.isListened = false
        episode.lastPosition = 0.0
        episode.hasBeenQueued = false
        episode.feed = feed
        
        feed.addToEpisodes(episode)
    }
    
    private func episodeExists(guid: String, feedId: String) -> Bool {
        let fetchRequest: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@ AND feedId == %@", guid, feedId)
        fetchRequest.fetchLimit = 1
        
        let count = (try? viewContext.count(for: fetchRequest)) ?? 0
        return count > 0  // swiftlint:disable:this empty_count
    }
    
    private func cleanupOldEpisodes() {
        let fetchRequest: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
        
        do {
            let episodes = try viewContext.fetch(fetchRequest)
            
            for episode in episodes {
                if episode.shouldCleanup() {
                    viewContext.delete(episode)
                }
            }
            
            if viewContext.hasChanges {
                try viewContext.save()
            }
        } catch {
            print("Error cleaning up episodes: \(error)")
        }
    }
    
    private func setupAutoRefresh() {
        // Refresh feeds periodically based on their update frequency
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in // 30 minutes
            Task { [weak self] in
                await self?.refreshStaleFeeds()
            }
        }
    }
    
    private func refreshStaleFeeds() async {
        let staleFeeds = feeds.filter { $0.isEnabled && $0.isStale }
        
        for feed in staleFeeds {
            await refreshFeed(feed)
        }
    }
}

// MARK: - Supporting Types

enum EpisodeFilter {
    case all
    case unlistened
    case fresh
    case partial
}

struct ParsedRSSEpisode {
    let guid: String
    let title: String
    let audioUrl: String
    let pubDate: Date
    let duration: Int?
    let description: String?
}