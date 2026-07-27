import Combine
import Foundation
import SwiftUI
import Testing
@testable import Briefeed

@Suite("Radio app lifecycle") @MainActor
struct RadioAppLifecycleTests {
    private let emptyRefresh = RSSRefreshBatchResult(results: [])

    @Test func coldLaunchRestoresBeforeItsSingleInitialRefresh() async {
        let monitor = LifecycleConnectivityMonitor(.online)
        var events: [String] = []
        var prepareCount = 0
        var sleepCalls: [TimeInterval] = []
        let driver = makeDriver(monitor: monitor, sleep: { seconds in
            sleepCalls.append(seconds)
            try await Task.sleep(for: .seconds(3_600))
        })
        driver.handleScenePhase(.active)

        let initial = refreshWork(
            begin: { events.append("initial-began") },
            load: { events.append("initial-loaded"); return emptyRefresh },
            apply: { _ in events.append("initial-applied") }
        )
        let foreground = refreshWork(
            begin: { events.append("foreground-began") },
            load: { self.emptyRefresh }
        )

        await driver.startColdLaunch(
            prepare: { prepareCount += 1 },
            restore: { _ in events.append("restored"); return nil },
            initialRefresh: initial,
            foregroundRefresh: foreground
        )
        await driver.startColdLaunch(
            prepare: { prepareCount += 1 },
            restore: { _ in events.append("restored-again"); return nil },
            initialRefresh: initial,
            foregroundRefresh: foreground
        )
        await settle()

        #expect(events == ["restored", "initial-began", "initial-loaded", "initial-applied"])
        #expect(prepareCount == 1)
        #expect(sleepCalls == [900])
    }

    @Test func unknownAndOfflineRetainOnePendingRefreshUntilFirstOnlineEvent() async {
        let monitor = LifecycleConnectivityMonitor(.unknown)
        var refreshCount = 0
        let driver = makeDriver(monitor: monitor)
        driver.handleScenePhase(.active)
        let work = refreshWork(begin: { refreshCount += 1 }, load: { self.emptyRefresh })

        await driver.startColdLaunch(restore: { _ in nil }, initialRefresh: work, foregroundRefresh: work)
        await settle()
        #expect(driver.hasPendingRefresh)
        #expect(refreshCount == 0)

        monitor.send(.offline)
        await settle()
        #expect(driver.hasPendingRefresh)
        #expect(refreshCount == 0)

        monitor.send(.online)
        await settle()
        #expect(!driver.hasPendingRefresh)
        #expect(refreshCount == 1)

        monitor.send(.online)
        await settle()
        #expect(refreshCount == 1)
    }

    @Test func delayedInitialRefreshMayAutoplayAt59SecondsButNotAt60() async {
        let beforeDeadline = await delayedInitialRefresh(offset: 59)
        #expect(beforeDeadline.intent?.key == RadioEpisodeKey(feedID: "npr", episodeID: "latest"))
        #expect(beforeDeadline.state == .loading)

        let atDeadline = await delayedInitialRefresh(offset: 60)
        #expect(atDeadline.intent == nil)
        #expect(atDeadline.state == .readyPaused)
    }

    @Test func foregroundWaitsForCancellationIgnoringRefreshBeforeStartingItsReplacement() async {
        let monitor = LifecycleConnectivityMonitor(.online)
        let loader = LifecycleSingleFlightLoader(
            initialResult: refreshResult(episodeID: "initial"),
            foregroundResult: refreshResult(episodeID: "foreground")
        )
        var appliedResults: [RSSRefreshBatchResult] = []
        var cancelAutoplayCount = 0
        var forceSaveCount = 0
        let driver = makeDriver(
            monitor: monitor,
            cancelAutoplay: { cancelAutoplayCount += 1 },
            forceSave: { _ in forceSaveCount += 1 }
        )
        driver.handleScenePhase(.active)
        let initial = refreshWork(
            load: { await loader.loadInitial() },
            apply: { appliedResults.append($0) }
        )
        let foreground = refreshWork(
            load: { await loader.loadForeground() },
            apply: { appliedResults.append($0) }
        )

        await driver.startColdLaunch(restore: { _ in nil }, initialRefresh: initial, foregroundRefresh: foreground)
        await settle()
        #expect(driver.hasInFlightRefresh)
        #expect(loader.isRefreshing)
        #expect(loader.initialLoadCount == 1)

        driver.handleScenePhase(.background)
        #expect(driver.hasInFlightRefresh)
        driver.handleScenePhase(.active)
        await settle()
        #expect(driver.hasPendingRefresh)
        #expect(loader.foregroundLoadCount == 0)
        #expect(loader.overlapCount == 0)
        #expect(appliedResults.isEmpty)

        loader.releaseInitial()
        await settle()

        #expect(!driver.hasPendingRefresh)
        #expect(!driver.hasInFlightRefresh)
        #expect(driver.hasActivePoll)
        #expect(!loader.isRefreshing)
        #expect(loader.foregroundLoadCount == 1)
        #expect(loader.overlapCount == 0)
        #expect(appliedResults == [refreshResult(episodeID: "foreground")])
        #expect(cancelAutoplayCount == 1)
        #expect(forceSaveCount == 1)
    }

    @Test func foregroundCyclesRearmOnePollAndNeverRestoreOrAutoplayAgain() async {
        let monitor = LifecycleConnectivityMonitor(.online)
        var restoreCount = 0
        var initialCount = 0
        var foregroundCount = 0
        var cancelAutoplayCount = 0
        var forceSaveCount = 0
        var sleepCalls: [TimeInterval] = []
        let driver = makeDriver(
            monitor: monitor,
            sleep: { seconds in
                sleepCalls.append(seconds)
                try await Task.sleep(for: .seconds(3_600))
            },
            cancelAutoplay: { cancelAutoplayCount += 1 },
            forceSave: { _ in forceSaveCount += 1 }
        )
        driver.handleScenePhase(.active)
        await driver.startColdLaunch(
            restore: { _ in restoreCount += 1; return nil },
            initialRefresh: refreshWork(begin: { initialCount += 1 }, load: { self.emptyRefresh }),
            foregroundRefresh: refreshWork(begin: { foregroundCount += 1 }, load: { self.emptyRefresh })
        )
        await settle()
        #expect(driver.hasActivePoll)
        #expect(sleepCalls == [900])

        driver.handleScenePhase(.active)
        await settle()
        #expect(sleepCalls == [900])
        #expect(foregroundCount == 0)

        driver.handleScenePhase(.background)
        await settle()
        #expect(!driver.hasActivePoll)

        driver.handleScenePhase(.active)
        driver.handleScenePhase(.active)
        await settle()
        #expect(driver.hasActivePoll)
        #expect(sleepCalls == [900, 900])
        #expect(foregroundCount == 1)

        driver.handleScenePhase(.inactive)
        driver.handleScenePhase(.background)
        await settle()
        #expect(!driver.hasActivePoll)
        #expect(restoreCount == 1)
        #expect(initialCount == 1)
        #expect(cancelAutoplayCount == 2)
        #expect(forceSaveCount == 2)
    }

    @Test func activeHeartbeatUsesItsStaleCheckInsteadOfTheForcedOpeningRefresh() async {
        let monitor = LifecycleConnectivityMonitor(.online)
        var sleepCount = 0
        var initialCount = 0
        var openingCount = 0
        var heartbeatCount = 0
        let driver = makeDriver(monitor: monitor, sleep: { _ in
            sleepCount += 1
            if sleepCount == 1 { return }
            throw CancellationError()
        })
        driver.handleScenePhase(.active)

        await driver.startColdLaunch(
            restore: { _ in nil },
            initialRefresh: refreshWork(begin: { initialCount += 1 }, load: { self.emptyRefresh }),
            foregroundRefresh: refreshWork(begin: { openingCount += 1 }, load: { self.emptyRefresh }),
            pollRefresh: refreshWork(begin: { heartbeatCount += 1 }, load: { self.emptyRefresh })
        )
        await settle()

        #expect(initialCount == 1)
        #expect(openingCount == 0)
        #expect(heartbeatCount == 1)
        driver.handleScenePhase(.background)
    }

    @Test func reopeningRadioRequestsOneFreshOpeningRefreshAfterTheLaunchDebounce() async {
        let launchedAt = Date(timeIntervalSince1970: 10_000)
        var now = launchedAt
        let monitor = LifecycleConnectivityMonitor(.online)
        var initialCount = 0
        var openingCount = 0
        let driver = makeDriver(monitor: monitor, now: { now })
        driver.handleScenePhase(.active)

        await driver.startColdLaunch(
            restore: { _ in nil },
            initialRefresh: refreshWork(
                begin: { initialCount += 1 },
                load: { self.emptyRefresh }
            ),
            foregroundRefresh: refreshWork(
                begin: { openingCount += 1 },
                load: { self.emptyRefresh }
            )
        )
        await settle()

        driver.handleRadioHomeAppeared()
        await settle()
        #expect(initialCount == 1)
        #expect(openingCount == 0)

        now = launchedAt.addingTimeInterval(61)
        driver.handleRadioHomeAppeared()
        driver.handleRadioHomeAppeared()
        await settle()

        #expect(openingCount == 1)
    }

    @Test func terminationCancelsWorkAndForceSavesOnce() async {
        let monitor = LifecycleConnectivityMonitor(.unknown)
        var cancelAutoplayCount = 0
        var forceSaveCount = 0
        let driver = makeDriver(
            monitor: monitor,
            cancelAutoplay: { cancelAutoplayCount += 1 },
            forceSave: { _ in forceSaveCount += 1 }
        )
        driver.handleScenePhase(.active)
        let work = refreshWork(load: { self.emptyRefresh })
        await driver.startColdLaunch(restore: { _ in nil }, initialRefresh: work, foregroundRefresh: work)
        #expect(driver.hasPendingRefresh)

        driver.handleTermination()
        driver.handleTermination()

        #expect(!driver.hasPendingRefresh)
        #expect(!driver.hasActivePoll)
        #expect(cancelAutoplayCount == 1)
        #expect(forceSaveCount == 1)
    }

    @Test func backgroundBeforeRestoreDisablesAutoplayAndUsesForegroundRefreshPath() async {
        let monitor = LifecycleConnectivityMonitor(.online)
        var restoreAutoplayValues: [Bool] = []
        var initialCount = 0
        var foregroundCount = 0
        let driver = makeDriver(monitor: monitor)
        driver.handleScenePhase(.background)

        await driver.startColdLaunch(
            restore: { restoreAutoplayValues.append($0); return nil },
            initialRefresh: refreshWork(begin: { initialCount += 1 }, load: { self.emptyRefresh }),
            foregroundRefresh: refreshWork(begin: { foregroundCount += 1 }, load: { self.emptyRefresh })
        )
        driver.handleScenePhase(.active)
        await settle()

        #expect(restoreAutoplayValues == [false])
        #expect(initialCount == 0)
        #expect(foregroundCount == 1)
    }

    @Test func transientInactiveBeforeFirstActivePreservesColdLaunchAutoplay() async {
        let monitor = LifecycleConnectivityMonitor(.online)
        var restoreAutoplayValues: [Bool] = []
        let driver = makeDriver(monitor: monitor)

        // iOS may report inactive while a cold launch is still transitioning
        // to its first active scene. That is not a backgrounding event.
        driver.handleScenePhase(.inactive)
        driver.handleScenePhase(.active)

        await driver.startColdLaunch(
            restore: { autoplayAllowed in
                restoreAutoplayValues.append(autoplayAllowed)
                return nil
            },
            initialRefresh: refreshWork(load: { self.emptyRefresh }),
            foregroundRefresh: refreshWork(load: { self.emptyRefresh })
        )
        await settle()

        #expect(restoreAutoplayValues == [true])
    }

    @Test func transientInactiveAfterFirstActiveKeepsColdLaunchEligible() async {
        let monitor = LifecycleConnectivityMonitor(.online)
        var restoreAutoplayValues: [Bool] = []
        var initialRefreshCount = 0
        let driver = makeDriver(monitor: monitor)

        driver.handleScenePhase(.active)
        driver.handleScenePhase(.inactive)

        await driver.startColdLaunch(
            restore: { autoplayAllowed in
                restoreAutoplayValues.append(autoplayAllowed)
                return nil
            },
            initialRefresh: refreshWork(
                begin: { initialRefreshCount += 1 },
                load: { self.emptyRefresh }
            ),
            foregroundRefresh: refreshWork(load: { self.emptyRefresh })
        )
        await settle()
        #expect(restoreAutoplayValues == [true])
        #expect(initialRefreshCount == 1)

        driver.handleScenePhase(.active)
        await driver.startColdLaunch(
            restore: { autoplayAllowed in
                restoreAutoplayValues.append(autoplayAllowed)
                return nil
            },
            initialRefresh: refreshWork(
                begin: { initialRefreshCount += 1 },
                load: { self.emptyRefresh }
            ),
            foregroundRefresh: refreshWork(load: { self.emptyRefresh })
        )
        await settle()

        #expect(restoreAutoplayValues == [true])
        #expect(initialRefreshCount == 1)
    }

    @Test func transientInactiveDuringStartupSettleKeepsAutoplayAlive() async {
        let monitor = LifecycleConnectivityMonitor(.online)
        let gate = LifecycleVoidGate()
        var settleCount = 0
        var restoreAutoplayValues: [Bool] = []
        var initialRefreshCount = 0
        let driver = makeDriver(
            monitor: monitor,
            settleActiveScene: {
                settleCount += 1
                if settleCount == 1 {
                    await gate.wait()
                }
            }
        )
        let initial = refreshWork(
            begin: { initialRefreshCount += 1 },
            load: { self.emptyRefresh }
        )
        let foreground = refreshWork(load: { self.emptyRefresh })

        driver.handleScenePhase(.active)
        let firstStartup = Task { @MainActor in
            await driver.startColdLaunch(
                restore: {
                    restoreAutoplayValues.append($0)
                    return nil
                },
                initialRefresh: initial,
                foregroundRefresh: foreground
            )
        }
        await settle()
        #expect(gate.isWaiting)

        driver.handleScenePhase(.inactive)
        gate.release()
        await firstStartup.value
        await settle()
        #expect(restoreAutoplayValues == [true])
        #expect(initialRefreshCount == 1)

        driver.handleScenePhase(.active)
        await driver.startColdLaunch(
            restore: {
                restoreAutoplayValues.append($0)
                return nil
            },
            initialRefresh: initial,
            foregroundRefresh: foreground
        )
        await settle()

        #expect(restoreAutoplayValues == [true])
        #expect(initialRefreshCount == 1)
    }

    @Test func coldLaunchServicesStartOnlyForAnActiveScene() {
        #expect(!RadioStartupPolicy.shouldStartServices(for: .inactive))
        #expect(!RadioStartupPolicy.shouldStartServices(for: .background))
        #expect(RadioStartupPolicy.shouldStartServices(for: .active))
    }

    @Test func activeReturnBeforeStaleRestoreCompletesUsesOnlyForegroundRefreshAndOnePoll() async {
        let monitor = LifecycleConnectivityMonitor(.online)
        let gate = LifecycleIntentGate()
        var appliedIntents: [RadioPlaybackIntent?] = []
        var initialCount = 0
        var foregroundCount = 0
        var sleepCalls: [TimeInterval] = []
        let driver = makeDriver(monitor: monitor, sleep: { seconds in
            sleepCalls.append(seconds)
            try await Task.sleep(for: .seconds(3_600))
        })
        driver.handleScenePhase(.active)

        let startup = Task { @MainActor in
            await driver.startColdLaunch(
                restore: { _ in await gate.wait() },
                applyRestoreIntent: { appliedIntents.append($0) },
                initialRefresh: refreshWork(begin: { initialCount += 1 }, load: { self.emptyRefresh }),
                foregroundRefresh: refreshWork(begin: { foregroundCount += 1 }, load: { self.emptyRefresh })
            )
        }
        await settle()
        driver.handleScenePhase(.background)
        driver.handleScenePhase(.active)
        await settle()
        #expect(initialCount == 0)
        #expect(foregroundCount == 0)
        #expect(!driver.hasActivePoll)

        gate.release(.play(RadioPlaybackRequest(
            key: RadioEpisodeKey(feedID: "npr", episodeID: "late"),
            url: URL(string: "https://example.com/late.mp3")!,
            title: "Late",
            source: "NPR",
            positionSeconds: 0
        )))
        await startup.value
        await settle()

        #expect(appliedIntents == [nil])
        #expect(initialCount == 0)
        #expect(foregroundCount == 1)
        #expect(driver.hasActivePoll)
        #expect(sleepCalls == [900])
    }

    @Test func restoreCompletedWhileInactiveReconcilesPresentationOnForegroundWithoutAutoplay() async {
        let monitor = LifecycleConnectivityMonitor(.online)
        let gate = LifecycleIntentGate()
        var appliedIntents: [RadioPlaybackIntent?] = []
        let driver = makeDriver(monitor: monitor)
        driver.handleScenePhase(.active)

        let startup = Task { @MainActor in
            await driver.startColdLaunch(
                restore: { _ in await gate.wait() },
                applyRestoreIntent: { appliedIntents.append($0) },
                initialRefresh: refreshWork(load: { self.emptyRefresh }),
                foregroundRefresh: refreshWork(load: { self.emptyRefresh })
            )
        }
        await settle()
        driver.handleScenePhase(.background)
        gate.release(.play(RadioPlaybackRequest(
            key: RadioEpisodeKey(feedID: "npr", episodeID: "late"),
            url: URL(string: "https://example.com/late.mp3")!,
            title: "Late",
            source: "NPR",
            positionSeconds: 12
        )))
        await startup.value
        await settle()
        #expect(appliedIntents.isEmpty)

        driver.handleScenePhase(.active)
        await settle()

        #expect(appliedIntents == [nil])
    }

    @Test func backgroundForceSavesActiveRadioTransportPositionAndBriefWithoutStoppingAudio() async {
        let episode = candidate(publicationDate: Date())
        let store = FakeRadioSessionStore(snapshot: session(for: episode.key, position: 12))
        let radio = RadioSessionCoordinator(
            store: store,
            repository: RecordingRadioRepository(candidates: [episode]),
            connectivityStatus: { .online }
        )
        _ = await radio.restore(autoplayEnabled: false)
        let brief = FakeBriefQueueCoordinator(currentPosition: 7)
        var transportEvents: [String] = []
        let transport = SpyAudioTransport { transportEvents.append($0) }
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true).container.viewContext
        )
        await player.playRadio()
        transport.currentTime = 42
        transport.duration = 300
        store.resetCalls()

        player.handleAppBackground()

        #expect(store.savedNow?.entries.first?.positionSeconds == 42)
        #expect(brief.saveCount == 1)
        #expect(!transportEvents.contains("pause"))
        #expect(!transportEvents.contains("stop"))
    }

    @Test func lifecycleSaveUsesPersistedRadioPositionWhenBriefOwnsTransport() async {
        let episode = candidate(publicationDate: Date())
        let store = FakeRadioSessionStore(snapshot: session(for: episode.key, position: 27))
        let radio = RadioSessionCoordinator(
            store: store,
            repository: RecordingRadioRepository(candidates: [episode]),
            connectivityStatus: { .online }
        )
        _ = await radio.restore(autoplayEnabled: false)
        let brief = FakeBriefQueueCoordinator(currentPosition: 8)
        let transport = SpyAudioTransport()
        transport.currentTime = 81
        transport.duration = 120
        let player = UnifiedAudioPlayer(
            audioPlayer: transport,
            queueCoordinator: brief,
            radioCoordinator: radio,
            context: PersistenceController(inMemory: true).container.viewContext
        )
        store.resetCalls()

        player.handleAppTermination()

        #expect(store.savedNow?.entries.first?.positionSeconds == 27)
        #expect(brief.currentPosition == 8)
        #expect(brief.saveCount == 1)
    }

    private func delayedInitialRefresh(offset: TimeInterval) async -> (intent: RadioPlaybackIntent?, state: RadioSessionState) {
        let launchedAt = Date(timeIntervalSince1970: 10_000)
        var now = launchedAt
        let monitor = LifecycleConnectivityMonitor(.unknown)
        let repository = FakeRadioEpisodeRepository(candidates: [])
        let coordinator = RadioSessionCoordinator(
            store: FakeRadioSessionStore(),
            repository: repository,
            now: { now },
            connectivity: monitor
        )
        let driver = makeDriver(monitor: monitor, now: { now })
        var appliedIntent: RadioPlaybackIntent?
        driver.handleScenePhase(.active)
        await driver.startColdLaunch(
            restore: { autoplayAllowed in
                await coordinator.restore(autoplayEnabled: autoplayAllowed)
            },
            applyRestoreIntent: { _ in },
            initialRefresh: refreshWork(
                begin: { coordinator.refreshStarted(enabledSourceCount: 1) },
                load: {
                    repository.values = [self.candidate(publicationDate: launchedAt)]
                    return RSSRefreshBatchResult(results: [
                        RSSFeedRefreshResult(feedID: "npr", outcome: .success(insertedEpisodeIDs: ["latest"]))
                    ])
                },
                apply: { appliedIntent = coordinator.applyInitialRefresh($0) }
            ),
            foregroundRefresh: refreshWork(load: { self.emptyRefresh })
        )

        now = launchedAt.addingTimeInterval(offset)
        monitor.send(.online)
        await settle()
        return (appliedIntent, coordinator.state)
    }

    private func candidate(publicationDate: Date) -> RadioEpisodeCandidate {
        RadioEpisodeCandidate(
            key: RadioEpisodeKey(feedID: "npr", episodeID: "latest"),
            originalPlaybackURL: URL(string: "https://example.com/latest.mp3")!,
            canonicalEnclosureURL: "https://example.com/latest.mp3",
            title: "Latest",
            sourceName: "NPR",
            publicationDate: publicationDate,
            durationSeconds: 300,
            normalizedCoreDataProgress: 0,
            isCompleted: false,
            sourcePriority: 1,
            sourceFrequency: .hourly
        )
    }

    private func refreshResult(episodeID: String) -> RSSRefreshBatchResult {
        RSSRefreshBatchResult(results: [
            RSSFeedRefreshResult(feedID: "npr", outcome: .success(insertedEpisodeIDs: [episodeID]))
        ])
    }

    private func session(for key: RadioEpisodeKey, position: TimeInterval) -> PersistedRadioSession {
        PersistedRadioSession(
            schemaVersion: PersistedRadioSession.schemaVersion,
            entries: [RadioQueueEntry(
                key: key,
                positionSeconds: position,
                disposition: .pending,
                playbackFailureCount: 0,
                lastPlaybackError: nil
            )],
            currentKey: key,
            savedAt: Date()
        )
    }

    private func makeDriver(
        monitor: LifecycleConnectivityMonitor,
        now: @escaping @MainActor () -> Date = Date.init,
        sleep: @escaping RadioAppLifecycleDriver.Sleep = { _ in
            try await Task.sleep(for: .seconds(3_600))
        },
        settleActiveScene: @escaping RadioAppLifecycleDriver.SettleActiveScene = {},
        cancelAutoplay: @escaping @MainActor () -> Void = {},
        forceSave: @escaping @MainActor (RadioAppLifecycleDriver.SaveReason) -> Void = { _ in }
    ) -> RadioAppLifecycleDriver {
        RadioAppLifecycleDriver(
            connectivity: monitor,
            now: now,
            sleep: sleep,
            settleActiveScene: settleActiveScene,
            cancelPendingColdLaunchAutoplay: cancelAutoplay,
            forceSave: forceSave
        )
    }

    private func refreshWork(
        begin: @escaping @MainActor () -> Void = {},
        load: @escaping @MainActor () async -> RSSRefreshBatchResult,
        apply: @escaping @MainActor (RSSRefreshBatchResult) async -> Void = { _ in }
    ) -> RadioAppLifecycleDriver.RefreshWork {
        RadioAppLifecycleDriver.RefreshWork(begin: begin, load: load, apply: apply)
    }

    private func settle() async {
        for _ in 0..<12 { await Task.yield() }
    }
}

@MainActor
private final class LifecycleConnectivityMonitor: ConnectivityMonitoring {
    private let subject: CurrentValueSubject<ConnectivityStatus, Never>
    var status: ConnectivityStatus { subject.value }
    var statusPublisher: AnyPublisher<ConnectivityStatus, Never> { subject.eraseToAnyPublisher() }

    init(_ status: ConnectivityStatus) { subject = CurrentValueSubject(status) }
    func send(_ status: ConnectivityStatus) { subject.send(status) }
}

@MainActor
private final class LifecycleSingleFlightLoader {
    private let initialResult: RSSRefreshBatchResult
    private let foregroundResult: RSSRefreshBatchResult
    private var initialContinuation: CheckedContinuation<RSSRefreshBatchResult, Never>?
    private(set) var isRefreshing = false
    private(set) var initialLoadCount = 0
    private(set) var foregroundLoadCount = 0
    private(set) var overlapCount = 0

    init(initialResult: RSSRefreshBatchResult, foregroundResult: RSSRefreshBatchResult) {
        self.initialResult = initialResult
        self.foregroundResult = foregroundResult
    }

    func loadInitial() async -> RSSRefreshBatchResult {
        initialLoadCount += 1
        guard !isRefreshing else {
            overlapCount += 1
            return RSSRefreshBatchResult(results: [])
        }
        isRefreshing = true
        let result = await withCheckedContinuation { initialContinuation = $0 }
        isRefreshing = false
        return result
    }

    func loadForeground() async -> RSSRefreshBatchResult {
        foregroundLoadCount += 1
        guard !isRefreshing else {
            overlapCount += 1
            return RSSRefreshBatchResult(results: [])
        }
        isRefreshing = true
        defer { isRefreshing = false }
        return foregroundResult
    }

    func releaseInitial() {
        initialContinuation?.resume(returning: initialResult)
        initialContinuation = nil
    }
}

@MainActor
private final class LifecycleIntentGate {
    private var continuation: CheckedContinuation<RadioPlaybackIntent?, Never>?

    func wait() async -> RadioPlaybackIntent? {
        await withCheckedContinuation { continuation = $0 }
    }

    func release(_ intent: RadioPlaybackIntent?) {
        continuation?.resume(returning: intent)
        continuation = nil
    }
}

@MainActor
private final class LifecycleVoidGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    func wait() async {
        isWaiting = true
        await withCheckedContinuation { continuation = $0 }
        isWaiting = false
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
