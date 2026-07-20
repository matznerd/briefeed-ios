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

    var enabledFeedCount: Int { feeds.lazy.filter(\.isEnabled).count }
    
    // MARK: - Private Properties
    private let viewContext: NSManagedObjectContext
    private let dataLoader: (String) async throws -> Data
    private let saveContext: () throws -> Void
    
    // MARK: - Default Feeds Configuration
    private static let defaultFeedsConfig: [(id: String, url: String, name: String, frequency: String, priority: Int)] = [
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
    private override init() {
        let context = PersistenceController.shared.container.viewContext
        self.viewContext = context
        self.dataLoader = { endpoint in
            try await NetworkService.shared.requestData(endpoint, method: .get, parameters: nil, headers: nil, timeout: nil)
        }
        self.saveContext = { try context.save() }
        super.init()
        loadFeeds()
    }

    init(
        viewContext: NSManagedObjectContext,
        dataLoader: @escaping (String) async throws -> Data,
        saveContext: (() throws -> Void)? = nil
    ) {
        self.viewContext = viewContext
        self.dataLoader = dataLoader
        self.saveContext = saveContext ?? { try viewContext.save() }
        super.init()
        loadFeeds()
    }
    
    // MARK: - Public Methods
    
    /// Inserts default feed rows only. Network refresh is owned by explicit refresh calls.
    @discardableResult
    func ensureDefaultFeedsExist() async -> Bool {
        do {
            let existingDefaultIDs = try Self.existingDefaultFeedIDs(in: viewContext)
            if try Self.insertMissingDefaultFeeds(in: viewContext) {
                do {
                    try saveContext()
                } catch {
                    Self.discardNewDefaultFeeds(in: viewContext, preserving: existingDefaultIDs)
                    throw error
                }
                loadFeeds()
            }
            return true
        } catch {
            print("Error creating default feeds: \(error)")
            return false
        }
    }

    @discardableResult
    static func insertMissingDefaultFeeds(in context: NSManagedObjectContext) throws -> Bool {
        let request: NSFetchRequest<RSSFeed> = RSSFeed.fetchRequest()
        let existingIDs = Set(try context.fetch(request).map(\.id))
        var inserted = false
        for config in defaultFeedsConfig where !existingIDs.contains(config.id) {
            let feed = RSSFeed(context: context)
            feed.id = config.id
            feed.url = config.url
            feed.displayName = config.name
            feed.updateFrequency = config.frequency
            feed.priority = Int16(config.priority)
            feed.isEnabled = true
            feed.createdDate = Date()
            inserted = true
        }
        return inserted
    }

    private static func existingDefaultFeedIDs(in context: NSManagedObjectContext) throws -> Set<String> {
        let request: NSFetchRequest<RSSFeed> = RSSFeed.fetchRequest()
        let defaults = Set(defaultFeedsConfig.map(\.id))
        return Set(try context.fetch(request).map(\.id).filter(defaults.contains))
    }

    private static func discardNewDefaultFeeds(in context: NSManagedObjectContext, preserving existingIDs: Set<String>) {
        let request: NSFetchRequest<RSSFeed> = RSSFeed.fetchRequest()
        let defaultIDs = Set(defaultFeedsConfig.map(\.id))
        guard let feeds = try? context.fetch(request) else { return }
        for feed in feeds where defaultIDs.contains(feed.id) && !existingIDs.contains(feed.id) {
            context.delete(feed)
        }
        context.processPendingChanges()
    }
    
    @discardableResult
    func refreshAllFeeds() async -> RSSRefreshBatchResult {
        await refreshAll(now: Date())
    }

    func refreshAll(now: Date) async -> RSSRefreshBatchResult {
        guard !isRefreshing else { return RSSRefreshBatchResult(results: []) }
        
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }
        
        var results: [RSSFeedRefreshResult] = []
        for feed in feeds.filter(\.isEnabled).sorted(by: { lhs, rhs in
            lhs.priority == rhs.priority ? lhs.id < rhs.id : lhs.priority < rhs.priority
        }) {
            results.append(await refreshFeed(feed, now: now))
        }
        
        // Clean up old episodes
        cleanupOldEpisodes()
        return RSSRefreshBatchResult(results: results)
    }

    func refreshIfStale(now: Date) async -> RSSRefreshBatchResult {
        guard !isRefreshing else { return RSSRefreshBatchResult(results: []) }
        isRefreshing = true
        defer { isRefreshing = false }
        var results: [RSSFeedRefreshResult] = []
        for feed in feeds.filter(\.isEnabled).sorted(by: { lhs, rhs in
            lhs.priority == rhs.priority ? lhs.id < rhs.id : lhs.priority < rhs.priority
        }) {
            results.append(await refreshIfStale(feed, now: now))
        }
        return RSSRefreshBatchResult(results: results)
    }

    func refreshIfStale(_ feed: RSSFeed, now: Date) async -> RSSFeedRefreshResult {
        if let lastSuccess = feed.lastFetchDate,
           !RSSRefreshPolicy.isStale(feed.updateFrequencyEnum, lastSuccess: lastSuccess, now: now) {
            return RSSFeedRefreshResult(feedID: feed.id, outcome: .skippedFresh(lastSuccessfulRefresh: lastSuccess))
        }
        return await refreshFeed(feed, now: now)
    }
    
    /// Refresh a specific feed
    func refreshFeed(_ feed: RSSFeed, now: Date = Date()) async -> RSSFeedRefreshResult {
        do {
            // Fetch RSS data
            guard let url = URL(string: feed.url) else {
                return failedResult(feedID: feed.id, error: NetworkError.invalidURL)
            }
            let data = try await dataLoader(url.absoluteString)
            
            // Parse RSS
            let parser = RSSParser()
            let episodes = try await parser.parse(data: data, feedId: feed.id)
            
            var insertedIDs: [String] = []
            var insertedEpisodes: [RSSEpisode] = []
            var updatedEpisodes: [(episode: RSSEpisode, snapshot: EpisodeSnapshot)] = []
            let previousFetchDate = feed.lastFetchDate
            for episodeData in episodes {
                if episodeData.usesFallbackIdentity,
                   let canonicalURL = episodeData.canonicalEnclosureURL,
                   let existing = episodeWithCanonicalEnclosure(canonicalURL, feedID: feed.id) {
                    if !updatedEpisodes.contains(where: { $0.episode === existing }) {
                        updatedEpisodes.append((existing, EpisodeSnapshot(episode: existing)))
                    }
                    updateSafeMetadata(existing, from: episodeData)
                } else if !episodeExists(guid: episodeData.guid, feedId: feed.id) {
                    insertedEpisodes.append(createEpisode(from: episodeData, for: feed))
                    insertedIDs.append(episodeData.guid)
                }
            }
            feed.lastFetchDate = now
            do {
                try saveContext()
            } catch {
                restoreRefreshState(
                    feed: feed,
                    previousFetchDate: previousFetchDate,
                    insertedEpisodes: insertedEpisodes,
                    updatedEpisodes: updatedEpisodes
                )
                throw error
            }
            return RSSFeedRefreshResult(feedID: feed.id, outcome: .success(insertedEpisodeIDs: insertedIDs))
        } catch {
            if let networkError = error as? NetworkError, case .networkUnavailable = networkError {
                return RSSFeedRefreshResult(feedID: feed.id, outcome: .skippedOffline)
            }
            return failedResult(feedID: feed.id, error: error)
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
        _ = await refreshFeed(feed)
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
        } catch {
            print("Error loading feeds: \(error)")
        }
    }
    
    private func createEpisode(from data: ParsedRSSEpisode, for feed: RSSFeed) -> RSSEpisode {
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
        return episode
    }
    
    private func episodeExists(guid: String, feedId: String) -> Bool {
        let fetchRequest: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@ AND feedId == %@", guid, feedId)
        fetchRequest.fetchLimit = 1
        
        let count = (try? viewContext.count(for: fetchRequest)) ?? 0
        return count > 0
    }

    private func episodeWithCanonicalEnclosure(_ canonicalURL: String, feedID: String) -> RSSEpisode? {
        let request: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
        request.predicate = NSPredicate(format: "feedId == %@", feedID)
        do {
            return try viewContext.fetch(request).first {
                (try? RSSEpisodeIdentity.canonicalEnclosureURL($0.audioUrl)) == canonicalURL
            }
        } catch {
            return nil
        }
    }

    private func updateSafeMetadata(_ episode: RSSEpisode, from data: ParsedRSSEpisode) {
        episode.title = data.title
        episode.pubDate = data.pubDate
        episode.duration = Int32(data.duration ?? 0)
        episode.episodeDescription = data.description
    }

    private func failedResult(feedID: String, error: Error) -> RSSFeedRefreshResult {
        print("Error refreshing feed \(feedID): \(error)")
        lastError = error
        return RSSFeedRefreshResult(feedID: feedID, outcome: .failed(message: error.localizedDescription))
    }

    private func restoreRefreshState(
        feed: RSSFeed,
        previousFetchDate: Date?,
        insertedEpisodes: [RSSEpisode],
        updatedEpisodes: [(episode: RSSEpisode, snapshot: EpisodeSnapshot)]
    ) {
        for episode in insertedEpisodes { viewContext.delete(episode) }
        for update in updatedEpisodes { update.snapshot.restore(on: update.episode) }
        feed.lastFetchDate = previousFetchDate
        viewContext.processPendingChanges()
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
    
}

private struct EpisodeSnapshot {
    let title: String
    let pubDate: Date
    let duration: Int32
    let episodeDescription: String?

    init(episode: RSSEpisode) {
        title = episode.title
        pubDate = episode.pubDate
        duration = episode.duration
        episodeDescription = episode.episodeDescription
    }

    func restore(on episode: RSSEpisode) {
        episode.title = title
        episode.pubDate = pubDate
        episode.duration = duration
        episode.episodeDescription = episodeDescription
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
    let canonicalEnclosureURL: String?
    let usesFallbackIdentity: Bool
    let pubDate: Date
    let duration: Int?
    let description: String?
}

enum RSSFeedRefreshOutcome: Equatable, Sendable {
    case success(insertedEpisodeIDs: [String])
    case failed(message: String)
    case skippedFresh(lastSuccessfulRefresh: Date)
    case skippedOffline
}

struct RSSFeedRefreshResult: Equatable, Sendable {
    let feedID: String
    let outcome: RSSFeedRefreshOutcome
}

struct RSSRefreshBatchResult: Equatable, Sendable {
    let results: [RSSFeedRefreshResult]

    var successfulSourceEvidenceCount: Int {
        results.reduce(into: 0) { count, result in
            switch result.outcome {
            case .success, .skippedFresh:
                count += 1
            case .failed, .skippedOffline:
                break
            }
        }
    }

    var attemptedFailureCount: Int {
        results.reduce(into: 0) { count, result in
            if case .failed = result.outcome { count += 1 }
        }
    }
}
