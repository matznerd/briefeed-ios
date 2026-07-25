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
        let transcript = try makeTranscript(
            fingerprint: "prepared-fingerprint",
            duration: 60
        )
        let asset = makeAsset(
            candidate: candidate,
            fingerprint: transcript.assetFingerprint,
            duration: transcript.audioDurationSeconds,
            localURL: localURL
        )
        let assets = PlaybackTranscriptAssetProvider(
            cached: [candidate.key: asset]
        )
        let (player, transport) = await makePlayer(
            candidates: [candidate],
            current: candidate.key,
            assets: assets
        )

        await player.playRadio()
        await player.validateActiveRadioTranscript(
            RadioTranscriptPresentation(
                episodeKey: candidate.key,
                state: .ready(transcript)
            )
        )

        #expect(transport.loads.map(\.1) == [localURL])
        #expect(player.radioTranscriptPlaybackIsValidated)
    }

    @Test func aCompletedLoadRequestsFreshTranscriptValidation() async {
        let candidate = makeCandidate("validation-revision")
        let (player, _) = await makePlayer(
            candidates: [candidate],
            current: candidate.key,
            assets: PlaybackTranscriptAssetProvider()
        )
        let initialRevision = player.radioTranscriptValidationRevision

        await player.playRadio()

        #expect(
            player.radioTranscriptValidationRevision > initialRevision
        )
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
        #expect(!player.radioTranscriptPlaybackIsValidated)
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

    @Test func aReadyTranscriptPromotesActivePlaybackToItsExactLocalAudio() async throws {
        let candidate = makeCandidate("promoted")
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("promoted-\(UUID().uuidString).mp3")
        try Data([0]).write(to: localURL)
        defer { try? FileManager.default.removeItem(at: localURL) }

        let transcript = try makeTranscript(
            fingerprint: "promoted-fingerprint",
            duration: 60
        )
        let asset = makeAsset(
            candidate: candidate,
            fingerprint: transcript.assetFingerprint,
            duration: transcript.audioDurationSeconds,
            localURL: localURL
        )
        let assets = PlaybackTranscriptAssetProvider()
        let (player, transport) = await makePlayer(
            candidates: [candidate],
            current: candidate.key,
            assets: assets
        )
        await player.playRadio()
        let remotePlaybackID = try #require(transport.lastPlaybackID)
        player.audioStateChanged(
            id: remotePlaybackID,
            to: .playing,
            from: .loading
        )
        transport.currentTime = 23
        transport.duration = 60
        await assets.setCached(asset, for: candidate.key)

        await player.validateActiveRadioTranscript(
            RadioTranscriptPresentation(
                episodeKey: candidate.key,
                state: .ready(transcript)
            )
        )

        let localPlaybackID = try #require(transport.lastPlaybackID)
        #expect(localPlaybackID != remotePlaybackID)
        #expect(transport.loads.map(\.1) == [
            candidate.originalPlaybackURL,
            localURL
        ])
        player.audioItemReady(id: localPlaybackID, duration: 60)
        #expect(transport.seeks == [23])
        #expect(player.radioTranscriptPlaybackIsValidated)
    }

    @Test func resumingAPausedEpisodePromotesItsPreparedTranscriptAudio() async throws {
        let candidate = makeCandidate("resume-promoted")
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("resume-promoted-\(UUID().uuidString).mp3")
        try Data([0]).write(to: localURL)
        defer { try? FileManager.default.removeItem(at: localURL) }

        let transcript = try makeTranscript(
            fingerprint: "resume-promoted-fingerprint",
            duration: 60
        )
        let asset = makeAsset(
            candidate: candidate,
            fingerprint: transcript.assetFingerprint,
            duration: transcript.audioDurationSeconds,
            localURL: localURL
        )
        let assets = PlaybackTranscriptAssetProvider()
        let (player, transport) = await makePlayer(
            candidates: [candidate],
            current: candidate.key,
            assets: assets
        )
        await player.playRadio()
        let remotePlaybackID = try #require(transport.lastPlaybackID)
        player.audioStateChanged(
            id: remotePlaybackID,
            to: .playing,
            from: .loading
        )
        transport.currentTime = 19
        transport.duration = 60
        player.audioProgressUpdated(
            id: remotePlaybackID,
            progress: 19 / 60,
            currentTime: 19,
            duration: 60
        )
        player.pause()
        await assets.setCached(asset, for: candidate.key)

        await player.beginEffectiveCurrent()

        let localPlaybackID = try #require(transport.lastPlaybackID)
        #expect(localPlaybackID != remotePlaybackID)
        #expect(transport.loads.map(\.1) == [
            candidate.originalPlaybackURL,
            localURL
        ])
        player.audioItemReady(id: localPlaybackID, duration: 60)
        #expect(transport.seeks == [19])
    }

    @Test func aFailedPreparedAudioLoadRestoresTheOriginalStream() async throws {
        let candidate = makeCandidate("promotion-fallback")
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("promotion-fallback-\(UUID().uuidString).mp3")
        try Data([0]).write(to: localURL)
        defer { try? FileManager.default.removeItem(at: localURL) }

        let transcript = try makeTranscript(
            fingerprint: "promotion-fallback-fingerprint",
            duration: 60
        )
        let asset = makeAsset(
            candidate: candidate,
            fingerprint: transcript.assetFingerprint,
            duration: transcript.audioDurationSeconds,
            localURL: localURL
        )
        let assets = PlaybackTranscriptAssetProvider()
        let transport = SpyAudioTransport(failingURLs: [localURL])
        let (player, _) = await makePlayer(
            candidates: [candidate],
            current: candidate.key,
            assets: assets,
            transport: transport
        )
        await player.playRadio()
        let remotePlaybackID = try #require(transport.lastPlaybackID)
        player.audioStateChanged(
            id: remotePlaybackID,
            to: .playing,
            from: .loading
        )
        transport.currentTime = 27
        transport.duration = 60
        await assets.setCached(asset, for: candidate.key)

        await player.validateActiveRadioTranscript(
            RadioTranscriptPresentation(
                episodeKey: candidate.key,
                state: .ready(transcript)
            )
        )

        let fallbackPlaybackID = try #require(transport.lastPlaybackID)
        #expect(fallbackPlaybackID != remotePlaybackID)
        #expect(transport.loads.map(\.1) == [
            candidate.originalPlaybackURL,
            localURL,
            candidate.originalPlaybackURL
        ])
        player.audioItemReady(id: fallbackPlaybackID, duration: 60)
        #expect(transport.seeks == [27])
        #expect(!player.radioTranscriptPlaybackIsValidated)

        await player.validateActiveRadioTranscript(
            RadioTranscriptPresentation(
                episodeKey: candidate.key,
                state: .ready(transcript)
            )
        )
        #expect(transport.loads.count == 3)
    }

    @Test func aDurationMismatchDoesNotPromotePreparedAudio() async throws {
        let candidate = makeCandidate("promotion-duration-mismatch")
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "promotion-duration-mismatch-\(UUID().uuidString).mp3"
            )
        try Data([0]).write(to: localURL)
        defer { try? FileManager.default.removeItem(at: localURL) }

        let transcript = try makeTranscript(
            fingerprint: "promotion-duration-mismatch-fingerprint",
            duration: 60
        )
        let asset = makeAsset(
            candidate: candidate,
            fingerprint: transcript.assetFingerprint,
            duration: transcript.audioDurationSeconds,
            localURL: localURL
        )
        let assets = PlaybackTranscriptAssetProvider()
        let (player, transport) = await makePlayer(
            candidates: [candidate],
            current: candidate.key,
            assets: assets
        )
        await player.playRadio()
        let remotePlaybackID = try #require(transport.lastPlaybackID)
        player.audioStateChanged(
            id: remotePlaybackID,
            to: .playing,
            from: .loading
        )
        transport.currentTime = 12
        transport.duration = 54
        await assets.setCached(asset, for: candidate.key)

        await player.validateActiveRadioTranscript(
            RadioTranscriptPresentation(
                episodeKey: candidate.key,
                state: .ready(transcript)
            )
        )

        #expect(transport.loads.map(\.1) == [
            candidate.originalPlaybackURL
        ])
        #expect(!player.radioTranscriptPlaybackIsValidated)
    }

    @Test func theNextEpisodeUsesItsPreparedLocalAssetWhenItLoads() async {
        let first = makeCandidate("first", feedID: "first-feed")
        let second = makeCandidate("second", feedID: "second-feed")
        let localURL = URL(fileURLWithPath: "/tmp/second-prepared.mp3")
        let asset = makeAsset(
            candidate: second,
            fingerprint: "second-fingerprint",
            duration: 60,
            localURL: localURL
        )
        let assets = PlaybackTranscriptAssetProvider(
            cached: [second.key: asset]
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

    @Test func observedMatchingRemoteIdentityCanPublishSynchronizedText() async throws {
        let candidate = makeCandidate("validated")
        let transcript = try makeTranscript(
            fingerprint: "validated-fingerprint",
            duration: 60
        )
        let asset = makeAsset(
            candidate: candidate,
            fingerprint: transcript.assetFingerprint,
            duration: transcript.audioDurationSeconds
        )
        let assets = PlaybackTranscriptAssetProvider(
            cached: [:]
        )
        let (player, transport) = await makePlayer(
            candidates: [candidate],
            current: candidate.key,
            assets: assets
        )
        await player.playRadio()
        await assets.setCached(asset, for: candidate.key)
        let playbackID = try #require(transport.lastPlaybackID)
        player.audioItemReady(id: playbackID, duration: 60)
        transport.activeRemotePlaybackIdentity = RemotePlaybackAssetIdentity(
            playbackID: playbackID,
            requestedURL: candidate.originalPlaybackURL,
            finalURL: asset.finalURL,
            etag: asset.etag,
            lastModified: asset.lastModified,
            responseContentLength: asset.responseContentLength,
            duration: 60
        )

        await player.validateActiveRadioTranscript(
            RadioTranscriptPresentation(
                episodeKey: candidate.key,
                state: .ready(transcript)
            )
        )

        #expect(player.radioTranscriptPlaybackIsValidated)
    }

    @Test func preparationDownloadAloneCannotValidateTheActiveRemoteStream() async throws {
        let candidate = makeCandidate("unobserved")
        let transcript = try makeTranscript(
            fingerprint: "unobserved-fingerprint",
            duration: 60
        )
        let asset = makeAsset(
            candidate: candidate,
            fingerprint: transcript.assetFingerprint,
            duration: transcript.audioDurationSeconds
        )
        let assets = PlaybackTranscriptAssetProvider()
        let (player, transport) = await makePlayer(
            candidates: [candidate],
            current: candidate.key,
            assets: assets
        )
        await player.playRadio()
        await assets.setCached(asset, for: candidate.key)
        let playbackID = try #require(transport.lastPlaybackID)
        player.audioItemReady(id: playbackID, duration: 60)

        await player.validateActiveRadioTranscript(
            RadioTranscriptPresentation(
                episodeKey: candidate.key,
                state: .ready(transcript)
            )
        )

        #expect(!player.radioTranscriptPlaybackIsValidated)
    }

    @Test func observedRemoteIdentityWithoutValidatorsFailsClosed() async throws {
        let candidate = makeCandidate("no-validators")
        let transcript = try makeTranscript(
            fingerprint: "no-validators-fingerprint",
            duration: 60
        )
        let asset = makeAsset(
            candidate: candidate,
            fingerprint: transcript.assetFingerprint,
            duration: transcript.audioDurationSeconds
        )
        let assets = PlaybackTranscriptAssetProvider()
        let (player, transport) = await makePlayer(
            candidates: [candidate],
            current: candidate.key,
            assets: assets
        )
        await player.playRadio()
        await assets.setCached(asset, for: candidate.key)
        let playbackID = try #require(transport.lastPlaybackID)
        transport.activeRemotePlaybackIdentity = RemotePlaybackAssetIdentity(
            playbackID: playbackID,
            requestedURL: candidate.originalPlaybackURL,
            finalURL: asset.finalURL,
            etag: nil,
            lastModified: nil,
            responseContentLength: asset.responseContentLength,
            duration: 60
        )

        await player.validateActiveRadioTranscript(
            RadioTranscriptPresentation(
                episodeKey: candidate.key,
                state: .ready(transcript)
            )
        )

        #expect(!player.radioTranscriptPlaybackIsValidated)
    }

    @Test func mismatchedCurrentRemoteDurationKeepsTranscriptHidden() async throws {
        let candidate = makeCandidate("mismatch")
        let transcript = try makeTranscript(
            fingerprint: "mismatch-fingerprint",
            duration: 60
        )
        let asset = makeAsset(
            candidate: candidate,
            fingerprint: transcript.assetFingerprint,
            duration: transcript.audioDurationSeconds
        )
        let assets = PlaybackTranscriptAssetProvider(
            cached: [:]
        )
        let (player, transport) = await makePlayer(
            candidates: [candidate],
            current: candidate.key,
            assets: assets
        )
        await player.playRadio()
        await assets.setCached(asset, for: candidate.key)
        let playbackID = try #require(transport.lastPlaybackID)
        player.audioItemReady(id: playbackID, duration: 54)
        transport.activeRemotePlaybackIdentity = RemotePlaybackAssetIdentity(
            playbackID: playbackID,
            requestedURL: candidate.originalPlaybackURL,
            finalURL: asset.finalURL,
            etag: asset.etag,
            lastModified: asset.lastModified,
            responseContentLength: asset.responseContentLength,
            duration: 54
        )

        await player.validateActiveRadioTranscript(
            RadioTranscriptPresentation(
                episodeKey: candidate.key,
                state: .ready(transcript)
            )
        )

        #expect(!player.radioTranscriptPlaybackIsValidated)
    }

    @Test func aPreparedLocalAssetWithAnotherFingerprintStaysHidden() async throws {
        let candidate = makeCandidate("stale-local")
        let localURL = URL(fileURLWithPath: "/tmp/stale-local.mp3")
        let asset = makeAsset(
            candidate: candidate,
            fingerprint: "asset-a",
            duration: 60,
            localURL: localURL
        )
        let transcript = try makeTranscript(
            fingerprint: "asset-b",
            duration: 60
        )
        let assets = PlaybackTranscriptAssetProvider(
            cached: [candidate.key: asset]
        )
        let (player, _) = await makePlayer(
            candidates: [candidate],
            current: candidate.key,
            assets: assets
        )

        await player.playRadio()
        await player.validateActiveRadioTranscript(
            RadioTranscriptPresentation(
                episodeKey: candidate.key,
                state: .ready(transcript)
            )
        )

        #expect(!player.radioTranscriptPlaybackIsValidated)
    }

    @Test func anOldValidationCannotValidateTheNextEpisode() async throws {
        let first = makeCandidate("first", feedID: "first-feed")
        let second = makeCandidate("second", feedID: "second-feed")
        let transcript = try makeTranscript(
            fingerprint: "first-fingerprint",
            duration: 60
        )
        let asset = makeAsset(
            candidate: first,
            fingerprint: transcript.assetFingerprint,
            duration: 60
        )
        let assets = PlaybackTranscriptAssetProvider()
        let (player, transport) = await makePlayer(
            candidates: [first, second],
            current: first.key,
            assets: assets
        )
        await player.playRadio()
        let firstPlaybackID = try #require(transport.lastPlaybackID)
        player.audioItemReady(id: firstPlaybackID, duration: 60)
        transport.activeRemotePlaybackIdentity = RemotePlaybackAssetIdentity(
            playbackID: firstPlaybackID,
            requestedURL: first.originalPlaybackURL,
            finalURL: asset.finalURL,
            etag: asset.etag,
            lastModified: asset.lastModified,
            responseContentLength: asset.responseContentLength,
            duration: 60
        )
        await assets.setCached(asset, for: first.key)
        await assets.blockLookup(for: first.key)

        let staleValidation = Task {
            await player.validateActiveRadioTranscript(
                RadioTranscriptPresentation(
                    episodeKey: first.key,
                    state: .ready(transcript)
                )
            )
        }
        try await assets.waitUntilLookupStarts(for: first.key)

        await player.playNext()
        await assets.releaseLookup(for: first.key)
        await staleValidation.value

        #expect(player.activeMode == .radio)
        #expect(!player.radioTranscriptPlaybackIsValidated)
    }

    private func makePlayer(
        candidates: [RadioEpisodeCandidate],
        current: RadioEpisodeKey,
        assets: PlaybackTranscriptAssetProvider,
        transport: SpyAudioTransport? = nil
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
        let resolvedTransport = transport ?? SpyAudioTransport()
        let player = UnifiedAudioPlayer(
            audioPlayer: resolvedTransport,
            queueCoordinator: FakeBriefQueueCoordinator(),
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true)
                .container.viewContext,
            radioTranscriptAssetProvider: assets
        )
        return (player, resolvedTransport)
    }

    private func makeCandidate(
        _ id: String,
        feedID: String = "feed"
    ) -> RadioEpisodeCandidate {
        RadioEpisodeCandidate(
            key: .init(feedID: feedID, episodeID: id),
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

    private func makeTranscript(
        fingerprint: String,
        duration: TimeInterval
    ) throws -> TimedTranscript {
        try TimedTranscript(
            assetFingerprint: fingerprint,
            engineIdentifier: "test",
            engineVersion: "1",
            localeIdentifier: "en-US",
            recognizedText: "Latest news",
            audioDurationSeconds: duration,
            processingDurationSeconds: 0.1,
            units: [
                TimedTranscriptUnit(
                    text: "Latest news",
                    startSeconds: 0,
                    endSeconds: 1,
                    confidence: 1,
                    granularity: .phrase
                )
            ]
        )
    }

    private func makeAsset(
        candidate: RadioEpisodeCandidate,
        fingerprint: String,
        duration: TimeInterval,
        localURL: URL? = nil
    ) -> RadioTranscriptAudioAsset {
        RadioTranscriptAudioAsset(
            schemaVersion: RadioTranscriptAudioAsset.currentSchemaVersion,
            episodeKey: candidate.key,
            originalURL: candidate.originalPlaybackURL,
            finalURL: candidate.originalPlaybackURL,
            etag: "\"fixture-etag\"",
            lastModified: nil,
            responseContentLength: 1_024,
            audioDurationSeconds: duration,
            assetFingerprint: fingerprint,
            localFileURL: localURL ??
                URL(fileURLWithPath:
                    "/tmp/\(candidate.key.episodeID).mp3"),
            completedAt: .now,
            lastAccessedAt: .now,
            isTranscriptReady: true
        )
    }
}

private actor PlaybackTranscriptAssetProvider:
    RadioTranscriptAssetProviding
{
    private var prepared: [RadioEpisodeKey: URL]
    private var cached: [RadioEpisodeKey: RadioTranscriptAudioAsset]
    private var blockedLookups = Set<RadioEpisodeKey>()
    private var lookupStarts = Set<RadioEpisodeKey>()
    private var lookupWaiters: [
        RadioEpisodeKey: [CheckedContinuation<Void, Never>]
    ] = [:]

    init(
        prepared: [RadioEpisodeKey: URL] = [:],
        cached: [RadioEpisodeKey: RadioTranscriptAudioAsset] = [:]
    ) {
        self.prepared = prepared
        self.cached = cached
    }

    func setPrepared(_ url: URL, for key: RadioEpisodeKey) {
        prepared[key] = url
    }

    func setCached(
        _ asset: RadioTranscriptAudioAsset,
        for key: RadioEpisodeKey
    ) {
        cached[key] = asset
    }

    func blockLookup(for key: RadioEpisodeKey) {
        blockedLookups.insert(key)
    }

    func releaseLookup(for key: RadioEpisodeKey) {
        blockedLookups.remove(key)
        let continuations = lookupWaiters.removeValue(forKey: key) ?? []
        continuations.forEach { $0.resume() }
    }

    func waitUntilLookupStarts(for key: RadioEpisodeKey) async throws {
        for _ in 0..<200 {
            if lookupStarts.contains(key) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CocoaError(.coderReadCorrupt)
    }

    func acquire(
        _ request: RadioTranscriptAudioRequest
    ) async throws -> RadioTranscriptAudioAsset {
        throw CocoaError(.fileNoSuchFile)
    }

    func cachedAsset(
        for episodeKey: RadioEpisodeKey
    ) async throws -> RadioTranscriptAudioAsset? {
        lookupStarts.insert(episodeKey)
        if blockedLookups.contains(episodeKey) {
            await withCheckedContinuation { continuation in
                lookupWaiters[episodeKey, default: []].append(continuation)
            }
        }
        return cached[episodeKey]
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
