//
//  BriefeedApp+RSS.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import SwiftUI

// MARK: - RSS App Initialization
extension BriefeedApp {
    
    /// Initialize RSS features on app launch
    func initializeRSSFeatures() {
        // Register RSS defaults
        UserDefaultsManager.shared.registerRSSDefaults()
        UserDefaultsManager.shared.loadRSSSettings()
        
        // Initialize RSS feeds and auto-play
        Task {
            // Initialize default RSS feeds if needed
            await RSSAudioService.shared.initializeDefaultFeedsIfNeeded()
            
            // Load enhanced queue
            await MainActor.run {
                QueueService.shared.loadEnhancedQueue()
                
                // Migrate legacy queue if needed
                if QueueService.shared.enhancedQueue.isEmpty && !QueueService.shared.queuedItems.isEmpty {
                    QueueService.shared.migrateLegacyQueue()
                }
            }
            
            // Handle auto-play if enabled
            if UserDefaultsManager.shared.autoPlayLiveNewsOnOpen {
                // Wait a moment for UI to be ready
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Refresh feeds and auto-populate queue
                await RSSAudioService.shared.refreshAllFeeds()
                await QueueService.shared.autoPopulateWithLiveNews()
            }
        }
        
        // Schedule periodic cleanup of expired episodes
        scheduleRSSCleanup()
    }
    
    /// Schedule periodic cleanup tasks
    private func scheduleRSSCleanup() {
        // Clean up expired items every hour
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in
                QueueService.shared.cleanupExpiredItems()
            }
        }
        
        // Refresh stale feeds every 30 minutes
        Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in
            Task {
                await RSSAudioService.shared.refreshAllFeeds()
            }
        }
    }
}