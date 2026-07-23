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

    var audioPurpose: RadioTranscriptAudioPurpose {
        switch priority {
        case .current:
            .current
        case .nextOne, .nextTwo:
            .automaticLookahead
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
    private let now: @Sendable () -> Date
    private var worker: Task<Void, Never>?
    private var activeGeneration = 0
    private var eventContinuation: AsyncStream<RadioTranscriptPipelineEvent>
        .Continuation?

    init(
        assetProvider: any RadioTranscriptAssetProviding,
        store: RadioTranscriptStore,
        engineResolver: any RadioTranscriptEngineResolving =
            AppleRadioTranscriptEngineResolver(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.assetProvider = assetProvider
        self.store = store
        self.engineResolver = engineResolver
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
    ) {
        let previousWorker = worker
        previousWorker?.cancel()
        activeGeneration = generation

        var seen = Set<RadioEpisodeKey>()
        let automatic = interactive
            .sorted(by: Self.jobPrecedes)
            .filter { seen.insert($0.episodeKey).inserted }
            .prefix(3)
        let remainingBatch = batch
            .filter { seen.insert($0.episodeKey).inserted }
        let jobs = Array(automatic) + remainingBatch
        let batchKeys = Set(batch.map(\.episodeKey))

        worker = Task {
            await previousWorker?.value
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

    func cancelAll() {
        worker?.cancel()
        worker = nil
    }

    private func process(
        _ job: RadioTranscriptJob,
        generation: Int,
        tracksBatchEntry: Bool
    ) async {
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
                return
            }

            emit(.preparation(
                episodeKey: job.episodeKey,
                generation: generation,
                state: .transcribing
            ))
            let transcript = try await resolved.engine.transcribe(
                fileURL: asset.localFileURL,
                assetFingerprint: asset.assetFingerprint,
                locale: resolved.locale,
                assetPolicy: job.priority == .nextOne ||
                    job.priority == .nextTwo
                    ? .installedOnly
                    : .allowDownload
            )
            try ensureCurrent(generation)

            let actualKey = RadioTranscriptCacheKey(
                episodeKey: job.episodeKey,
                assetFingerprint: transcript.assetFingerprint,
                engineIdentifier: transcript.engineIdentifier,
                engineVersion: transcript.engineVersion,
                localeIdentifier: transcript.localeIdentifier
            )
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
            } catch {
                try? await store.removeTranscript(for: actualKey)
                throw error
            }
            try await assetProvider.markTranscriptReady(asset)
            if tracksBatchEntry {
                try await updateBatch(
                    job.episodeKey,
                    state: .transcriptReady(cacheKey: actualKey)
                )
            }
            emitReady(
                transcript,
                episodeKey: job.episodeKey,
                generation: generation
            )
        } catch is CancellationError {
            return
        } catch {
            guard generation == activeGeneration else { return }
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

    private func emit(_ event: RadioTranscriptPipelineEvent) {
        eventContinuation?.yield(event)
    }

    private static func jobPrecedes(
        _ lhs: RadioTranscriptJob,
        _ rhs: RadioTranscriptJob
    ) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        if lhs.episodeKey.feedID != rhs.episodeKey.feedID {
            return lhs.episodeKey.feedID < rhs.episodeKey.feedID
        }
        return lhs.episodeKey.episodeID < rhs.episodeKey.episodeID
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

    private static func errorMessage(_ error: Error) -> String {
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
                return "Long episodes are prepared only with Prepare All."
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
        return error.localizedDescription
    }
}
