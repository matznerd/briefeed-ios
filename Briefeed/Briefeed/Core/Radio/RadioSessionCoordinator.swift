import Combine
import Foundation

@MainActor
protocol RadioSessionCoordinating: AnyObject {
    var state: RadioSessionState { get }
    var entries: [RadioQueueEntry] { get }
    var currentKey: RadioEpisodeKey? { get }
    var currentEpisode: RadioEpisodeCandidate? { get }
    var sourceFailures: [String: String] { get }
    var sleepTimer: RadioSleepTimer { get }
    var hasPendingColdLaunchAutoplay: Bool { get }
    var canPlayNext: Bool { get }
    var statePublisher: AnyPublisher<RadioSessionState, Never> { get }
    var entriesPublisher: AnyPublisher<[RadioQueueEntry], Never> { get }
    var currentEpisodePublisher: AnyPublisher<RadioEpisodeCandidate?, Never> { get }
    var sourceFailuresPublisher: AnyPublisher<[String: String], Never> { get }
    var sleepTimerPublisher: AnyPublisher<RadioSleepTimer, Never> { get }
    var canPlayNextPublisher: AnyPublisher<Bool, Never> { get }

    func restore(autoplayEnabled: Bool) async -> RadioPlaybackIntent?
    func refreshStarted(enabledSourceCount: Int)
    func applyRefresh(_ result: RSSRefreshBatchResult) -> RadioPlaybackIntent?
    func beginCurrent() -> RadioPlaybackIntent?
    func selectEpisode(_ key: RadioEpisodeKey) -> RadioPlaybackIntent?
    func cancelPendingColdLaunchAutoplay()
}

@MainActor
final class RadioSessionCoordinator: ObservableObject, RadioSessionCoordinating {
    @Published private(set) var state: RadioSessionState = .idle
    @Published private(set) var entries: [RadioQueueEntry] = []
    @Published private(set) var currentKey: RadioEpisodeKey?
    @Published private(set) var currentEpisode: RadioEpisodeCandidate?
    @Published private(set) var sourceFailures: [String: String] = [:]
    @Published private(set) var sleepTimer: RadioSleepTimer = .off
    @Published private(set) var canPlayNext = false
    @Published private(set) var hasPendingColdLaunchAutoplay = false

    var statePublisher: AnyPublisher<RadioSessionState, Never> { $state.eraseToAnyPublisher() }
    var entriesPublisher: AnyPublisher<[RadioQueueEntry], Never> { $entries.eraseToAnyPublisher() }
    var currentEpisodePublisher: AnyPublisher<RadioEpisodeCandidate?, Never> { $currentEpisode.eraseToAnyPublisher() }
    var sourceFailuresPublisher: AnyPublisher<[String: String], Never> { $sourceFailures.eraseToAnyPublisher() }
    var sleepTimerPublisher: AnyPublisher<RadioSleepTimer, Never> { $sleepTimer.eraseToAnyPublisher() }
    var canPlayNextPublisher: AnyPublisher<Bool, Never> { $canPlayNext.eraseToAnyPublisher() }

    private let store: RadioSessionStoreProtocol
    private let repository: RadioEpisodeRepository
    private let now: () -> Date
    private let connectivityStatus: () -> ConnectivityStatus
    private var candidatesByKey: [RadioEpisodeKey: RadioEpisodeCandidate] = [:]
    private var enabledSourceCount = 0
    private var isRefreshing = false
    private var successfulSourceEvidenceCount = 0
    private var attemptedFailureCount = 0
    private var coldLaunchAutoplayDeadline: Date?
    private var didEvaluateColdLaunchAutoplay = false

    init(
        store: RadioSessionStoreProtocol,
        repository: RadioEpisodeRepository,
        now: @escaping () -> Date = Date.init,
        connectivityStatus: @escaping () -> ConnectivityStatus = { .unknown }
    ) {
        self.store = store
        self.repository = repository
        self.now = now
        self.connectivityStatus = connectivityStatus
    }

    func restore(autoplayEnabled: Bool) async -> RadioPlaybackIntent? {
        state = .restoring
        let candidates: [RadioEpisodeCandidate]
        do {
            candidates = try repository.candidates()
        } catch {
            candidates = []
        }
        setCandidates(candidates)
        let durations = Dictionary(uniqueKeysWithValues: candidates.compactMap { candidate in
            candidate.durationSeconds.map { (candidate.key, $0) }
        })
        let snapshot: PersistedRadioSession?
        do {
            snapshot = try store.load(durations: durations)
        } catch {
            snapshot = nil
        }
        let builder = RadioQueueBuilder(now: now())
        let restored = snapshot.map { builder.restore(snapshot: $0, candidates: candidates) }
            ?? builder.buildInitial(candidates: candidates)
        install(restored)
        store.saveDebounced(currentSession())

        guard !didEvaluateColdLaunchAutoplay else { return nil }
        didEvaluateColdLaunchAutoplay = true
        guard autoplayEnabled else { return nil }
        if let request = requestForCurrent() {
            return .play(request)
        }
        coldLaunchAutoplayDeadline = now().addingTimeInterval(60)
        hasPendingColdLaunchAutoplay = true
        return nil
    }

    func refreshStarted(enabledSourceCount: Int) {
        self.enabledSourceCount = enabledSourceCount
        isRefreshing = true
        if state != .playing { state = resolveNoPlayableEntry() }
    }

    func applyRefresh(_ result: RSSRefreshBatchResult) -> RadioPlaybackIntent? {
        isRefreshing = false
        successfulSourceEvidenceCount = result.successfulSourceEvidenceCount
        attemptedFailureCount = result.attemptedFailureCount
        sourceFailures = Dictionary(uniqueKeysWithValues: result.results.compactMap { item in
            guard case .failed(let message) = item.outcome else { return nil }
            return (item.feedID, message)
        })

        let candidates: [RadioEpisodeCandidate]
        do {
            candidates = try repository.candidates()
        } catch {
            candidates = []
        }
        setCandidates(candidates)
        let session = currentSession()
        let reconciled = RadioQueueBuilder(now: now()).reconcile(snapshot: session, candidates: candidates)
        install(reconciled, preservePlayingState: true)
        store.saveDebounced(currentSession())

        guard hasPendingColdLaunchAutoplay else { return nil }
        guard let deadline = coldLaunchAutoplayDeadline, now() < deadline else {
            cancelPendingColdLaunchAutoplay()
            return nil
        }
        defer { cancelPendingColdLaunchAutoplay() }
        guard let request = requestForCurrent() else { return nil }
        return .play(request)
    }

    func beginCurrent() -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        guard let request = requestForCurrent() else { return nil }
        state = .playing
        return .play(request)
    }

    func selectEpisode(_ key: RadioEpisodeKey) -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        guard let candidate = try? repository.candidate(for: key),
              isEligibleForSelection(candidate) else { return nil }
        setCandidates(Array(candidatesByKey.values.filter { $0.key != key }) + [candidate])

        var updated = entries.filter { $0.key != key }
        if let currentKey, let currentIndex = updated.firstIndex(where: { $0.key == currentKey }),
           updated[currentIndex].positionSeconds > 0 {
            updated[currentIndex].disposition = .deferred
        }
        let selected = entries.first(where: { $0.key == key })
            ?? RadioQueueEntry(key: key, positionSeconds: initialPosition(for: candidate), disposition: .pending, playbackFailureCount: 0, lastPlaybackError: nil)
        updated.insert(selected, at: 0)
        entries = updated
        currentKey = key
        currentEpisode = candidate
        updateCanPlayNext()
        do {
            try store.saveNow(currentSession())
        } catch {
            state = .failed(.persistence(error.localizedDescription))
            return nil
        }
        state = .loading
        return .play(playbackRequest(for: candidate, position: selected.positionSeconds))
    }

    func cancelPendingColdLaunchAutoplay() {
        hasPendingColdLaunchAutoplay = false
        coldLaunchAutoplayDeadline = nil
    }

    private func install(_ session: PersistedRadioSession, preservePlayingState: Bool = false) {
        entries = session.entries
        currentKey = session.currentKey
        currentEpisode = currentKey.flatMap { candidatesByKey[$0] }
        updateCanPlayNext()
        if preservePlayingState && state == .playing { return }
        state = currentEpisode == nil ? resolveNoPlayableEntry() : .readyPaused
    }

    private func currentSession() -> PersistedRadioSession {
        PersistedRadioSession(schemaVersion: PersistedRadioSession.schemaVersion, entries: entries, currentKey: currentKey, savedAt: now())
    }

    private func setCandidates(_ candidates: [RadioEpisodeCandidate]) {
        candidatesByKey = candidates.reduce(into: [:]) { result, candidate in
            result[candidate.key] = result[candidate.key] ?? candidate
        }
    }

    private func requestForCurrent() -> RadioPlaybackRequest? {
        guard let currentKey, let candidate = candidatesByKey[currentKey],
              let entry = entries.first(where: { $0.key == currentKey }),
              entry.disposition != .failedThisSession, !candidate.isCompleted else { return nil }
        return playbackRequest(for: candidate, position: entry.positionSeconds)
    }

    private func playbackRequest(for candidate: RadioEpisodeCandidate, position: TimeInterval) -> RadioPlaybackRequest {
        RadioPlaybackRequest(key: candidate.key, url: candidate.originalPlaybackURL, title: candidate.title, source: candidate.sourceName, positionSeconds: position)
    }

    private func initialPosition(for candidate: RadioEpisodeCandidate) -> TimeInterval {
        guard let duration = candidate.durationSeconds, duration.isFinite, duration > 0,
              candidate.normalizedCoreDataProgress.isFinite else { return 0 }
        return min(max(candidate.normalizedCoreDataProgress, 0), 1) * duration
    }

    private func isEligibleForSelection(_ candidate: RadioEpisodeCandidate) -> Bool {
        guard !candidate.isCompleted else { return false }
        guard !entries.contains(where: {
            $0.key != candidate.key && candidatesByKey[$0.key]?.canonicalEnclosureURL == candidate.canonicalEnclosureURL
        }) else { return false }
        return RadioQueueBuilder(now: now()).buildInitial(candidates: [candidate]).entries.contains { $0.key == candidate.key }
    }

    private func updateCanPlayNext() {
        canPlayNext = RadioQueueBuilder(now: now()).nextEligible(in: currentSession()) != nil
    }

    private func resolveNoPlayableEntry() -> RadioSessionState {
        resolveNoPlayableEntry(
            enabledSourceCount: enabledSourceCount,
            connectivityStatus: connectivityStatus(),
            isRefreshing: isRefreshing,
            successfulSourceEvidenceCount: successfulSourceEvidenceCount,
            attemptedFailureCount: attemptedFailureCount
        )
    }

    private func resolveNoPlayableEntry(
        enabledSourceCount: Int,
        connectivityStatus: ConnectivityStatus,
        isRefreshing: Bool,
        successfulSourceEvidenceCount: Int,
        attemptedFailureCount: Int
    ) -> RadioSessionState {
        if state == .playing { return .playing }
        guard enabledSourceCount > 0 else { return .noSources }
        if connectivityStatus == .offline { return .waitingForNetwork }
        if connectivityStatus == .unknown || isRefreshing { return .refreshing }
        if attemptedFailureCount == enabledSourceCount && successfulSourceEvidenceCount == 0 {
            return .failed(.allSourcesUnavailable)
        }
        if successfulSourceEvidenceCount > 0 { return .exhausted }
        return .refreshing
    }
}
