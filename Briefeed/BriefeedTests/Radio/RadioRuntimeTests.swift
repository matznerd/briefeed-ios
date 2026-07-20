import Foundation
import Testing
@testable import Briefeed

@Suite("Radio runtime")
struct RadioRuntimeTests {
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
}
