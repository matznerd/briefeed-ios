//
//  FeedViewModel.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import Foundation
import CoreData
import Combine

@MainActor
class FeedViewModel: ObservableObject {
    @Published var feeds: [Feed] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchResults: [SubredditInfo] = []
    
    private let redditService: RedditServiceProtocol
    private let storageService: StorageServiceProtocol
    private let viewContext: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()
    
    init(redditService: RedditServiceProtocol = RedditService(),
         storageService: StorageServiceProtocol = StorageService.shared,
         viewContext: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.redditService = redditService
        self.storageService = storageService
        self.viewContext = viewContext
        
        Task {
            await initializeFeeds()
        }
    }
    
    private func initializeFeeds() async {
        // Create default feeds if needed
        do {
            try await DefaultDataService.shared.createDefaultFeedsIfNeeded()
        } catch {
            print("Failed to create default feeds: \(error)")
        }
        
        // Fetch all feeds
        await MainActor.run {
            fetchFeeds()
        }
    }
    
    func fetchFeeds() {
        let request: NSFetchRequest<Feed> = Feed.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Feed.sortOrder, ascending: true)]
        
        do {
            feeds = try viewContext.fetch(request)
        } catch {
            errorMessage = "Failed to fetch feeds: \(error.localizedDescription)"
        }
    }
    
    func addFeed(name: String, type: String, path: String? = nil) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Generate path if not provided
            let feedPath: String
            if let path = path {
                feedPath = path
            } else {
                switch type {
                case "subreddit":
                    // Default to hot sort for new subreddits
                    let cleanName = name.replacingOccurrences(of: "r/", with: "")
                    feedPath = "/r/\(cleanName)/hot"
                case "multireddit":
                    feedPath = name.hasPrefix("/") ? name : "/\(name)"
                default:
                    feedPath = name
                }
            }
            
            // Validate the feed exists
            if type == "subreddit" {
                let cleanName = name.replacingOccurrences(of: "r/", with: "")
                _ = try await redditService.fetchSubreddit(name: cleanName, after: nil, limit: 1)
            } else if type == "multireddit" {
                _ = try await redditService.fetchMultireddit(path: feedPath, after: nil, limit: 1)
            }
            
            // Create the feed
            let feed = try await storageService.createFeed(name: name, type: type, path: feedPath)
            feed.sortOrder = Int16(feeds.count)
            try await storageService.saveContext()
            
            await MainActor.run {
                self.feeds.append(feed)
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func deleteFeed(_ feed: Feed) async {
        do {
            // Clear pagination token for this feed
            if let feedID = feed.id {
                DefaultDataService.shared.clearPaginationToken(for: feedID)
            }
            
            viewContext.delete(feed)
            try await storageService.saveContext()
            await MainActor.run {
                self.feeds.removeAll { $0.id == feed.id }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to delete feed: \(error.localizedDescription)"
            }
        }
    }
    
    func moveFeed(from source: IndexSet, to destination: Int) async {
        feeds.move(fromOffsets: source, toOffset: destination)
        
        // Update sort order
        for (index, feed) in feeds.enumerated() {
            feed.sortOrder = Int16(index)
        }
        
        do {
            try await storageService.saveContext()
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to reorder feeds: \(error.localizedDescription)"
            }
        }
    }
    
    func toggleFeedActive(_ feed: Feed) async {
        feed.isActive.toggle()
        
        do {
            try await storageService.saveContext()
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to update feed: \(error.localizedDescription)"
            }
        }
    }
    
    func searchSubreddits(query: String) async {
        guard !query.isEmpty else {
            await MainActor.run {
                self.searchResults = []
            }
            return
        }
        
        isLoading = true
        
        do {
            let results = try await redditService.searchSubreddits(query: query)
            await MainActor.run {
                self.searchResults = results
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Search failed: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Feed URL Support
    func addFeedFromURL(_ urlString: String) async {
        let lowercased = urlString.lowercased()
        
        // Parse Reddit URLs
        if lowercased.contains("reddit.com") || lowercased.contains("old.reddit.com") {
            // Handle subreddit URLs
            if let match = urlString.range(of: #"/r/([^/\s]+)(/[^/\s]+)?"#, options: .regularExpression) {
                let fullPath = String(urlString[match])
                let components = fullPath.split(separator: "/").map(String.init)
                
                if components.count >= 2 {
                    let subredditName = components[1]
                    let sort = components.count >= 3 ? components[2] : "hot"
                    await addFeed(name: "r/\(subredditName)", type: "subreddit", path: "/r/\(subredditName)/\(sort)")
                }
            } else if let match = urlString.range(of: #"/user/[^/]+/m/[^/\s]+"#, options: .regularExpression) {
                // Handle multireddit URLs
                let multiredditPath = String(urlString[match])
                let components = multiredditPath.split(separator: "/")
                if components.count >= 4 {
                    let multiredditName = String(components[3])
                    let fullPath = urlString.contains("old.reddit.com") ? multiredditPath : multiredditPath
                    await addFeed(name: multiredditName, type: "multireddit", path: fullPath)
                }
            }
        }
    }
}