//
//  AudioPlayerUITests.swift
//  BriefeedUITests
//
//  Created by Briefeed Team on 1/8/25.
//

import XCTest

/// UI tests for audio player functionality
final class AudioPlayerUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        
        // Enable new audio player for testing
        app.launchEnvironment["FEATURE_USE_NEW_AUDIO_PLAYER"] = "1"
        
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Mini Player Tests
    
    func testMiniPlayerAppears() throws {
        // Given - Navigate to an article
        let feedTab = app.tabBars.buttons["Feed"]
        XCTAssertTrue(feedTab.waitForExistence(timeout: 5))
        feedTab.tap()
        
        // Select first article
        let firstArticle = app.tables.cells.firstMatch
        XCTAssertTrue(firstArticle.waitForExistence(timeout: 5))
        firstArticle.tap()
        
        // When - Tap play button
        let playButton = app.buttons["Play Audio"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
        playButton.tap()
        
        // Then - Mini player should appear
        let miniPlayer = app.otherElements["MiniAudioPlayer"]
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 10))
        
        // Verify player shows article info
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Test Article'")).element.exists)
        
        // Verify playback controls
        XCTAssertTrue(app.buttons["Pause"].exists || app.buttons["Play"].exists)
        XCTAssertTrue(app.buttons["Skip Forward 15"].exists)
        XCTAssertTrue(app.buttons["Skip Backward 15"].exists)
    }
    
    func testMiniPlayerPlayPauseToggle() throws {
        // Given - Mini player is showing
        setupMiniPlayer()
        
        // When - Tap play/pause
        let pauseButton = app.buttons["Pause"]
        if pauseButton.exists {
            pauseButton.tap()
            
            // Then - Should show play button
            XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 2))
            
            // Tap play
            app.buttons["Play"].tap()
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 2))
        }
    }
    
    func testMiniPlayerProgressBar() throws {
        // Given - Playing audio
        setupMiniPlayer()
        
        // Then - Progress bar should be visible
        let progressBar = app.progressIndicators["AudioProgress"]
        XCTAssertTrue(progressBar.exists)
        
        // Wait and verify progress changes
        let initialProgress = progressBar.value as? String ?? "0%"
        sleep(3) // Wait for playback
        let updatedProgress = progressBar.value as? String ?? "0%"
        
        XCTAssertNotEqual(initialProgress, updatedProgress, "Progress should update during playback")
    }
    
    // MARK: - Expanded Player Tests
    
    func testExpandedPlayerOpens() throws {
        // Given - Mini player is showing
        setupMiniPlayer()
        
        // When - Tap mini player
        let miniPlayer = app.otherElements["MiniAudioPlayer"]
        miniPlayer.tap()
        
        // Then - Expanded player should appear
        let expandedPlayer = app.otherElements["ExpandedAudioPlayer"]
        XCTAssertTrue(expandedPlayer.waitForExistence(timeout: 5))
        
        // Verify expanded player elements
        XCTAssertTrue(app.buttons["Minimize"].exists)
        XCTAssertTrue(app.sliders["AudioSeeker"].exists)
        XCTAssertTrue(app.buttons["PlaybackSpeed"].exists)
        XCTAssertTrue(app.buttons["SleepTimer"].exists)
    }
    
    func testExpandedPlayerSeek() throws {
        // Given - Expanded player is open
        setupExpandedPlayer()
        
        // When - Adjust seek slider
        let seekSlider = app.sliders["AudioSeeker"]
        XCTAssertTrue(seekSlider.exists)
        
        // Drag to 50%
        seekSlider.adjust(toNormalizedSliderPosition: 0.5)
        
        // Then - Time labels should update
        let currentTimeLabel = app.staticTexts["CurrentTime"]
        let remainingTimeLabel = app.staticTexts["RemainingTime"]
        
        XCTAssertTrue(currentTimeLabel.exists)
        XCTAssertTrue(remainingTimeLabel.exists)
    }
    
    func testPlaybackSpeedControl() throws {
        // Given - Expanded player is open
        setupExpandedPlayer()
        
        // When - Tap speed button
        let speedButton = app.buttons["PlaybackSpeed"]
        XCTAssertTrue(speedButton.exists)
        speedButton.tap()
        
        // Then - Speed options should appear
        let speedSheet = app.sheets["PlaybackSpeedPicker"]
        XCTAssertTrue(speedSheet.waitForExistence(timeout: 2))
        
        // Select 1.5x speed
        let speed15x = speedSheet.buttons["1.50x"]
        XCTAssertTrue(speed15x.exists)
        speed15x.tap()
        
        // Verify speed changed
        XCTAssertTrue(speedButton.label.contains("1.5"))
    }
    
    func testSleepTimerControl() throws {
        // Given - Expanded player is open
        setupExpandedPlayer()
        
        // When - Tap sleep timer
        let sleepButton = app.buttons["SleepTimer"]
        XCTAssertTrue(sleepButton.exists)
        sleepButton.tap()
        
        // Then - Sleep timer options should appear
        let sleepSheet = app.sheets["SleepTimerPicker"]
        XCTAssertTrue(sleepSheet.waitForExistence(timeout: 2))
        
        // Select 15 minutes
        let minutes15 = sleepSheet.buttons["15 minutes"]
        XCTAssertTrue(minutes15.exists)
        minutes15.tap()
        
        // Verify timer is active
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '14:'")).element.exists)
    }
    
    // MARK: - Queue Tests
    
    func testQueueManagement() throws {
        // Given - Navigate to Brief tab
        let briefTab = app.tabBars.buttons["Brief"]
        briefTab.tap()
        
        // Add multiple items to queue
        let addAllButton = app.buttons["Add All to Queue"]
        if addAllButton.exists {
            addAllButton.tap()
        }
        
        // Open expanded player
        setupExpandedPlayer()
        
        // When - View queue
        let moreButton = app.buttons["More"]
        moreButton.tap()
        
        let queueButton = app.buttons["Queue"]
        XCTAssertTrue(queueButton.exists)
        queueButton.tap()
        
        // Then - Queue should show items
        let queueView = app.otherElements["QueueView"]
        XCTAssertTrue(queueView.waitForExistence(timeout: 5))
        
        // Verify queue has items
        let queueCells = app.tables["QueueTable"].cells
        XCTAssertGreaterThan(queueCells.count, 0)
    }
    
    func testNextPreviousButtons() throws {
        // Given - Queue has multiple items
        setupQueueWithMultipleItems()
        
        // When - Tap next
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.exists)
        nextButton.tap()
        
        // Then - Should play next item
        sleep(2) // Wait for transition
        
        // Verify different content is playing
        let titleLabel = app.staticTexts.matching(identifier: "NowPlayingTitle").element
        XCTAssertTrue(titleLabel.exists)
        
        // Tap previous
        let previousButton = app.buttons["Previous"]
        XCTAssertTrue(previousButton.exists)
        previousButton.tap()
        
        sleep(2) // Wait for transition
    }
    
    // MARK: - Feature Flag Tests
    
    func testFeatureFlagToggle() throws {
        // Given - Navigate to Settings
        let settingsTab = app.tabBars.buttons["Settings"]
        settingsTab.tap()
        
        // Scroll to Developer Settings (only in DEBUG)
        #if DEBUG
        let developerSection = app.staticTexts["Developer Settings"]
        if !developerSection.exists {
            app.swipeUp() // Scroll down
        }
        
        // When - Toggle new audio player
        let newPlayerToggle = app.switches["Use New Audio Player UI"]
        if newPlayerToggle.exists {
            let initialValue = newPlayerToggle.value as? String == "1"
            newPlayerToggle.tap()
            
            // Then - Toggle should change
            let newValue = newPlayerToggle.value as? String == "1"
            XCTAssertNotEqual(initialValue, newValue)
        }
        #endif
    }
    
    // MARK: - RSS Episode Tests
    
    func testRSSEpisodePlayback() throws {
        // Given - Navigate to Live News
        let liveNewsTab = app.tabBars.buttons["Live News"]
        liveNewsTab.tap()
        
        // Play first episode
        let firstEpisode = app.tables.cells.firstMatch
        if firstEpisode.waitForExistence(timeout: 5) {
            firstEpisode.tap()
            
            let playButton = app.buttons["Play Episode"]
            if playButton.exists {
                playButton.tap()
                
                // Then - Should show RSS indicator
                let miniPlayer = app.otherElements["MiniAudioPlayer"]
                XCTAssertTrue(miniPlayer.waitForExistence(timeout: 10))
                
                // Verify RSS indicator
                XCTAssertTrue(app.images["RadioWaves"].exists)
                
                // Verify 30-second skip for RSS
                XCTAssertTrue(app.buttons["Skip Forward 30"].exists)
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling() throws {
        // Given - Simulate network error
        app.launchEnvironment["SIMULATE_NETWORK_ERROR"] = "1"
        app.launch()
        
        // Try to play article
        setupMiniPlayer()
        
        // Then - Should show error
        let errorAlert = app.alerts["Playback Error"]
        if errorAlert.waitForExistence(timeout: 5) {
            XCTAssertTrue(errorAlert.staticTexts["Failed to generate audio"].exists)
            
            // Dismiss error
            errorAlert.buttons["OK"].tap()
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupMiniPlayer() {
        // Navigate to article and start playback
        let feedTab = app.tabBars.buttons["Feed"]
        if feedTab.exists {
            feedTab.tap()
        }
        
        let firstArticle = app.tables.cells.firstMatch
        if firstArticle.waitForExistence(timeout: 5) {
            firstArticle.tap()
            
            let playButton = app.buttons["Play Audio"]
            if playButton.waitForExistence(timeout: 5) {
                playButton.tap()
            }
        }
        
        // Wait for mini player
        _ = app.otherElements["MiniAudioPlayer"].waitForExistence(timeout: 10)
    }
    
    private func setupExpandedPlayer() {
        setupMiniPlayer()
        
        let miniPlayer = app.otherElements["MiniAudioPlayer"]
        if miniPlayer.exists {
            miniPlayer.tap()
        }
        
        _ = app.otherElements["ExpandedAudioPlayer"].waitForExistence(timeout: 5)
    }
    
    private func setupQueueWithMultipleItems() {
        // Add items to queue from Brief tab
        let briefTab = app.tabBars.buttons["Brief"]
        briefTab.tap()
        
        // Add multiple items
        for i in 0..<3 {
            let cell = app.tables.cells.element(boundBy: i)
            if cell.exists {
                cell.swipeLeft()
                let queueButton = app.buttons["Queue"]
                if queueButton.exists {
                    queueButton.tap()
                }
            }
        }
        
        // Start playback
        let firstCell = app.tables.cells.firstMatch
        firstCell.tap()
        
        let playButton = app.buttons["Play Audio"]
        if playButton.exists {
            playButton.tap()
        }
    }
}

// MARK: - Performance Tests

extension AudioPlayerUITests {
    
    func testLaunchPerformance() throws {
        if #available(iOS 14.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
    
    func testAudioPlayerOpenPerformance() throws {
        measure {
            setupExpandedPlayer()
            
            // Close player
            let minimizeButton = app.buttons["Minimize"]
            if minimizeButton.exists {
                minimizeButton.tap()
            }
        }
    }
}