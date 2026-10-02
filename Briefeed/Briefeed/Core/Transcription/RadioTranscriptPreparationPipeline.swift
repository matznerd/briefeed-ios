import CryptoKit
import Foundation
import Speech

enum RadioTranscriptJobPriority: Int, Codable, Comparable, Sendable {
    case current = 0
    case nextOne = 1
    case nextTwo = 2
    case batch = 3

    static func < (
        lhs: RadioTranscriptJobPriority,
        rhs: RadioTranscriptJobPriority
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct RadioTranscriptJob: Equatable, Sendable {
    let episodeKey: RadioEpisodeKey
    let remoteURL: URL
    let expectedDurationSeconds: TimeInterval?
    let languageTag: String
    let priority: RadioTranscriptJobPriority
    let prepareAds: Bool

    init(episodeKey: RadioEpisodeKey, remoteURL: URL, expectedDurationSeconds: TimeInterval?,
         languageTag: String, priority: RadioTranscriptJobPriority, prepareAds: Bool = false) {
        self.episodeKey = episodeKey
        self.remoteURL = remoteURL
        self.expectedDurationSeconds = expectedDurationSeconds
        self.languageTag = languageTag
        self.priority = priority
        self.prepareAds = prepareAds
    }

    var executionRank: Int {
        guard prepareAds else { return priority.rawValue }
        return switch priority {
        case .nextOne: 0
        case .nextTwo: 1
        case .current: 2
        case .batch: 3
        }
    }

    var audioPurpose: RadioTranscriptAudioPurpose {
        switch priority {
        case .current:
            .current
        case .nextOne, .nextTwo:
            prepareAds ? .automaticAdLookahead : .automaticLookahead
        case .batch:
            .explicitBatch
        }
    }
}

struct RadioResolvedTranscriptEngine: Sendable {
    let engine: any TimedTranscriptEngine
    let locale: Locale
    let engineIdentifier: String
    let engineVersion: String
}

protocol RadioTranscriptEngineResolving: Sendable {
    func resolve(
        languageTag: String
    ) async throws -> RadioResolvedTranscriptEngine
}

struct AppleRadioTranscriptEngineResolver: RadioTranscriptEngineResolving {
    func resolve(
        languageTag: String
    ) async throws -> RadioResolvedTranscriptEngine {
        guard #available(iOS 26.0, *) else {
            throw TimedTranscriptEngineError.unsupportedOS
        }
        guard SpeechTranscriber.isAvailable else {
            throw TimedTranscriptEngineError.engineUnavailable
        }

        let requested = Locale(
            identifier: RadioFeedSpeechMetadata.normalizedLanguageTag(
                languageTag
            ) ?? RadioFeedSpeechMetadata.fallback.languageTag
        )
        guard let supported = await SpeechTranscriber.supportedLocale(
            equivalentTo: requested
        ) else {
            throw TimedTranscriptEngineError.unsupportedLocale(
                requested.identifier
            )
        }
        return RadioResolvedTranscriptEngine(
            engine: AppleSpeechAnalyzerEngine(),
            locale: supported,
            engineIdentifier: "apple-speech-analyzer",
            engineVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }
}

enum RadioTranscriptPipelineEvent: Equatable, Sendable {
    case adPreparation(episodeKey: RadioEpisodeKey, generation: Int, state: RadioAdPreparationState)
    case preparation(
        episodeKey: RadioEpisodeKey,
        generation: Int,
        state: RadioTranscriptPreparationState
    )
    case batchUpdated(RadioTranscriptBatchManifest)
}

protocol RadioTranscriptPipelineScheduling: Sendable {
    func events() async -> AsyncStream<RadioTranscriptPipelineEvent>
    func reconcile(
        interactive: [RadioTranscriptJob],
        batch: [RadioTranscriptJob],
        generation: Int
    ) async
    func cancelAll() async
}

actor RadioTranscriptPreparationPipeline: RadioTranscriptPipelineScheduling {
    private let assetProvider: any RadioTranscriptAssetProviding
    private let store: RadioTranscriptStore
    private let engineResolver: any RadioTranscriptEngineResolving
    private let adService: RadioAdPreparationService?
    private let now: @Sendable () -> Date
    private var worker: Task<Void, Never>?
    private var activeGeneration = 0
    private var latestCheckpoints:
        [RadioTranscriptCacheKey: TimedTranscriptProgress] = [:]
    private var persistedCheckpointCoverage:
        [RadioTranscriptCacheKey: TimeInterval] = [:]
    private var eventContinuation: AsyncStream<RadioTranscriptPipelineEvent>
        .Continuation?

    init(
        assetProvider: any RadioTranscriptAssetProviding,
        store: RadioTranscriptStore,
        engineResolver: any RadioTranscriptEngineResolving =
            AppleRadioTranscriptEngineResolver(),
        adService: RadioAdPreparationService? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.assetProvider = assetProvider
        self.store = store
        self.engineResolver = engineResolver
        self.adService = adService
        self.now = now
    }

    deinit {
        worker?.cancel()
        eventContinuation?.finish()
    }

    func events() -> AsyncStream<RadioTranscriptPipelineEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(100)) { continuation in
            eventContinuation?.finish()
            eventContinuation = continuation
        }
    }

    func reconcile(
        interactive: [RadioTranscriptJob],
        batch: [RadioTranscriptJob],
        generation: Int
    ) async {
        let previousWorker = worker
        previousWorker?.cancel()
        worker = nil
        await previousWorker?.value
        await flushCheckpoints()
        activeGeneration = generation

        var seen = Set<RadioEpisodeKey>()
        let automatic = interactive
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.executionRank != rhs.element.executionRank {
                    return lhs.element.executionRank < rhs.element.executionRank
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
            .filter { seen.insert($0.episodeKey).inserted }
            .prefix(3)
        let remainingBatch = batch
            .filter { seen.insert($0.episodeKey).inserted }
        let jobs = Array(automatic) + remainingBatch
        let batchKeys = Set(batch.map(\.episodeKey))

        worker = Task {
            for job in jobs {
                guard !Task.isCancelled,
                      generation == self.activeGeneration else {
                    return
                }
                await self.process(
                    job,
                    generation: generation,
                    tracksBatchEntry: batchKeys.contains(job.episodeKey)
                )
            }
        }
    }

    func cancelAll() async {
        let previousWorker = worker
        previousWorker?.cancel()
        worker = nil
        await previousWorker?.value
        await flushCheckpoints()
    }

    private func process(
        _ job: RadioTranscriptJob,
        generation: Int,
        tracksBatchEntry: Bool
    ) async {
        if job.prepareAds {
            emit(.adPreparation(episodeKey: job.episodeKey, generation: generation, state: .queued))
        }
        emit(.preparation(
            episodeKey: job.episodeKey,
            generation: generation,
            state: .downloading(progress: nil)
        ))

        do {
            let asset = try await assetProvider.acquire(
                RadioTranscriptAudioRequest(
                    episodeKey: job.episodeKey,
                    remoteURL: job.remoteURL,
                    expectedDurationSeconds: job.expectedDurationSeconds,
                    purpose: job.audioPurpose
                )
            )
            try ensureCurrent(generation)

            if tracksBatchEntry {
                try await updateBatch(
                    job.episodeKey,
                    state: .audioReady(
                        assetFingerprint: asset.assetFingerprint
                    )
                )
            }

            let resolved = try await engineResolver.resolve(
                languageTag: job.languageTag
            )
            try ensureCurrent(generation)

            let expectedKey = RadioTranscriptCacheKey(
                episodeKey: job.episodeKey,
                assetFingerprint: asset.assetFingerprint,
                engineIdentifier: resolved.engineIdentifier,
                engineVersion: resolved.engineVersion,
                localeIdentifier: resolved.locale.identifier
            )
            if let cached = try await store.loadTranscript(for: expectedKey) {
                try await assetProvider.markTranscriptReady(asset)
                if tracksBatchEntry {
                    try await updateBatch(
                        job.episodeKey,
                        state: .transcriptReady(cacheKey: expectedKey)
                    )
                }
                emitReady(
                    cached,
                    episodeKey: job.episodeKey,
                    generation: generation
                )
                await prepareAds(for: job, transcript: cached, generation: generation)
                return
            }

            emit(.preparation(
                episodeKey: job.episodeKey,
                generation: generation,
                state: .transcribing
            ))
            if let checkpoint = try await store.loadCheckpoint(
                for: expectedKey
            ) {
                latestCheckpoints[expectedKey] = checkpoint
                persistedCheckpointCoverage[expectedKey] =
                    checkpoint.finalizedThroughSeconds
                emitProgress(
                    checkpoint,
                    episodeKey: job.episodeKey,
                    generation: generation
                )
            }
            let transcript = try await resolved.engine.transcribe(
                fileURL: asset.localFileURL,
                assetFingerprint: asset.assetFingerprint,
                locale: resolved.locale,
                assetPolicy: job.priority == .nextOne ||
                    job.priority == .nextTwo
                    ? .installedOnly
                    : .allowDownload,
                onProgress: { [weak self] progress in
                    guard let self else { return }
                    await self.acceptProgress(
                        progress,
                        cacheKey: expectedKey,
                        episodeKey: job.episodeKey,
                        generation: generation
                    )
                }
            )
            try ensureCurrent(generation)

            let actualKey = RadioTranscriptCacheKey(
                episodeKey: job.episodeKey,
                assetFingerprint: transcript.assetFingerprint,
                engineIdentifier: transcript.engineIdentifier,
                engineVersion: transcript.engineVersion,
                localeIdentifier: transcript.localeIdentifier
            )
            guard actualKey == expectedKey else {
                throw RadioTranscriptStore.StoreError.invalidTranscriptIdentity
            }
            let preparedAt = now()
            let record = RadioTranscriptRecord(
                schemaVersion: RadioTranscriptRecord.currentSchemaVersion,
                key: actualKey,
                sourceURLHash: Self.hash(url: job.remoteURL),
                audioDurationSeconds: transcript.audioDurationSeconds,
                transcriptRelativePath:
                    "artifacts/\(UUID().uuidString).json",
                preparedAt: preparedAt,
                lastAccessedAt: preparedAt
            )

            try await store.save(transcript: transcript, record: record)
            do {
                try ensureCurrent(generation)
                try await assetProvider.markTranscriptReady(asset)
                try ensureCurrent(generation)
                if tracksBatchEntry {
                    try await updateBatch(
                        job.episodeKey,
                        state: .transcriptReady(cacheKey: actualKey)
                    )
                    try ensureCurrent(generation)
                }
                try? await store.removeCheckpoint(for: actualKey)
                latestCheckpoints.removeValue(forKey: actualKey)
                persistedCheckpointCoverage.removeValue(forKey: actualKey)
                emitReady(
                    transcript,
                    episodeKey: job.episodeKey,
                    generation: generation
                )
                await prepareAds(for: job, transcript: transcript, generation: generation)
            } catch {
                try? await store.removeTranscript(for: actualKey)
                throw error
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == activeGeneration else { return }
            if job.prepareAds {
                emit(.adPreparation(episodeKey: job.episodeKey, generation: generation,
                                    state: .unavailable(Self.errorMessage(error))))
            }
            if tracksBatchEntry {
                try? await updateBatch(
                    job.episodeKey,
                    state: .failed(message: Self.errorMessage(error))
                )
            }
            emit(.preparation(
                episodeKey: job.episodeKey,
                generation: generation,
                state: Self.preparationState(for: error)
            ))
        }
    }

    private func prepareAds(for job: RadioTranscriptJob, transcript: TimedTranscript, generation: Int) async {
        guard job.prepareAds, generation == activeGeneration, !Task.isCancelled else { return }
        guard let adService else {
            emit(.adPreparation(episodeKey: job.episodeKey, generation: generation,
                                state: .unavailable("Ad preparation unavailable")))
            return
        }
        do {
            let record = try await adService.prepare(transcript: transcript, episodeKey: job.episodeKey) { [weak self] state in
                await self?.emitAdProgress(state, for: job.episodeKey, generation: generation)
            }
            try ensureCurrent(generation)
            emit(.adPreparation(episodeKey: job.episodeKey, generation: generation, state: .ready(record)))
        } catch is CancellationError { }
        catch {
            guard generation == activeGeneration, !Task.isCancelled else { return }
            let state: RadioAdPreparationState = if error as? RadioAdPreparationError == .resourceDeferred {
                .deferred
            } else {
                .unavailable("On-device ad analysis unavailable")
            }
            emit(.adPreparation(episodeKey: job.episodeKey, generation: generation, state: state))
        }
    }

    private func emitAdProgress(_ state: RadioAdPreparationState, for key: RadioEpisodeKey, generation: Int) {
        guard generation == activeGeneration, !Task.isCancelled else { return }
        emit(.adPreparation(episodeKey: key, generation: generation, state: state))
    }

    private func updateBatch(
        _ episodeKey: RadioEpisodeKey,
        state: RadioTranscriptBatchEntryState
    ) async throws {
        if let manifest = try await store.updateBatchEntry(
            for: episodeKey,
            state: state,
            updatedAt: now()
        ) {
            emit(.batchUpdated(manifest))
        }
    }

    private func ensureCurrent(_ generation: Int) throws {
        try Task.checkCancellation()
        guard generation == activeGeneration else {
            throw CancellationError()
        }
    }

    private func emitReady(
        _ transcript: TimedTranscript,
        episodeKey: RadioEpisodeKey,
        generation: Int
    ) {
        emit(.preparation(
            episodeKey: episodeKey,
            generation: generation,
            state: .ready(transcript)
        ))
    }

    private func emitProgress(
        _ progress: TimedTranscriptProgress,
        episodeKey: RadioEpisodeKey,
        generation: Int
    ) {
        guard !Task.isCancelled,
              generation == activeGeneration else {
            return
        }
        emit(.preparation(
            episodeKey: episodeKey,
            generation: generation,
            state: .partial(progress)
        ))
    }

    private func acceptProgress(
        _ progress: TimedTranscriptProgress,
        cacheKey: RadioTranscriptCacheKey,
        episodeKey: RadioEpisodeKey,
        generation: Int
    ) async {
        guard !Task.isCancelled,
              generation == activeGeneration,
              progress.transcript.assetFingerprint ==
                cacheKey.assetFingerprint,
              progress.transcript.engineIdentifier ==
                cacheKey.engineIdentifier,
              progress.transcript.engineVersion == cacheKey.engineVersion,
              progress.transcript.localeIdentifier ==
                cacheKey.localeIdentifier else {
            return
        }
        if let latest = latestCheckpoints[cacheKey],
           progress.finalizedThroughSeconds <=
            latest.finalizedThroughSeconds {
            return
        }
        latestCheckpoints[cacheKey] = progress
        let persisted = persistedCheckpointCoverage[cacheKey]
        if persisted == nil ||
            progress.finalizedThroughSeconds - (persisted ?? 0) >= 15 {
            do {
                try await store.saveCheckpoint(progress, for: cacheKey)
                persistedCheckpointCoverage[cacheKey] =
                    progress.finalizedThroughSeconds
            } catch {
                // A transient checkpoint failure must not stop transcription.
            }
        }
        emitProgress(
            progress,
            episodeKey: episodeKey,
            generation: generation
        )
    }

    private func flushCheckpoints() async {
        for (key, progress) in latestCheckpoints {
            do {
                try await store.saveCheckpoint(progress, for: key)
                persistedCheckpointCoverage[key] =
                    progress.finalizedThroughSeconds
            } catch {
                // The worker can safely reanalyze if a flush cannot commit.
            }
        }
    }

    private func emit(_ event: RadioTranscriptPipelineEvent) {
        eventContinuation?.yield(event)
    }

    private static func hash(url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func preparationState(
        for error: Error
    ) -> RadioTranscriptPreparationState {
        guard let engineError = error as? TimedTranscriptEngineError else {
            return .failed(message: errorMessage(error), canRetry: true)
        }
        switch engineError {
        case .unsupportedOS:
            return .unavailableOS
        case .engineUnavailable:
            return .unsupportedDevice
        case .unsupportedLocale(let identifier):
            return .unsupportedLocale(identifier)
        case .assetRequired:
            return .assetRequired
        case .emptyTranscript, .invalidAudio:
            return .failed(message: errorMessage(error), canRetry: true)
        }
    }

    static func errorMessage(_ error: Error) -> String {
        if let engineError = error as? TimedTranscriptEngineError {
            switch engineError {
            case .unsupportedOS:
                return "Transcripts require iOS 26 or later."
            case .engineUnavailable:
                return "On-device speech recognition is unavailable."
            case .unsupportedLocale(let identifier):
                return "Speech recognition does not support \(identifier)."
            case .assetRequired(let identifier):
                return "The \(identifier) speech model is not installed."
            case .emptyTranscript:
                return "No speech was recognized in this episode."
            case .invalidAudio:
                return "This episode audio could not be analyzed."
            }
        }
        if let assetError = error as? RadioTranscriptAssetService.AssetError {
            switch assetError {
            case .automaticDurationLimit:
                return "Automatic preparation duration limit reached."
            case .automaticByteLimit:
                return "Audio exceeds the preparation download size limit."
            case .unsupportedStreamingManifest:
                return "Streaming playlists cannot be prepared as exact audio files."
            case .invalidAudioDuration:
                return "The episode duration could not be read."
            case .missingDownloadedFile:
                return "The downloaded episode audio is missing."
            case .storagePressure:
                return "More device storage is needed to prepare transcripts."
            case .unsupportedIndexSchema:
                return "The transcript audio cache needs to be rebuilt."
            }
        }
        let networkError = error as NSError
        if networkError.domain == NSURLErrorDomain,
           networkError.code ==
            NSURLErrorAppTransportSecurityRequiresSecureConnection {
            return "This source's audio could not be downloaded securely."
        }
        return error.localizedDescription
    }
}
