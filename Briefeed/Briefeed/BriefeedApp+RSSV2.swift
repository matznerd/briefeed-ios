//
//  BriefeedApp+RSSV2.swift
//  Briefeed
//
//  Updated to use new audio system
//

import SwiftUI

// MARK: - RSS App Initialization
extension BriefeedApp {
    
    /// Initialize RSS features on app launch
    func initializeRSSFeatures() {
        print("📡 Initializing RSS features...")
        UserDefaultsManager.shared.registerRSSDefaults()
        UserDefaultsManager.shared.loadRSSSettings()
        print("✅ RSS settings loaded")

        Task {
            await RSSAudioService.shared.ensureDefaultFeedsExist()
            print("✅ RSS feeds initialized")
        }
    }
}
