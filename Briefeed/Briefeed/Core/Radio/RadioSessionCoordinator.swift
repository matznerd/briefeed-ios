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
    func applyInitialRefresh(_ result: RSSRefreshBatchResult) -> RadioPlaybackIntent?
    func beginCurrent() -> RadioPlaybackIntent?
    func selectEpisode(_ key: RadioEpisodeKey) -> RadioPlaybackIntent?
    func recordProgress(positionSeconds: TimeInterval, duration: TimeInterval?)
    func pauseByUser(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent?
    func seekEnded(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent?
    func manualNext(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent?
    func playbackCompleted(at: Date) -> RadioPlaybackIntent?
    func playbackFailed(message: String) -> RadioPlaybackIntent?
    func retry() -> RadioPlaybackIntent?
    func setSleepTimer(_ timer: RadioSleepTimer)
    func evaluateSleepTimer(at: Date, positionSeconds: TimeInterval?, duration: TimeInterval?) -> RadioPlaybackIntent?
    func handleInterruptionBegan(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent?
    func handleInterruptionEnded(shouldResume: Bool) -> RadioPlaybackIntent?
    func handleRouteRemoval(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent?
    func cancelPendingColdLaunchAutoplay()
}

extension RadioSessionCoordinating {
    func evaluateSleepTimer(at date: Date) -> RadioPlaybackIntent? {
        evaluateSleepTimer(at: date, positionSeconds: nil, duration: nil)
    }
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
    private let connectivity: ConnectivityMonitoring?
    private let connectivityStatus: () -> ConnectivityStatus
    private var connectivityCancellable: AnyCancellable?
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
        connectivity: ConnectivityMonitoring? = nil,
        connectivityStatus: @escaping () -> ConnectivityStatus = { .unknown }
    ) {
        self.store = store
        self.repository = repository
        self.now = now
        self.connectivity = connectivity
        self.connectivityStatus = connectivity.map { monitor in { monitor.status } } ?? connectivityStatus
        if let connectivity {
            connectivityCancellable = connectivity.statusPublisher.sink { [weak self] status in
                self?.connectivityChanged(status)
            }
        }
    }

    func restore(autoplayEnabled: Bool) async -> RadioPlaybackIntent? {
        if !hasActivePlaybackState { state = .restoring }
        let candidates: [RadioEpisodeCandidate]
        do {
            candidates = try repository.candidates()
        } catch {
            return handleReadFailure(error)
        }
        let durations = Dictionary(uniqueKeysWithValues: candidates.compactMap { candidate in
            candidate.durationSeconds.map { (candidate.key, $0) }
        })
        let snapshot: PersistedRadioSession?
        do {
            snapshot = try store.load(durations: durations)
        } catch {
            return handleReadFailure(error)
        }
        let builder = RadioQueueBuilder(now: now())
        let restored = snapshot.map { builder.restore(snapshot: $0, candidates: candidates) }
            ?? builder.buildInitial(candidates: candidates)
        let previousCurrentKey = currentKey
        let previousState = state
        setCandidates(candidates)
        install(
            restored,
            preservedPlaybackState: previousCurrentKey == restored.currentKey ? previousState : nil
        )
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
        if !hasActivePlaybackState { state = resolveNoPlayableEntry() }
    }

    func applyRefresh(_ result: RSSRefreshBatchResult) -> RadioPlaybackIntent? {
        applyRefresh(result, isInitialColdLaunchRefresh: false)
    }

    func applyInitialRefresh(_ result: RSSRefreshBatchResult) -> RadioPlaybackIntent? {
        applyRefresh(result, isInitialColdLaunchRefresh: true)
    }

    private func applyRefresh(_ result: RSSRefreshBatchResult, isInitialColdLaunchRefresh: Bool) -> RadioPlaybackIntent? {
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
            return handleReadFailure(error)
        }
        setCandidates(candidates)
        let session = currentSession()
        let preReconcileKeys = Set(entries.map(\.key))
        let reconciled = RadioQueueBuilder(now: now()).reconcile(snapshot: session, candidates: candidates)
        let previousCurrentKey = currentKey
        let previousState = state
        install(
            reconciled,
            preservedPlaybackState: previousCurrentKey == reconciled.currentKey ? previousState : nil
        )
        let refreshedSources = Set(result.results.compactMap { item -> String? in
            if case .success = item.outcome { return item.feedID }
            return nil
        })
        if !refreshedSources.isEmpty {
            entries = entries.map { entry in
                guard refreshedSources.contains(entry.key.feedID) else { return entry }
                var reset = entry
                reset.playbackFailureCount = 0
                reset.lastPlaybackError = nil
                if reset.disposition == .failedThisSession { reset.disposition = .pending }
                return reset
            }
        }
        store.saveDebounced(currentSession())

        guard isInitialColdLaunchRefresh, hasPendingColdLaunchAutoplay else { return nil }
        guard let deadline = coldLaunchAutoplayDeadline, now() < deadline else {
            cancelPendingColdLaunchAutoplay()
            return nil
        }
        let appendedKeys = Set(reconciled.entries.map(\.key)).subtracting(preReconcileKeys)
        if result.successfulSourceEvidenceCount > 0,
           let currentKey,
           appendedKeys.contains(currentKey),
           let request = requestForCurrent() {
            cancelPendingColdLaunchAutoplay()
            return .play(request)
        }
        if isTerminalInitialRefresh(result) { cancelPendingColdLaunchAutoplay() }
        return nil
    }

    func beginCurrent() -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        guard let request = requestForCurrent() else { return nil }
        state = .playing
        return .play(request)
    }

    func selectEpisode(_ key: RadioEpisodeKey) -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        let candidate: RadioEpisodeCandidate
        do {
            guard let loaded = try repository.candidate(for: key) else { return nil }
            candidate = loaded
        } catch {
            return handleReadFailure(error)
        }
        guard entries.first(where: { $0.key == key })?.disposition != .failedThisSession,
              isEligibleForSelection(candidate) else { return nil }

        let previousCurrent = currentKey.flatMap { current in entries.first(where: { $0.key == current }) }
        let selected = entries.first(where: { $0.key == key })
            ?? RadioQueueEntry(key: key, positionSeconds: initialPosition(for: candidate), disposition: .pending, playbackFailureCount: 0, lastPlaybackError: nil)
        var selectedEntry = selected
        selectedEntry.disposition = .pending
        let remaining = entries.filter { $0.key != key && $0.key != previousCurrent?.key }
        var pending = remaining.filter { $0.disposition == .pending }
        var deferred = remaining.filter { $0.disposition == .deferred }
        if var previousCurrent, previousCurrent.key != key, previousCurrent.positionSeconds > 0 {
            previousCurrent.disposition = .deferred
            deferred.append(previousCurrent)
        } else if let previousCurrent, previousCurrent.key != key {
            var normalized = previousCurrent
            normalized.disposition = .pending
            pending.insert(normalized, at: 0)
        }
        let stagedEntries = [selectedEntry] + pending + deferred + remaining.filter { $0.disposition == .failedThisSession }
        return commitSelection(stagedEntries, selected: selectedEntry, candidate: candidate)
    }

    func recordProgress(positionSeconds: TimeInterval, duration: TimeInterval?) {
        let previousBucket = entries.first(where: { $0.key == currentKey }).map { Int($0.positionSeconds / 5) }
        guard updateCurrentPosition(positionSeconds) else { return }
        let bucket = Int(max(positionSeconds, 0) / 5)
        guard previousBucket != bucket else { return }
        store.saveDebounced(currentSession())
        persistProgress(positionSeconds: positionSeconds, duration: duration)
    }

    func pauseByUser(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        guard forceSave(positionSeconds: positionSeconds, duration: duration) else { return nil }
        state = .pausedByUser
        return .pause
    }

    func seekEnded(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        forceSave(positionSeconds: positionSeconds, duration: duration)
        return nil
    }

    func manualNext(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        sleepTimer = .off
        guard let currentKey, let current = entries.first(where: { $0.key == currentKey }) else { return nil }
        if isNearlyComplete(positionSeconds: positionSeconds, duration: duration) {
            return playbackCompleted(at: now())
        }
        var deferred = current
        deferred.positionSeconds = validPosition(positionSeconds)
        deferred.disposition = .deferred
        replaceCurrent(deferred)
        guard forceSave(positionSeconds: deferred.positionSeconds, duration: duration) else { return nil }
        return advance(afterRemovingCurrent: false)
    }

    func playbackCompleted(at date: Date) -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        guard let currentKey else { return nil }
        do {
            try repository.markCompleted(key: currentKey, at: date)
        } catch {
            state = .failed(.persistence(error.localizedDescription))
            return nil
        }
        entries.removeAll { $0.key == currentKey }
        self.currentKey = nil
        currentEpisode = nil
        updateCanPlayNext()
        do {
            try store.saveNow(currentSession())
        } catch {
            // Core Data is authoritative: the stale snapshot is deliberately repaired on restore.
            state = .failed(.persistence(error.localizedDescription))
            return nil
        }
        if sleepTimer == .endOfEpisode {
            sleepTimer = .off
            selectNextPaused()
            return nil
        }
        return advance(afterRemovingCurrent: true)
    }

    func playbackFailed(message: String) -> RadioPlaybackIntent? {
        guard let currentKey, let index = entries.firstIndex(where: { $0.key == currentKey }) else { return nil }
        guard connectivityStatus() == .online else {
            state = .waitingForNetwork
            return nil
        }
        entries[index].playbackFailureCount += 1
        entries[index].lastPlaybackError = message
        if entries[index].playbackFailureCount < 2 {
            state = .loading
            return requestForCurrent().map(RadioPlaybackIntent.play)
        }
        entries[index].disposition = .failedThisSession
        state = .failed(.playback(message))
        guard forceSave(positionSeconds: entries[index].positionSeconds, duration: currentEpisode?.durationSeconds) else { return nil }
        return advance(afterRemovingCurrent: false)
    }

    func retry() -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        guard let currentKey, let index = entries.firstIndex(where: { $0.key == currentKey }) else { return nil }
        entries[index].playbackFailureCount = 0
        entries[index].lastPlaybackError = nil
        entries[index].disposition = .pending
        state = .loading
        return requestForCurrent().map(RadioPlaybackIntent.play)
    }

    func setSleepTimer(_ timer: RadioSleepTimer) {
        cancelPendingColdLaunchAutoplay()
        sleepTimer = timer
    }

    func evaluateSleepTimer(at date: Date, positionSeconds: TimeInterval? = nil, duration: TimeInterval? = nil) -> RadioPlaybackIntent? {
        guard case .deadline(let deadline) = sleepTimer, date >= deadline else { return nil }
        sleepTimer = .off
        guard forceSave(positionSeconds: positionSeconds, duration: duration) else { return nil }
        state = .pausedByUser
        return .pause
    }

    func handleInterruptionBegan(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent? {
        forceSave(positionSeconds: positionSeconds, duration: duration)
        state = .pausedByUser
        return .pause
    }

    func handleInterruptionEnded(shouldResume: Bool) -> RadioPlaybackIntent? {
        guard shouldResume, state == .pausedByUser else { return nil }
        state = .loading
        return requestForCurrent().map(RadioPlaybackIntent.play)
    }

    func handleRouteRemoval(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent? {
        forceSave(positionSeconds: positionSeconds, duration: duration)
        state = .pausedByUser
        return .pause
    }

    private func commitSelection(_ stagedEntries: [RadioQueueEntry], selected: RadioQueueEntry, candidate: RadioEpisodeCandidate) -> RadioPlaybackIntent? {
        let staged = PersistedRadioSession(schemaVersion: PersistedRadioSession.schemaVersion, entries: stagedEntries, currentKey: selected.key, savedAt: now())
        do {
            try store.saveNow(staged)
        } catch {
            state = .failed(.persistence(error.localizedDescription))
            return nil
        }
        entries = stagedEntries
        currentKey = selected.key
        currentEpisode = candidate
        setCandidates(Array(candidatesByKey.values.filter { $0.key != selected.key }) + [candidate])
        updateCanPlayNext()
        state = .loading
        return .play(playbackRequest(for: candidate, position: selected.positionSeconds))
    }

    func cancelPendingColdLaunchAutoplay() {
        hasPendingColdLaunchAutoplay = false
        coldLaunchAutoplayDeadline = nil
    }

    private func connectivityChanged(_ status: ConnectivityStatus) {
        guard currentEpisode == nil else { return }
        if status == .offline { state = .waitingForNetwork }
        else if status == .online { state = resolveNoPlayableEntry() }
    }

    @discardableResult
    private func forceSave(positionSeconds: TimeInterval?, duration: TimeInterval?) -> Bool {
        if let positionSeconds { _ = updateCurrentPosition(positionSeconds) }
        if let positionSeconds { persistProgress(positionSeconds: positionSeconds, duration: duration) }
        do {
            try store.saveNow(currentSession())
            return true
        } catch {
            state = .failed(.persistence(error.localizedDescription))
            return false
        }
    }

    private func persistProgress(positionSeconds: TimeInterval, duration: TimeInterval?) {
        guard let currentKey else { return }
        do { try repository.saveProgress(key: currentKey, seconds: positionSeconds, duration: duration) }
        catch { state = .failed(.persistence(error.localizedDescription)) }
    }

    @discardableResult
    private func updateCurrentPosition(_ positionSeconds: TimeInterval) -> Bool {
        guard let currentKey, let index = entries.firstIndex(where: { $0.key == currentKey }) else { return false }
        entries[index].positionSeconds = validPosition(positionSeconds)
        return true
    }

    private func validPosition(_ seconds: TimeInterval) -> TimeInterval {
        seconds.isFinite ? max(seconds, 0) : 0
    }

    private func isNearlyComplete(positionSeconds: TimeInterval, duration: TimeInterval?) -> Bool {
        guard let duration, duration.isFinite, duration > 0 else { return false }
        return validPosition(positionSeconds) / duration >= 0.95
    }

    private func replaceCurrent(_ replacement: RadioQueueEntry) {
        guard let index = entries.firstIndex(where: { $0.key == replacement.key }) else { return }
        entries.remove(at: index)
        entries.append(replacement)
    }

    private func advance(afterRemovingCurrent: Bool) -> RadioPlaybackIntent? {
        let next = RadioQueueBuilder(now: now()).nextEligible(in: currentSession())
        guard let next, let candidate = candidatesByKey[next], let index = entries.firstIndex(where: { $0.key == next }) else {
            currentKey = nil
            currentEpisode = nil
            updateCanPlayNext()
            state = entries.contains(where: { $0.disposition == .failedThisSession }) ? .failed(.playback("All entries failed")) : .exhausted
            return nil
        }
        currentKey = next
        currentEpisode = candidate
        entries[index].disposition = .pending
        updateCanPlayNext()
        state = .loading
        return .play(playbackRequest(for: candidate, position: entries[index].positionSeconds))
    }

    private func selectNextPaused() {
        guard let next = RadioQueueBuilder(now: now()).nextEligible(in: currentSession()),
              let candidate = candidatesByKey[next] else {
            currentKey = nil; currentEpisode = nil; state = .exhausted; updateCanPlayNext(); return
        }
        currentKey = next
        currentEpisode = candidate
        state = .readyPaused
        updateCanPlayNext()
    }

    private func install(_ session: PersistedRadioSession, preservedPlaybackState: RadioSessionState? = nil) {
        entries = session.entries
        currentKey = session.currentKey
        currentEpisode = currentKey.flatMap { candidatesByKey[$0] }
        updateCanPlayNext()
        if let preservedPlaybackState, isPlaybackState(preservedPlaybackState) {
            state = preservedPlaybackState
            return
        }
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

    private var hasActivePlaybackState: Bool { isPlaybackState(state) }

    private func isPlaybackState(_ state: RadioSessionState) -> Bool {
        state == .playing || state == .loading || state == .pausedByUser
    }

    #if DEBUG
    func setPlaybackStateForTesting(_ state: RadioSessionState) {
        guard isPlaybackState(state) else { return }
        self.state = state
    }
    #endif

    private func handleReadFailure(_ error: Error) -> RadioPlaybackIntent? {
        if !hasActivePlaybackState { state = .failed(.persistence(error.localizedDescription)) }
        return nil
    }

    private func isTerminalInitialRefresh(_ result: RSSRefreshBatchResult) -> Bool {
        if result.successfulSourceEvidenceCount > 0 { return true }
        return enabledSourceCount > 0 && result.attemptedFailureCount == enabledSourceCount
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
