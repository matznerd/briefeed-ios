//
//  UserDefaultsManager+RSS.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import Foundation

// MARK: - RSS UserDefaults Keys
extension UserDefaultsKey {
    // RSS Settings
    static let autoPlayLiveNewsOnOpen = UserDefaultsKey(rawValue: "autoPlayLiveNewsOnOpen")!
    static let rssPlaybackSpeed = UserDefaultsKey(rawValue: "rssPlaybackSpeed")!
    static let defaultBriefFilter = UserDefaultsKey(rawValue: "defaultBriefFilter")!
    static let rssRetentionHours = UserDefaultsKey(rawValue: "rssRetentionHours")!
    static let rssFeedPriorities = UserDefaultsKey(rawValue: "rssFeedPriorities")!
    static let rssLastPlayedEpisodeId = UserDefaultsKey(rawValue: "rssLastPlayedEpisodeId")!
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
        rssPlaybackSpeed = userDefaults.float(forKey: UserDefaultsKey.rssPlaybackSpeed.rawValue)
        if rssPlaybackSpeed == 0 { rssPlaybackSpeed = 1.0 }
        
        defaultBriefFilter = userDefaults.string(forKey: UserDefaultsKey.defaultBriefFilter.rawValue) ?? "all"
        
        let retention = userDefaults.integer(forKey: UserDefaultsKey.rssRetentionHours.rawValue)
        rssRetentionHours = retention > 0 ? retention : 24
    }
    
    // MARK: - Register RSS Defaults
    
    /// Register default values for RSS settings
    func registerRSSDefaults() {
        let defaults: [String: Any] = [
            UserDefaultsKey.autoPlayLiveNewsOnOpen.rawValue: false,
            UserDefaultsKey.rssPlaybackSpeed.rawValue: 1.0,
            UserDefaultsKey.defaultBriefFilter.rawValue: "all",
            UserDefaultsKey.rssRetentionHours.rawValue: 24
        ]
        userDefaults.register(defaults: defaults)
    }
}