import Combine
import Foundation

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

    private let pipeline: any RadioTranscriptPipelineScheduling
    private let store: RadioTranscriptStore
    private let assetProvider: any RadioTranscriptAssetProviding
    private let metadataStore: any RadioFeedSpeechMetadataStoring
    private let backgroundDriver: any RadioTranscriptBackgroundDriving
    private var eventTask: Task<Void, Never>?
    private var reconciliationTask: Task<Void, Never>?
    private var generation = 0
    private var currentCandidate: RadioEpisodeCandidate?
    private var nextCandidates: [RadioEpisodeCandidate] = []
    private var visibleSnapshot: [RadioEpisodeCandidate] = []
    private var activeBatchID: UUID?
    private var activeBatchCandidates: [RadioEpisodeCandidate] = []
    private var automaticPins = Set<RadioEpisodeKey>()
    private var batchPins = Set<RadioEpisodeKey>()
    private var pinnedBatchID: UUID?
    private var isActive = true
    private var hasAcceptedBackgroundContinuation = false

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
        reconciliationTask?.cancel()
    }

    func updateCurrent(
        _ current: RadioEpisodeCandidate?,
        next: [RadioEpisodeCandidate]
    ) {
        let previousKey = currentCandidate?.key
        currentCandidate = current
        var seen = Set<RadioEpisodeKey>()
        if let current {
            seen.insert(current.key)
        }
        nextCandidates = next
            .filter { !$0.isCompleted && seen.insert($0.key).inserted }
            .prefix(2)
            .map { $0 }

        if previousKey != current?.key {
            presentation = current.map {
                RadioTranscriptPresentation(
                    episodeKey: $0.key,
                    state: .queued
                )
            } ?? .idle
        }
        reconcileDesired(automaticAllowed: isActive)
    }

    func updateVisibleSnapshot(_ candidates: [RadioEpisodeCandidate]) {
        var seen = Set<RadioEpisodeKey>()
        visibleSnapshot = candidates.filter {
            !$0.isCompleted && seen.insert($0.key).inserted
        }
    }

    func prepareAll() {
        let eligible = visibleSnapshot
        guard !eligible.isEmpty else {
            batchPresentation = RadioTranscriptBatchPresentation(
                state: .completed,
                completedCount: 0,
                totalCount: 0,
                backgroundContinuation: .none
            )
            return
        }

        let batchID = UUID()
        releaseBatchPins(batchID: pinnedBatchID)
        activeBatchID = batchID
        activeBatchCandidates = eligible
        let submission = backgroundDriver.submit(
            batchID: batchID,
            total: eligible.count
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
            completedCount: 0,
            totalCount: eligible.count,
            backgroundContinuation: continuation
        )
        reconcileDesired(
            automaticAllowed: isActive,
            createBatchManifest: true
        )
    }

    func retryCurrent() {
        guard currentCandidate != nil else { return }
        reconcileDesired(automaticAllowed: isActive)
    }

    func stopPrepareAll() {
        backgroundDriver.cancel()
        hasAcceptedBackgroundContinuation = false
        let oldBatchID = activeBatchID
        activeBatchID = nil
        activeBatchCandidates = []
        batchPresentation = RadioTranscriptBatchPresentation(
            state: .stopped,
            completedCount: batchPresentation.completedCount,
            totalCount: batchPresentation.totalCount,
            backgroundContinuation: .none
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
           !activeBatchCandidates.isEmpty {
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
        createBatchManifest: Bool = false
    ) {
        generation += 1
        let requestedGeneration = generation
        reconciliationTask?.cancel()
        let automaticCandidates = automaticAllowed
            ? [currentCandidate].compactMap { $0 } + nextCandidates
            : []
        let batchID = activeBatchID
        let batchCandidates = activeBatchCandidates

        reconciliationTask = Task { [weak self] in
            guard let self else { return }
            let automaticJobs = await self.makeJobs(
                candidates: automaticCandidates,
                priorities: [.current, .nextOne, .nextTwo]
            )
            let batchJobs = await self.makeJobs(
                candidates: batchCandidates,
                priorities: Array(
                    repeating: .batch,
                    count: batchCandidates.count
                )
            )
            guard !Task.isCancelled,
                  requestedGeneration == self.generation else {
                return
            }

            if createBatchManifest, let batchID {
                let now = Date()
                let manifest = RadioTranscriptBatchManifest(
                    schemaVersion:
                        RadioTranscriptBatchManifest.currentSchemaVersion,
                    id: batchID,
                    createdAt: now,
                    updatedAt: now,
                    entries: batchCandidates.enumerated().map {
                        RadioTranscriptBatchEntry(
                            episodeKey: $0.element.key,
                            order: $0.offset,
                            state: .pending
                        )
                    }
                )
                do {
                    try await self.store.saveBatch(manifest)
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
            batchPresentation = RadioTranscriptBatchPresentation(
                state: completed == manifest.totalCount
                    ? .completed
                    : .preparing,
                completedCount: completed,
                totalCount: manifest.totalCount,
                backgroundContinuation:
                    batchPresentation.backgroundContinuation
            )
            backgroundDriver.update(
                completed: completed,
                total: manifest.totalCount
            )
            if completed == manifest.totalCount {
                backgroundDriver.complete(success: true)
                hasAcceptedBackgroundContinuation = false
                let finishedBatchID = activeBatchID
                activeBatchID = nil
                activeBatchCandidates = []
                releaseBatchPins(batchID: finishedBatchID)
            }
        }
    }

    private func expirePrepareAll() {
        hasAcceptedBackgroundContinuation = false
        let expiredBatchID = activeBatchID
        activeBatchID = nil
        activeBatchCandidates = []
        batchPresentation = RadioTranscriptBatchPresentation(
            state: .stopped,
            completedCount: batchPresentation.completedCount,
            totalCount: batchPresentation.totalCount,
            backgroundContinuation: .none
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
        activeBatchCandidates = []
        batchPresentation = RadioTranscriptBatchPresentation(
            state: .stopped,
            completedCount: 0,
            totalCount: batchPresentation.totalCount,
            backgroundContinuation: .rejected(
                message: error.localizedDescription
            )
        )
    }
}
