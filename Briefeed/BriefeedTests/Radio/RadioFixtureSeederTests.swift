import AVFoundation
import CoreData
import Foundation
import Testing
@testable import Briefeed

#if DEBUG
@Suite("Radio fixture seeder", .serialized) @MainActor
struct RadioFixtureSeederTests {
    private let clock = Date(timeIntervalSince1970: 1_752_393_600)

    @Test func seedsDeterministicCatalogAndReadableLongAudio() throws {
        let harness = try makeHarness()
        harness.prepareReset(scenario: .partial)
        try harness.seeder.seed(scenario: .partial, reset: true)

        let feeds = try harness.context.fetch(RSSFeed.fetchRequest())
            .sorted { $0.priority < $1.priority }
        let episodes = try harness.context.fetch(RSSEpisode.fetchRequest())
        let audioURL = try #require(episodes.compactMap(\.downloadedFilePath).first.map(URL.init(fileURLWithPath:)))
        let audio = try AVAudioFile(forReading: audioURL)

        #expect(feeds.map(\.id) == RadioFixtureSeeder.feedIDs)
        #expect(feeds.map(\.priority) == [0, 1, 2])
        #expect(episodes.contains { $0.id == RadioFixtureSeeder.EpisodeID.fresh })
        #expect(episodes.contains { $0.id == RadioFixtureSeeder.EpisodeID.partial && $0.lastPosition > 0 && $0.lastPosition < 0.95 })
        #expect(episodes.contains { $0.id == RadioFixtureSeeder.EpisodeID.completed && $0.isListened })
        #expect(episodes.contains { $0.id == RadioFixtureSeeder.EpisodeID.stale && clock.timeIntervalSince($0.pubDate) > 2 * 60 * 60 })
        #expect(episodes.contains { $0.id == RadioFixtureSeeder.EpisodeID.malformed && URL(string: $0.audioUrl) == nil })
        #expect(Dictionary(grouping: episodes, by: \.id)[RadioFixtureSeeder.EpisodeID.duplicateGUID]?.count == 2)
        #expect(Dictionary(grouping: episodes, by: \.audioUrl).values.contains { $0.count > 1 })
        #expect(FileManager.default.isReadableFile(atPath: audioURL.path))
        #expect(audio.processingFormat.sampleRate == 44_100)
        #expect(audio.processingFormat.channelCount == 1)
        #expect(Double(audio.length) / audio.processingFormat.sampleRate > 60)
    }

    @Test func resetIsIdempotentAndNoResetPreservesSessionAndPreferences() async throws {
        let harness = try makeHarness()
        harness.prepareReset(scenario: .partial)
        try harness.seeder.seed(scenario: .partial, reset: true)
        harness.prepareReset(scenario: .partial)
        try harness.seeder.seed(scenario: .partial, reset: true)

        #expect(try harness.context.count(for: RSSFeed.fetchRequest()) == 3)
        let firstEpisodeCount = try harness.context.count(for: RSSEpisode.fetchRequest())

        let coordinator = harness.makeCoordinator(status: .online)
        _ = await coordinator.restore(autoplayEnabled: false)
        _ = coordinator.pauseByUser(positionSeconds: 44, duration: 90)
        harness.defaults.set(true, forKey: UserDefaultsKey.autoPlayLiveNewsOnOpen.rawValue)
        harness.defaults.set(1.75, forKey: UserDefaultsKey.playbackSpeed.rawValue)

        try harness.seeder.seed(scenario: .partial, reset: false)
        let restored = harness.makeCoordinator(status: .online)
        _ = await restored.restore(autoplayEnabled: false)

        #expect(try harness.context.count(for: RSSEpisode.fetchRequest()) == firstEpisodeCount)
        #expect(restored.entries.first(where: { $0.key == restored.currentKey })?.positionSeconds == 44)
        #expect(harness.defaults.bool(forKey: UserDefaultsKey.autoPlayLiveNewsOnOpen.rawValue))
        #expect(harness.defaults.double(forKey: UserDefaultsKey.playbackSpeed.rawValue) == 1.75)
    }

    @Test func resetPreventsCrossScenarioStateBleedAndRelaunchPreservesNewState() async throws {
        let harness = try makeHarness()
        harness.prepareReset(scenario: .partial)
        try harness.seeder.seed(scenario: .partial, reset: true)
        let partial = harness.makeCoordinator(status: .online)
        _ = await partial.restore(autoplayEnabled: false)
        _ = partial.pauseByUser(positionSeconds: 47, duration: 90)
        harness.defaults.set(true, forKey: UserDefaultsKey.autoPlayLiveNewsOnOpen.rawValue)
        harness.defaults.set(2.5, forKey: UserDefaultsKey.playbackSpeed.rawValue)
        harness.defaults.set(1.5, forKey: UserDefaultsKey.rssPlaybackSpeed.rawValue)
        harness.defaults.set("old-episode", forKey: UserDefaultsKey.rssLastPlayedEpisodeId.rawValue)

        harness.prepareReset(scenario: .completed)
        try harness.seeder.seed(scenario: .completed, reset: true)
        #expect(harness.defaults.data(forKey: RadioSessionStore.storageKey) == nil)
        #expect(!harness.defaults.bool(forKey: UserDefaultsKey.autoPlayLiveNewsOnOpen.rawValue))
        #expect(harness.defaults.double(forKey: UserDefaultsKey.playbackSpeed.rawValue) == 1)
        #expect(harness.defaults.object(forKey: UserDefaultsKey.rssPlaybackSpeed.rawValue) == nil)
        #expect(harness.defaults.object(forKey: UserDefaultsKey.rssLastPlayedEpisodeId.rawValue) == nil)

        let completed = harness.makeCoordinator(status: .online)
        _ = await completed.restore(autoplayEnabled: false)
        #expect(completed.currentKey != partial.currentKey)
        #expect(completed.entries.first(where: { $0.key == completed.currentKey })?.positionSeconds == 0)
        _ = completed.pauseByUser(positionSeconds: 23, duration: 90)
        harness.defaults.set(1.25, forKey: UserDefaultsKey.playbackSpeed.rawValue)

        try harness.seeder.seed(scenario: .completed, reset: false)
        let relaunched = harness.makeCoordinator(status: .online)
        _ = await relaunched.restore(autoplayEnabled: false)
        #expect(relaunched.currentKey == completed.currentKey)
        #expect(relaunched.entries.first(where: { $0.key == relaunched.currentKey })?.positionSeconds == 23)
        #expect(harness.defaults.double(forKey: UserDefaultsKey.playbackSpeed.rawValue) == 1.25)
    }

    @Test(arguments: RadioFixtureScenario.allCases)
    func scenarioUsesOnlyScriptedCoordinatorTransitions(scenario: RadioFixtureScenario) async throws {
        let harness = try makeHarness()
        harness.prepareReset(scenario: scenario)
        try harness.seeder.seed(scenario: scenario, reset: true)
        let definition = RadioFixtureScenarioDefinition.make(scenario: scenario, now: clock)
        let monitor = RadioFixtureConnectivityMonitor(initialStatus: definition.initialConnectivity)
        let coordinator = RadioSessionCoordinator(
            store: RadioSessionStore(defaults: harness.defaults),
            repository: CoreDataRadioEpisodeRepository(context: harness.context),
            now: { clock },
            connectivity: monitor
        )

        _ = await coordinator.restore(autoplayEnabled: false)
        let intent = definition.applyPostRestore(to: coordinator)

        #expect(monitor.status == definition.initialConnectivity)
        switch scenario {
        case .partial:
            #expect(coordinator.state == .readyPaused)
            #expect(coordinator.entries.first(where: { $0.key == coordinator.currentKey })?.positionSeconds == 18)
            #expect(coordinator.currentEpisode?.originalPlaybackURL.scheme == "https")
            #expect(intent == nil)
        case .completed:
            #expect(coordinator.state == .readyPaused)
            #expect(coordinator.currentKey?.episodeID == RadioFixtureSeeder.EpisodeID.fresh)
            #expect(coordinator.entries.allSatisfy { $0.key.episodeID != RadioFixtureSeeder.EpisodeID.partial })
            #expect(intent == nil)
        case .offline:
            let request: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", RadioFixtureSeeder.EpisodeID.partial)
            let episode = try #require(harness.context.fetch(request).first)
            #expect(coordinator.state == .waitingForNetwork)
            #expect(coordinator.currentEpisode?.originalPlaybackURL.scheme == "https")
            #expect(episode.downloadedFilePath == nil)
            #expect(intent == nil)
        case .allFailed:
            #expect(coordinator.state == .failed(.allSourcesUnavailable))
            #expect(coordinator.sourceFailures.count == definition.enabledSourceCount)
            #expect(intent == nil)
        case .degraded:
            let request: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", RadioFixtureSeeder.EpisodeID.partial)
            let episode = try #require(harness.context.fetch(request).first)
            let localPath = try #require(episode.downloadedFilePath)
            #expect(coordinator.state == .readyPaused)
            #expect(coordinator.currentEpisode != nil)
            #expect(coordinator.sourceFailures.count == 1)
            #expect(FileManager.default.isReadableFile(atPath: localPath))
            #expect(intent == nil)
        case .noSources:
            #expect(coordinator.state == .noSources)
            #expect(definition.enabledSourceCount == 0)
            #expect(intent == nil)
        case .refreshing:
            #expect(coordinator.state == .refreshing)
            #expect(coordinator.sourceFailures.isEmpty)
            #expect(intent == nil)
        case .exhausted:
            #expect(coordinator.state == .exhausted)
            #expect(coordinator.entries.isEmpty)
            #expect(intent == nil)
        }
    }

    @Test func diagnosticsCountOnlyExecutedBootstrapPlayIntentsAndRefreshes() {
        let diagnostics = RadioFixtureDiagnostics()
        let request = RadioPlaybackRequest(
            key: .init(feedID: "fixture-npr", episodeID: "fixture-partial"),
            url: URL(string: "https://fixtures.briefeed.test/partial.wav")!,
            title: "Morning Update",
            source: "NPR News Now",
            positionSeconds: 18
        )

        diagnostics.reset()
        diagnostics.recordBootstrapExecution(of: nil)
        diagnostics.recordBootstrapExecution(of: .pause)
        diagnostics.recordBootstrapExecution(of: .play(request))
        diagnostics.recordRefreshInvocation()

        #expect(diagnostics.bootstrapPlayIntentCount == 1)
        #expect(diagnostics.refreshInvocationCount == 1)
        #expect(diagnostics.accessibilityValue == "bootstrapPlayIntents=1;refreshInvocations=1")
    }

    private func makeHarness() throws -> Harness {
        let persistence = PersistenceController(inMemory: true)
        let suiteName = "RadioFixtureSeederTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RadioFixtureSeederTests-Shared", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return Harness(
            context: persistence.container.viewContext,
            defaults: defaults,
            directory: directory,
            now: clock
        )
    }

    @MainActor
    private struct Harness {
        let context: NSManagedObjectContext
        let defaults: UserDefaults
        let directory: URL
        let now: Date

        var seeder: RadioFixtureSeeder {
            RadioFixtureSeeder(
                context: context,
                applicationSupportDirectory: directory,
                now: { now }
            )
        }

        func prepareReset(scenario: RadioFixtureScenario) {
            AppRuntime.prepareRadioFixturePreferencesIfNeeded(
                configuration: .init(
                    arguments: ["Briefeed", "-briefeed-radio-fixture", scenario.rawValue],
                    environment: ["BRIEFEED_RADIO_RESET_STORE": "1"]
                ),
                defaults: defaults
            )
        }

        func makeCoordinator(status: ConnectivityStatus) -> RadioSessionCoordinator {
            RadioSessionCoordinator(
                store: RadioSessionStore(defaults: defaults),
                repository: CoreDataRadioEpisodeRepository(context: context),
                now: { now },
                connectivityStatus: { status }
            )
        }
    }
}
#endif
