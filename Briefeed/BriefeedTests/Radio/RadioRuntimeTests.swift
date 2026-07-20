import Foundation
import Testing
@testable import Briefeed

@Suite("Radio runtime")
struct RadioRuntimeTests {
    private enum StoreRemovalError: Error {
        case denied
    }

    @Test func fixtureArgumentsSelectScenarioAndIsolatedStore() {
        let runtime = AppRuntime.Configuration(
            arguments: ["Briefeed", "-briefeed-radio-fixture", "partial"],
            environment: ["BRIEFEED_RADIO_RESET_STORE": "1"]
        )

        #expect(runtime.radioFixtureScenario == "partial")
        #expect(runtime.shouldResetRadioFixtureStore)
        #expect(runtime.shouldSkipAutomaticStartupWork)
        #expect(runtime.usesIsolatedRadioStore)
    }

    @Test func productionArgumentsUseProductionStore() {
        let runtime = AppRuntime.Configuration(arguments: ["Briefeed"], environment: [:])

        #expect(runtime.radioFixtureScenario == nil)
        #expect(!runtime.usesIsolatedRadioStore)
    }

    @Test func existingHostedTestOverrideStillSkipsStartup() {
        let runtime = AppRuntime.Configuration(
            arguments: ["Briefeed"],
            environment: ["BRIEFEED_FORCE_HOSTED_XCTEST": "1"]
        )

        #expect(runtime.shouldSkipAutomaticStartupWork)
    }

    #if DEBUG
    @Test func fixturePreflightResetsOnlyRadioKeysBeforeSettingsResolution() throws {
        let suiteName = "RadioRuntimeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set("keep-me", forKey: "unrelated-preference")
        defaults.set(Data([1]), forKey: RadioSessionStore.storageKey)
        defaults.set(2.5, forKey: UserDefaultsKey.playbackSpeed.rawValue)
        defaults.set(1.75, forKey: UserDefaultsKey.rssPlaybackSpeed.rawValue)
        defaults.set(true, forKey: UserDefaultsKey.autoPlayLiveNewsOnOpen.rawValue)
        defaults.set("legacy", forKey: UserDefaultsKey.rssLastPlayedEpisodeId.rawValue)

        AppRuntime.prepareRadioFixturePreferencesIfNeeded(
            configuration: .init(
                arguments: ["Briefeed", "-briefeed-radio-fixture", "partial"],
                environment: ["BRIEFEED_RADIO_RESET_STORE": "1"]
            ),
            defaults: defaults
        )

        #expect(defaults.string(forKey: "unrelated-preference") == "keep-me")
        #expect(defaults.data(forKey: RadioSessionStore.storageKey) == nil)
        #expect(defaults.double(forKey: UserDefaultsKey.playbackSpeed.rawValue) == 1)
        #expect(defaults.object(forKey: UserDefaultsKey.rssPlaybackSpeed.rawValue) == nil)
        #expect(!defaults.bool(forKey: UserDefaultsKey.autoPlayLiveNewsOnOpen.rawValue))
        #expect(defaults.object(forKey: UserDefaultsKey.rssLastPlayedEpisodeId.rawValue) == nil)
    }

    @Test func invalidFixtureNameCannotResetPreferencesOrSelectFixtureRuntime() throws {
        let suiteName = "RadioRuntimeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(2, forKey: UserDefaultsKey.playbackSpeed.rawValue)
        let configuration = AppRuntime.Configuration(
            arguments: ["Briefeed", "-briefeed-radio-fixture", "not-a-scenario"],
            environment: ["BRIEFEED_RADIO_RESET_STORE": "1"]
        )

        AppRuntime.prepareRadioFixturePreferencesIfNeeded(
            configuration: configuration,
            defaults: defaults
        )

        #expect(defaults.double(forKey: UserDefaultsKey.playbackSpeed.rawValue) == 2)
        #expect(configuration.radioFixtureScenario == "not-a-scenario")
        #expect(RadioFixtureScenario(rawValue: configuration.radioFixtureScenario ?? "") == nil)
    }
    #endif

    @Test func resettingExplicitStoreRemovesPreviouslySavedObjects() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Briefeed-RadioRuntime-\(UUID().uuidString).sqlite")
        defer {
            for url in [
                storeURL,
                URL(fileURLWithPath: storeURL.path + "-wal"),
                URL(fileURLWithPath: storeURL.path + "-shm")
            ] {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let initial = PersistenceController(storeURL: storeURL)
        let feed = Feed(context: initial.container.viewContext)
        feed.id = UUID()
        feed.name = "sentinel"
        try initial.container.viewContext.save()

        let reset = PersistenceController(storeURL: storeURL, resetStore: true)
        let request = Feed.fetchRequest()
        #expect(try reset.container.viewContext.count(for: request) == 0)
    }

    @Test func resetStoreIgnoresMissingStoreAndSidecars() throws {
        var removedURLs: [URL] = []
        let storeURL = URL(fileURLWithPath: "/tmp/Briefeed-RadioRuntime.sqlite")

        try PersistenceController.removeStoreFiles(at: storeURL) { url in
            removedURLs.append(url)
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        }

        #expect(removedURLs == [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm")
        ])
    }

    @Test func resetStorePropagatesNonMissingRemovalErrors() {
        let storeURL = URL(fileURLWithPath: "/tmp/Briefeed-RadioRuntime.sqlite")

        #expect(throws: StoreRemovalError.self) {
            try PersistenceController.removeStoreFiles(at: storeURL) { _ in
                throw StoreRemovalError.denied
            }
        }
    }
}
