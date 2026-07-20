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
        UserDefaultsManager.shared.registerRSSDefaults()
        UserDefaultsManager.shared.loadRSSSettings()
        print("✅ RSS settings loaded")

        Task {
            await RSSAudioService.shared.ensureDefaultFeedsExist()
            print("✅ RSS feeds initialized")

            if UserDefaultsManager.shared.autoPlayLiveNewsOnOpen {
                try? await Task.sleep(nanoseconds: 500_000_000)
                _ = await RSSAudioService.shared.refreshAllFeeds()
                await playLiveNewsRadio()
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
