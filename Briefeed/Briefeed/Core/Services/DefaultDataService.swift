//
//  DefaultDataService.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import Foundation
import CoreData

// MARK: - Default Data Service
class DefaultDataService {
    static let shared = DefaultDataService()
    
    private let storageService: StorageServiceProtocol
    private let userDefaults = UserDefaultsManager.shared
    
    init(storageService: StorageServiceProtocol = StorageService.shared) {
        self.storageService = storageService
    }
    
    // MARK: - Create Default Feeds
    func createDefaultFeedsIfNeeded() async throws {
        // First, update any legacy feeds
        try await storageService.updateLegacyFeeds()

        // Get existing feeds
        let existingFeeds = try await storageService.fetchAllFeeds()
        let existingNames = Set(existingFeeds.compactMap { $0.name })

        // Check if all default feeds exist
        let defaultNames = Set(Constants.Reddit.defaultFeeds.map { $0.name })
        let missingFeeds = defaultNames.subtracting(existingNames)

        // If flag is set and no feeds missing, skip
        if userDefaults.hasCreatedDefaultFeeds && missingFeeds.isEmpty {
            return
        }

        print("📱 Creating default feeds... (missing: \(missingFeeds))")

        for (index, feedData) in Constants.Reddit.defaultFeeds.enumerated() {
            // Skip if feed already exists
            guard !existingNames.contains(feedData.name) else {
                continue
            }

            do {
                let feed = try await storageService.createFeed(
                    name: feedData.name,
                    type: feedData.type,
                    path: feedData.path
                )
                feed.sortOrder = Int16(index)
                feed.isActive = true
                print("  ✓ Created feed: \(feedData.name)")
            } catch {
                print("Failed to create default feed \(feedData.name): \(error)")
            }
        }

        try await storageService.saveContext()
        userDefaults.hasCreatedDefaultFeeds = true
    }
    
    // MARK: - Generate Feed URL
    func generateFeedURL(for feed: Feed, sort: String = "hot", after: String? = nil, limit: Int? = nil) -> String {
        let actualLimit = limit ?? Constants.Reddit.initialLoadLimit
        
        print("🔗 Generating URL for feed: \(feed.name ?? "Unknown") type: \(feed.type ?? "Unknown") path: \(feed.path ?? "No path")")
        
        // Check if path already contains the full URL
        var url: String
        if let path = feed.path, path.contains("://") {
            // If it's already a full URL, use it as is
            url = path
            print("  ✓ Using full URL from path: \(url)")
        } else if let path = feed.path {
            // For relative paths, prepend the appropriate base URL
            let baseURL = Constants.API.redditBaseURL
            // Ensure path starts with /
            let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
            url = "\(baseURL)\(cleanPath)"
            print("  ✓ Built URL from relative path: \(url)")
        } else {
            // Fallback to base URL
            url = Constants.API.redditBaseURL
            print("  ⚠️ No path provided, using base URL: \(url)")
        }
        
        // Handle multireddit URLs differently than subreddit URLs
        if feed.type == "multireddit" {
            // For multireddits, the format is /user/{username}/m/{multireddit_name}
            // Add sort only if not default hot
            if sort != "hot" && !url.contains("/\(sort)") && !url.hasSuffix(".json") {
                url += "/\(sort)"
            }
        } else {
            // Handle sorting for subreddits - if not hot, insert sort before .json
            if sort != "hot" && !url.contains("/\(sort)") {
                // Check if the path already has .json
                if url.hasSuffix(".json") {
                    url = url.replacingOccurrences(of: ".json", with: "/\(sort).json")
                } else if url.contains(".json?") {
                    // Handle case where .json is followed by query parameters
                    url = url.replacingOccurrences(of: ".json?", with: "/\(sort).json?")
                } else {
                    url += "/\(sort)"
                }
            }
        }
        
        // Ensure .json suffix
        if !url.hasSuffix(".json") && !url.contains(".json?") {
            url += ".json"
            print("  ✓ Added .json suffix: \(url)")
        }
        
        // Add query parameters
        var queryParams = ["limit=\(actualLimit)", "raw_json=1"]
        
        if let after = after {
            queryParams.append("after=\(after)")
        }
        
        let queryString = queryParams.joined(separator: "&")
        url += url.contains("?") ? "&\(queryString)" : "?\(queryString)"
        
        print("  ✓ Final URL with params: \(url)")
        return url
    }
    
    // MARK: - Content Filtering
    func shouldFilterPost(_ post: RedditPost) -> Bool {
        // Filter out video posts
        if post.isVideo == true {
            return true
        }
        
        // Filter out self posts (they don't have external articles to summarize)
        // Even if they have selftext, we want external articles only
        if post.isSelf == true {
            return true
        }
        
        // Filter out posts without URLs
        guard let url = post.url else {
            return true
        }
        
        let lowercasedURL = url.lowercased()
        
        // Filter out image-only posts from specific domains
        for domain in Constants.Reddit.filteredDomains {
            if lowercasedURL.contains(domain) {
                return true
            }
        }
        
        // Filter out direct file links (PDFs, documents, etc.)
        for fileExt in Constants.Reddit.filteredFileExtensions {
            if lowercasedURL.hasSuffix(fileExt.lowercased()) {
                return true
            }
            // Also check if file extension appears before query parameters
            if lowercasedURL.contains(fileExt.lowercased() + "?") {
                return true
            }
        }
        
        // Filter out Reddit internal links that aren't articles
        if lowercasedURL.contains("reddit.com/") || lowercasedURL.contains("redd.it/") {
            // Allow reddit.com links only if they're to comments (which might link to articles)
            // Filter out user profiles, subreddit pages, etc.
            if lowercasedURL.contains("/user/") ||
               lowercasedURL.contains("/u/") ||
               lowercasedURL.contains("/r/") && !lowercasedURL.contains("/comments/") ||
               lowercasedURL.contains("/message/") ||
               lowercasedURL.contains("/chat/") {
                return true
            }
        }
        
        // Keep the post if it passes all filters
        return false
    }
    
    // MARK: - Feed Pagination Management
    func getPaginationToken(for feedID: UUID) -> String? {
        let tokens = UserDefaults.standard.dictionary(forKey: Constants.UserDefaultsKeys.feedPaginationTokens) as? [String: String] ?? [:]
        return tokens[feedID.uuidString]
    }
    
    func setPaginationToken(_ token: String?, for feedID: UUID) {
        var tokens = UserDefaults.standard.dictionary(forKey: Constants.UserDefaultsKeys.feedPaginationTokens) as? [String: String] ?? [:]
        
        if let token = token {
            tokens[feedID.uuidString] = token
        } else {
            tokens.removeValue(forKey: feedID.uuidString)
        }
        
        UserDefaults.standard.set(tokens, forKey: Constants.UserDefaultsKeys.feedPaginationTokens)
    }
    
    func clearPaginationToken(for feedID: UUID) {
        setPaginationToken(nil, for: feedID)
    }
    
    func clearAllPaginationTokens() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.feedPaginationTokens)
    }
}

// MARK: - Feed Extension for URL Generation
extension Feed {
    func generateURL(sort: String = "hot", after: String? = nil, limit: Int? = nil) -> String {
        return DefaultDataService.shared.generateFeedURL(for: self, sort: sort, after: after, limit: limit)
    }
}