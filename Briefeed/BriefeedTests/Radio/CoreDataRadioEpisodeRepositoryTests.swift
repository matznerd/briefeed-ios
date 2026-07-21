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
        try repository.saveProgress(key: RadioEpisodeKey(feedID: "feed", episodeID: "sibling"), seconds: .nan, duration: 0)

        #expect(target.lastPosition == 0.25)
        #expect(sibling.lastPosition == 0)
    }

    @Test @MainActor func candidateUsesCompositeKeyAndOriginalPlaybackURL() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let one = makeFeed(in: context, id: "one", enabled: true)
        let two = makeFeed(in: context, id: "two", enabled: true)
        _ = makeEpisode(in: context, feed: one, id: "same", audioURL: "HTTPS://Example.COM:443/one.mp3?b=2&a=1#fragment")
        _ = makeEpisode(in: context, feed: two, id: "same", audioURL: "https://example.com/two.mp3")
        try context.save()

        let fetched = try CoreDataRadioEpisodeRepository(context: context).candidate(for: RadioEpisodeKey(feedID: "one", episodeID: "same"))
        let candidate = try #require(fetched)

        #expect(candidate.originalPlaybackURL.absoluteString == "HTTPS://Example.COM:443/one.mp3?b=2&a=1#fragment")
        #expect(candidate.canonicalEnclosureURL == "https://example.com/one.mp3?a=1&b=2")
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

    @Test @MainActor func failedCompletionSaveRestoresCompletionFieldsWithoutRollingBackUnrelatedChanges() throws {
        enum SaveError: Error { case denied }
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let feed = makeFeed(in: context, id: "feed", enabled: true)
        let episode = makeEpisode(in: context, feed: feed, id: "episode")
        try context.save()
        feed.displayName = "Unsaved name"
        let repository = CoreDataRadioEpisodeRepository(context: context, saveContext: { throw SaveError.denied })

        #expect(throws: SaveError.denied) {
            try repository.markCompleted(key: RadioEpisodeKey(feedID: "feed", episodeID: "episode"), at: .now)
        }

        #expect(!episode.isListened)
        #expect(episode.listenedDate == nil)
        #expect(episode.lastPosition == 0)
        #expect(feed.displayName == "Unsaved name")
        #expect(context.hasChanges)
    }

    @Test @MainActor func restartingForReplayClearsCompletionAndProgress() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let feed = makeFeed(in: context, id: "feed", enabled: true)
        let episode = makeEpisode(in: context, feed: feed, id: "episode")
        episode.isListened = true
        episode.listenedDate = Date(timeIntervalSince1970: 42)
        episode.lastPosition = 1
        try context.save()

        let candidate = try CoreDataRadioEpisodeRepository(context: context).restartForReplay(
            key: RadioEpisodeKey(feedID: "feed", episodeID: "episode")
        )

        #expect(candidate?.isCompleted == false)
        #expect(candidate?.normalizedCoreDataProgress == 0)
        #expect(!episode.isListened)
        #expect(episode.listenedDate == nil)
        #expect(episode.lastPosition == 0)
    }

    @Test @MainActor func failedReplaySaveRestoresCompletionWithoutRollingBackUnrelatedChanges() throws {
        enum SaveError: Error { case denied }
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let feed = makeFeed(in: context, id: "feed", enabled: true)
        let episode = makeEpisode(in: context, feed: feed, id: "episode")
        let listenedDate = Date(timeIntervalSince1970: 42)
        episode.isListened = true
        episode.listenedDate = listenedDate
        episode.lastPosition = 1
        try context.save()
        feed.displayName = "Unsaved name"
        let repository = CoreDataRadioEpisodeRepository(context: context, saveContext: { throw SaveError.denied })

        #expect(throws: SaveError.denied) {
            try repository.restartForReplay(key: RadioEpisodeKey(feedID: "feed", episodeID: "episode"))
        }

        #expect(episode.isListened)
        #expect(episode.listenedDate == listenedDate)
        #expect(episode.lastPosition == 1)
        #expect(feed.displayName == "Unsaved name")
        #expect(context.hasChanges)
    }

    @Test @MainActor func progressCannotLowerAnAuthoritativelyCompletedRow() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let feed = makeFeed(in: context, id: "feed", enabled: true)
        let episode = makeEpisode(in: context, feed: feed, id: "episode")
        episode.isListened = true
        episode.listenedDate = .now
        episode.lastPosition = 1
        try context.save()

        try CoreDataRadioEpisodeRepository(context: context).saveProgress(
            key: RadioEpisodeKey(feedID: "feed", episodeID: "episode"),
            seconds: 20,
            duration: 100
        )

        #expect(episode.isListened)
        #expect(episode.lastPosition == 1)
    }

    @Test @MainActor func coordinatorCrashBeforeCoreDataCompletionKeepsEpisodeResumable() async throws {
        enum SaveError: LocalizedError { case denied; var errorDescription: String? { "core data denied" } }
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let feed = makeFeed(in: context, id: "feed", enabled: true)
        let episode = makeEpisode(in: context, feed: feed, id: "episode")
        try context.save()
        let key = RadioEpisodeKey(feedID: "feed", episodeID: "episode")
        let store = FakeRadioSessionStore(snapshot: persistedSession(key: key))
        let repository = CoreDataRadioEpisodeRepository(context: context, saveContext: { throw SaveError.denied })
        let coordinator = RadioSessionCoordinator(store: store, repository: repository, connectivityStatus: { .online })
        _ = await coordinator.restore(autoplayEnabled: false)

        #expect(coordinator.playbackCompleted(for: key, at: .now) == nil)
        #expect(!episode.isListened)
        #expect(coordinator.currentKey == key)
        #expect(coordinator.entries.contains { $0.key == key })

        let reconstructed = RadioSessionCoordinator(store: store, repository: repository, connectivityStatus: { .online })
        _ = await reconstructed.restore(autoplayEnabled: false)
        #expect(reconstructed.currentKey == key)
        #expect(reconstructed.entries.contains { $0.key == key })
    }

    @Test @MainActor func coordinatorCrashAfterCoreDataCompletionDropsEpisodeInProcess() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let feed = makeFeed(in: context, id: "feed", enabled: true)
        let episode = makeEpisode(in: context, feed: feed, id: "episode")
        try context.save()
        let key = RadioEpisodeKey(feedID: "feed", episodeID: "episode")
        let store = FakeRadioSessionStore(snapshot: persistedSession(key: key))
        let repository = CoreDataRadioEpisodeRepository(context: context)
        let coordinator = RadioSessionCoordinator(store: store, repository: repository, connectivityStatus: { .online })
        _ = await coordinator.restore(autoplayEnabled: false)
        store.saveNowError = NSError(domain: "snapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "snapshot denied"])

        #expect(coordinator.playbackCompleted(for: key, at: .now) == nil)
        #expect(episode.isListened)
        #expect(episode.lastPosition == 1)
        #expect(!coordinator.entries.contains { $0.key == key })
        #expect(coordinator.currentKey == nil)
        #expect(coordinator.retry() == nil)

        store.saveNowError = nil
        let reconstructed = RadioSessionCoordinator(store: store, repository: repository, connectivityStatus: { .online })
        _ = await reconstructed.restore(autoplayEnabled: false)
        #expect(reconstructed.currentKey == nil)
        #expect(!reconstructed.entries.contains { $0.key == key })
    }

    @MainActor private func persistedSession(key: RadioEpisodeKey) -> PersistedRadioSession {
        .init(
            schemaVersion: 1,
            entries: [.init(key: key, positionSeconds: 0, disposition: .pending, playbackFailureCount: 0, lastPlaybackError: nil)],
            currentKey: key,
            savedAt: .now
        )
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
