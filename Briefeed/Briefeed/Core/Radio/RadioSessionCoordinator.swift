import Combine
import Foundation

@MainActor
protocol RadioRetryScheduling: AnyObject {
    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
private final class RadioRetryScheduler: RadioRetryScheduling {
    private var task: Task<Void, Never>?

    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () -> Void) {
        cancel()
        task = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

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
    var currentConnectivityStatus: ConnectivityStatus { get }
    var statePublisher: AnyPublisher<RadioSessionState, Never> { get }
    var entriesPublisher: AnyPublisher<[RadioQueueEntry], Never> { get }
    var currentEpisodePublisher: AnyPublisher<RadioEpisodeCandidate?, Never> { get }
    var sourceFailuresPublisher: AnyPublisher<[String: String], Never> { get }
    var sleepTimerPublisher: AnyPublisher<RadioSleepTimer, Never> { get }
    var canPlayNextPublisher: AnyPublisher<Bool, Never> { get }
    var pendingNetworkIntentPublisher: AnyPublisher<RadioPlaybackIntent, Never> { get }

    func restore(autoplayEnabled: Bool) async -> RadioPlaybackIntent?
    func refreshStarted(enabledSourceCount: Int)
    func applyRefresh(_ result: RSSRefreshBatchResult) -> RadioPlaybackIntent?
    func applyInitialRefresh(_ result: RSSRefreshBatchResult) -> RadioPlaybackIntent?
    func sourceConfigurationDidChange(enabledSourceCount: Int) -> RadioPlaybackIntent?
    func beginCurrent() -> RadioPlaybackIntent?
    func selectEpisode(_ key: RadioEpisodeKey) -> RadioPlaybackIntent?
    func queueEpisode(_ key: RadioEpisodeKey) -> Bool
    func pauseByUser(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent?
    func seekEnded(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent?
    func manualNext(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent?
    func retry() -> RadioPlaybackIntent?
    func setSleepTimer(_ timer: RadioSleepTimer)
    func evaluateSleepTimer(at: Date, positionSeconds: TimeInterval?, duration: TimeInterval?) -> RadioPlaybackIntent?
    func handleInterruptionBegan(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent?
    func handleInterruptionEnded(shouldResume: Bool) -> RadioPlaybackIntent?
    func handleRouteRemoval(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent?
    func handleBackground(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent?
    func handleTermination(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent?
    func recordProgress(for key: RadioEpisodeKey, positionSeconds: TimeInterval, duration: TimeInterval?)
    func playbackCompleted(for key: RadioEpisodeKey, at: Date) -> RadioPlaybackIntent?
    func playbackFailed(for key: RadioEpisodeKey, message: String, positionSeconds: TimeInterval, duration: TimeInterval?, connectivity: ConnectivityStatus) -> RadioPlaybackIntent?
    func transportDidStart(for key: RadioEpisodeKey)
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
    private let pendingNetworkIntentSubject = PassthroughSubject<RadioPlaybackIntent, Never>()

    var statePublisher: AnyPublisher<RadioSessionState, Never> { $state.eraseToAnyPublisher() }
    var entriesPublisher: AnyPublisher<[RadioQueueEntry], Never> { $entries.eraseToAnyPublisher() }
    var currentEpisodePublisher: AnyPublisher<RadioEpisodeCandidate?, Never> { $currentEpisode.eraseToAnyPublisher() }
    var sourceFailuresPublisher: AnyPublisher<[String: String], Never> { $sourceFailures.eraseToAnyPublisher() }
    var sleepTimerPublisher: AnyPublisher<RadioSleepTimer, Never> { $sleepTimer.eraseToAnyPublisher() }
    var canPlayNextPublisher: AnyPublisher<Bool, Never> { $canPlayNext.eraseToAnyPublisher() }
    var pendingNetworkIntentPublisher: AnyPublisher<RadioPlaybackIntent, Never> { pendingNetworkIntentSubject.eraseToAnyPublisher() }
    var currentConnectivityStatus: ConnectivityStatus { connectivityStatus() }

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
    private let retryScheduler: RadioRetryScheduling
    private var pendingGeneration = 0
    private var pendingRequest: PendingRequest?
    private var interruptionResumeEligible = false
    private var lastProgressBucket: (key: RadioEpisodeKey, bucket: Int)?
    private var completionRecovery: CompletionRecovery?

    private enum PendingPurpose {
        case coldLaunchAutoplay, userStart, selection, automaticRetry, networkRecovery, interruptionResume, advance
    }

    private struct PendingRequest {
        let request: RadioPlaybackRequest
        let purpose: PendingPurpose
        let generation: Int
    }

    private enum CompletionContinuation {
        case advance(endOfEpisode: Bool)
        case selection
    }

    private struct CompletionPlan {
        let completedKey: RadioEpisodeKey
        let completedAt: Date
        let repairedSession: PersistedRadioSession
        let continuation: CompletionContinuation
    }

    private enum CompletionRecovery {
        case markCoreData(CompletionPlan)
        case saveSnapshot(CompletionPlan)
    }

    init(
        store: RadioSessionStoreProtocol,
        repository: RadioEpisodeRepository,
        now: @escaping () -> Date = Date.init,
        connectivity: ConnectivityMonitoring? = nil,
        connectivityStatus: @escaping () -> ConnectivityStatus = { .unknown },
        retryScheduler: RadioRetryScheduling? = nil
    ) {
        self.store = store
        self.repository = repository
        self.now = now
        self.connectivity = connectivity
        self.connectivityStatus = connectivity.map { monitor in { monitor.status } } ?? connectivityStatus
        self.retryScheduler = retryScheduler ?? RadioRetryScheduler()
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
        if previousCurrentKey != restored.currentKey { cancelPendingRequest() }
        setCandidates(candidates)
        install(
            restored,
            preservedPlaybackState: previousCurrentKey == restored.currentKey ? previousState : nil
        )
        completionRecovery = nil
        store.saveDebounced(currentSession())

        guard !didEvaluateColdLaunchAutoplay else { return nil }
        didEvaluateColdLaunchAutoplay = true
        guard autoplayEnabled else { return nil }
        if let request = requestForCurrent(), request.url.isFileURL, canLoad(request.url) {
            state = .loading
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

    func sourceConfigurationDidChange(enabledSourceCount: Int) -> RadioPlaybackIntent? {
        let previousCurrentKey = currentKey
        let previousState = state
        let previousHadActivePlayback = hasActivePlaybackState
        let candidates: [RadioEpisodeCandidate]
        do {
            candidates = try repository.candidates()
        } catch {
            return handleReadFailure(error)
        }

        self.enabledSourceCount = enabledSourceCount
        let reconciled = RadioQueueBuilder(now: now()).reconcile(
            snapshot: currentSession(),
            candidates: candidates
        )
        let currentChanged = previousCurrentKey != reconciled.currentKey
        if currentChanged {
            cancelPendingRequest()
            // The transport may still own the removed episode. Clear the stale
            // playback state before installing the new local-only selection.
            state = .idle
        }
        setCandidates(candidates)
        install(
            reconciled,
            preservedPlaybackState: currentChanged ? nil : previousState
        )

        do {
            try store.saveNow(currentSession())
        } catch {
            if !(previousHadActivePlayback && !currentChanged) {
                state = .failed(.persistence(error.localizedDescription))
            }
        }

        return currentChanged && previousHadActivePlayback ? .pause : nil
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
        var session = currentSession()
        let refreshedSources = Set(result.results.compactMap { item -> String? in
            if case .success = item.outcome { return item.feedID }
            return nil
        })
        if !refreshedSources.isEmpty {
            session.entries = session.entries.map { entry in
                guard refreshedSources.contains(entry.key.feedID) else { return entry }
                var reset = entry
                reset.playbackFailureCount = 0
                reset.lastPlaybackError = nil
                if reset.disposition == .failedThisSession { reset.disposition = .pending }
                return reset
            }
            if session.currentKey == nil {
                session.currentKey = session.entries.first(where: { $0.disposition == .pending })?.key
                    ?? session.entries.first(where: { $0.disposition == .deferred })?.key
            }
        }
        let reconciled = RadioQueueBuilder(now: now()).reconcile(snapshot: session, candidates: candidates)
        let previousCurrentKey = currentKey
        let previousState = state
        if previousCurrentKey != reconciled.currentKey { cancelPendingRequest() }
        install(
            reconciled,
            preservedPlaybackState: previousCurrentKey == reconciled.currentKey ? previousState : nil
        )
        store.saveDebounced(currentSession())

        guard isInitialColdLaunchRefresh, hasPendingColdLaunchAutoplay else { return nil }
        guard let deadline = coldLaunchAutoplayDeadline, now() < deadline else {
            cancelPendingColdLaunchAutoplay()
            return nil
        }
        if result.successfulSourceEvidenceCount > 0,
           let request = requestForCurrent() {
            if canLoad(request.url) {
                cancelPendingColdLaunchAutoplay()
                state = .loading
                return .play(request)
            }
            setPending(request, purpose: .coldLaunchAutoplay)
            state = .waitingForNetwork
            return nil
        }
        if isTerminalInitialRefresh(result) { cancelPendingColdLaunchAutoplay() }
        return nil
    }

    func beginCurrent() -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        guard let request = requestForCurrent() else { return nil }
        cancelPendingRequest()
        guard canLoad(request.url) else { setPending(request, purpose: .userStart); state = .waitingForNetwork; return nil }
        state = .loading
        return .play(request)
    }

    func selectEpisode(_ key: RadioEpisodeKey) -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        cancelPendingRequest()
        var candidate: RadioEpisodeCandidate
        do {
            guard let loaded = try repository.candidate(for: key) else { return nil }
            candidate = loaded
            if candidate.isCompleted {
                guard entries.first(where: { $0.key == key })?.disposition != .failedThisSession,
                      isEligibleForSelection(replayCandidate(from: candidate)) else { return nil }
                guard let restarted = try repository.restartForReplay(key: key) else { return nil }
                candidate = restarted
            }
        } catch {
            return handleReadFailure(error)
        }
        guard entries.first(where: { $0.key == key })?.disposition != .failedThisSession,
              isEligibleForSelection(candidate) else { return nil }
        candidatesByKey[key] = candidate

        let previousCurrent = currentKey.flatMap { current in entries.first(where: { $0.key == current }) }
        let selected = entries.first(where: { $0.key == key })
            ?? RadioQueueEntry(
                key: key,
                positionSeconds: initialPosition(for: candidate),
                disposition: .pending,
                playbackFailureCount: 0,
                lastPlaybackError: nil,
                isManuallyQueued: !isLatestCandidateForSource(candidate)
            )
        var selectedEntry = selected
        selectedEntry.disposition = .pending
        let remaining = entries.filter {
            $0.key != key
                && $0.key != previousCurrent?.key
                && ($0.key.feedID != key.feedID || $0.isManuallyQueued)
        }
        var pending = remaining.filter { $0.disposition == .pending }
        var deferred = remaining.filter { $0.disposition == .deferred }
        let retired = remaining.filter { $0.disposition == .retired }
        if let previousCurrent,
           previousCurrent.key != key,
           isNearlyComplete(
               positionSeconds: previousCurrent.positionSeconds,
               duration: candidatesByKey[previousCurrent.key]?.durationSeconds
           ) {
            guard forceSave(
                positionSeconds: previousCurrent.positionSeconds,
                duration: candidatesByKey[previousCurrent.key]?.durationSeconds
            ) else { return nil }
            let stagedEntries = [selectedEntry] + pending + deferred
                + retired
                + remaining.filter { $0.disposition == .failedThisSession }
            let repaired = PersistedRadioSession(
                schemaVersion: PersistedRadioSession.schemaVersion,
                entries: stagedEntries,
                currentKey: selectedEntry.key,
                savedAt: now()
            )
            return executeCompletionPlan(
                CompletionPlan(
                    completedKey: previousCurrent.key,
                    completedAt: now(),
                    repairedSession: repaired,
                    continuation: .selection
                ),
                markCoreData: true
            )
        }
        let replacesAutomaticSourceSlot = previousCurrent?.key.feedID == key.feedID
            && previousCurrent?.isManuallyQueued == false
        if replacesAutomaticSourceSlot, let previousCurrent {
            do {
                try repository.saveProgress(
                    key: previousCurrent.key,
                    seconds: previousCurrent.positionSeconds,
                    duration: candidatesByKey[previousCurrent.key]?.durationSeconds
                )
            } catch {
                state = .failed(.persistence(error.localizedDescription))
                return nil
            }
        } else if var previousCurrent, previousCurrent.key != key, previousCurrent.positionSeconds > 0 {
            previousCurrent.disposition = .deferred
            deferred.append(previousCurrent)
        } else if let previousCurrent, previousCurrent.key != key {
            var normalized = previousCurrent
            normalized.disposition = .pending
            pending.insert(normalized, at: 0)
        }
        let stagedEntries = [selectedEntry] + pending + deferred + retired
            + remaining.filter { $0.disposition == .failedThisSession }
        let intent = commitSelection(stagedEntries, selected: selectedEntry, candidate: candidate)
        if let intent, case .play(let request) = intent, !canLoad(request.url) {
            setPending(request, purpose: .selection); state = .waitingForNetwork; return nil
        }
        return intent
    }

    func queueEpisode(_ key: RadioEpisodeKey) -> Bool {
        cancelPendingColdLaunchAutoplay()
        let candidate: RadioEpisodeCandidate
        do {
            guard let loaded = try repository.candidate(for: key) else { return false }
            candidate = loaded
        } catch {
            _ = handleReadFailure(error)
            return false
        }
        guard isEligibleForSelection(candidate),
              !entries.contains(where: { $0.key == key }) else { return false }

        candidatesByKey[key] = candidate
        let becomesCurrent = currentKey == nil
        let queued = RadioQueueEntry(
            key: key,
            positionSeconds: initialPosition(for: candidate),
            disposition: becomesCurrent ? .pending : .deferred,
            playbackFailureCount: 0,
            lastPlaybackError: nil,
            isManuallyQueued: true
        )
        let stagedEntries = entries + [queued]
        let stagedCurrent = currentKey ?? key
        let staged = PersistedRadioSession(
            schemaVersion: PersistedRadioSession.schemaVersion,
            entries: stagedEntries,
            currentKey: stagedCurrent,
            savedAt: now()
        )
        do {
            try store.saveNow(staged)
        } catch {
            state = .failed(.persistence(error.localizedDescription))
            return false
        }
        entries = stagedEntries
        currentKey = stagedCurrent
        currentEpisode = candidatesByKey[stagedCurrent]
        updateCanPlayNext()
        if becomesCurrent { state = .readyPaused }
        return true
    }

    func recordProgress(for key: RadioEpisodeKey, positionSeconds: TimeInterval, duration: TimeInterval?) {
        guard key == currentKey else { return }
        let sanitizedPosition = validPosition(positionSeconds)
        let bucket = Int(sanitizedPosition / 5)
        if lastProgressBucket == nil {
            let initial = entries.first(where: { $0.key == key }).map { Int($0.positionSeconds / 5) } ?? bucket
            lastProgressBucket = (key, initial)
        }
        guard lastProgressBucket?.key != key || lastProgressBucket?.bucket != bucket else { return }
        guard updateCurrentPosition(sanitizedPosition) else { return }
        lastProgressBucket = (key, bucket)
        store.saveDebounced(currentSession())
        _ = persistProgress(positionSeconds: sanitizedPosition, duration: duration)
    }

    func transportDidStart(for key: RadioEpisodeKey) {
        guard key == currentKey else { return }
        if let index = entries.firstIndex(where: { $0.key == key }) {
            entries[index].disposition = .playing
        }
        state = .playing
    }

    func pauseByUser(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        cancelPendingRequest()
        let saved = forceSave(positionSeconds: positionSeconds, duration: duration)
        if saved { state = .pausedByUser }
        return .pause
    }

    func seekEnded(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        lastProgressBucket = nil
        forceSave(positionSeconds: positionSeconds, duration: duration)
        return nil
    }

    func manualNext(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        cancelPendingRequest()
        if sleepTimer == .endOfEpisode { sleepTimer = .off }
        guard let currentKey, let current = entries.first(where: { $0.key == currentKey }) else { return nil }
        if isNearlyComplete(positionSeconds: positionSeconds, duration: duration) {
            guard forceSave(positionSeconds: positionSeconds, duration: duration) else { return nil }
            return completeCurrent(at: now())
        }
        var retiredOrDeferred = current
        retiredOrDeferred.positionSeconds = validPosition(positionSeconds)
        let retiresHourlySource = candidatesByKey[currentKey]?.sourceFrequency == .hourly
            && !current.isManuallyQueued
        retiredOrDeferred.disposition = retiresHourlySource ? .retired : .deferred
        let remaining = entries.filter { $0.key != currentKey }
        var stagedEntries = remaining.filter { $0.disposition == .pending }
            + remaining.filter { $0.disposition == .deferred }
        stagedEntries.append(retiredOrDeferred)
        stagedEntries += remaining.filter { $0.disposition == .retired }
        stagedEntries += remaining.filter { $0.disposition == .failedThisSession }
        let next = stagedEntries.first(where: { $0.disposition == .pending })
            ?? stagedEntries.first(where: { $0.disposition == .deferred && $0.key != currentKey })
        let staged = PersistedRadioSession(
            schemaVersion: PersistedRadioSession.schemaVersion,
            entries: stagedEntries,
            currentKey: next?.key,
            savedAt: now()
        )
        do {
            try repository.saveProgress(key: currentKey, seconds: retiredOrDeferred.positionSeconds, duration: duration)
            try store.saveNow(staged)
        } catch { state = .failed(.persistence(error.localizedDescription)); return nil }
        guard let next, let candidate = candidatesByKey[next.key] else {
            entries = stagedEntries
            self.currentKey = nil
            currentEpisode = nil
            updateCanPlayNext()
            state = .exhausted
            return .pause
        }
        entries = stagedEntries; self.currentKey = next.key; currentEpisode = candidate; updateCanPlayNext(); state = .loading
        let request = playbackRequest(for: candidate, position: next.positionSeconds)
        lastProgressBucket = nil
        guard canLoad(request.url) else { setPending(request, purpose: .advance); state = .waitingForNetwork; return nil }
        return .play(request)
    }

    func playbackCompleted(for key: RadioEpisodeKey, at date: Date) -> RadioPlaybackIntent? {
        guard key == currentKey else { return nil }
        cancelPendingColdLaunchAutoplay()
        cancelPendingRequest()
        return completeCurrent(at: date)
    }

    private func completeCurrent(at date: Date) -> RadioPlaybackIntent? {
        guard let currentKey else { return nil }
        let remaining = entries.filter { $0.key != currentKey }
        let nextKey = remaining.first(where: { $0.disposition == .pending })?.key
            ?? remaining.first(where: { $0.disposition == .deferred })?.key
        let isEOE = sleepTimer == .endOfEpisode
        let staged = PersistedRadioSession(schemaVersion: PersistedRadioSession.schemaVersion, entries: remaining, currentKey: nextKey, savedAt: now())
        return executeCompletionPlan(
            CompletionPlan(
                completedKey: currentKey,
                completedAt: date,
                repairedSession: staged,
                continuation: .advance(endOfEpisode: isEOE)
            ),
            markCoreData: true
        )
    }

    private func executeCompletionPlan(_ plan: CompletionPlan, markCoreData: Bool) -> RadioPlaybackIntent? {
        if markCoreData {
            completionRecovery = .markCoreData(plan)
            do {
                try repository.markCompleted(key: plan.completedKey, at: plan.completedAt)
            } catch {
                state = .failed(.persistence(error.localizedDescription))
                return nil
            }
            applyAuthoritativeCompletion(plan)
            completionRecovery = .saveSnapshot(plan)
        }

        do {
            try store.saveNow(plan.repairedSession)
        } catch {
            state = .failed(.persistence(error.localizedDescription))
            return nil
        }
        completionRecovery = nil
        return continueAfterCompletion(plan)
    }

    private func applyAuthoritativeCompletion(_ plan: CompletionPlan) {
        entries = plan.repairedSession.entries
        currentKey = plan.repairedSession.currentKey
        candidatesByKey.removeValue(forKey: plan.completedKey)
        currentEpisode = currentKey.flatMap { candidatesByKey[$0] }
        updateCanPlayNext()
        lastProgressBucket = nil
    }

    private func continueAfterCompletion(_ plan: CompletionPlan) -> RadioPlaybackIntent? {
        if case .advance(let endOfEpisode) = plan.continuation, endOfEpisode {
            sleepTimer = .off
            state = currentEpisode == nil ? .exhausted : .readyPaused
            return nil
        }
        guard let candidate = currentEpisode,
              let entry = entries.first(where: { $0.key == candidate.key }) else {
            state = .exhausted
            return nil
        }
        state = .loading
        let request = playbackRequest(for: candidate, position: entry.positionSeconds)
        let purpose: PendingPurpose
        if case .selection = plan.continuation { purpose = .selection }
        else { purpose = .advance }
        guard canLoad(request.url) else { setPending(request, purpose: purpose); state = .waitingForNetwork; return nil }
        return .play(request)
    }

    func playbackFailed(for key: RadioEpisodeKey, message: String, positionSeconds: TimeInterval, duration: TimeInterval?, connectivity: ConnectivityStatus) -> RadioPlaybackIntent? {
        guard key == currentKey else { return nil }
        _ = updateCurrentPosition(positionSeconds)
        cancelPendingRequest()
        guard connectivity == .online else {
            guard forceSave(positionSeconds: positionSeconds, duration: duration) else { return nil }
            if let request = requestForCurrent() { setPending(request, purpose: .networkRecovery) }
            state = .waitingForNetwork
            return nil
        }
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        entries[index].playbackFailureCount += 1
        entries[index].lastPlaybackError = message
        if entries[index].playbackFailureCount < 2 {
            guard forceSave(positionSeconds: positionSeconds, duration: duration), let request = requestForCurrent() else { return nil }
            setPending(request, purpose: .automaticRetry)
            state = .loading
            schedulePendingIfPossible()
            return nil
        }

        entries[index].disposition = .failedThisSession
        let nextKey = RadioQueueBuilder(now: now()).nextEligible(in: currentSession())
        let persistedCurrent = nextKey ?? key
        let staged = PersistedRadioSession(schemaVersion: PersistedRadioSession.schemaVersion, entries: entries, currentKey: persistedCurrent, savedAt: now())
        do {
            try repository.saveProgress(key: key, seconds: validPosition(positionSeconds), duration: duration)
            try store.saveNow(staged)
        } catch {
            state = .failed(.persistence(error.localizedDescription))
            return nil
        }
        guard let nextKey, let candidate = candidatesByKey[nextKey] else {
            currentKey = key
            currentEpisode = candidatesByKey[key]
            updateCanPlayNext()
            state = .failed(.playback(message))
            return nil
        }
        currentKey = nextKey
        currentEpisode = candidate
        updateCanPlayNext()
        lastProgressBucket = nil
        state = .loading
        let request = playbackRequest(for: candidate, position: entries.first(where: { $0.key == nextKey })?.positionSeconds ?? 0)
        guard canLoad(request.url) else { setPending(request, purpose: .advance); state = .waitingForNetwork; return nil }
        return .play(request)
    }

    func retry() -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        cancelPendingRequest()
        if let completionRecovery {
            switch completionRecovery {
            case .markCoreData(let plan):
                return executeCompletionPlan(plan, markCoreData: true)
            case .saveSnapshot(let plan):
                return executeCompletionPlan(plan, markCoreData: false)
            }
        }
        guard case .failed(.persistence) = state else {
            return resetAndRetryCurrent()
        }
        return nil
    }

    private func resetAndRetryCurrent() -> RadioPlaybackIntent? {
        guard let currentKey, let index = entries.firstIndex(where: { $0.key == currentKey }) else { return nil }
        entries[index].playbackFailureCount = 0
        entries[index].lastPlaybackError = nil
        entries[index].disposition = .pending
        guard forceSave(positionSeconds: entries[index].positionSeconds, duration: currentEpisode?.durationSeconds) else { return nil }
        guard let request = requestForCurrent() else { return nil }
        guard canLoad(request.url) else { setPending(request, purpose: .userStart); state = .waitingForNetwork; return nil }
        state = .loading
        return .play(request)
    }

    func setSleepTimer(_ timer: RadioSleepTimer) {
        cancelPendingColdLaunchAutoplay()
        sleepTimer = timer
    }

    func evaluateSleepTimer(at date: Date, positionSeconds: TimeInterval? = nil, duration: TimeInterval? = nil) -> RadioPlaybackIntent? {
        guard case .deadline(let deadline) = sleepTimer, date >= deadline else { return nil }
        sleepTimer = .off
        cancelPendingRequest()
        let saved = forceSave(positionSeconds: positionSeconds, duration: duration)
        if saved { state = .pausedByUser }
        // A deadline must pause transport even when persistence is unavailable.
        return .pause
    }

    func handleInterruptionBegan(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent? {
        interruptionResumeEligible = state == .playing || state == .loading
        cancelPendingColdLaunchAutoplay()
        cancelPendingRequest()
        let saved = forceSave(positionSeconds: positionSeconds, duration: duration)
        if saved { state = .pausedByUser }
        else { interruptionResumeEligible = false }
        return .pause
    }

    func handleInterruptionEnded(shouldResume: Bool) -> RadioPlaybackIntent? {
        let eligible = interruptionResumeEligible
        interruptionResumeEligible = false
        guard shouldResume, eligible, let request = requestForCurrent() else { return nil }
        guard canLoad(request.url) else {
            setPending(request, purpose: .interruptionResume)
            state = .waitingForNetwork
            return nil
        }
        state = .loading
        return .play(request)
    }

    func handleRouteRemoval(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay()
        cancelPendingRequest()
        let saved = forceSave(positionSeconds: positionSeconds, duration: duration)
        if saved { state = .pausedByUser }
        return .pause
    }

    func handleBackground(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay(); cancelPendingRequest(); forceSave(positionSeconds: positionSeconds, duration: duration); return nil
    }

    func handleTermination(positionSeconds: TimeInterval, duration: TimeInterval?) -> RadioPlaybackIntent? {
        cancelPendingColdLaunchAutoplay(); cancelPendingRequest(); forceSave(positionSeconds: positionSeconds, duration: duration); return nil
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
        if pendingRequest?.purpose == .coldLaunchAutoplay { cancelPendingRequest() }
    }

    private func connectivityChanged(_ status: ConnectivityStatus) {
        if status != .online, pendingRequest != nil || currentEpisode == nil {
            retryScheduler.cancel()
            state = .waitingForNetwork
            return
        }
        guard status == .online else { return }
        if pendingRequest != nil { schedulePendingIfPossible() }
        else if currentEpisode == nil { state = resolveNoPlayableEntry() }
    }

    private func setPending(_ request: RadioPlaybackRequest, purpose: PendingPurpose) {
        cancelPendingRequest()
        pendingGeneration &+= 1
        pendingRequest = PendingRequest(request: request, purpose: purpose, generation: pendingGeneration)
    }

    private func schedulePendingIfPossible() {
        guard let pending = pendingRequest else { return }
        if pending.purpose == .coldLaunchAutoplay,
           (!hasPendingColdLaunchAutoplay || coldLaunchAutoplayDeadline.map({ now() >= $0 }) != false) {
            cancelPendingColdLaunchAutoplay()
            return
        }
        guard
              pending.request.key == currentKey,
              requestForCurrent()?.key == pending.request.key,
              canLoad(pending.request.url) else { return }
        let generation = pending.generation
        let key = pending.request.key
        retryScheduler.schedule(after: 0.5) { [weak self] in
            guard let self, let active = self.pendingRequest,
                  active.generation == generation, active.request.key == key,
                  self.currentKey == key, self.requestForCurrent()?.key == key,
                  self.canLoad(active.request.url) else { return }
            if active.purpose == .coldLaunchAutoplay,
               (!self.hasPendingColdLaunchAutoplay || self.coldLaunchAutoplayDeadline.map({ self.now() >= $0 }) != false) {
                self.cancelPendingColdLaunchAutoplay()
                return
            }
            self.pendingRequest = nil
            if active.purpose == .coldLaunchAutoplay {
                self.hasPendingColdLaunchAutoplay = false
                self.coldLaunchAutoplayDeadline = nil
            }
            self.state = .loading
            self.pendingNetworkIntentSubject.send(.play(active.request))
        }
    }

    private func cancelPendingRequest() {
        pendingGeneration &+= 1
        pendingRequest = nil
        retryScheduler.cancel()
    }

    @discardableResult
    private func forceSave(positionSeconds: TimeInterval?, duration: TimeInterval?) -> Bool {
        if let positionSeconds { _ = updateCurrentPosition(positionSeconds) }
        if let positionSeconds, !persistProgress(positionSeconds: positionSeconds, duration: duration) { return false }
        do {
            try store.saveNow(currentSession())
            return true
        } catch {
            state = .failed(.persistence(error.localizedDescription))
            return false
        }
    }

    private func persistProgress(positionSeconds: TimeInterval, duration: TimeInterval?) -> Bool {
        guard let currentKey else { return true }
        do { try repository.saveProgress(key: currentKey, seconds: positionSeconds, duration: duration) }
        catch { state = .failed(.persistence(error.localizedDescription)); return false }
        return true
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

    private func install(_ session: PersistedRadioSession, preservedPlaybackState: RadioSessionState? = nil) {
        entries = session.entries
        currentKey = session.currentKey
        currentEpisode = currentKey.flatMap { candidatesByKey[$0] }
        lastProgressBucket = currentKey.flatMap { key in
            entries.first(where: { $0.key == key }).map { (key, Int($0.positionSeconds / 5)) }
        }
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
              entry.disposition != .failedThisSession,
              entry.disposition != .retired,
              !candidate.isCompleted else { return nil }
        return playbackRequest(for: candidate, position: entry.positionSeconds)
    }

    private func canLoad(_ url: URL) -> Bool {
        if url.isFileURL { return FileManager.default.isReadableFile(atPath: url.path) }
        return connectivityStatus() == .online
    }

    private func playbackRequest(for candidate: RadioEpisodeCandidate, position: TimeInterval) -> RadioPlaybackRequest {
        RadioPlaybackRequest(
            key: candidate.key,
            url: candidate.originalPlaybackURL,
            title: candidate.displayTitle(),
            source: candidate.sourceName,
            positionSeconds: position
        )
    }

    private func initialPosition(for candidate: RadioEpisodeCandidate) -> TimeInterval {
        guard let duration = candidate.durationSeconds, duration.isFinite, duration > 0,
              candidate.normalizedCoreDataProgress.isFinite else { return 0 }
        return min(max(candidate.normalizedCoreDataProgress, 0), 1) * duration
    }

    private func replayCandidate(from candidate: RadioEpisodeCandidate) -> RadioEpisodeCandidate {
        RadioEpisodeCandidate(
            key: candidate.key,
            originalPlaybackURL: candidate.originalPlaybackURL,
            canonicalEnclosureURL: candidate.canonicalEnclosureURL,
            title: candidate.title,
            sourceName: candidate.sourceName,
            publicationDate: candidate.publicationDate,
            durationSeconds: candidate.durationSeconds,
            normalizedCoreDataProgress: 0,
            isCompleted: false,
            sourcePriority: candidate.sourcePriority,
            sourceFrequency: candidate.sourceFrequency
        )
    }

    private func isEligibleForSelection(_ candidate: RadioEpisodeCandidate) -> Bool {
        guard !candidate.isCompleted else { return false }
        guard !entries.contains(where: {
            $0.key != candidate.key && candidatesByKey[$0.key]?.canonicalEnclosureURL == candidate.canonicalEnclosureURL
        }) else { return false }
        return RadioQueueBuilder(now: now()).isEligibleForManualSelection(candidate)
    }

    private func isLatestCandidateForSource(_ candidate: RadioEpisodeCandidate) -> Bool {
        !candidatesByKey.values.contains {
            $0.key.feedID == candidate.key.feedID
                && ($0.publicationDate > candidate.publicationDate
                    || ($0.publicationDate == candidate.publicationDate && $0.key.episodeID < candidate.key.episodeID))
        }
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
