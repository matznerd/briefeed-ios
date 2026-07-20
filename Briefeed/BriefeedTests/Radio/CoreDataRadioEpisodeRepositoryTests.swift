import CoreData
import Foundation
import Testing
@testable import Briefeed

@Suite("Core Data Radio episode repository")
struct CoreDataRadioEpisodeRepositoryTests {
    @Test @MainActor func candidatesRequireEnabledFeedsAndCanonicalEnclosures() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let enabled = makeFeed(in: context, id: "enabled", enabled: true)
        let disabled = makeFeed(in: context, id: "disabled", enabled: false)
        _ = makeEpisode(in: context, feed: enabled, id: "episode", audioURL: "HTTPS://Example.COM:443/a.mp3?b=2&a=1#fragment")
        _ = makeEpisode(in: context, feed: disabled, id: "hidden")
        try context.save()

        let candidates = try CoreDataRadioEpisodeRepository(context: context).candidates()

        #expect(candidates.count == 1)
        #expect(candidates[0].key == RadioEpisodeKey(feedID: "enabled", episodeID: "episode"))
        #expect(candidates[0].canonicalEnclosureURL == "https://example.com/a.mp3?a=1&b=2")
    }

    @Test @MainActor func progressUsesFinitePositiveDurationAndExactKey() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let feed = makeFeed(in: context, id: "feed", enabled: true)
        let target = makeEpisode(in: context, feed: feed, id: "target")
        let sibling = makeEpisode(in: context, feed: feed, id: "sibling")
        try context.save()
        let repository = CoreDataRadioEpisodeRepository(context: context)

        try repository.saveProgress(key: RadioEpisodeKey(feedID: "feed", episodeID: "target"), seconds: 30, duration: 120)
        try repository.saveProgress(key: RadioEpisodeKey(feedID: "feed", episodeID: "sibling"), seconds: 50, duration: .infinity)

        #expect(target.lastPosition == 0.25)
        #expect(sibling.lastPosition == 0)
    }

    @Test @MainActor func completionSetsAllFieldsAndSavesAtomically() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let feed = makeFeed(in: context, id: "feed", enabled: true)
        let episode = makeEpisode(in: context, feed: feed, id: "episode")
        try context.save()
        let date = Date(timeIntervalSince1970: 42)

        try CoreDataRadioEpisodeRepository(context: context).markCompleted(key: RadioEpisodeKey(feedID: "feed", episodeID: "episode"), at: date)
        context.refresh(episode, mergeChanges: false)

        #expect(episode.isListened)
        #expect(episode.listenedDate == date)
        #expect(episode.lastPosition == 1)
    }

    @Test @MainActor func failedCompletionSaveRollsBackAllFields() throws {
        enum SaveError: Error { case denied }
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let feed = makeFeed(in: context, id: "feed", enabled: true)
        let episode = makeEpisode(in: context, feed: feed, id: "episode")
        try context.save()
        let repository = CoreDataRadioEpisodeRepository(context: context, saveContext: { throw SaveError.denied })

        #expect(throws: SaveError.denied) {
            try repository.markCompleted(key: RadioEpisodeKey(feedID: "feed", episodeID: "episode"), at: .now)
        }

        #expect(!episode.isListened)
        #expect(episode.listenedDate == nil)
        #expect(episode.lastPosition == 0)
        #expect(!context.hasChanges)
    }

    @MainActor private func makeFeed(in context: NSManagedObjectContext, id: String, enabled: Bool) -> RSSFeed {
        let feed = RSSFeed(context: context)
        feed.id = id
        feed.url = "https://example.com/\(id).xml"
        feed.displayName = id
        feed.updateFrequency = "hourly"
        feed.priority = 1
        feed.isEnabled = enabled
        feed.createdDate = .now
        return feed
    }

    @MainActor private func makeEpisode(in context: NSManagedObjectContext, feed: RSSFeed, id: String, audioURL: String = "https://example.com/\(UUID().uuidString).mp3") -> RSSEpisode {
        let episode = RSSEpisode(context: context)
        episode.id = id
        episode.feedId = feed.id
        episode.title = id
        episode.audioUrl = audioURL
        episode.pubDate = .now
        episode.duration = 120
        episode.feed = feed
        feed.addToEpisodes(episode)
        return episode
    }
}
