import Foundation
import CoreData
import Testing
@testable import Briefeed

@Suite("RSS refresh policy")
struct RSSRefreshPolicyTests {
    @Test func stalenessUsesThirtyMinutesAndSixHours() {
        let now = Date(timeIntervalSince1970: 10_000_000)

        #expect(RSSRefreshPolicy.isStale(.hourly, lastSuccess: now.addingTimeInterval(-1_801), now: now))
        #expect(!RSSRefreshPolicy.isStale(.hourly, lastSuccess: now.addingTimeInterval(-1_799), now: now))
        #expect(RSSRefreshPolicy.isStale(.daily, lastSuccess: now.addingTimeInterval(-21_601), now: now))
        #expect(!RSSRefreshPolicy.isStale(.daily, lastSuccess: now.addingTimeInterval(-21_599), now: now))
    }

    @Test func allFreshSourcesProvideEvidenceWithoutAttemptedFailures() {
        let date = Date(timeIntervalSince1970: 10_000_000)
        let batch = RSSRefreshBatchResult(results: [
            RSSFeedRefreshResult(feedID: "fresh-one", outcome: .skippedFresh(lastSuccessfulRefresh: date)),
            RSSFeedRefreshResult(feedID: "fresh-two", outcome: .skippedFresh(lastSuccessfulRefresh: date))
        ])

        #expect(batch.successfulSourceEvidenceCount == 2)
        #expect(batch.attemptedFailureCount == 0)
    }

    @Test @MainActor func networkUnavailableIsSkippedOffline() async throws {
        let persistence = PersistenceController(inMemory: true)
        let feed = makeFeed(in: persistence.container.viewContext, id: "offline")
        let service = RSSAudioService(
            viewContext: persistence.container.viewContext,
            dataLoader: { _ in throw NetworkError.networkUnavailable }
        )

        let result = await service.refreshFeed(feed, now: Date(timeIntervalSince1970: 10))

        #expect(result.outcome == .skippedOffline)
        #expect(RSSRefreshBatchResult(results: [result]).attemptedFailureCount == 0)
    }

    @Test @MainActor func failedSaveRestoresFeedAndEpisodeState() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let oldDate = Date(timeIntervalSince1970: 100)
        let feed = makeFeed(in: context, id: "save-failure", lastFetchDate: oldDate)
        let episode = makeEpisode(in: context, feed: feed, id: "stable", date: oldDate)
        episode.isListened = true
        episode.listenedDate = oldDate
        episode.lastPosition = 0.4
        try context.save()

        let service = RSSAudioService(
            viewContext: context,
            dataLoader: { _ in Self.feedXML(url: "https://example.com/one.mp3", date: "Wed, 17 Jul 2024 12:05:00 GMT") },
            saveContext: { throw SaveError.denied }
        )
        let result = await service.refreshFeed(feed, now: Date(timeIntervalSince1970: 200))

        #expect({ if case .failed = result.outcome { return true }; return false }())
        #expect(feed.lastFetchDate == oldDate)
        #expect(episode.id == "stable")
        #expect(episode.isListened)
        #expect(episode.listenedDate == oldDate)
        #expect(episode.lastPosition == 0.4)
        #expect(!context.hasChanges)
    }

    @Test @MainActor func shiftedFallbackPublicationDateReusesSameEpisodeHistory() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let feed = makeFeed(in: context, id: "history")
        let service = RSSAudioService(
            viewContext: context,
            dataLoader: { _ in Self.feedXML(url: "HTTPS://Example.COM:443/hourly.mp3?b=2&a=1#old", date: "Wed, 17 Jul 2024 12:00:00 GMT") }
        )
        _ = await service.refreshFeed(feed, now: Date(timeIntervalSince1970: 100))
        let original = try #require(feed.episodes?.allObjects.first as? RSSEpisode)
        original.isListened = true
        original.listenedDate = Date(timeIntervalSince1970: 50)
        original.lastPosition = 0.4
        try context.save()
        let originalPubDate = original.pubDate

        let corrected = RSSAudioService(
            viewContext: context,
            dataLoader: { _ in Self.feedXML(url: "https://example.com/hourly.mp3?a=1&b=2", date: "Wed, 17 Jul 2024 12:05:00 GMT") }
        )
        _ = await corrected.refreshFeed(feed, now: Date(timeIntervalSince1970: 200))
        let reused = try #require(feed.episodes?.allObjects.first as? RSSEpisode)

        #expect(reused.objectID == original.objectID)
        #expect(reused.id == original.id)
        #expect(reused.isListened)
        #expect(reused.listenedDate == Date(timeIntervalSince1970: 50))
        #expect(reused.lastPosition == 0.4)
        #expect(reused.pubDate > originalPubDate)
    }

    @Test @MainActor func missingDefaultRowsAreAddedWithoutRemovingCustomRows() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        _ = makeFeed(in: context, id: "custom")
        _ = makeFeed(in: context, id: "npr-news-now")
        try context.save()

        let inserted = try RSSAudioService.insertMissingDefaultFeeds(in: context)
        let request: NSFetchRequest<RSSFeed> = RSSFeed.fetchRequest()
        let ids = Set(try context.fetch(request).map(\.id))

        #expect(inserted)
        #expect(ids.contains("custom"))
        #expect(ids.count == 10)
    }

    private enum SaveError: Error { case denied }

    @MainActor private func makeFeed(in context: NSManagedObjectContext, id: String, lastFetchDate: Date? = nil) -> RSSFeed {
        let feed = RSSFeed(context: context)
        feed.id = id
        feed.url = "https://example.com/feed.xml"
        feed.displayName = id
        feed.updateFrequency = "hourly"
        feed.isEnabled = true
        feed.createdDate = .now
        feed.lastFetchDate = lastFetchDate
        return feed
    }

    @MainActor private func makeEpisode(in context: NSManagedObjectContext, feed: RSSFeed, id: String, date: Date) -> RSSEpisode {
        let episode = RSSEpisode(context: context)
        episode.id = id
        episode.feedId = feed.id
        episode.title = "Original"
        episode.audioUrl = "https://example.com/one.mp3"
        episode.pubDate = date
        episode.feed = feed
        feed.addToEpisodes(episode)
        return episode
    }

    private static func feedXML(url: String, date: String) -> Data {
        Data("<rss><channel><item><title>Updated</title><pubDate>\(date)</pubDate><enclosure url=\"\(url)\" type=\"audio/mpeg\" /></item></channel></rss>".utf8)
    }
}
