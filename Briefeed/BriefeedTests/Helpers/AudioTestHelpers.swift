//
//  AudioTestHelpers.swift
//  BriefeedTests
//
//  Created by Briefeed Team on 1/8/25.
//

import Foundation
import CoreData
@testable import Briefeed

/// Test helpers for audio-related testing
struct AudioTestHelpers {
    
    // MARK: - Test Article Creation
    static func createTestArticle(
        id: UUID = UUID(),
        title: String = "Test Article",
        author: String? = "Test Author",
        content: String = "This is test content for the article.",
        summary: String? = "Test summary",
        url: String = "https://example.com/article",
        createdAt: Date = Date(),
        in context: NSManagedObjectContext
    ) -> Article {
        let article = Article(context: context)
        article.id = id
        article.title = title
        article.author = author
        article.content = content
        article.summary = summary
        article.url = url
        article.createdAt = createdAt
        article.isRead = false
        article.isSaved = false
        
        // Create a test feed
        let feed = Feed(context: context)
        feed.id = UUID()
        feed.name = "Test Feed"
        feed.path = "https://example.com/feed"
        feed.type = "rss"
        article.feed = feed
        
        return article
    }
    
    // MARK: - Test RSS Episode Creation
    static func createTestRSSEpisode(
        title: String = "Test Episode",
        author: String? = "Test Podcaster",
        audioUrl: String = "https://example.com/episode.mp3",
        duration: Int32 = 1800, // 30 minutes
        pubDate: Date = Date(),
        in context: NSManagedObjectContext
    ) -> RSSEpisode {
        let episode = RSSEpisode(context: context)
        episode.title = title
        episode.author = author
        episode.audioUrl = audioUrl
        episode.duration = duration
        episode.pubDate = pubDate
        episode.episodeDescription = "Test episode description"
        episode.isListened = false
        episode.lastPosition = 0
        
        // Create a test RSS feed
        let rssFeed = RSSFeed(context: context)
        rssFeed.id = UUID()
        rssFeed.displayName = "Test Podcast"
        rssFeed.feedUrl = "https://example.com/podcast.xml"
        episode.feed = rssFeed
        
        return episode
    }
    
    // MARK: - Test Audio Item Creation
    static func createTestBriefeedAudioItem(
        type: AudioContentType = .article,
        title: String = "Test Audio Item",
        audioURL: URL? = URL(string: "file:///test/audio.m4a")
    ) -> BriefeedAudioItem {
        if type == .article {
            let content = MinimalArticleContent(
                id: UUID(),
                title: title,
                author: "Test Author",
                articleURL: URL(string: "https://example.com/article"),
                dateAdded: Date()
            )
            return BriefeedAudioItem(content: content, audioURL: audioURL)
        } else {
            let content = MinimalRSSContent(
                id: UUID(),
                title: title,
                author: "Test Podcaster",
                episodeURL: URL(string: "https://example.com/episode.mp3"),
                feedTitle: "Test Podcast",
                dateAdded: Date()
            )
            return BriefeedAudioItem(content: content, audioURL: audioURL)
        }
    }
    
    // MARK: - Test History Item Creation
    static func createTestHistoryItem(
        contentType: AudioContentType = .article,
        title: String = "Test History Item",
        progress: Double = 0.5,
        isCompleted: Bool = false
    ) -> PlaybackHistoryItem {
        return PlaybackHistoryItem(
            id: UUID(),
            contentType: contentType,
            title: title,
            author: contentType == .article ? "Test Author" : "Test Podcaster",
            feedTitle: contentType == .rssEpisode ? "Test Podcast" : nil,
            duration: 180, // 3 minutes
            lastPlaybackPosition: 90, // 1.5 minutes
            lastPlayedDate: Date(),
            playbackProgress: progress,
            isCompleted: isCompleted,
            articleID: contentType == .article ? UUID() : nil,
            episodeURL: contentType == .rssEpisode ? "https://example.com/episode.mp3" : nil
        )
    }
    
    // MARK: - Test Queue Creation
    static func createTestQueue(itemCount: Int = 5, context: NSManagedObjectContext) -> [BriefeedAudioItem] {
        var queue: [BriefeedAudioItem] = []
        
        for i in 0..<itemCount {
            if i % 2 == 0 {
                // Create article items
                let article = createTestArticle(
                    title: "Article \(i + 1)",
                    in: context
                )
                let content = ArticleAudioContent(article: article)
                let item = BriefeedAudioItem(content: content)
                queue.append(item)
            } else {
                // Create RSS episode items
                let episode = createTestRSSEpisode(
                    title: "Episode \(i + 1)",
                    in: context
                )
                let content = RSSEpisodeAudioContent(episode: episode)
                let item = BriefeedAudioItem(
                    content: content,
                    audioURL: URL(string: episode.audioUrl),
                    isTemporary: false
                )
                queue.append(item)
            }
        }
        
        return queue
    }
    
    // MARK: - Test Cache File Creation
    static func createTestCacheFile(at url: URL, size: Int = 1024 * 1024) throws {
        let data = Data(repeating: 0, count: size)
        try data.write(to: url)
    }
    
    // MARK: - Async Test Helpers
    static func waitFor(_ condition: @escaping () -> Bool, timeout: TimeInterval = 5.0) async throws {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                throw TestError.timeout
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }
    
    enum TestError: Error {
        case timeout
    }
}

// MARK: - Test Core Data Stack
class TestPersistenceController {
    static func createInMemoryContext() -> NSManagedObjectContext {
        let container = NSPersistentContainer(name: "Briefeed")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load test store: \(error)")
            }
        }
        
        return container.viewContext
    }
}

// MARK: - Mock URL Session
class MockURLSession: URLSession {
    var mockData: Data?
    var mockResponse: URLResponse?
    var mockError: Error?
    
    override func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = mockError {
            throw error
        }
        
        let data = mockData ?? Data()
        let response = mockResponse ?? HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        
        return (data, response)
    }
}