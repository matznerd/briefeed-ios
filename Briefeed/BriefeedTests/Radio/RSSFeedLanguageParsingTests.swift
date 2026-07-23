import CoreData
import Foundation
import Testing
@testable import Briefeed

@Suite("RSS feed language parsing")
struct RSSFeedLanguageParsingTests {
    @Test func rssChannelLanguageIsNormalizedAlongsideEpisodes() async throws {
        let parser = RSSParser()
        let parsed = try await parser.parseFeed(
            data: Self.rss(languageElement: "<language>en_US</language>"),
            feedId: "npr"
        )

        #expect(parsed.languageTag == "en-US")
        #expect(parsed.episodes.map(\.guid) == ["episode"])
    }

    @Test func atomFeedXMLLanguageIsNormalized() async throws {
        let data = Data("""
        <feed xmlns="http://www.w3.org/2005/Atom" xml:lang="fr_CA">
          <entry>
            <title>Latest</title>
            <id>episode</id>
            <published>2026-07-23T08:00:00Z</published>
            <enclosure url="https://example.com/latest.mp3" type="audio/mpeg" />
          </entry>
        </feed>
        """.utf8)

        let parsed = try await RSSParser().parseFeed(data: data, feedId: "radio")

        #expect(parsed.languageTag == "fr-CA")
    }

    @Test func invalidOrMissingLanguageSurfacesNoPublisherOverride() async throws {
        let invalid = try await RSSParser().parseFeed(
            data: Self.rss(languageElement: "<language>invalid_locale!</language>"),
            feedId: "invalid"
        )
        let missing = try await RSSParser().parseFeed(
            data: Self.rss(languageElement: ""),
            feedId: "missing"
        )

        #expect(invalid.languageTag == nil)
        #expect(missing.languageTag == nil)
    }

    @Test @MainActor func successfulRefreshPersistsLanguageBeforeReturning() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let feed = Self.makeFeed(in: context)
        let metadataStore = InMemoryRadioFeedSpeechMetadataStore()
        let service = RSSAudioService(
            viewContext: context,
            dataLoader: { _ in Self.rss(languageElement: "<language>de_DE</language>") },
            speechMetadataStore: metadataStore
        )

        let result = await service.refreshFeed(feed, now: .now)

        #expect({ if case .success = result.outcome { return true }; return false }())
        #expect(await metadataStore.metadata(for: feed.id) == .init(
            languageTag: "de-DE",
            source: .publisher
        ))
    }

    @Test @MainActor func missingPublisherLanguageStoresFallback() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let feed = Self.makeFeed(in: context)
        let metadataStore = InMemoryRadioFeedSpeechMetadataStore()
        let service = RSSAudioService(
            viewContext: context,
            dataLoader: { _ in Self.rss(languageElement: "") },
            speechMetadataStore: metadataStore
        )

        _ = await service.refreshFeed(feed, now: .now)

        #expect(await metadataStore.metadata(for: feed.id) == .init(
            languageTag: "en-US",
            source: .fallback
        ))
    }

    private static func rss(languageElement: String) -> Data {
        Data("""
        <rss><channel>
          \(languageElement)
          <item>
            <title>Latest</title>
            <guid>episode</guid>
            <pubDate>Thu, 23 Jul 2026 08:00:00 GMT</pubDate>
            <enclosure url="https://example.com/latest.mp3" type="audio/mpeg" />
          </item>
        </channel></rss>
        """.utf8)
    }

    @MainActor
    private static func makeFeed(in context: NSManagedObjectContext) -> RSSFeed {
        let feed = NSEntityDescription.insertNewObject(
            forEntityName: "RSSFeed",
            into: context
        ) as! RSSFeed
        feed.id = "feed"
        feed.url = "https://example.com/feed.xml"
        feed.displayName = "Feed"
        feed.updateFrequency = "hourly"
        feed.isEnabled = true
        feed.createdDate = .now
        return feed
    }
}
