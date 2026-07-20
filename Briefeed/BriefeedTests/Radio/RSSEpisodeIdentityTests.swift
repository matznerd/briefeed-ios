import Foundation
import Testing
@testable import Briefeed

@Suite("RSS episode identity")
struct RSSEpisodeIdentityTests {
    @Test func fallbackIdentityCanonicalizesWithoutChangingPlaybackURL() throws {
        let original = "HTTPS://Example.COM:443/show/one.mp3?b=2&a=1#frag"
        let date = Date(timeIntervalSince1970: 1_720_000_000.9)

        let id1 = try RSSEpisodeIdentity.episodeID(
            guid: "",
            enclosureURL: original,
            publicationDate: date
        )
        let id2 = try RSSEpisodeIdentity.episodeID(
            guid: nil,
            enclosureURL: "https://example.com/show/one.mp3?a=1&b=2",
            publicationDate: Date(timeIntervalSince1970: 1_720_000_000.1)
        )

        #expect(id1 == id2)
        #expect(original == "HTTPS://Example.COM:443/show/one.mp3?b=2&a=1#frag")
    }

    @Test func trimmedGuidWinsUnchanged() throws {
        let identity = try RSSEpisodeIdentity.episodeID(
            guid: "  provider-guid  ",
            enclosureURL: "not a URL",
            publicationDate: nil
        )

        #expect(identity == "provider-guid")
    }

    @Test func missingGuidAndPublicationDateIsRejected() {
        #expect(throws: RSSEpisodeIdentity.Error.missingStableIdentity) {
            try RSSEpisodeIdentity.episodeID(
                guid: nil,
                enclosureURL: "https://example.com/audio.mp3",
                publicationDate: nil
            )
        }
    }

    @Test func nonHTTPEnclosureIsRejectedForFallbackIdentity() {
        #expect(throws: RSSEpisodeIdentity.Error.invalidEnclosureURL) {
            try RSSEpisodeIdentity.episodeID(
                guid: nil,
                enclosureURL: "ftp://example.com/audio.mp3",
                publicationDate: Date(timeIntervalSince1970: 1)
            )
        }
    }

    @Test func parserRejectsItemsWithMalformedIdentityOrDate() async throws {
        let data = Data("""
        <rss><channel>
          <item><title>No date</title><enclosure url="https://example.com/no-date.mp3" type="audio/mpeg" /></item>
          <item><title>Bad URL</title><pubDate>Wed, 17 Jul 2024 12:00:00 GMT</pubDate><enclosure url="ftp://example.com/bad.mp3" type="audio/mpeg" /></item>
        </channel></rss>
        """.utf8)
        let parser = RSSParser()

        let episodes = try await parser.parse(data: data, feedId: "feed")

        #expect(episodes.isEmpty)
        #expect(parser.rejectedItemCount == 2)
    }

    @Test func parserKeepsGuidWhenEnclosureCannotBeCanonicalized() async throws {
        let data = Data("""
        <rss><channel><item><title>Guid episode</title><guid>  source-guid  </guid><pubDate>Wed, 17 Jul 2024 12:00:00 GMT</pubDate><enclosure url="not a URL" type="audio/mpeg" /></item></channel></rss>
        """.utf8)
        let parser = RSSParser()

        let episodes = try await parser.parse(data: data, feedId: "feed")

        #expect(episodes.count == 1)
        #expect(episodes.first?.guid == "source-guid")
        #expect(episodes.first?.audioUrl == "not a URL")
        #expect(episodes.first?.canonicalEnclosureURL == nil)
    }
}
