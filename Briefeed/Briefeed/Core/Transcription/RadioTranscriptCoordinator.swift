import Combine
import CryptoKit
import Foundation
import Speech

struct RadioTranscriptPresentation: Equatable, Sendable {
    let episodeKey: RadioEpisodeKey?
    let state: RadioTranscriptPreparationState

    static let idle = RadioTranscriptPresentation(
        episodeKey: nil,
        state: .deferred
    )

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    var transcript: TimedTranscript? {
        guard case .ready(let transcript) = state else { return nil }
        return transcript
    }
}

enum RadioTranscriptBatchState: Equatable, Sendable {
    case idle
    case preparing
    case completed
    case stopped
}

enum RadioTranscriptBackgroundContinuation: Equatable, Sendable {
    case none
    case accepted
    case unavailableOS
    case rejected(message: String)
}

struct RadioTranscriptBatchPresentation: Equatable, Sendable {
    let state: RadioTranscriptBatchState
    let completedCount: Int
    let totalCount: Int
    let backgroundContinuation: RadioTranscriptBackgroundContinuation
    let episodeKeys: [RadioEpisodeKey]

    init(
        state: RadioTranscriptBatchState,
        completedCount: Int,
        totalCount: Int,
        backgroundContinuation: RadioTranscriptBackgroundContinuation,
        episodeKeys: [RadioEpisodeKey] = []
    ) {
        self.state = state
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.backgroundContinuation = backgroundContinuation
        self.episodeKeys = episodeKeys
    }

    static let idle = RadioTranscriptBatchPresentation(
        state: .idle,
        completedCount: 0,
        totalCount: 0,
        backgroundContinuation: .none
    )
}

@MainActor
protocol RadioTranscriptCoordinating: AnyObject {
    var presentation: RadioTranscriptPresentation { get }
    var batchPresentation: RadioTranscriptBatchPresentation { get }
    var isPreparationAvailable: Bool { get }
    var presentationPublisher:
        AnyPublisher<RadioTranscriptPresentation, Never> { get }
    var batchPresentationPublisher:
        AnyPublisher<RadioTranscriptBatchPresentation, Never> { get }

    func updateCurrent(
        _ current: RadioEpisodeCandidate?,
        next: [RadioEpisodeCandidate]
    )
    func updateVisibleSnapshot(_ candidates: [RadioEpisodeCandidate])
    func prepareAll()
    func retryCurrent()
    func stopPrepareAll()
    func handleActive()
    func handleBackground()
    func handleMemoryWarning()
    func preparedPlaybackURL(
        for episodeKey: RadioEpisodeKey
    ) async -> URL?
}

@MainActor
final class RadioTranscriptCoordinator:
    ObservableObject,
    RadioTranscriptCoordinating
{
    @Published private(set) var presentation =
        RadioTranscriptPresentation.idle
    @Published private(set) var batchPresentation =
        RadioTranscriptBatchPresentation.idle

    var presentationPublisher:
        AnyPublisher<RadioTranscriptPresentation, Never> {
        $presentation.eraseToAnyPublisher()
    }

    var batchPresentationPublisher:
        AnyPublisher<RadioTranscriptBatchPresentation, Never> {
        $batchPresentation.eraseToAnyPublisher()
    }

    var isPreparationAvailable: Bool {
        if #available(iOS 26.0, *) {
            return SpeechTranscriber.isAvailable
        }
        return false
    }

    private let pipeline: any RadioTranscriptPipelineScheduling
    private let store: RadioTranscriptStore
    private let assetProvider: any RadioTranscriptAssetProviding
    private let metadataStore: any RadioFeedSpeechMetadataStoring
    private let backgroundDriver: any RadioTranscriptBackgroundDriving
    private var eventTask: Task<Void, Never>?
    private var startupReconciliationTask: Task<Void, Never>?
    private var reconciliationTask: Task<Void, Never>?
    private var batchRestoreTask: Task<Void, Never>?
    private var generation = 0
    private var currentCandidate: RadioEpisodeCandidate?
    private var nextCandidates: [RadioEpisodeCandidate] = []
    private var visibleSnapshot: [RadioEpisodeCandidate] = []
    private var activeBatchID: UUID?
    private var activeBatchJobs: [RadioTranscriptJob] = []
    private var automaticPins = Set<RadioEpisodeKey>()
    private var batchPins = Set<RadioEpisodeKey>()
    private var pinnedBatchID: UUID?
    private var isActive = true
    private var hasAcceptedBackgroundContinuation = false
    private var batchOperationGeneration = 0
    private var shouldReplaceBatchSnapshot = false

    private struct AutomaticWorkIdentity: Equatable {
        let current: CandidateWorkIdentity?
        let next: [CandidateWorkIdentity]
    }

    private struct CandidateWorkIdentity: Equatable {
        let key: RadioEpisodeKey
        let remoteURL: URL
        let expectedDurationSeconds: TimeInterval?
        let isCompleted: Bool

        init(_ candidate: RadioEpisodeCandidate) {
            key = candidate.key
            remoteURL = candidate.originalPlaybackURL
            expectedDurationSeconds = candidate.durationSeconds
            isCompleted = candidate.isCompleted
        }
    }

    init(
        pipeline: any RadioTranscriptPipelineScheduling,
        store: RadioTranscriptStore,
        assetProvider: any RadioTranscriptAssetProviding,
        metadataStore: any RadioFeedSpeechMetadataStoring,
        backgroundDriver: any RadioTranscriptBackgroundDriving
    ) {
        self.pipeline = pipeline
        self.store = store
        self.assetProvider = assetProvider
        self.metadataStore = metadataStore
        self.backgroundDriver = backgroundDriver
        startupReconciliationTask = Task { [store] in
            try? await store.reconcile()
        }
        eventTask = Task { [weak self, pipeline] in
            let events = await pipeline.events()
            for await event in events {
                guard !Task.isCancelled else { return }
                self?.handle(event)
            }
        }
    }

    deinit {
        eventTask?.cancel()
        startupReconciliationTask?.cancel()
        reconciliationTask?.cancel()
        batchRestoreTask?.cancel()
    }

    func updateCurrent(
        _ current: RadioEpisodeCandidate?,
        next: [RadioEpisodeCandidate]
    ) {
        let previousIdentity = automaticWorkIdentity
        var seen = Set<RadioEpisodeKey>()
        if let current {
            seen.insert(current.key)
        }
        let filteredNext = next
            .filter { !$0.isCompleted && seen.insert($0.key).inserted }
            .prefix(2)
            .map { $0 }
        currentCandidate = current
        nextCandidates = filteredNext
        let updatedIdentity = automaticWorkIdentity

        guard previousIdentity != updatedIdentity else { return }

        if previousIdentity?.current != updatedIdentity?.current {
            presentation = current.map {
                RadioTranscriptPresentation(
                    episodeKey: $0.key,
                    state: .queued
                )
            } ?? .idle
        }
        reconcileDesired(automaticAllowed: isActive)
    }

    private var automaticWorkIdentity: AutomaticWorkIdentity? {
        guard currentCandidate != nil || !nextCandidates.isEmpty else {
            return nil
        }
        return AutomaticWorkIdentity(
            current: currentCandidate.map(CandidateWorkIdentity.init),
            next: nextCandidates.map(CandidateWorkIdentity.init)
        )
    }

    func updateVisibleSnapshot(_ candidates: [RadioEpisodeCandidate]) {
        var seen = Set<RadioEpisodeKey>()
        visibleSnapshot = candidates.filter {
            !$0.isCompleted && seen.insert($0.key).inserted
        }
        restoreBatchPresentationIfNeeded()
    }

    func prepareAll() {
        let eligible = visibleSnapshot
        guard !eligible.isEmpty else {
            batchPresentation = RadioTranscriptBatchPresentation(
                state: .completed,
                completedCount: 0,
                totalCount: 0,
                backgroundContinuation: .none,
                episodeKeys: []
            )
            return
        }
        guard activeBatchID == nil else { return }
        batchOperationGeneration += 1
        let operationGeneration = batchOperationGeneration
        batchRestoreTask?.cancel()
        batchRestoreTask = Task { [weak self] in
            await self?.beginPrepareAll(
                eligible,
                operationGeneration: operationGeneration
            )
        }
    }

    func retryCurrent() {
        guard currentCandidate != nil else { return }
        reconcileDesired(automaticAllowed: isActive)
    }

    func stopPrepareAll() {
        batchOperationGeneration += 1
        batchRestoreTask?.cancel()
        batchRestoreTask = nil
        backgroundDriver.cancel()
        hasAcceptedBackgroundContinuation = false
        let oldBatchID = activeBatchID
        activeBatchID = nil
        activeBatchJobs = []
        batchPresentation = RadioTranscriptBatchPresentation(
            state: .stopped,
            completedCount: batchPresentation.completedCount,
            totalCount: batchPresentation.totalCount,
            backgroundContinuation: .none,
            episodeKeys: batchPresentation.episodeKeys
        )
        releaseBatchPins(batchID: oldBatchID)
        reconcileDesired(automaticAllowed: isActive)
    }

    func handleActive() {
        isActive = true
        reconcileDesired(automaticAllowed: true)
    }

    func handleBackground() {
        isActive = false
        if hasAcceptedBackgroundContinuation,
           activeBatchID != nil,
           !activeBatchJobs.isEmpty {
            reconcileDesired(automaticAllowed: false)
        } else {
            reconciliationTask?.cancel()
            releaseAutomaticPins()
            Task { [pipeline] in
                await pipeline.cancelAll()
            }
        }
    }

    func handleMemoryWarning() {
        guard currentCandidate == nil else { return }
        presentation = .idle
    }

    func preparedPlaybackURL(
        for episodeKey: RadioEpisodeKey
    ) async -> URL? {
        await assetProvider.preparedPlaybackURL(for: episodeKey)
    }

    private func reconcileDesired(
        automaticAllowed: Bool,
        createBatchManifest: RadioTranscriptBatchManifest? = nil
    ) {
        generation += 1
        let requestedGeneration = generation
        reconciliationTask?.cancel()
        let automaticCandidates = automaticAllowed
            ? [currentCandidate].compactMap { $0 } + nextCandidates
            : []
        let batchID = activeBatchID
        let batchJobs = activeBatchJobs

        reconciliationTask = Task { [weak self] in
            guard let self else { return }
            await self.finishStartupReconciliation()
            guard !Task.isCancelled,
                  requestedGeneration == self.generation else {
                return
            }
            let automaticJobs = await self.makeJobs(
                candidates: automaticCandidates,
                priorities: [.current, .nextOne, .nextTwo]
            )
            guard !Task.isCancelled,
                  requestedGeneration == self.generation else {
                return
            }

            if let createBatchManifest {
                do {
                    try await self.store.saveBatch(createBatchManifest)
                } catch {
                    self.failBatchForPersistence(error)
                    return
                }
            }

            await self.reconcilePins(
                automatic: Set(automaticJobs.map(\.episodeKey)),
                batch: Set(batchJobs.map(\.episodeKey)),
                batchID: batchID
            )
            guard !Task.isCancelled,
                  requestedGeneration == self.generation else {
                return
            }
            await self.pipeline.reconcile(
                interactive: automaticJobs,
                batch: batchJobs,
                generation: requestedGeneration
            )
        }
    }

    private func restoreBatchPresentationIfNeeded() {
        guard activeBatchID == nil,
              batchPresentation.state != .preparing,
              !visibleSnapshot.isEmpty else {
            return
        }
        batchOperationGeneration += 1
        let operationGeneration = batchOperationGeneration
        let visible = visibleSnapshot
        batchRestoreTask?.cancel()
        batchRestoreTask = Task { [weak self] in
            guard let self else { return }
            await self.finishStartupReconciliation()
            guard
                  let manifest = try? await self.store.loadBatch(),
                  !Task.isCancelled,
                  operationGeneration == self.batchOperationGeneration,
                  self.activeBatchID == nil,
                  self.batchPresentation.state != .preparing else {
                return
            }
            var completed = 0
            for entry in manifest.entries {
                if await self.isValidReadyCheckpoint(
                    entry,
                    visibleCandidate: visible.first {
                        $0.key == entry.episodeKey
                    }
                ) {
                    completed += 1
                }
            }
            guard !Task.isCancelled,
                  operationGeneration == self.batchOperationGeneration,
                  self.activeBatchID == nil,
                  self.batchPresentation.state != .preparing else {
                return
            }
            let manifestKeys = manifest.entries
                .sorted { $0.order < $1.order }
                .map(\.episodeKey)
            self.shouldReplaceBatchSnapshot = manifest.entries.contains {
                entry in
                guard let persistedURL = entry.remoteURL,
                      let candidate = visible.first(where: {
                          $0.key == entry.episodeKey
                      }) else {
                    return false
                }
                return persistedURL != candidate.originalPlaybackURL
            }
            let manifestKeySet = Set(manifestKeys)
            let newVisibleKeys = visible
                .map(\.key)
                .filter { !manifestKeySet.contains($0) }
            let keys = completed == manifest.entries.count
                ? manifestKeys + newVisibleKeys
                : manifestKeys
            self.batchPresentation = RadioTranscriptBatchPresentation(
                state: completed == manifest.entries.count &&
                    newVisibleKeys.isEmpty
                    ? .completed
                    : .stopped,
                completedCount: completed,
                totalCount: keys.count,
                backgroundContinuation: .none,
                episodeKeys: keys
            )
        }
    }

    private func beginPrepareAll(
        _ eligible: [RadioEpisodeCandidate],
        operationGeneration: Int
    ) async {
        await finishStartupReconciliation()
        guard !Task.isCancelled,
              operationGeneration == batchOperationGeneration,
              activeBatchID == nil else {
            return
        }
        let previous = try? await store.loadBatch()
        guard !Task.isCancelled,
              operationGeneration == batchOperationGeneration,
              activeBatchID == nil else {
            return
        }
        let resumesPrevious =
            batchPresentation.state == .stopped &&
            previous?.entries.isEmpty == false &&
            previous?.entries.count == batchPresentation.episodeKeys.count &&
            !shouldReplaceBatchSnapshot
        shouldReplaceBatchSnapshot = false
        let visibleByKey = Dictionary(
            uniqueKeysWithValues: eligible.map { ($0.key, $0) }
        )
        let sourceEntries: [RadioTranscriptBatchEntry]
        if resumesPrevious, let previous {
            sourceEntries = previous.entries.sorted { $0.order < $1.order }
        } else {
            var created: [RadioTranscriptBatchEntry] = []
            for (order, candidate) in eligible.enumerated() {
                let metadata = await metadataStore.metadata(
                    for: candidate.key.feedID
                )
                created.append(RadioTranscriptBatchEntry(
                    episodeKey: candidate.key,
                    order: order,
                    remoteURL: candidate.originalPlaybackURL,
                    expectedDurationSeconds: candidate.durationSeconds,
                    languageTag: metadata.languageTag,
                    state: .pending
                ))
            }
            sourceEntries = created
        }

        var entries: [RadioTranscriptBatchEntry] = []
        var remainingJobs: [RadioTranscriptJob] = []

        for sourceEntry in sourceEntries {
            guard !Task.isCancelled,
                  operationGeneration == batchOperationGeneration else {
                return
            }
            let candidate = visibleByKey[sourceEntry.episodeKey]
            let remoteURL = sourceEntry.remoteURL ??
                candidate?.originalPlaybackURL
            let expectedDuration = sourceEntry.expectedDurationSeconds ??
                candidate?.durationSeconds
            let languageTag: String
            if let persisted = sourceEntry.languageTag {
                languageTag = persisted
            } else {
                languageTag = await metadataStore.metadata(
                    for: sourceEntry.episodeKey.feedID
                ).languageTag
            }
            let state: RadioTranscriptBatchEntryState
            switch sourceEntry.state {
            case .transcriptReady(let key):
                let candidateMatchesSource = candidate.map {
                    remoteURL == $0.originalPlaybackURL
                } ?? true
                if candidateMatchesSource,
                   await isValidReadyCheckpoint(
                       sourceEntry,
                       visibleCandidate: candidate
                   ) {
                    state = .transcriptReady(cacheKey: key)
                } else {
                    state = .pending
                }
            case .audioReady(let fingerprint):
                if let asset = try? await assetProvider.cachedAsset(
                    for: sourceEntry.episodeKey
                ),
                   asset.assetFingerprint == fingerprint,
                   remoteURL.map({ asset.originalURL == $0 }) ?? true {
                    state = .audioReady(assetFingerprint: fingerprint)
                } else {
                    state = .pending
                }
            case .pending, .failed:
                state = .pending
            }
            var entry = RadioTranscriptBatchEntry(
                episodeKey: sourceEntry.episodeKey,
                order: sourceEntry.order,
                remoteURL: remoteURL,
                expectedDurationSeconds: expectedDuration,
                languageTag: languageTag,
                state: state
            )
            if case .transcriptReady = state {
                entries.append(entry)
                continue
            }
            if let remoteURL {
                remainingJobs.append(RadioTranscriptJob(
                    episodeKey: sourceEntry.episodeKey,
                    remoteURL: remoteURL,
                    expectedDurationSeconds: expectedDuration,
                    languageTag: languageTag,
                    priority: .batch
                ))
            } else {
                entry.state = .failed(
                    message: "Episode audio is no longer available"
                )
            }
            entries.append(entry)
        }

        guard !Task.isCancelled,
              operationGeneration == batchOperationGeneration,
              activeBatchID == nil else {
            return
        }
        let now = Date()
        let manifest = RadioTranscriptBatchManifest(
            schemaVersion:
                RadioTranscriptBatchManifest.currentSchemaVersion,
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            entries: entries
        )
        do {
            try await store.saveBatch(manifest)
        } catch {
            failBatchForPersistence(error)
            return
        }
        guard !Task.isCancelled,
              operationGeneration == batchOperationGeneration,
              activeBatchID == nil else {
            return
        }

        releaseBatchPins(batchID: pinnedBatchID)
        let completed = manifest.completedCount
        let episodeKeys = manifest.entries
            .sorted { $0.order < $1.order }
            .map(\.episodeKey)
        guard !remainingJobs.isEmpty else {
            batchPresentation = RadioTranscriptBatchPresentation(
                state: manifest.failedCount == 0 ? .completed : .stopped,
                completedCount: completed,
                totalCount: manifest.totalCount,
                backgroundContinuation: .none,
                episodeKeys: episodeKeys
            )
            return
        }

        activeBatchID = manifest.id
        activeBatchJobs = remainingJobs
        let submission = backgroundDriver.submit(
            batchID: manifest.id,
            total: manifest.totalCount
        ) { [weak self] in
            self?.expirePrepareAll()
        }
        let continuation: RadioTranscriptBackgroundContinuation
        switch submission {
        case .accepted:
            continuation = .accepted
            hasAcceptedBackgroundContinuation = true
        case .unavailableOS:
            continuation = .unavailableOS
            hasAcceptedBackgroundContinuation = false
        case .rejected(let message):
            continuation = .rejected(message: message)
            hasAcceptedBackgroundContinuation = false
        }
        batchPresentation = RadioTranscriptBatchPresentation(
            state: .preparing,
            completedCount: completed,
            totalCount: manifest.totalCount,
            backgroundContinuation: continuation,
            episodeKeys: episodeKeys
        )
        backgroundDriver.update(
            completed: completed,
            total: manifest.totalCount
        )
        reconcileDesired(automaticAllowed: isActive)
    }

    private func isValidReadyCheckpoint(
        _ entry: RadioTranscriptBatchEntry,
        visibleCandidate: RadioEpisodeCandidate?
    ) async -> Bool {
        guard case .transcriptReady(let key) = entry.state,
              key.episodeKey == entry.episodeKey,
              (try? await store.loadTranscript(for: key)) != nil,
              let record = try? await store.record(for: key) else {
            return false
        }
        guard let expectedURL = entry.remoteURL else { return true }
        guard visibleCandidate.map({
            $0.originalPlaybackURL == expectedURL
        }) ?? true else {
            return false
        }
        return record.sourceURLHash == Self.hash(url: expectedURL)
    }

    private func finishStartupReconciliation() async {
        guard let task = startupReconciliationTask else { return }
        await task.value
        startupReconciliationTask = nil
    }

    private func makeJobs(
        candidates: [RadioEpisodeCandidate],
        priorities: [RadioTranscriptJobPriority]
    ) async -> [RadioTranscriptJob] {
        var jobs: [RadioTranscriptJob] = []
        for (candidate, priority) in zip(candidates, priorities) {
            if Task.isCancelled { return [] }
            let metadata = await metadataStore.metadata(
                for: candidate.key.feedID
            )
            jobs.append(RadioTranscriptJob(
                episodeKey: candidate.key,
                remoteURL: candidate.originalPlaybackURL,
                expectedDurationSeconds: candidate.durationSeconds,
                languageTag: metadata.languageTag,
                priority: priority
            ))
        }
        return jobs
    }

    private func reconcilePins(
        automatic: Set<RadioEpisodeKey>,
        batch: Set<RadioEpisodeKey>,
        batchID: UUID?
    ) async {
        for key in automaticPins.subtracting(automatic) {
            await assetProvider.unpin(key, reason: .automaticWorkingSet)
        }
        for key in automatic.subtracting(automaticPins) {
            await assetProvider.pin(key, reason: .automaticWorkingSet)
        }
        automaticPins = automatic

        if let batchID {
            if let pinnedBatchID, pinnedBatchID != batchID {
                for key in batchPins {
                    await assetProvider.unpin(
                        key,
                        reason: .batch(pinnedBatchID)
                    )
                }
                batchPins = []
            }
            for key in batchPins.subtracting(batch) {
                await assetProvider.unpin(key, reason: .batch(batchID))
            }
            for key in batch.subtracting(batchPins) {
                await assetProvider.pin(key, reason: .batch(batchID))
            }
            batchPins = batch
            pinnedBatchID = batchID
        }
    }

    private func releaseBatchPins(batchID: UUID?) {
        guard let batchID else {
            batchPins = []
            pinnedBatchID = nil
            return
        }
        let pins = batchPins
        batchPins = []
        pinnedBatchID = nil
        Task { [assetProvider] in
            for key in pins {
                await assetProvider.unpin(key, reason: .batch(batchID))
            }
        }
    }

    private func releaseAutomaticPins() {
        let pins = automaticPins
        automaticPins = []
        Task { [assetProvider] in
            for key in pins {
                await assetProvider.unpin(
                    key,
                    reason: .automaticWorkingSet
                )
            }
        }
    }

    private func handle(_ event: RadioTranscriptPipelineEvent) {
        switch event {
        case .preparation(let episodeKey, let eventGeneration, let state):
            guard eventGeneration == generation,
                  episodeKey == currentCandidate?.key else {
                return
            }
            presentation = RadioTranscriptPresentation(
                episodeKey: episodeKey,
                state: state
            )

        case .batchUpdated(let manifest):
            guard manifest.id == activeBatchID else { return }
            let completed = manifest.completedCount
            let isTerminal = manifest.terminalCount == manifest.totalCount
            let succeeded = isTerminal && manifest.failedCount == 0
            batchPresentation = RadioTranscriptBatchPresentation(
                state: isTerminal
                    ? (succeeded ? .completed : .stopped)
                    : .preparing,
                completedCount: completed,
                totalCount: manifest.totalCount,
                backgroundContinuation:
                    batchPresentation.backgroundContinuation,
                episodeKeys: manifest.entries
                    .sorted { $0.order < $1.order }
                    .map(\.episodeKey)
            )
            backgroundDriver.update(
                completed: completed,
                total: manifest.totalCount
            )
            if isTerminal {
                backgroundDriver.complete(success: succeeded)
                hasAcceptedBackgroundContinuation = false
                let finishedBatchID = activeBatchID
                activeBatchID = nil
                activeBatchJobs = []
                releaseBatchPins(batchID: finishedBatchID)
            }
        }
    }

    private func expirePrepareAll() {
        hasAcceptedBackgroundContinuation = false
        let expiredBatchID = activeBatchID
        activeBatchID = nil
        activeBatchJobs = []
        batchPresentation = RadioTranscriptBatchPresentation(
            state: .stopped,
            completedCount: batchPresentation.completedCount,
            totalCount: batchPresentation.totalCount,
            backgroundContinuation: .none,
            episodeKeys: batchPresentation.episodeKeys
        )
        releaseBatchPins(batchID: expiredBatchID)
        if isActive {
            reconcileDesired(automaticAllowed: true)
        } else {
            Task { [pipeline] in
                await pipeline.cancelAll()
            }
        }
    }

    private func failBatchForPersistence(_ error: Error) {
        backgroundDriver.complete(success: false)
        hasAcceptedBackgroundContinuation = false
        activeBatchID = nil
        activeBatchJobs = []
        batchPresentation = RadioTranscriptBatchPresentation(
            state: .stopped,
            completedCount: 0,
            totalCount: batchPresentation.totalCount,
            backgroundContinuation: .rejected(
                message: error.localizedDescription
            ),
            episodeKeys: batchPresentation.episodeKeys
        )
    }

    private static func hash(url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
