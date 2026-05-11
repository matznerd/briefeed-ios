//
//  AppRuntime.swift
//  Briefeed
//
//  Runtime helpers for keeping app launch behavior predictable in tests.
//

import Foundation

enum AppRuntime {
    static var isHostedXCTest: Bool {
        if ProcessInfo.processInfo.environment["BRIEFEED_FORCE_HOSTED_XCTEST"] == "1" {
            return true
        }

        let hasXCTestEnvironment = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let hasLoadedUnitTestBundle = Bundle.allBundles.contains { bundle in
            let path = bundle.bundlePath
            return path.hasSuffix(".xctest") && !path.contains("UITests")
        }

        return hasXCTestEnvironment || hasLoadedUnitTestBundle
    }

    static var shouldSkipAutomaticStartupWork: Bool {
        ProcessInfo.processInfo.environment["BRIEFEED_DISABLE_AUTOMATIC_STARTUP"] == "1" || isHostedXCTest
    }
}
