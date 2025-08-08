//
//  BriefeedApp+RSS.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import SwiftUI
import CoreData

// MARK: - RSS App Initialization
extension BriefeedApp {
    
    /// Initialize RSS features on app launch
    func initializeRSSFeatures() {
        print("📡 Initializing RSS features...")
        
        // Register RSS defaults
        UserDefaultsManager.shared.registerRSSDefaults()
        UserDefaultsManager.shared.loadRSSSettings()
        
        print("✅ RSS settings loaded")
        
        // Defer the actual RSS initialization to avoid state changes during app init
        Task {
            // Wait for views to be fully rendered
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            do {
                // Initialize default RSS feeds if needed
                await RSSAudioService.shared.initializeDefaultFeedsIfNeeded()
                print("✅ RSS feeds initialized")
                
                // Load enhanced queue
                // MIGRATION: QueueServiceV2 loads queue automatically in init
                // No need to call loadEnhancedQueue or migrateLegacyQueue
                print("✅ Queue loaded")
                
                // Handle auto-play if enabled
                if UserDefaultsManager.shared.autoPlayLiveNewsOnOpen {
                    // Refresh feeds if needed
                    await RSSAudioService.shared.refreshAllFeeds()
                    
                    // Play live news like a radio
                    await playLiveNewsRadio()
                }
            } catch {
                print("❌ Error in RSS initialization: \(error)")
            }
        }
        
        // Schedule periodic cleanup of expired episodes
        scheduleRSSCleanup()
    }
    
    /// Schedule periodic cleanup tasks
    private func scheduleRSSCleanup() {
        // Clean up expired items every hour - handled by QueueServiceV2
        // Note: QueueServiceV2 automatically handles cleanup
        
        // Refresh stale feeds every 30 minutes - handled by RSSAudioService's own timer
        // Note: RSSAudioService has its own setupAutoRefresh method
    }
    
    /// Play live news like a radio - automatically queue and play latest episodes
    private func playLiveNewsRadio() async {
        let feeds = await MainActor.run {
            let viewContext = PersistenceController.shared.container.viewContext
            let fetchRequest: NSFetchRequest<RSSFeed> = RSSFeed.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "isEnabled == YES")
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \RSSFeed.priority, ascending: true),
                NSSortDescriptor(keyPath: \RSSFeed.displayName, ascending: true)
            ]
            
            do {
                return try viewContext.fetch(fetchRequest)
            } catch {
                print("❌ Error fetching RSS feeds: \(error)")
                return []
            }
        }
        
        // Clear queue first
        await MainActor.run {
            QueueServiceV2.shared.clearQueue()
        }
        
        // Add the latest unlistened episode from each feed
        for feed in feeds {
            if let episodes = feed.episodes?.allObjects as? [RSSEpisode] {
                if let latestEpisode = episodes
                    .filter({ !$0.isListened })
                    .sorted(by: { $0.pubDate > $1.pubDate })
                    .first {
                    await MainActor.run {
                        QueueServiceV2.shared.addRSSEpisode(latestEpisode)
                    }
                }
            }
        }
        
        // Start playing
        await QueueServiceV2.shared.playNext()
    }
}