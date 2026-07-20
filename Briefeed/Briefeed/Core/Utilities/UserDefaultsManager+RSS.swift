//
//  UserDefaultsManager+RSS.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import Foundation

enum PlaybackSpeedPolicy {
    static let supported: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    static func normalize(_ raw: Float) -> Float {
        guard raw.isFinite else { return 1.0 }
        let clamped = min(3.0, max(0.5, raw))
        return supported.min { lhs, rhs in
            let left = abs(lhs - clamped)
            let right = abs(rhs - clamped)
            return left == right ? lhs < rhs : left < right
        } ?? 1.0
    }

    static func loadAndMigrate(defaults: UserDefaults) -> Float {
        let canonical = UserDefaultsKey.playbackSpeed.rawValue
        let legacy = UserDefaultsKey.rssPlaybackSpeed.rawValue
        let raw: Float
        if defaults.object(forKey: canonical) != nil {
            raw = defaults.float(forKey: canonical)
        } else if defaults.object(forKey: legacy) != nil {
            raw = defaults.float(forKey: legacy)
        } else {
            raw = 1.0
        }
        let normalized = normalize(raw)
        defaults.set(normalized, forKey: canonical)
        return normalized
    }
}

// MARK: - RSS UserDefaults Properties
extension UserDefaultsManager {
    
    // MARK: - RSS Settings
    // Note: RSS properties have been moved to the main UserDefaultsManager class
    // to avoid Swift extension limitations with property wrappers
    
    /// RSS feed priority order
    var rssFeedPriorities: [String] {
        get {
            userDefaults.stringArray(forKey: UserDefaultsKey.rssFeedPriorities.rawValue) ?? []
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultsKey.rssFeedPriorities.rawValue)
        }
    }
    
    /// Last played RSS episode ID
    var rssLastPlayedEpisodeId: String? {
        get {
            userDefaults.string(forKey: UserDefaultsKey.rssLastPlayedEpisodeId.rawValue)
        }
        set {
            if let newValue = newValue {
                userDefaults.set(newValue, forKey: UserDefaultsKey.rssLastPlayedEpisodeId.rawValue)
            } else {
                userDefaults.removeObject(forKey: UserDefaultsKey.rssLastPlayedEpisodeId.rawValue)
            }
        }
    }
    
    // MARK: - Load RSS Settings
    
    /// Load RSS-specific settings
    func loadRSSSettings() {
        autoPlayLiveNewsOnOpen = userDefaults.bool(forKey: UserDefaultsKey.autoPlayLiveNewsOnOpen.rawValue)
        defaultBriefFilter = userDefaults.string(forKey: UserDefaultsKey.defaultBriefFilter.rawValue) ?? "all"
        
        let retention = userDefaults.integer(forKey: UserDefaultsKey.rssRetentionHours.rawValue)
        rssRetentionHours = retention > 0 ? retention : 24
    }
    
    // MARK: - Register RSS Defaults
    
    /// Register default values for RSS settings
    func registerRSSDefaults() {
        let defaults: [String: Any] = [
            UserDefaultsKey.autoPlayLiveNewsOnOpen.rawValue: false,
            UserDefaultsKey.defaultBriefFilter.rawValue: "all",
            UserDefaultsKey.rssRetentionHours.rawValue: 24
        ]
        userDefaults.register(defaults: defaults)
    }
}
