//
//  FeatureFlagManager.swift
//  Briefeed
//
//  Created by Briefeed Team on 1/8/25.
//

import Foundation
import Combine
import UIKit

/// Manages feature flags for gradual migration to new audio system
final class FeatureFlagManager: ObservableObject {
    static let shared = FeatureFlagManager()
    
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Published Properties
    
    /// Controls whether to use the new BriefeedAudioService
    @Published var useNewAudioService: Bool = false {
        didSet {
            userDefaults.set(useNewAudioService, forKey: "feature.useNewAudioService")
            NotificationCenter.default.post(
                name: .featureFlagChanged,
                object: self,
                userInfo: ["flag": "useNewAudioService", "value": useNewAudioService]
            )
        }
    }
    
    /// Controls whether to use the new audio player UI components
    @Published var useNewAudioPlayerUI: Bool = false {
        didSet {
            userDefaults.set(useNewAudioPlayerUI, forKey: "feature.useNewAudioPlayerUI")
            NotificationCenter.default.post(
                name: .featureFlagChanged,
                object: self,
                userInfo: ["flag": "useNewAudioPlayerUI", "value": useNewAudioPlayerUI]
            )
        }
    }
    
    /// Controls whether to use the new queue format
    @Published var useNewQueueFormat: Bool = false {
        didSet {
            userDefaults.set(useNewQueueFormat, forKey: "feature.useNewQueueFormat")
            NotificationCenter.default.post(
                name: .featureFlagChanged,
                object: self,
                userInfo: ["flag": "useNewQueueFormat", "value": useNewQueueFormat]
            )
        }
    }
    
    /// Controls whether to enable playback history
    @Published var enablePlaybackHistory: Bool = false {
        didSet {
            userDefaults.set(enablePlaybackHistory, forKey: "feature.enablePlaybackHistory")
            NotificationCenter.default.post(
                name: .featureFlagChanged,
                object: self,
                userInfo: ["flag": "enablePlaybackHistory", "value": enablePlaybackHistory]
            )
        }
    }
    
    /// Controls whether to enable audio caching
    @Published var enableAudioCaching: Bool = false {
        didSet {
            userDefaults.set(enableAudioCaching, forKey: "feature.enableAudioCaching")
            NotificationCenter.default.post(
                name: .featureFlagChanged,
                object: self,
                userInfo: ["flag": "enableAudioCaching", "value": enableAudioCaching]
            )
        }
    }
    
    /// Controls whether to enable sleep timer feature
    @Published var enableSleepTimer: Bool = true {
        didSet {
            userDefaults.set(enableSleepTimer, forKey: "feature.enableSleepTimer")
            NotificationCenter.default.post(
                name: .featureFlagChanged,
                object: self,
                userInfo: ["flag": "enableSleepTimer", "value": enableSleepTimer]
            )
        }
    }
    
    /// Percentage of users who should get the new features (0-100)
    @Published var rolloutPercentage: Int = 0 {
        didSet {
            userDefaults.set(rolloutPercentage, forKey: "feature.rolloutPercentage")
            updateRolloutStatus()
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        loadFlags()
    }
    
    // MARK: - Public Methods
    
    /// Check if current user is in rollout group
    var isInRolloutGroup: Bool {
        guard rolloutPercentage > 0 else { return false }
        guard rolloutPercentage < 100 else { return true }
        
        // Generate a stable user hash
        let userHash = getUserHash()
        let threshold = rolloutPercentage
        
        return (userHash % 100) < threshold
    }
    
    /// Enable all new features
    func enableAllNewFeatures() {
        useNewAudioService = true
        useNewAudioPlayerUI = true
        useNewQueueFormat = true
        enablePlaybackHistory = true
        enableAudioCaching = true
        enableSleepTimer = true
    }
    
    /// Disable all new features (rollback)
    func disableAllNewFeatures() {
        useNewAudioService = false
        useNewAudioPlayerUI = false
        useNewQueueFormat = false
        enablePlaybackHistory = false
        enableAudioCaching = false
        enableSleepTimer = false
    }
    
    /// Reset to default state
    func resetToDefaults() {
        let keysToRemove = [
            "feature.useNewAudioService",
            "feature.useNewAudioPlayerUI",
            "feature.useNewQueueFormat",
            "feature.enablePlaybackHistory",
            "feature.enableAudioCaching",
            "feature.enableSleepTimer",
            "feature.rolloutPercentage"
        ]
        
        keysToRemove.forEach { userDefaults.removeObject(forKey: $0) }
        loadFlags()
    }
    
    // MARK: - Private Methods
    
    private func loadFlags() {
        useNewAudioService = userDefaults.bool(forKey: "feature.useNewAudioService")
        useNewAudioPlayerUI = userDefaults.bool(forKey: "feature.useNewAudioPlayerUI")
        useNewQueueFormat = userDefaults.bool(forKey: "feature.useNewQueueFormat")
        enablePlaybackHistory = userDefaults.bool(forKey: "feature.enablePlaybackHistory")
        enableAudioCaching = userDefaults.bool(forKey: "feature.enableAudioCaching")
        
        // Sleep timer defaults to true
        if userDefaults.object(forKey: "feature.enableSleepTimer") != nil {
            enableSleepTimer = userDefaults.bool(forKey: "feature.enableSleepTimer")
        } else {
            enableSleepTimer = true
        }
        
        rolloutPercentage = userDefaults.integer(forKey: "feature.rolloutPercentage")
    }
    
    private func getUserHash() -> Int {
        // Generate a stable hash based on device ID
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        var hash = 0
        for char in deviceID {
            hash = (hash << 5) &- hash &+ Int(char.asciiValue ?? 0)
        }
        return abs(hash)
    }
    
    private func updateRolloutStatus() {
        // Update feature flags based on rollout status
        if isInRolloutGroup {
            enableAllNewFeatures()
        } else {
            disableAllNewFeatures()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let featureFlagChanged = Notification.Name("FeatureFlagChanged")
}