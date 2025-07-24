//
//  Persistence.swift
//  Briefeed
//
//  Created by Eric M on 6/21/25.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create the 3 default feeds matching Constants.Reddit.defaultFeeds
        let newsFeed = Feed(context: viewContext)
        newsFeed.id = UUID()
        newsFeed.name = "r/news"
        newsFeed.type = "subreddit"
        newsFeed.path = "/r/news"
        newsFeed.isActive = true
        newsFeed.sortOrder = 0
        
        let enviroMonitorFeed = Feed(context: viewContext)
        enviroMonitorFeed.id = UUID()
        enviroMonitorFeed.name = "enviromonitor"
        enviroMonitorFeed.type = "multireddit"
        enviroMonitorFeed.path = "/user/matznerd/m/enviromonitor"
        enviroMonitorFeed.isActive = true
        enviroMonitorFeed.sortOrder = 1
        
        let futurologyFeed = Feed(context: viewContext)
        futurologyFeed.id = UUID()
        futurologyFeed.name = "r/futurology"
        futurologyFeed.type = "subreddit"
        futurologyFeed.path = "/r/futurology"
        futurologyFeed.isActive = true
        futurologyFeed.sortOrder = 2
        
        // Create sample articles for each feed
        let feeds = [newsFeed, enviroMonitorFeed, futurologyFeed]
        let subreddits = ["news", "environment", "futurology"]
        
        for (index, feed) in feeds.enumerated() {
            for i in 0..<3 {
                let article = Article(context: viewContext)
                article.id = UUID()
                article.title = "Sample \(feed.name ?? "") Article \(i + 1)"
                article.author = "user\(i)"
                article.subreddit = subreddits[index]
                article.url = "https://example.com/\(subreddits[index])/article\(i)"
                article.content = "This is a sample article content for preview purposes. It contains some text to simulate a real article."
                article.createdAt = Date().addingTimeInterval(TimeInterval(-i * 3600))
                article.isRead = i == 0
                article.isSaved = i == 1
                article.feed = feed
            }
        }
        
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    var container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Briefeed")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Enable automatic lightweight migration
        if let description = container.persistentStoreDescriptions.first {
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }
        
        // Load the persistent stores
        var loadError: NSError?
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                print("❌ Core Data error: \(error), \(error.userInfo)")
                loadError = error
            }
        }
        
        // Handle migration failure after the initial load
        if let error = loadError {
            // If migration fails, delete the store and recreate
            if error.code == 134140 || error.code == 134100 {
                print("⚠️ Migration failed, attempting to recreate store...")
                
                if let storeURL = container.persistentStoreDescriptions.first?.url {
                    do {
                        // Remove the existing store
                        try FileManager.default.removeItem(at: storeURL)
                        
                        // Also remove journal files
                        let walURL = storeURL.appendingPathExtension("sqlite-wal")
                        let shmURL = storeURL.appendingPathExtension("sqlite-shm")
                        try? FileManager.default.removeItem(at: walURL)
                        try? FileManager.default.removeItem(at: shmURL)
                        
                        print("✅ Removed old store, recreating...")
                        
                        // Create a new container and try loading again
                        let newContainer = NSPersistentContainer(name: "Briefeed")
                        if inMemory {
                            newContainer.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
                        }
                        
                        newContainer.loadPersistentStores { _, retryError in
                            if let retryError = retryError {
                                print("❌ Failed to recreate store: \(retryError)")
                                fatalError("Could not recreate Core Data store: \(retryError)")
                            } else {
                                print("✅ Successfully recreated Core Data store")
                            }
                        }
                        
                        // Replace the container
                        container = newContainer
                    } catch {
                        print("❌ Failed to remove old store: \(error)")
                        fatalError("Could not remove old Core Data store: \(error)")
                    }
                }
            } else {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
