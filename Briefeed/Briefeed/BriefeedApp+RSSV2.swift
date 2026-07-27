//
//  BriefeedApp+RSSV2.swift
//  Briefeed
//
//  Radio startup and scene lifecycle ownership.
//

import Combine
import SwiftUI

enum RadioStartupPolicy {
    static func shouldStartServices(for phase: ScenePhase) -> Bool {
        switch phase {
        case .active:
            true
        case .inactive, .background:
            false
        @unknown default:
            false
        }
    }
}

@MainActor
final class RadioAppLifecycleDriver {
    typealias Sleep = @MainActor (TimeInterval) async throws -> Void
    typealias SettleActiveScene = @MainActor () async -> Void

    enum SaveReason {
        case background
        case termination
    }

    struct RefreshWork {
        let begin: @MainActor () -> Void
        let load: @MainActor () async -> RSSRefreshBatchResult
        let apply: @MainActor (RSSRefreshBatchResult) async -> Void

        init(
            begin: @escaping @MainActor () -> Void = {},
            load: @escaping @MainActor () async -> RSSRefreshBatchResult,
            apply: @escaping @MainActor (RSSRefreshBatchResult) async -> Void = { _ in }
        ) {
            self.begin = begin
            self.load = load
            self.apply = apply
        }
    }

    private struct PendingRefresh {
        let generation: Int
        let work: RefreshWork
    }

    private static let pollInterval: TimeInterval = 15 * 60
    private static let radioHomeRefreshDebounce: TimeInterval = 60

    private let connectivity: ConnectivityMonitoring
    private let now: @MainActor () -> Date
    private let sleep: Sleep
    private let settleActiveScene: SettleActiveScene
    private let cancelPendingColdLaunchAutoplay: @MainActor () -> Void
    private let forceSave: @MainActor (SaveReason) -> Void
    private var connectivityCancellable: AnyCancellable?
    private var pendingRefresh: PendingRefresh?
    private var refreshTask: Task<Void, Never>?
    private var inFlightRefreshID: UUID?
    private var pollTask: Task<Void, Never>?
    private var pollID: UUID?
    private var initialRefreshWork: RefreshWork?
    private var foregroundRefreshWork: RefreshWork?
    private var pollRefreshWork: RefreshWork?
    private var generation = 0
    private var didStartColdLaunch = false
    private var didFinishRestore = false
    private var didRequestInitialRefresh = false
    private var coldLaunchAutoplayAllowed = true
    private var hasObservedActiveScene = false
    private var isActive = false
    private var isInInactiveSequence = false
    private var didTerminate = false
    private var lastOpeningRefreshRequestAt: Date?
    private var pendingRestoreProjection: (@MainActor () async -> Void)?
    private var restoreProjectionTask: Task<Void, Never>?

    var hasPendingRefresh: Bool { pendingRefresh != nil }
    var hasInFlightRefresh: Bool { inFlightRefreshID != nil }
    var hasActivePoll: Bool { pollTask != nil }

    init(
        connectivity: ConnectivityMonitoring,
        now: @escaping @MainActor () -> Date = Date.init,
        sleep: @escaping Sleep = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        },
        settleActiveScene: @escaping SettleActiveScene = {
            try? await Task.sleep(for: .milliseconds(300))
        },
        cancelPendingColdLaunchAutoplay: @escaping @MainActor () -> Void,
        forceSave: @escaping @MainActor (SaveReason) -> Void
    ) {
        self.connectivity = connectivity
        self.now = now
        self.sleep = sleep
        self.settleActiveScene = settleActiveScene
        self.cancelPendingColdLaunchAutoplay = cancelPendingColdLaunchAutoplay
        self.forceSave = forceSave
        connectivityCancellable = connectivity.statusPublisher.sink { [weak self] status in
            self?.connectivityChanged(status)
        }
    }

    func startColdLaunch(
        prepare: @escaping @MainActor () async -> Void = {},
        restore: @escaping @MainActor (Bool) async -> RadioPlaybackIntent?,
        applyRestoreIntent: @escaping @MainActor (RadioPlaybackIntent?) async -> Void = { _ in },
        initialRefresh: RefreshWork,
        foregroundRefresh: RefreshWork,
        pollRefresh: RefreshWork? = nil
    ) async {
        // Let the first active callback settle before consuming the one
        // cold-launch autoplay evaluation. iOS can immediately follow that
        // callback with a transient inactive transition during presentation.
        guard isActive || !coldLaunchAutoplayAllowed else { return }
        guard !didStartColdLaunch, !didTerminate else { return }
        if coldLaunchAutoplayAllowed {
            let settleGeneration = generation
            await settleActiveScene()
            guard isActive,
                  settleGeneration == generation,
                  !didStartColdLaunch,
                  !didTerminate else { return }
        }
        didStartColdLaunch = true

        await prepare()
        guard !didTerminate else { return }

        initialRefreshWork = initialRefresh
        foregroundRefreshWork = foregroundRefresh
        pollRefreshWork = pollRefresh ?? foregroundRefresh

        let restoreGeneration = generation
        let restoreIntent = await restore(coldLaunchAutoplayAllowed)
        guard !didTerminate else { return }
        didFinishRestore = true

        guard restoreGeneration == generation, isActive else {
            cancelPendingColdLaunchAutoplay()
            pendingRestoreProjection = { await applyRestoreIntent(nil) }
            applyPendingRestoreProjectionIfActive()
            recoverFromStaleRestoreIfActive()
            return
        }
        await applyRestoreIntent(restoreIntent)
        guard restoreGeneration == generation, isActive, !didTerminate else { return }

        requestInitialRefreshIfNeeded()
        armPollIfNeeded()
    }

    func requestStaleRefreshWhenOnline(now: Date, operation: RefreshWork) {
        guard isActive, !didTerminate, pendingRefresh == nil else { return }
        _ = now
        pendingRefresh = PendingRefresh(generation: generation, work: operation)
        launchPendingRefreshIfPossible()
    }

    func handleRadioHomeAppeared() {
        guard isActive,
              didFinishRestore,
              didRequestInitialRefresh,
              !didTerminate,
              let foregroundRefreshWork else { return }
        let requestedAt = now()
        if let lastOpeningRefreshRequestAt,
           requestedAt.timeIntervalSince(lastOpeningRefreshRequestAt)
            < Self.radioHomeRefreshDebounce {
            return
        }
        requestOpeningRefresh(requestedAt, operation: foregroundRefreshWork)
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            guard !isActive, !didTerminate else { return }
            isActive = true
            isInInactiveSequence = false
            let isForegroundReturn = hasObservedActiveScene
            hasObservedActiveScene = true

            applyPendingRestoreProjectionIfActive()

            if didFinishRestore {
                if !didRequestInitialRefresh {
                    requestInitialRefreshIfNeeded()
                } else if isForegroundReturn, let foregroundRefreshWork {
                    requestOpeningRefresh(now(), operation: foregroundRefreshWork)
                }
            }
            armPollIfNeeded()

        case .inactive:
            // Inactive is still a foreground scene. Launch animations,
            // iPhone Mirroring focus, system overlays, and interruptions can
            // all produce this phase without sending the app to background.
            // Waiting for `.background` keeps the opening refresh and its
            // autoplay opportunity alive through those transient changes.
            break

        case .background:
            coldLaunchAutoplayAllowed = false
            guard !isInInactiveSequence, !didTerminate else { return }
            isInInactiveSequence = true
            isActive = false
            cancelLifecycleWork()
            cancelPendingColdLaunchAutoplay()
            forceSave(.background)

        @unknown default:
            break
        }
    }

    func handleTermination() {
        guard !didTerminate else { return }
        didTerminate = true
        isActive = false
        isInInactiveSequence = true
        coldLaunchAutoplayAllowed = false
        cancelLifecycleWork()
        restoreProjectionTask?.cancel()
        restoreProjectionTask = nil
        pendingRestoreProjection = nil
        cancelPendingColdLaunchAutoplay()
        forceSave(.termination)
    }

    private func requestInitialRefreshIfNeeded() {
        guard !didRequestInitialRefresh else { return }
        didRequestInitialRefresh = true
        if coldLaunchAutoplayAllowed, let initialRefreshWork {
            requestOpeningRefresh(now(), operation: initialRefreshWork)
        } else if let foregroundRefreshWork {
            requestOpeningRefresh(now(), operation: foregroundRefreshWork)
        }
    }

    private func recoverFromStaleRestoreIfActive() {
        guard isActive, !didTerminate else { return }
        didRequestInitialRefresh = true
        if let foregroundRefreshWork {
            requestOpeningRefresh(now(), operation: foregroundRefreshWork)
        }
        armPollIfNeeded()
    }

    private func requestOpeningRefresh(_ requestedAt: Date, operation: RefreshWork) {
        guard isActive, !didTerminate, pendingRefresh == nil else { return }
        lastOpeningRefreshRequestAt = requestedAt
        requestStaleRefreshWhenOnline(now: requestedAt, operation: operation)
    }

    private func applyPendingRestoreProjectionIfActive() {
        guard isActive, !didTerminate, let projection = pendingRestoreProjection else { return }
        pendingRestoreProjection = nil
        restoreProjectionTask?.cancel()
        restoreProjectionTask = Task { @MainActor in await projection() }
    }

    private func connectivityChanged(_ status: ConnectivityStatus) {
        guard status == .online else { return }
        launchPendingRefreshIfPossible()
    }

    private func launchPendingRefreshIfPossible() {
        guard isActive,
              !didTerminate,
              connectivity.status == .online,
              inFlightRefreshID == nil,
              let pendingRefresh,
              pendingRefresh.generation == generation else { return }

        self.pendingRefresh = nil
        let id = UUID()
        let taskGeneration = generation
        let work = pendingRefresh.work
        inFlightRefreshID = id
        work.begin()
        refreshTask = Task { @MainActor [weak self] in
            let result = await work.load()
            let wasCancelled = Task.isCancelled
            await self?.finishRefresh(
                id: id,
                generation: taskGeneration,
                result: result,
                work: work,
                wasCancelled: wasCancelled
            )
        }
    }

    private func finishRefresh(
        id: UUID,
        generation taskGeneration: Int,
        result: RSSRefreshBatchResult,
        work: RefreshWork,
        wasCancelled: Bool
    ) async {
        guard id == inFlightRefreshID else { return }
        let shouldApply = !wasCancelled
            && taskGeneration == generation
            && isActive
            && !didTerminate
        if shouldApply {
            await work.apply(result)
        }
        guard id == inFlightRefreshID else { return }
        inFlightRefreshID = nil
        refreshTask = nil
        launchPendingRefreshIfPossible()
    }

    private func armPollIfNeeded() {
        guard isActive,
              didFinishRestore,
              pollRefreshWork != nil,
              pollTask == nil,
              !didTerminate else { return }

        let id = UUID()
        let taskGeneration = generation
        pollID = id
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await self.sleep(Self.pollInterval)
                } catch {
                    break
                }
                guard !Task.isCancelled,
                      taskGeneration == self.generation,
                      self.isActive,
                      let pollRefreshWork = self.pollRefreshWork else { break }
                self.requestStaleRefreshWhenOnline(now: self.now(), operation: pollRefreshWork)
            }
            self.finishPoll(id: id)
        }
    }

    private func finishPoll(id: UUID) {
        guard id == pollID else { return }
        pollID = nil
        pollTask = nil
    }

    private func cancelLifecycleWork() {
        generation += 1
        pendingRefresh = nil
        refreshTask?.cancel()
        pollTask?.cancel()
        pollTask = nil
        pollID = nil
    }
}

// MARK: - Radio App Initialization
extension BriefeedApp {
    #if DEBUG
    func startRadioFixtureSession() async {
        guard let definition = AppRuntime.radioFixtureDefinition else { return }
        let services = RadioServiceContainer.shared
        let restoreIntent = await services.coordinator.restore(
            autoplayEnabled: UserDefaultsManager.shared.autoPlayLiveNewsOnOpen
        )
        await UnifiedAudioPlayer.shared.execute(restoreIntent)
        RadioFixtureDiagnostics.shared.recordBootstrapExecution(of: restoreIntent)
        let postRestoreIntent = definition.applyPostRestore(to: services.coordinator)
        await UnifiedAudioPlayer.shared.execute(postRestoreIntent)
        RadioFixtureDiagnostics.shared.recordBootstrapExecution(of: postRestoreIntent)
        if AppRuntime.shouldCompleteRadioFixtureCurrent,
           let currentKey = services.coordinator.currentKey {
            let completionIntent = services.coordinator.playbackCompleted(
                for: currentKey,
                at: AppRuntime.radioFixtureNow
            )
            await UnifiedAudioPlayer.shared.execute(completionIntent)
        }
        print("🧪 Radio fixture ready: \(definition.scenario.rawValue)")
    }
    #endif

    func startRadioServices() async {
        let services = RadioServiceContainer.shared

        await radioLifecycleDriver.startColdLaunch(
            prepare: {
                _ = await RSSAudioService.shared.ensureDefaultFeedsExist()
            },
            restore: { autoplayAllowed in
                await services.coordinator.restore(
                    autoplayEnabled: autoplayAllowed
                        && UserDefaultsManager.shared.autoPlayLiveNewsOnOpen
                )
            },
            applyRestoreIntent: { intent in
                await UnifiedAudioPlayer.shared.execute(intent)
            },
            initialRefresh: makeRadioRefreshWork(
                useInitialAutoplayOpportunity: true,
                forceNetworkRefresh: true
            ),
            foregroundRefresh: makeRadioRefreshWork(
                useInitialAutoplayOpportunity: false,
                forceNetworkRefresh: true
            ),
            pollRefresh: makeRadioRefreshWork(
                useInitialAutoplayOpportunity: false,
                forceNetworkRefresh: false
            )
        )
    }

    func handleScenePhase(_ phase: ScenePhase) {
        radioLifecycleDriver.handleScenePhase(phase)
    }

    func handleRadioHomeAppeared() {
        radioLifecycleDriver.handleRadioHomeAppeared()
    }

    private func makeRadioRefreshWork(
        useInitialAutoplayOpportunity: Bool,
        forceNetworkRefresh: Bool
    ) -> RadioAppLifecycleDriver.RefreshWork {
        let services = RadioServiceContainer.shared
        return RadioAppLifecycleDriver.RefreshWork(
            begin: {
                services.coordinator.refreshStarted(
                    enabledSourceCount: RSSAudioService.shared.enabledFeedCount
                )
            },
            load: {
                let now = Date()
                return forceNetworkRefresh
                    ? await RSSAudioService.shared.refreshAll(now: now)
                    : await RSSAudioService.shared.refreshIfStale(now: now)
            },
            apply: { result in
                let intent = useInitialAutoplayOpportunity
                    ? services.coordinator.applyInitialRefresh(result)
                    : services.coordinator.applyRefresh(
                        result,
                        autoplayWhenIdle:
                            UserDefaultsManager.shared.autoPlayLiveNewsOnOpen
                            && !UnifiedAudioPlayer.shared.isPlaying
                            && UnifiedAudioPlayer.shared.activeMode != .brief
                    )
                await UnifiedAudioPlayer.shared.execute(intent)
            }
        )
    }
}
