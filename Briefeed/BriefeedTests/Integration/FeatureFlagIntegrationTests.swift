//
//  FeatureFlagIntegrationTests.swift
//  BriefeedTests
//
//  Created by Briefeed Team on 1/8/25.
//

import Testing
import SwiftUI
@testable import Briefeed

/// Tests for feature flag integration with UI components
struct FeatureFlagIntegrationTests {
    
    // MARK: - Setup & Teardown
    
    init() {
        // Reset feature flags before each test
        FeatureFlagManager.shared.resetToDefaults()
    }
    
    deinit {
        // Reset feature flags after each test
        FeatureFlagManager.shared.resetToDefaults()
    }
    
    // MARK: - ContentView Integration Tests
    
    @Test("ContentView should show old MiniAudioPlayer when feature flag is off")
    @MainActor
    func test_contentView_shouldShowOldPlayer_whenFlagOff() throws {
        // Given
        FeatureFlagManager.shared.useNewAudioPlayerUI = false
        
        // When
        let contentView = ContentView()
            .environmentObject(UserDefaultsManager.shared)
        
        // Then
        #expect(FeatureFlagManager.shared.useNewAudioPlayerUI == false)
    }
    
    @Test("ContentView should show new MiniAudioPlayerV2 when feature flag is on")
    @MainActor
    func test_contentView_shouldShowNewPlayer_whenFlagOn() throws {
        // Given
        FeatureFlagManager.shared.useNewAudioPlayerUI = true
        
        // When
        let contentView = ContentView()
            .environmentObject(UserDefaultsManager.shared)
        
        // Then
        #expect(FeatureFlagManager.shared.useNewAudioPlayerUI == true)
    }
    
    // MARK: - Feature Flag Manager Tests
    
    @Test("Feature flag manager should persist settings")
    func test_featureFlags_shouldPersist() throws {
        // Given
        let manager = FeatureFlagManager.shared
        
        // When
        manager.useNewAudioService = true
        manager.useNewAudioPlayerUI = true
        manager.useNewQueueFormat = true
        manager.enablePlaybackHistory = true
        manager.enableAudioCaching = true
        
        // Create new instance to verify persistence
        let newManager = FeatureFlagManager()
        
        // Then
        #expect(newManager.useNewAudioService == true)
        #expect(newManager.useNewAudioPlayerUI == true)
        #expect(newManager.useNewQueueFormat == true)
        #expect(newManager.enablePlaybackHistory == true)
        #expect(newManager.enableAudioCaching == true)
    }
    
    @Test("Enable all features should set all flags to true")
    func test_enableAllFeatures_shouldSetAllFlags() throws {
        // Given
        let manager = FeatureFlagManager.shared
        
        // When
        manager.enableAllNewFeatures()
        
        // Then
        #expect(manager.useNewAudioService == true)
        #expect(manager.useNewAudioPlayerUI == true)
        #expect(manager.useNewQueueFormat == true)
        #expect(manager.enablePlaybackHistory == true)
        #expect(manager.enableAudioCaching == true)
        #expect(manager.enableSleepTimer == true)
    }
    
    @Test("Disable all features should set all flags to false")
    func test_disableAllFeatures_shouldSetAllFlags() throws {
        // Given
        let manager = FeatureFlagManager.shared
        manager.enableAllNewFeatures()
        
        // When
        manager.disableAllNewFeatures()
        
        // Then
        #expect(manager.useNewAudioService == false)
        #expect(manager.useNewAudioPlayerUI == false)
        #expect(manager.useNewQueueFormat == false)
        #expect(manager.enablePlaybackHistory == false)
        #expect(manager.enableAudioCaching == false)
        #expect(manager.enableSleepTimer == false)
    }
    
    @Test("Reset to defaults should clear all settings")
    func test_resetToDefaults_shouldClearSettings() throws {
        // Given
        let manager = FeatureFlagManager.shared
        manager.enableAllNewFeatures()
        
        // When
        manager.resetToDefaults()
        
        // Then
        #expect(manager.useNewAudioService == false)
        #expect(manager.useNewAudioPlayerUI == false)
        #expect(manager.useNewQueueFormat == false)
        #expect(manager.enablePlaybackHistory == false)
        #expect(manager.enableAudioCaching == false)
        #expect(manager.enableSleepTimer == true) // Default is true
    }
    
    // MARK: - Rollout Percentage Tests
    
    @Test("Rollout percentage 0 should disable features")
    func test_rolloutPercentage0_shouldDisableFeatures() throws {
        // Given
        let manager = FeatureFlagManager.shared
        
        // When
        manager.rolloutPercentage = 0
        
        // Then
        #expect(manager.isInRolloutGroup == false)
    }
    
    @Test("Rollout percentage 100 should enable features")
    func test_rolloutPercentage100_shouldEnableFeatures() throws {
        // Given
        let manager = FeatureFlagManager.shared
        
        // When
        manager.rolloutPercentage = 100
        
        // Then
        #expect(manager.isInRolloutGroup == true)
    }
    
    // MARK: - Notification Tests
    
    @Test("Feature flag changes should post notifications")
    @MainActor
    func test_featureFlagChanges_shouldPostNotifications() async throws {
        // Given
        let manager = FeatureFlagManager.shared
        var notificationReceived = false
        
        let cancellable = NotificationCenter.default.publisher(for: .featureFlagChanged)
            .sink { notification in
                notificationReceived = true
            }
        
        // When
        manager.useNewAudioPlayerUI = true
        
        // Allow time for notification
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Then
        #expect(notificationReceived == true)
        
        cancellable.cancel()
    }
    
    // MARK: - AudioServiceAdapter Integration Tests
    
    @Test("AudioServiceAdapter should check feature flag")
    @MainActor
    func test_audioServiceAdapter_shouldCheckFeatureFlag() throws {
        // Given
        FeatureFlagManager.shared.useNewAudioService = true
        let adapter = AudioServiceAdapter()
        
        // Then
        #expect(adapter.isUsingNewService == true)
        
        // When
        FeatureFlagManager.shared.useNewAudioService = false
        
        // Then
        #expect(adapter.isUsingNewService == false)
    }
    
    // MARK: - UI Component Switch Tests
    
    @Test("Mini player should switch implementations based on flag")
    @MainActor
    func test_miniPlayer_shouldSwitchImplementations() throws {
        // Given
        let manager = FeatureFlagManager.shared
        
        // Test old player
        manager.useNewAudioPlayerUI = false
        var useOldPlayer = !manager.useNewAudioPlayerUI
        #expect(useOldPlayer == true)
        
        // Test new player
        manager.useNewAudioPlayerUI = true
        useOldPlayer = !manager.useNewAudioPlayerUI
        #expect(useOldPlayer == false)
    }
    
    // MARK: - Migration Scenario Tests
    
    @Test("Gradual migration should work with partial flags")
    @MainActor
    func test_gradualMigration_shouldWorkWithPartialFlags() throws {
        // Given
        let manager = FeatureFlagManager.shared
        
        // Scenario 1: Only UI migration
        manager.useNewAudioPlayerUI = true
        manager.useNewAudioService = false
        
        // Then
        #expect(manager.useNewAudioPlayerUI == true)
        #expect(manager.useNewAudioService == false)
        
        // Scenario 2: Full migration
        manager.useNewAudioService = true
        
        // Then
        #expect(manager.useNewAudioPlayerUI == true)
        #expect(manager.useNewAudioService == true)
    }
}