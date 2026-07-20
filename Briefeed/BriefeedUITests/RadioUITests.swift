import XCTest

final class RadioUITests: XCTestCase {
    private var app: XCUIApplication!

    private struct FixtureDiagnostics: Equatable {
        let bootstrapPlayIntents: Int
        let refreshInvocations: Int
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-briefeed-radio-fixture", "partial"]
        app.launchEnvironment["BRIEFEED_RADIO_RESET_STORE"] = "1"
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testLaunchesIntoRadioAndSwitchesAccessibleRail() throws {
        app.launch()

        XCTAssertTrue(app.buttons["tab.radio"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.radio"].isSelected)
        XCTAssertTrue(app.staticTexts["Morning Update"].waitForExistence(timeout: 3))

        app.buttons["tab.brief"].tap()
        XCTAssertTrue(app.buttons["tab.brief"].isSelected)

        app.buttons["tab.feed"].tap()
        XCTAssertTrue(app.buttons["tab.feed"].isSelected)

        app.buttons["tab.radio"].tap()
        XCTAssertTrue(app.buttons["tab.radio"].isSelected)
        XCTAssertTrue(app.staticTexts["Morning Update"].exists)
        XCTAssertEqual(
            app.otherElements.matching(identifier: "navigation.rail").count,
            1,
            "Radio, Brief, and Feed must have exactly one navigation rail"
        )
        XCTAssertEqual(
            app.tabBars.allElementsBoundByIndex.filter(\.isHittable).count,
            0,
            "The root view must not expose a native tab bar alongside the custom rail"
        )
    }

    @MainActor
    func testRailControlsAreAccessibleAndMeetMinimumHitSize() throws {
        app.launch()

        for (identifier, label) in [
            ("tab.radio", "Radio"),
            ("tab.brief", "Brief"),
            ("tab.feed", "Feed")
        ] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertEqual(button.label, label)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
    }

    @MainActor
    func testSettingsOpensAndDismissesFromEveryPrimarySection() throws {
        app.launch()

        for tab in ["tab.radio", "tab.brief", "tab.feed"] {
            app.buttons[tab].tap()

            let settingsButton = app.buttons["navigation.settings"]
            XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
            XCTAssertGreaterThanOrEqual(settingsButton.frame.width, 44)
            XCTAssertGreaterThanOrEqual(settingsButton.frame.height, 44)
            settingsButton.tap()

            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
            app.buttons["settings.done"].tap()
            XCTAssertFalse(app.navigationBars["Settings"].exists)
        }
    }

    @MainActor
    func testSettingsLinksToFeedOrderAndEnablement() throws {
        app.launch()
        app.buttons["navigation.settings"].tap()

        let sourceSettings = app.buttons["settings.feedOrder"]
        for _ in 0..<4 where !sourceSettings.exists {
            app.swipeUp()
        }
        XCTAssertTrue(sourceSettings.waitForExistence(timeout: 3))
        sourceSettings.tap()
        XCTAssertTrue(app.navigationBars["Radio Sources"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testRadioSourceManagementPreservesDetailsAndDeleteAffordances() throws {
        app.launch()
        app.buttons["navigation.settings"].tap()
        let sourceSettings = app.buttons["settings.feedOrder"]
        for _ in 0..<4 where !sourceSettings.exists {
            app.swipeUp()
        }
        sourceSettings.tap()
        XCTAssertTrue(app.navigationBars["Radio Sources"].waitForExistence(timeout: 3))

        let source = app.buttons["radio.sourceDetail"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        source.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        source.swipeRight()

        source.tap()
        let details = app.descendants(matching: .any)["radio.sourceDetails"]
        XCTAssertTrue(details.waitForExistence(timeout: 3))
    }

    @MainActor
    func testCompactRadioPlayerExposesRightHandTransportAndAccessibleScrubber() throws {
        app.launch()

        let player = app.otherElements["miniPlayer.container"]
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["miniPlayer.previous"].exists)

        for identifier in [
            "miniPlayer.expand",
            "miniPlayer.title",
            "miniPlayer.speed",
            "miniPlayer.sleep",
            "miniPlayer.rewind",
            "miniPlayer.playPause",
            "miniPlayer.forward",
            "miniPlayer.next"
        ] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.waitForExistence(timeout: 3))
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }

        let scrubber = app.otherElements["miniPlayer.scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(scrubber.frame.height, 44)
        XCTAssertFalse(scrubber.value as? String == nil)
        XCTAssertLessThanOrEqual(
            abs(app.buttons["miniPlayer.speed"].frame.midY - scrubber.frame.midY),
            8,
            "Speed, sleep, and scrubbing should share the compact lower control row"
        )
        XCTAssertLessThanOrEqual(
            player.frame.height,
            130,
            "The compact controls plus the home-indicator safe area should remain short"
        )
        XCTAssertLessThanOrEqual(
            app.frame.maxY - player.frame.maxY,
            40,
            "Player controls should end at the phone's bottom safe-area boundary"
        )

        let rail = app.otherElements["navigation.rail"]
        XCTAssertTrue(rail.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(rail.frame.maxY, player.frame.minY + 1)
    }

    @MainActor
    func testRadioHomeShowsOneLatestRowPerSourceInPriorityOrder() throws {
        app.launch()

        let npr = app.staticTexts["radio.episodeTitle.fixture-npr.fixture-partial"]
        let bbc = app.staticTexts["radio.episodeTitle.fixture-bbc.fixture-fresh"]
        XCTAssertTrue(npr.waitForExistence(timeout: 5))
        XCTAssertTrue(bbc.waitForExistence(timeout: 5))
        XCTAssertLessThan(npr.frame.minY, bbc.frame.minY)
        XCTAssertTrue(app.staticTexts["20% listened"].exists)
        XCTAssertFalse(app.buttons["radio.manageSources"].exists)
    }

    @MainActor
    func testRadioHomeRowsCanClearTheBottomChrome() throws {
        app.launch()

        let bottomSource = app.buttons["radio.episode.fixture-world.fixture-malformed"]
        for _ in 0..<5 where !bottomSource.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(bottomSource.waitForExistence(timeout: 3))
        XCTAssertTrue(bottomSource.isHittable)
        let rail = app.otherElements["navigation.rail"]
        XCTAssertTrue(rail.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(
            bottomSource.frame.maxY,
            rail.frame.minY + 1,
            "A source row must scroll fully above the navigation and player chrome"
        )
    }

    @MainActor
    func testSourceArchiveExposesEarlierEpisodesAndManualQueueing() throws {
        app.launch()

        let npr = app.buttons["radio.episode.fixture-npr.fixture-partial"]
        XCTAssertTrue(npr.waitForExistence(timeout: 5))
        npr.tap()

        XCTAssertTrue(app.otherElements["radio.sourceArchive"].waitForExistence(timeout: 3))
        let options = app.buttons["radio.archiveOptions.fixture-npr.fixture-duplicate-guid"]
        XCTAssertTrue(options.waitForExistence(timeout: 3))
        options.tap()
        let playLater = app.buttons["Play Later"].exists
            ? app.buttons["Play Later"]
            : app.menuItems["Play Later"]
        XCTAssertTrue(playLater.waitForExistence(timeout: 2))
        playLater.tap()
        XCTAssertTrue(app.staticTexts["Queued for later"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCaughtUpMiniPlayerOffersOnlyRefresh() throws {
        app.launchArguments = ["-briefeed-radio-fixture", "exhausted"]
        app.launchEnvironment["BRIEFEED_RADIO_RESET_STORE"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["You're caught up"].waitForExistence(timeout: 5))
        let refresh = app.buttons["miniPlayer.refresh"]
        XCTAssertTrue(refresh.exists)
        XCTAssertGreaterThanOrEqual(refresh.frame.width, 44)
        XCTAssertGreaterThanOrEqual(refresh.frame.height, 44)
        XCTAssertFalse(app.buttons["miniPlayer.playPause"].exists)
        XCTAssertFalse(app.otherElements["miniPlayer.scrubber"].exists)
        XCTAssertFalse(app.buttons["miniPlayer.expand"].exists)
    }

    @MainActor
    func testCompactRadioPlayerOffersCanonicalSpeedAndSleepControls() throws {
        app.launch()

        let speed = app.buttons["miniPlayer.speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 5))
        speed.tap()
        for label in ["0.5x", "0.75x", "1x", "1.25x", "1.5x", "1.75x", "2x", "2.5x", "3x"] {
            XCTAssertTrue(app.buttons[label].exists || app.menuItems[label].exists)
        }
        app.tap()

        let sleep = app.buttons["miniPlayer.sleep"]
        XCTAssertTrue(sleep.waitForExistence(timeout: 3))
        sleep.tap()
        for label in ["Off", "End of Episode", "10 min", "20 min", "30 min", "45 min", "60 min", "Custom"] {
            XCTAssertTrue(app.buttons[label].exists || app.menuItems[label].exists)
        }
    }

    @MainActor
    func testPartialPlaybackPersistsAcrossProcessRelaunch() throws {
        app = launchFixture("partial", reset: true)
        let scrubber = app.otherElements["miniPlayer.scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 15))
        let initial = try elapsedSeconds(in: scrubber)

        app.buttons["miniPlayer.forward"].tap()
        XCTAssertGreaterThan(try elapsedSeconds(in: scrubber), initial)
        app.buttons["miniPlayer.playPause"].tap()
        XCTAssertTrue(waitForLabel("Pause", on: app.buttons["miniPlayer.playPause"]))
        app.buttons["miniPlayer.playPause"].tap()
        XCTAssertTrue(waitForLabel("Play", on: app.buttons["miniPlayer.playPause"]))
        let paused = try elapsedSeconds(in: scrubber)
        XCTAssertGreaterThan(paused, initial)

        app.terminate()
        app = launchFixture("partial", reset: false)
        let restored = app.otherElements["miniPlayer.scrubber"]
        XCTAssertTrue(restored.waitForExistence(timeout: 15))
        XCTAssertEqual(try elapsedSeconds(in: restored), paused, accuracy: 3)
        XCTAssertTrue(app.staticTexts["Morning Update"].exists)
    }

    @MainActor
    func testCompletedEpisodeDoesNotReplayAfterSameHourRelaunch() throws {
        app = launchFixture("partial", reset: true, completeCurrent: true)
        XCTAssertTrue(waitForMiniPlayerTitle("World Service Brief", timeout: 15))
        XCTAssertTrue(app.staticTexts["Morning Update"].exists)
        XCTAssertTrue(app.staticTexts["Listened"].exists)

        app.terminate()
        app = launchFixture("partial", reset: false)
        XCTAssertTrue(waitForMiniPlayerTitle("World Service Brief", timeout: 15))
        XCTAssertTrue(app.staticTexts["Morning Update"].exists)
        XCTAssertTrue(app.staticTexts["Listened"].exists)
    }

    @MainActor
    func testAutoplayRemainsOptInAndStartsOnlyWhenEnabled() throws {
        app = launchFixture("partial", reset: true, autoplay: false)
        XCTAssertTrue(app.buttons["miniPlayer.playPause"].waitForExistence(timeout: 15))
        XCTAssertTrue(waitForLabel("Play", on: app.buttons["miniPlayer.playPause"]))
        XCTAssertEqual(try fixtureDiagnostics(), FixtureDiagnostics(bootstrapPlayIntents: 0, refreshInvocations: 0))
        app.terminate()

        app = launchFixture("partial", reset: false, autoplay: false)
        XCTAssertTrue(app.buttons["miniPlayer.playPause"].waitForExistence(timeout: 15))
        XCTAssertEqual(try fixtureDiagnostics(), FixtureDiagnostics(bootstrapPlayIntents: 0, refreshInvocations: 0))
        app.terminate()

        app = launchFixture("partial", reset: true, autoplay: true)
        XCTAssertTrue(app.buttons["miniPlayer.playPause"].waitForExistence(timeout: 15))
        XCTAssertTrue(waitForLabel("Pause", on: app.buttons["miniPlayer.playPause"], timeout: 8))
        XCTAssertEqual(try fixtureDiagnostics(), FixtureDiagnostics(bootstrapPlayIntents: 1, refreshInvocations: 0))
        app.terminate()

        app = launchFixture("partial", reset: false, autoplay: true)
        XCTAssertTrue(app.buttons["miniPlayer.playPause"].waitForExistence(timeout: 15))
        XCTAssertTrue(waitForLabel("Pause", on: app.buttons["miniPlayer.playPause"], timeout: 8))
        XCTAssertEqual(try fixtureDiagnostics(), FixtureDiagnostics(bootstrapPlayIntents: 1, refreshInvocations: 0))
    }

    @MainActor
    func testResetBoundariesPreventCrossScenarioBleed() throws {
        app = launchFixture("partial", reset: true)
        XCTAssertTrue(app.staticTexts["Morning Update"].waitForExistence(timeout: 15))
        app.terminate()

        app = launchFixture("completed", reset: true)
        XCTAssertTrue(waitForMiniPlayerTitle("World Service Brief", timeout: 15))
        XCTAssertTrue(app.staticTexts["Morning Update"].exists)
        XCTAssertTrue(app.staticTexts["Listened"].exists)
        app.terminate()

        app = launchFixture("partial", reset: true)
        XCTAssertTrue(app.staticTexts["Morning Update"].waitForExistence(timeout: 15))
        let scrubber = app.otherElements["miniPlayer.scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        XCTAssertEqual(try elapsedSeconds(in: scrubber), 18, accuracy: 1)
    }

    @MainActor
    func testFixtureStatesRemainDistinctAndExposeRecoveryActions() throws {
        let expectations: [(scenario: String, title: String, action: String?)] = [
            ("offline", "Waiting for Network", "radio.retry"),
            ("refreshing", "Refreshing Radio", nil),
            ("all-failed", "Radio needs attention", "radio.refresh"),
            ("no-sources", "Choose your sources", "radio.addSource"),
            ("exhausted", "You're caught up", "radio.refresh")
        ]

        for expected in expectations {
            app?.terminate()
            app = launchFixture(expected.scenario, reset: true)
            XCTAssertTrue(app.staticTexts[expected.title].waitForExistence(timeout: 15), expected.scenario)
            if let action = expected.action {
                let button = app.buttons[action].firstMatch
                XCTAssertTrue(button.waitForExistence(timeout: 3), expected.scenario)
                button.tap()
                switch expected.scenario {
                case "offline", "exhausted":
                    XCTAssertTrue(app.staticTexts[expected.title].waitForExistence(timeout: 3))
                case "all-failed":
                    XCTAssertEqual(try fixtureDiagnostics(), FixtureDiagnostics(bootstrapPlayIntents: 0, refreshInvocations: 1))
                    XCTAssertTrue(app.staticTexts[expected.title].waitForExistence(timeout: 3))
                case "no-sources":
                    XCTAssertTrue(app.navigationBars["Add RSS Feed"].waitForExistence(timeout: 3))
                default:
                    break
                }
            }
        }

        app.terminate()
        app = launchFixture("degraded", reset: true)
        XCTAssertTrue(app.staticTexts["Morning Update"].waitForExistence(timeout: 15))
        let homeFailureNotice = app.descendants(matching: .any)
            .matching(identifier: "radio.sourceFailures")
            .firstMatch
        XCTAssertFalse(homeFailureNotice.exists)
        XCTAssertFalse(app.staticTexts["Some sources could not refresh"].exists)
        XCTAssertFalse(app.staticTexts["Radio needs attention"].exists)

        app.buttons["navigation.settings"].tap()
        let sourceSettings = app.buttons["settings.feedOrder"]
        for _ in 0..<4 where !sourceSettings.exists {
            app.swipeUp()
        }
        XCTAssertTrue(sourceSettings.waitForExistence(timeout: 3))
        sourceSettings.tap()
        XCTAssertTrue(app.navigationBars["Radio Sources"].waitForExistence(timeout: 3))
        let sourceFailure = app.descendants(matching: .any)
            .matching(identifier: "radio.sourceFailure.fixture-world")
            .firstMatch
        XCTAssertTrue(sourceFailure.waitForExistence(timeout: 3))
    }

    @MainActor
    func testSpeedPersistsAndSleepTimerCanUseEndOfEpisode() throws {
        app = launchFixture("partial", reset: true)
        let speed = app.buttons["miniPlayer.speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 15))
        speed.tap()
        app.buttons["1.5x"].tap()
        XCTAssertEqual(speed.value as? String, "1.5x")

        let sleepTimer = app.buttons["miniPlayer.sleep"]
        sleepTimer.tap()
        app.buttons["End of Episode"].tap()
        XCTAssertEqual(sleepTimer.value as? String, "End of Episode")

        sleepTimer.tap()
        app.buttons["Custom"].tap()
        let customMinutes = app.steppers["sleepTimer.customMinutes"]
        XCTAssertTrue(customMinutes.waitForExistence(timeout: 3))
        XCTAssertEqual(customMinutes.value as? String, "20 minutes")
        app.buttons["sleepTimer.set"].tap()
        XCTAssertTrue(
            ["19 min", "20 min"].contains(sleepTimer.value as? String),
            "The custom timer should show its current remaining minutes, not exceed the selected duration"
        )

        app.terminate()
        app = launchFixture("partial", reset: false)
        let restoredSpeed = app.buttons["miniPlayer.speed"]
        XCTAssertTrue(restoredSpeed.waitForExistence(timeout: 15))
        XCTAssertEqual(restoredSpeed.value as? String, "1.5x")
    }

    @MainActor
    func testHeadlessRadioSmoke() throws {
        app = launchFixture("partial", reset: true)
        XCTAssertTrue(app.staticTexts["Morning Update"].waitForExistence(timeout: 15))
        let scrubber = app.otherElements["miniPlayer.scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        let initial = try elapsedSeconds(in: scrubber)

        app.buttons["miniPlayer.playPause"].tap()
        XCTAssertTrue(waitForLabel("Pause", on: app.buttons["miniPlayer.playPause"]))
        sleep(2)
        app.buttons["miniPlayer.forward"].tap()
        XCTAssertGreaterThan(try elapsedSeconds(in: scrubber), initial + 8)
        app.buttons["miniPlayer.rewind"].tap()
        app.buttons["miniPlayer.next"].tap()
        XCTAssertTrue(waitForMiniPlayerTitle("World Service Brief", timeout: 5))
        app.buttons["miniPlayer.playPause"].tap()

        app.terminate()
        app = launchFixture("partial", reset: false)
        XCTAssertTrue(waitForMiniPlayerTitle("World Service Brief", timeout: 15))
    }

    @MainActor
    private func launchFixture(
        _ scenario: String,
        reset: Bool,
        autoplay: Bool? = nil,
        completeCurrent: Bool = false
    ) -> XCUIApplication {
        let launched = XCUIApplication()
        launched.launchArguments = ["-briefeed-radio-fixture", scenario]
        launched.launchEnvironment["BRIEFEED_RADIO_RESET_STORE"] = reset ? "1" : "0"
        if let autoplay {
            launched.launchEnvironment["BRIEFEED_RADIO_AUTOPLAY"] = autoplay ? "1" : "0"
        }
        launched.launchEnvironment["BRIEFEED_RADIO_COMPLETE_CURRENT"] = completeCurrent ? "1" : "0"
        launched.launch()
        return launched
    }

    private func elapsedSeconds(in scrubber: XCUIElement) throws -> Double {
        let value = try XCTUnwrap(scrubber.value as? String)
        let expression = try NSRegularExpression(
            pattern: #"([0-9]+) minutes?, ([0-9]+) seconds? elapsed"#
        )
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: range),
              let minuteRange = Range(match.range(at: 1), in: value),
              let secondRange = Range(match.range(at: 2), in: value),
              let minutes = Double(value[minuteRange]),
              let seconds = Double(value[secondRange]) else {
            XCTFail("Unexpected scrubber value: \(value)")
            return 0
        }
        return minutes * 60 + seconds
    }

    private func fixtureDiagnostics() throws -> FixtureDiagnostics {
        let diagnostics = app.otherElements["radio.fixtureDiagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        let value = try XCTUnwrap(diagnostics.value as? String)
        let expression = try NSRegularExpression(
            pattern: #"bootstrapPlayIntents=([0-9]+);refreshInvocations=([0-9]+)"#
        )
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let match = try XCTUnwrap(expression.firstMatch(in: value, range: range))
        let playRange = try XCTUnwrap(Range(match.range(at: 1), in: value))
        let refreshRange = try XCTUnwrap(Range(match.range(at: 2), in: value))
        return FixtureDiagnostics(
            bootstrapPlayIntents: try XCTUnwrap(Int(value[playRange])),
            refreshInvocations: try XCTUnwrap(Int(value[refreshRange]))
        )
    }

    private func waitForLabel(
        _ label: String,
        on element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForMiniPlayerTitle(_ title: String, timeout: TimeInterval) -> Bool {
        let titleButton = app.buttons["miniPlayer.title"]
        guard titleButton.waitForExistence(timeout: timeout) else { return false }
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", title)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: titleButton)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
