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

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Briefeed")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
