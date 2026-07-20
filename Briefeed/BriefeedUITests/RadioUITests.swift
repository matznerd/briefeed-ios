import XCTest

final class RadioUITests: XCTestCase {
    private var app: XCUIApplication!

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
        XCTAssertEqual(app.tabBars.count, 0, "The hidden native tab bar must not create a second navigation row")
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
        app.buttons["radio.manageSources"].tap()
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
}
