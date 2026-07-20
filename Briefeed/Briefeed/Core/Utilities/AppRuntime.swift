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

        var shouldCompleteRadioFixtureCurrent: Bool {
            environment["BRIEFEED_RADIO_COMPLETE_CURRENT"] == "1"
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

    #if DEBUG
    static var radioFixtureScenario: RadioFixtureScenario? {
        configuration.radioFixtureScenario.flatMap(RadioFixtureScenario.init(rawValue:))
    }

    static var shouldResetRadioFixtureStore: Bool {
        radioFixtureScenario != nil && configuration.shouldResetRadioFixtureStore
    }

    static var shouldCompleteRadioFixtureCurrent: Bool {
        radioFixtureScenario != nil && configuration.shouldCompleteRadioFixtureCurrent
    }

    static let radioFixtureNow: Date = {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 3_600) * 3_600)
    }()

    static var radioFixtureDefinition: RadioFixtureScenarioDefinition? {
        radioFixtureScenario.map { RadioFixtureScenarioDefinition.make(scenario: $0, now: radioFixtureNow) }
    }

    static func prepareRadioFixturePreferencesIfNeeded(
        configuration: Configuration = configuration,
        defaults: UserDefaults = .standard
    ) {
        guard configuration.radioFixtureScenario.flatMap(RadioFixtureScenario.init(rawValue:)) != nil else {
            return
        }
        if configuration.shouldResetRadioFixtureStore {
            resetRadioFixturePreferences(defaults: defaults)
        }
        if let rawAutoplay = configuration.environment["BRIEFEED_RADIO_AUTOPLAY"] {
            defaults.set(rawAutoplay == "1", forKey: UserDefaultsKey.autoPlayLiveNewsOnOpen.rawValue)
        }
    }

    static func resetRadioFixturePreferences(defaults: UserDefaults = .standard) {
        for key in [
            RadioSessionStore.storageKey,
            UserDefaultsKey.playbackSpeed.rawValue,
            UserDefaultsKey.rssPlaybackSpeed.rawValue,
            UserDefaultsKey.autoPlayLiveNewsOnOpen.rawValue,
            UserDefaultsKey.rssLastPlayedEpisodeId.rawValue
        ] {
            defaults.removeObject(forKey: key)
        }
        defaults.set(false, forKey: UserDefaultsKey.autoPlayLiveNewsOnOpen.rawValue)
        defaults.set(1.0, forKey: UserDefaultsKey.playbackSpeed.rawValue)
    }
    #else
    static var radioFixtureScenario: Never? { nil }
    static var shouldResetRadioFixtureStore: Bool { false }
    static var shouldCompleteRadioFixtureCurrent: Bool { false }
    #endif

    static var shouldSkipAutomaticStartupWork: Bool {
        #if DEBUG
        return radioFixtureScenario != nil
            || configuration.environment["BRIEFEED_DISABLE_AUTOMATIC_STARTUP"] == "1"
            || isHostedXCTest
        #else
        return configuration.environment["BRIEFEED_DISABLE_AUTOMATIC_STARTUP"] == "1"
            || isHostedXCTest
        #endif
    }
}
