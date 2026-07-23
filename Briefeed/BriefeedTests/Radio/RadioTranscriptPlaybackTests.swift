import CoreData
import Foundation
import Testing
@testable import Briefeed

@MainActor
@Suite("Radio transcript exact playback")
struct RadioTranscriptPlaybackTests {
    @Test func aPreparedEpisodeLoadsItsExactFingerprintLocalURL() async throws {
        let candidate = makeCandidate("prepared")
        let localURL = URL(fileURLWithPath: "/tmp/prepared-fingerprint.mp3")
        let assets = PlaybackTranscriptAssetProvider(
            prepared: [candidate.key: localURL]
        )
        let (player, transport) = await makePlayer(
            candidates: [candidate],
            current: candidate.key,
            assets: assets
        )

        await player.playRadio()

        #expect(transport.loads.map(\.1) == [localURL])
    }

    @Test func anUnpreparedEpisodeStartsItsRemoteAudioImmediately() async {
        let candidate = makeCandidate("remote")
        let (player, transport) = await makePlayer(
            candidates: [candidate],
            current: candidate.key,
            assets: PlaybackTranscriptAssetProvider()
        )

        await player.playRadio()

        #expect(transport.loads.map(\.1) == [
            candidate.originalPlaybackURL
        ])
    }

    @Test func finishingPreparationNeverHotSwapsTheActiveRemotePlayer() async {
        let candidate = makeCandidate("active")
        let assets = PlaybackTranscriptAssetProvider()
        let (player, transport) = await makePlayer(
            candidates: [candidate],
            current: candidate.key,
            assets: assets
        )
        await player.playRadio()

        await assets.setPrepared(
            URL(fileURLWithPath: "/tmp/active-prepared.mp3"),
            for: candidate.key
        )
        await Task.yield()

        #expect(transport.loads.map(\.1) == [
            candidate.originalPlaybackURL
        ])
    }

    @Test func theNextEpisodeUsesItsPreparedLocalAssetWhenItLoads() async {
        let first = makeCandidate("first")
        let second = makeCandidate("second")
        let localURL = URL(fileURLWithPath: "/tmp/second-prepared.mp3")
        let assets = PlaybackTranscriptAssetProvider(
            prepared: [second.key: localURL]
        )
        let (player, transport) = await makePlayer(
            candidates: [first, second],
            current: first.key,
            assets: assets
        )
        await player.playRadio()

        await player.playNext()

        #expect(transport.loads.map(\.1) == [
            first.originalPlaybackURL,
            localURL
        ])
    }

    private func makePlayer(
        candidates: [RadioEpisodeCandidate],
        current: RadioEpisodeKey,
        assets: PlaybackTranscriptAssetProvider
    ) async -> (UnifiedAudioPlayer, SpyAudioTransport) {
        let radio = RadioSessionCoordinator(
            store: FakeRadioSessionStore(
                snapshot: PersistedRadioSession(
                    schemaVersion: PersistedRadioSession.schemaVersion,
                    entries: candidates.map {
                        RadioQueueEntry(
                            key: $0.key,
                            positionSeconds: 0,
                            disposition: .pending,
                            playbackFailureCount: 0,
                            lastPlaybackError: nil
                        )
                    },
                    currentKey: current,
                    savedAt: .now
                )
            ),
            repository: RecordingRadioRepository(candidates: candidates),
            connectivityStatus: { .online }
        )
        _ = await radio.restore(autoplayEnabled: false)
        let transport = SpyAudioTransport()
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: FakeBriefQueueCoordinator(),
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true)
                .container.viewContext,
            radioTranscriptAssetProvider: assets
        )
        return (player, transport)
    }

    private func makeCandidate(_ id: String) -> RadioEpisodeCandidate {
        RadioEpisodeCandidate(
            key: .init(feedID: "feed", episodeID: id),
            originalPlaybackURL:
                URL(string: "https://example.com/\(id).mp3")!,
            canonicalEnclosureURL:
                "https://example.com/\(id).mp3",
            title: id,
            sourceName: "Source",
            publicationDate: .now,
            durationSeconds: 60,
            normalizedCoreDataProgress: 0,
            isCompleted: false,
            sourcePriority: 0,
            sourceFrequency: .daily
        )
    }
}

private actor PlaybackTranscriptAssetProvider:
    RadioTranscriptAssetProviding
{
    private var prepared: [RadioEpisodeKey: URL]

    init(prepared: [RadioEpisodeKey: URL] = [:]) {
        self.prepared = prepared
    }

    func setPrepared(_ url: URL, for key: RadioEpisodeKey) {
        prepared[key] = url
    }

    func acquire(
        _ request: RadioTranscriptAudioRequest
    ) async throws -> RadioTranscriptAudioAsset {
        throw CocoaError(.fileNoSuchFile)
    }

    func cachedAsset(
        for episodeKey: RadioEpisodeKey
    ) async throws -> RadioTranscriptAudioAsset? {
        nil
    }

    func preparedPlaybackURL(for episodeKey: RadioEpisodeKey) async -> URL? {
        prepared[episodeKey]
    }

    func markTranscriptReady(_ asset: RadioTranscriptAudioAsset) async throws {}
    func pin(
        _ episodeKey: RadioEpisodeKey,
        reason: RadioTranscriptAssetPinReason
    ) {}
    func unpin(
        _ episodeKey: RadioEpisodeKey,
        reason: RadioTranscriptAssetPinReason
    ) {}
}
