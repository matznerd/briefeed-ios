//
//  StorageService.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import Foundation
import CoreData

protocol StorageServiceProtocol {
    func saveContext() async throws
    func deleteOldArticles() async throws
    func calculateCacheSize() async -> Int64
    func clearCache() async throws
    func createFeed(name: String, type: String, path: String) async throws -> Feed
    func markArticleAsRead(_ article: Article) async throws
    func toggleArticleSaved(_ article: Article) async throws
    func deleteArticle(_ article: Article) async throws
    func updateLegacyFeeds() async throws
}

class StorageService: StorageServiceProtocol {
    static let shared = StorageService()
    
    private let persistenceController = PersistenceController.shared
    private var viewContext: NSManagedObjectContext {
        persistenceController.container.viewContext
    }
    
    private init() {}
    
    func saveContext() async throws {
        guard viewContext.hasChanges else { return }
        
        try await viewContext.perform {
            do {
                try self.viewContext.save()
            } catch {
                print("Failed to save context: \(error)")
                throw error
            }
        }
    }
    
    func deleteOldArticles() async throws {
        let expirationDate = Calendar.current.date(byAdding: .day, value: -Constants.Storage.cacheExpirationDays, to: Date())!
        
        let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "createdAt < %@ AND isSaved == false", expirationDate as NSDate)
        
        try await viewContext.perform {
            let articles = try self.viewContext.fetch(fetchRequest)
            articles.forEach { self.viewContext.delete($0) }
            try self.viewContext.save()
        }
    }
    
    func calculateCacheSize() async -> Int64 {
        await viewContext.perform {
            let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
            
            do {
                let articles = try self.viewContext.fetch(fetchRequest)
                let totalSize = articles.reduce(Int64(0)) { total, article in
                    var size: Int64 = 0
                    size += Int64((article.title ?? "").count)
                    size += Int64((article.content ?? "").count)
                    size += Int64((article.summary ?? "").count)
                    size += Int64((article.thumbnail ?? "").count)
                    return total + size
                }
                return totalSize
            } catch {
                print("Failed to calculate cache size: \(error)")
                return 0
            }
        }
    }
    
    func clearCache() async throws {
        try await viewContext.perform {
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Article.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            
            try self.viewContext.execute(deleteRequest)
            try self.viewContext.save()
        }
    }
    
    // MARK: - Feed Management
    func createFeed(name: String, type: String, path: String) async throws -> Feed {
        try await viewContext.perform {
            let feed = Feed(context: self.viewContext)
            feed.id = UUID()
            feed.name = name
            feed.type = type
            feed.path = path
            feed.isActive = true
            feed.sortOrder = try self.getNextSortOrder()
            
            try self.viewContext.save()
            return feed
        }
    }
    
    private func getNextSortOrder() throws -> Int16 {
        let fetchRequest: NSFetchRequest<Feed> = Feed.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Feed.sortOrder, ascending: false)]
        fetchRequest.fetchLimit = 1
        
        let feeds = try viewContext.fetch(fetchRequest)
        return (feeds.first?.sortOrder ?? 0) + 1
    }
    
    // MARK: - Article Management
    func markArticleAsRead(_ article: Article) async throws {
        try await viewContext.perform {
            article.isRead = true
            try self.viewContext.save()
        }
    }
    
    func toggleArticleSaved(_ article: Article) async throws {
        try await viewContext.perform {
            article.isSaved.toggle()
            article.savedAt = article.isSaved ? Date() : nil
            try self.viewContext.save()
        }
    }
    
    func deleteArticle(_ article: Article) async throws {
        try await viewContext.perform {
            self.viewContext.delete(article)
            try self.viewContext.save()
        }
    }
    
    // MARK: - Feed Migration
    func updateLegacyFeeds() async throws {
        try await viewContext.perform {
            let fetchRequest: NSFetchRequest<Feed> = Feed.fetchRequest()
            let feeds = try self.viewContext.fetch(fetchRequest)
            
            // Check for and remove duplicate feeds
            var seenFeeds: Set<String> = []
            var feedsToDelete: [Feed] = []
            
            for feed in feeds {
                let feedKey = "\(feed.name ?? "")-\(feed.type ?? "")"
                
                if seenFeeds.contains(feedKey) {
                    // This is a duplicate, mark for deletion
                    feedsToDelete.append(feed)
                    print("🗑️ Found duplicate feed: \(feed.name ?? "") - will delete")
                } else {
                    seenFeeds.insert(feedKey)
                    
                    // Update enviromonitor multireddit
                    if feed.name == "enviromonitor" && feed.type == "multireddit" {
                        // Check if it's using the old path format
                        if feed.path?.contains("IceMetalPunk") == true || 
                           feed.path?.contains("old.reddit.com") == true ||
                           feed.path?.contains("://") == true {
                            feed.path = "/user/matznerd/m/enviromonitor"
                            print("📝 Updated enviromonitor feed path to: \(feed.path ?? "")")
                        }
                    }
                    
                    // Ensure all subreddit paths are relative
                    if feed.type == "subreddit" && feed.path?.contains("://") == true {
                        // Extract just the path portion
                        if let url = URL(string: feed.path ?? ""), let path = url.path.isEmpty ? nil : url.path {
                            feed.path = path
                            print("📝 Updated \(feed.name ?? "") feed path to relative: \(feed.path ?? "")")
                        }
                    }
                }
            }
            
            // Delete duplicate feeds
            for feed in feedsToDelete {
                self.viewContext.delete(feed)
            }
            
            if !feedsToDelete.isEmpty {
                print("🗑️ Deleted \(feedsToDelete.count) duplicate feeds")
            }
            
            try self.viewContext.save()
        }
    }
}