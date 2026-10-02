import CryptoKit
import Foundation
import Testing
@testable import Briefeed

@Suite("Radio ad pipeline integration")
struct RadioAdPipelineIntegrationTests {
    @Test func upcomingAudioIsReadyBeforeClassificationAndUsesOneRendition() async throws {
        let fixture = try AdPipelineFixture()
        defer { fixture.removeFiles() }
        let events = await fixture.pipeline.events()
        await fixture.pipeline.reconcile(
            interactive: [fixture.job("current", priority: .current),
                          fixture.job("nextTwo", priority: .nextTwo),
                          fixture.job("nextOne", priority: .nextOne)],
            batch: [], generation: 1
        )
        let received = try await collect(events, terminalCount: 3) {
            if case .adPreparation(_, _, .ready) = $0 { return true }
            return false
        }
        await fixture.pipeline.cancelAll()
        #expect(await fixture.assets.requestedKeys == ["nextOne", "nextTwo", "current"])
        #expect(await fixture.assets.requestedPurposes == [.automaticAdLookahead, .automaticAdLookahead, .current])
        #expect(await fixture.classifier.audioWasReadyBeforeEveryCall)
        #expect(await fixture.engine.callCount == 3)
        for name in ["nextOne", "nextTwo", "current"] {
            let transcriptReady = received.firstIndex {
                if case .preparation(let key, _, .ready) = $0 { return key.episodeID == name }
                return false
            }
            let adReady = received.firstIndex {
                if case .adPreparation(let key, _, .ready(let record)) = $0 {
                    return key.episodeID == name && record.key.assetFingerprint == fixture.asset(name).assetFingerprint
                }
                return false
            }
            #expect(transcriptReady != nil)
            #expect(adReady != nil)
            #expect((transcriptReady ?? Int.max) < (adReady ?? -1))
        }
    }

    @Test func cachedSpeechStillPreparesAdsWithoutAnotherASRPass() async throws {
        let fixture = try AdPipelineFixture()
        defer { fixture.removeFiles() }
        try await fixture.saveTranscript("nextOne")
        let events = await fixture.pipeline.events()
        await fixture.pipeline.reconcile(interactive: [fixture.job("nextOne", priority: .nextOne)],
                                         batch: [], generation: 1)
        _ = try await collect(events, terminalCount: 1) {
            if case .adPreparation(_, _, .ready) = $0 { return true }
            return false
        }
        await fixture.pipeline.cancelAll()
        #expect(await fixture.engine.callCount == 0)
        #expect(await fixture.classifier.callCount == 1)
        #expect(await fixture.classifier.audioWasReadyBeforeEveryCall)
    }

    @Test func cancellingSemanticWorkKeepsGoodTranscriptButNoAdMap() async throws {
        let fixture = try AdPipelineFixture(suspendClassification: true)
        defer { fixture.removeFiles() }
        let events = await fixture.pipeline.events()
        await fixture.pipeline.reconcile(interactive: [fixture.job("nextOne", priority: .nextOne)],
                                         batch: [], generation: 1)
        _ = try await collect(events, terminalCount: 1) {
            if case .adPreparation(_, _, .analyzing) = $0 { return true }
            return false
        }
        await fixture.pipeline.cancelAll()
        #expect(try await fixture.transcriptStore.loadTranscript(for: fixture.transcriptKey("nextOne")) != nil)
        #expect(try await fixture.adStore.load(for: fixture.adKey("nextOne")) == nil)
        #expect(await fixture.assets.readyKeys.contains(fixture.key("nextOne")))
    }

    @Test func semanticFailureDoesNotInvalidatePreparedPlayback() async throws {
        let fixture = try AdPipelineFixture(classifierAvailable: false)
        defer { fixture.removeFiles() }
        let events = await fixture.pipeline.events()
        await fixture.pipeline.reconcile(interactive: [fixture.job("nextOne", priority: .nextOne)],
                                         batch: [], generation: 1)
        _ = try await collect(events, terminalCount: 1) {
            if case .adPreparation(_, _, .unavailable) = $0 { return true }
            return false
        }
        await fixture.pipeline.cancelAll()
        #expect(try await fixture.transcriptStore.loadTranscript(for: fixture.transcriptKey("nextOne")) != nil)
        #expect(await fixture.assets.preparedPlaybackURL(for: fixture.key("nextOne")) == fixture.asset("nextOne").localFileURL)
    }

    private func collect(
        _ events: AsyncStream<RadioTranscriptPipelineEvent>, terminalCount: Int,
        terminal: @escaping @Sendable (RadioTranscriptPipelineEvent) -> Bool
    ) async throws -> [RadioTranscriptPipelineEvent] {
        try await withThrowingTaskGroup(of: [RadioTranscriptPipelineEvent].self) { group in
            group.addTask {
                var received: [RadioTranscriptPipelineEvent] = []
                var count = 0
                for await event in events {
                    received.append(event)
                    if terminal(event) { count += 1 }
                    if count == terminalCount { return received }
                }
                throw CancellationError()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw AdPipelineTestError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next() ?? []
        }
    }
}

private enum AdPipelineTestError: Error { case timeout }

private struct AdPipelineFixture: Sendable {
    let root: URL
    let assets: AdPipelineAssets
    let engine: AdPipelineSpeechEngine
    let classifier: AdPipelineClassifier
    let transcriptStore: RadioTranscriptStore
    let adStore: RadioAdStore
    let pipeline: RadioTranscriptPreparationPipeline

    init(suspendClassification: Bool = false, classifierAvailable: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("briefeed-ad-pipeline-\(UUID())")
        assets = AdPipelineAssets(root: root)
        engine = AdPipelineSpeechEngine()
        classifier = AdPipelineClassifier(assets: assets, suspend: suspendClassification, available: classifierAvailable)
        transcriptStore = try RadioTranscriptStore(rootDirectory: root.appendingPathComponent("transcripts"))
        adStore = try RadioAdStore(rootDirectory: root.appendingPathComponent("ads"))
        pipeline = RadioTranscriptPreparationPipeline(
            assetProvider: assets, store: transcriptStore, engineResolver: AdPipelineResolver(engine: engine),
            adService: RadioAdPreparationService(store: adStore, classifier: classifier, shouldDefer: { false })
        )
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
    func key(_ name: String) -> RadioEpisodeKey { .init(feedID: "synthetic", episodeID: name) }
    func asset(_ name: String) -> RadioTranscriptAudioAsset { AdPipelineAssets.asset(key: key(name), root: root) }
    func job(_ name: String, priority: RadioTranscriptJobPriority) -> RadioTranscriptJob {
        .init(episodeKey: key(name), remoteURL: asset(name).originalURL, expectedDurationSeconds: 3600,
              languageTag: "en-US", priority: priority, prepareAds: true)
    }
    func transcriptKey(_ name: String) -> RadioTranscriptCacheKey {
        .init(episodeKey: key(name), assetFingerprint: asset(name).assetFingerprint,
              engineIdentifier: "fixture", engineVersion: "1", localeIdentifier: "en-US")
    }
    func adKey(_ name: String) -> RadioAdCacheKey {
        .init(episodeKey: key(name), assetFingerprint: asset(name).assetFingerprint,
              transcriptEngine: "fixture", transcriptVersion: "1", locale: "en-US",
              detectorVersion: RadioAdPreparationService.detectorVersion, modelVersion: "fixture")
    }
    func saveTranscript(_ name: String) async throws {
        let transcript = try AdPipelineSpeechEngine.transcript(fingerprint: asset(name).assetFingerprint)
        let record = RadioTranscriptRecord(schemaVersion: RadioTranscriptRecord.currentSchemaVersion,
                                          key: transcriptKey(name), sourceURLHash: "synthetic",
                                          audioDurationSeconds: 3600, transcriptRelativePath: "artifacts/fixture.json",
                                          preparedAt: Date(), lastAccessedAt: Date())
        try await transcriptStore.save(transcript: transcript, record: record)
    }
}

private actor AdPipelineAssets: RadioTranscriptAssetProviding {
    let root: URL
    private(set) var requestedKeys: [String] = []
    private(set) var requestedPurposes: [RadioTranscriptAudioPurpose] = []
    private(set) var readyKeys: Set<RadioEpisodeKey> = []
    init(root: URL) { self.root = root }
    static func asset(key: RadioEpisodeKey, root: URL) -> RadioTranscriptAudioAsset {
        let remote = URL(string: "https://example.invalid/\(key.episodeID).mp3")!
        let hash = SHA256.hash(data: Data(key.episodeID.utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(schemaVersion: 1, episodeKey: key, originalURL: remote, finalURL: remote,
                     etag: nil, lastModified: nil, responseContentLength: 100, audioDurationSeconds: 3600,
                     assetFingerprint: hash, localFileURL: root.appendingPathComponent(key.episodeID),
                     completedAt: Date(timeIntervalSince1970: 1), lastAccessedAt: Date(timeIntervalSince1970: 1),
                     isTranscriptReady: false)
    }
    func acquire(_ request: RadioTranscriptAudioRequest) async throws -> RadioTranscriptAudioAsset {
        requestedKeys.append(request.episodeKey.episodeID)
        requestedPurposes.append(request.purpose)
        return Self.asset(key: request.episodeKey, root: root)
    }
    func cachedAsset(for key: RadioEpisodeKey) async throws -> RadioTranscriptAudioAsset? { Self.asset(key: key, root: root) }
    func preparedPlaybackURL(for key: RadioEpisodeKey) async -> URL? {
        readyKeys.contains(key) ? Self.asset(key: key, root: root).localFileURL : nil
    }
    func markTranscriptReady(_ asset: RadioTranscriptAudioAsset) async throws { readyKeys.insert(asset.episodeKey) }
    func pin(_ key: RadioEpisodeKey, reason: RadioTranscriptAssetPinReason) async { }
    func unpin(_ key: RadioEpisodeKey, reason: RadioTranscriptAssetPinReason) async { }
}

private actor AdPipelineSpeechEngine: TimedTranscriptEngine {
    private(set) var callCount = 0
    static func transcript(fingerprint: String) throws -> TimedTranscript {
        try .init(assetFingerprint: fingerprint, engineIdentifier: "fixture", engineVersion: "1", localeIdentifier: "en-US",
                  recognizedText: "This episode is sponsored by Acme.", audioDurationSeconds: 3600, processingDurationSeconds: 1,
                  units: [.init(text: "This episode is sponsored by Acme.", startSeconds: 0, endSeconds: 5,
                                confidence: 1, granularity: .phrase)])
    }
    func transcribe(fileURL: URL, assetFingerprint: String, locale: Locale,
                    assetPolicy: SpeechAssetPolicy) async throws -> TimedTranscript {
        callCount += 1
        return try Self.transcript(fingerprint: assetFingerprint)
    }
}

private struct AdPipelineResolver: RadioTranscriptEngineResolving {
    let engine: AdPipelineSpeechEngine
    func resolve(languageTag: String) async throws -> RadioResolvedTranscriptEngine {
        .init(engine: engine, locale: Locale(identifier: "en-US"), engineIdentifier: "fixture", engineVersion: "1")
    }
}

private actor AdPipelineClassifier: RadioAdClassifying {
    nonisolated let modelVersion = "fixture"
    nonisolated let isAvailable: Bool
    let assets: AdPipelineAssets
    let suspend: Bool
    private(set) var callCount = 0
    private(set) var audioWasReadyBeforeEveryCall = true
    init(assets: AdPipelineAssets, suspend: Bool, available: Bool) {
        self.assets = assets
        self.suspend = suspend
        isAvailable = available
    }
    func classify(_ window: AdTranscriptWindow) async throws -> [RadioAdSpan] {
        callCount += 1
        let readyCount = await assets.readyKeys.count
        audioWasReadyBeforeEveryCall = audioWasReadyBeforeEveryCall && readyCount == callCount
        if suspend { try await Task.sleep(for: .seconds(30)) }
        return [.init(kind: .sponsorship, startSeconds: 0, endSeconds: 5)]
    }
}
