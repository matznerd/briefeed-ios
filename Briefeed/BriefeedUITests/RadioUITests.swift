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
}
