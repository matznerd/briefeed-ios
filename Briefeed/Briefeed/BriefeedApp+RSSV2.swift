//
//  BriefeedApp+RSSV2.swift
//  Briefeed
//
//  Updated to use new audio system
//

import SwiftUI
import CoreData

// MARK: - RSS App Initialization
extension BriefeedApp {
    
    /// Initialize RSS features on app launch
    func initializeRSSFeatures() {
        do {
            print("📡 Initializing RSS features...")
            
            // Register RSS defaults
            UserDefaultsManager.shared.registerRSSDefaults()
            UserDefaultsManager.shared.loadRSSSettings()
            
            print("✅ RSS settings loaded")
            
            // Initialize RSS feeds and auto-play
            Task {
                do {
                    // Initialize default RSS feeds if needed
                    await RSSAudioService.shared.initializeDefaultFeedsIfNeeded()
                    print("✅ RSS feeds initialized")
                    
                    // Handle auto-play if enabled
                    if UserDefaultsManager.shared.autoPlayLiveNewsOnOpen {
                        // Wait a moment for UI to be ready
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                        
                        // Refresh feeds if needed
                        await RSSAudioService.shared.refreshAllFeeds()
                        
                        // Play live news like a radio
                        await playLiveNewsRadio()
                    }
                } catch {
                    print("❌ Error in RSS initialization: \(error)")
                }
            }
            
            // Schedule periodic cleanup (handled by new cache manager)
            scheduleRSSRefresh()
            
        } catch {
            print("❌ Fatal error initializing RSS features: \(error)")
        }
    }
    
    /// Schedule periodic feed refresh
    private func scheduleRSSRefresh() {
        // Refresh feeds every 30 minutes
        Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in
            Task {
                await RSSAudioService.shared.refreshAllFeeds()
            }
        }
    }
    
    /// Play live news like a radio - automatically queue and play latest episodes
    private func playLiveNewsRadio() async {
        let viewContext = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<RSSFeed> = RSSFeed.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isEnabled == YES")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \RSSFeed.priority, ascending: true),
            NSSortDescriptor(keyPath: \RSSFeed.displayName, ascending: true)
        ]
        
        do {
            let feeds = try viewContext.fetch(fetchRequest)
            var episodesToPlay: [RSSEpisode] = []
            
            // Add the latest unlistened episode from each feed
            for feed in feeds {
                if let episodes = feed.episodes?.allObjects as? [RSSEpisode] {
                    if let latestEpisode = episodes
                        .filter({ !$0.isListened })
                        .sorted(by: { $0.pubDate > $1.pubDate })
                        .first {
                        episodesToPlay.append(latestEpisode)
                    }
                }
            }
            
            // Play all episodes through the shared player so the app-wide mini player updates.
            if !episodesToPlay.isEmpty {
                await UnifiedAudioPlayer.shared.playLiveNewsStream(episodes: episodesToPlay)
            }
        } catch {
            print("❌ Error playing live news radio: \(error)")
        }
    }
}
