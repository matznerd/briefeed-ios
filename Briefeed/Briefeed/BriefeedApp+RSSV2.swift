//
//  BriefeedApp+RSSV2.swift
//  Briefeed
//
//  Radio startup and scene lifecycle ownership.
//

import Combine
import SwiftUI

@MainActor
final class RadioAppLifecycleDriver {
    typealias Sleep = @MainActor (TimeInterval) async throws -> Void

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

    private let connectivity: ConnectivityMonitoring
    private let now: @MainActor () -> Date
    private let sleep: Sleep
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
    private var generation = 0
    private var didStartColdLaunch = false
    private var didFinishRestore = false
    private var didRequestInitialRefresh = false
    private var coldLaunchAutoplayAllowed = true
    private var hasObservedActiveScene = false
    private var isActive = false
    private var isInInactiveSequence = false
    private var didTerminate = false

    var hasPendingRefresh: Bool { pendingRefresh != nil }
    var hasInFlightRefresh: Bool { inFlightRefreshID != nil }
    var hasActivePoll: Bool { pollTask != nil }

    init(
        connectivity: ConnectivityMonitoring,
        now: @escaping @MainActor () -> Date = Date.init,
        sleep: @escaping Sleep = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        },
        cancelPendingColdLaunchAutoplay: @escaping @MainActor () -> Void,
        forceSave: @escaping @MainActor (SaveReason) -> Void
    ) {
        self.connectivity = connectivity
        self.now = now
        self.sleep = sleep
        self.cancelPendingColdLaunchAutoplay = cancelPendingColdLaunchAutoplay
        self.forceSave = forceSave
        connectivityCancellable = connectivity.statusPublisher.sink { [weak self] status in
            self?.connectivityChanged(status)
        }
    }

    func startColdLaunch(
        restore: @escaping @MainActor (Bool) async -> RadioPlaybackIntent?,
        applyRestoreIntent: @escaping @MainActor (RadioPlaybackIntent?) async -> Void = { _ in },
        initialRefresh: RefreshWork,
        foregroundRefresh: RefreshWork
    ) async {
        guard !didStartColdLaunch, !didTerminate else { return }
        didStartColdLaunch = true
        initialRefreshWork = initialRefresh
        foregroundRefreshWork = foregroundRefresh

        let restoreGeneration = generation
        let restoreIntent = await restore(coldLaunchAutoplayAllowed)
        guard !didTerminate else { return }
        didFinishRestore = true

        guard restoreGeneration == generation, isActive else {
            cancelPendingColdLaunchAutoplay()
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

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            guard !isActive, !didTerminate else { return }
            isActive = true
            isInInactiveSequence = false
            let isForegroundReturn = hasObservedActiveScene
            hasObservedActiveScene = true

            if didFinishRestore {
                if !didRequestInitialRefresh {
                    requestInitialRefreshIfNeeded()
                } else if isForegroundReturn, let foregroundRefreshWork {
                    requestStaleRefreshWhenOnline(now: now(), operation: foregroundRefreshWork)
                }
            }
            armPollIfNeeded()

        case .inactive, .background:
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
        cancelPendingColdLaunchAutoplay()
        forceSave(.termination)
    }

    private func requestInitialRefreshIfNeeded() {
        guard !didRequestInitialRefresh else { return }
        didRequestInitialRefresh = true
        if coldLaunchAutoplayAllowed, let initialRefreshWork {
            requestStaleRefreshWhenOnline(now: now(), operation: initialRefreshWork)
        } else if let foregroundRefreshWork {
            requestStaleRefreshWhenOnline(now: now(), operation: foregroundRefreshWork)
        }
    }

    private func recoverFromStaleRestoreIfActive() {
        guard isActive, !didTerminate else { return }
        didRequestInitialRefresh = true
        if let foregroundRefreshWork {
            requestStaleRefreshWhenOnline(now: now(), operation: foregroundRefreshWork)
        }
        armPollIfNeeded()
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
              foregroundRefreshWork != nil,
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
                      let foregroundRefreshWork = self.foregroundRefreshWork else { break }
                self.requestStaleRefreshWhenOnline(now: self.now(), operation: foregroundRefreshWork)
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
    func startRadioServices() async {
        let services = RadioServiceContainer.shared
        _ = await RSSAudioService.shared.ensureDefaultFeedsExist()

        await radioLifecycleDriver.startColdLaunch(
            restore: { autoplayAllowed in
                await services.coordinator.restore(
                    autoplayEnabled: autoplayAllowed
                        && UserDefaultsManager.shared.autoPlayLiveNewsOnOpen
                )
            },
            applyRestoreIntent: { intent in
                await UnifiedAudioPlayer.shared.execute(intent)
            },
            initialRefresh: makeRadioRefreshWork(useInitialAutoplayOpportunity: true),
            foregroundRefresh: makeRadioRefreshWork(useInitialAutoplayOpportunity: false)
        )
    }

    func handleScenePhase(_ phase: ScenePhase) {
        radioLifecycleDriver.handleScenePhase(phase)
    }

    private func makeRadioRefreshWork(useInitialAutoplayOpportunity: Bool) -> RadioAppLifecycleDriver.RefreshWork {
        let services = RadioServiceContainer.shared
        return RadioAppLifecycleDriver.RefreshWork(
            begin: {
                services.coordinator.refreshStarted(
                    enabledSourceCount: RSSAudioService.shared.enabledFeedCount
                )
            },
            load: {
                await RSSAudioService.shared.refreshIfStale(now: Date())
            },
            apply: { result in
                let intent = useInitialAutoplayOpportunity
                    ? services.coordinator.applyInitialRefresh(result)
                    : services.coordinator.applyRefresh(result)
                await UnifiedAudioPlayer.shared.execute(intent)
            }
        )
    }
}
