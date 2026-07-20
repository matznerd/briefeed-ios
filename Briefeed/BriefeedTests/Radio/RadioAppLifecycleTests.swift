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
            restore: { _ in events.append("restored"); return nil },
            initialRefresh: initial,
            foregroundRefresh: foreground
        )
        await driver.startColdLaunch(
            restore: { _ in events.append("restored-again"); return nil },
            initialRefresh: initial,
            foregroundRefresh: foreground
        )
        await settle()

        #expect(events == ["restored", "initial-began", "initial-loaded", "initial-applied"])
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
        #expect(beforeDeadline.state == .readyPaused)

        let atDeadline = await delayedInitialRefresh(offset: 60)
        #expect(atDeadline.intent == nil)
        #expect(atDeadline.state == .readyPaused)
    }

    @Test func backgroundCancelsPendingWorkAndGuardsLateRefreshApplication() async {
        let monitor = LifecycleConnectivityMonitor(.online)
        let gate = LifecycleRefreshGate()
        var applyCount = 0
        var cancelAutoplayCount = 0
        var forceSaveCount = 0
        let driver = makeDriver(
            monitor: monitor,
            cancelAutoplay: { cancelAutoplayCount += 1 },
            forceSave: { _ in forceSaveCount += 1 }
        )
        driver.handleScenePhase(.active)
        var foregroundApplyCount = 0
        let initial = refreshWork(load: { await gate.wait() }, apply: { _ in applyCount += 1 })
        let foreground = refreshWork(load: { self.emptyRefresh }, apply: { _ in foregroundApplyCount += 1 })

        await driver.startColdLaunch(restore: { _ in nil }, initialRefresh: initial, foregroundRefresh: foreground)
        await settle()
        #expect(driver.hasInFlightRefresh)

        driver.handleScenePhase(.background)
        #expect(!driver.hasInFlightRefresh)
        driver.handleScenePhase(.active)
        await settle()
        #expect(foregroundApplyCount == 1)

        gate.release(emptyRefresh)
        await settle()

        #expect(!driver.hasPendingRefresh)
        #expect(!driver.hasInFlightRefresh)
        #expect(driver.hasActivePoll)
        #expect(applyCount == 0)
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

    @Test func backgroundDuringRestoreRejectsLateAutoplayIntent() async {
        let monitor = LifecycleConnectivityMonitor(.online)
        let gate = LifecycleIntentGate()
        var appliedIntents: [RadioPlaybackIntent?] = []
        var foregroundCount = 0
        let driver = makeDriver(monitor: monitor)
        driver.handleScenePhase(.active)

        let startup = Task { @MainActor in
            await driver.startColdLaunch(
                restore: { _ in await gate.wait() },
                applyRestoreIntent: { appliedIntents.append($0) },
                initialRefresh: refreshWork(load: { self.emptyRefresh }),
                foregroundRefresh: refreshWork(begin: { foregroundCount += 1 }, load: { self.emptyRefresh })
            )
        }
        await settle()
        driver.handleScenePhase(.background)
        gate.release(.play(RadioPlaybackRequest(
            key: RadioEpisodeKey(feedID: "npr", episodeID: "late"),
            url: URL(string: "https://example.com/late.mp3")!,
            title: "Late",
            source: "NPR",
            positionSeconds: 0
        )))
        await startup.value

        #expect(appliedIntents.isEmpty)
        driver.handleScenePhase(.active)
        await settle()
        #expect(foregroundCount == 1)
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
        cancelAutoplay: @escaping @MainActor () -> Void = {},
        forceSave: @escaping @MainActor (RadioAppLifecycleDriver.SaveReason) -> Void = { _ in }
    ) -> RadioAppLifecycleDriver {
        RadioAppLifecycleDriver(
            connectivity: monitor,
            now: now,
            sleep: sleep,
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
private final class LifecycleRefreshGate {
    private var continuation: CheckedContinuation<RSSRefreshBatchResult, Never>?

    func wait() async -> RSSRefreshBatchResult {
        await withCheckedContinuation { continuation = $0 }
    }

    func release(_ result: RSSRefreshBatchResult) {
        continuation?.resume(returning: result)
        continuation = nil
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
