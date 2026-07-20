//
//  AppRuntime.swift
//  Briefeed
//
//  Runtime helpers for keeping app launch behavior predictable in tests.
//

import Foundation

enum AppRuntime {
    struct Configuration: Equatable {
        let arguments: [String]
        let environment: [String: String]

        init(
            arguments: [String] = ProcessInfo.processInfo.arguments,
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) {
            self.arguments = arguments
            self.environment = environment
        }

        var radioFixtureScenario: String? {
            guard let index = arguments.firstIndex(of: "-briefeed-radio-fixture"),
                  arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }

        var shouldResetRadioFixtureStore: Bool {
            environment["BRIEFEED_RADIO_RESET_STORE"] == "1"
        }

        var usesIsolatedRadioStore: Bool { radioFixtureScenario != nil }

        var isHostedXCTestEnvironment: Bool {
            environment["BRIEFEED_FORCE_HOSTED_XCTEST"] == "1"
                || environment["XCTestConfigurationFilePath"] != nil
        }

        var shouldSkipAutomaticStartupWork: Bool {
            usesIsolatedRadioStore
                || environment["BRIEFEED_DISABLE_AUTOMATIC_STARTUP"] == "1"
                || isHostedXCTestEnvironment
        }
    }

    static let configuration = Configuration()

    static var isHostedXCTest: Bool {
        let hasLoadedUnitTestBundle = Bundle.allBundles.contains { bundle in
            let path = bundle.bundlePath
            return path.hasSuffix(".xctest") && !path.contains("UITests")
        }

        return configuration.isHostedXCTestEnvironment || hasLoadedUnitTestBundle
    }

    static var radioFixtureScenario: String? { configuration.radioFixtureScenario }
    static var shouldResetRadioFixtureStore: Bool { configuration.shouldResetRadioFixtureStore }

    static var shouldSkipAutomaticStartupWork: Bool {
        configuration.shouldSkipAutomaticStartupWork || isHostedXCTest
    }
}
