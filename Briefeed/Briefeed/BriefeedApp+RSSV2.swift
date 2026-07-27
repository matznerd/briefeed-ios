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
        print("📡 Initializing RSS features...")

        // Register RSS defaults
        UserDefaultsManager.shared.registerRSSDefaults()
        UserDefaultsManager.shared.loadRSSSettings()

        print("✅ RSS settings loaded")

        // Initialize RSS feeds and auto-play
        Task {
            // Initialize default RSS feeds if needed
            let refreshedDuringFeedSetup = await RSSAudioService.shared.initializeDefaultFeedsIfNeeded()
            print("✅ RSS feeds initialized")

            await handleLaunchLiveNewsAutoplayIfNeeded(refreshedDuringFeedSetup: refreshedDuringFeedSetup)
        }

        // Schedule periodic cleanup (handled by new cache manager)
        scheduleRSSRefresh()
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
    
    /// If launch autoplay is enabled, keep the one launch opportunity pending
    /// through the refresh so a newly fetched NPR/BBC/etc. episode can start.
    private func handleLaunchLiveNewsAutoplayIfNeeded(refreshedDuringFeedSetup: Bool) async {
        guard UserDefaultsManager.shared.autoPlayLiveNewsOnOpen else { return }

        if !refreshedDuringFeedSetup {
            await RSSAudioService.shared.refreshAllFeeds()
        }

        _ = await playLiveNewsRadioIfIdle()
    }

    /// Play live news like a radio - automatically queue and play latest episodes
    @discardableResult
    private func playLiveNewsRadioIfIdle() async -> Bool {
        guard !UnifiedAudioPlayer.shared.isPlaying,
              UnifiedAudioPlayer.shared.currentItem == nil else {
            return false
        }

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
                return UnifiedAudioPlayer.shared.isPlaying || UnifiedAudioPlayer.shared.currentItem != nil
            }
        } catch {
            print("❌ Error playing live news radio: \(error)")
        }

        return false
    }
}
