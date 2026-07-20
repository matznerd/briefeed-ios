//
//  RSSFeed+CoreDataClass.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import Foundation
import CoreData

@objc(RSSFeed)
public class RSSFeed: NSManagedObject {
    
    // MARK: - Computed Properties
    
    var updateFrequencyEnum: RSSUpdateFrequency {
        get {
            return RSSUpdateFrequency(rawValue: updateFrequency ?? "") ?? .daily
        }
        set {
            updateFrequency = newValue.rawValue
        }
    }
    
    var isStale: Bool {
        RSSRefreshPolicy.isStale(updateFrequencyEnum, lastSuccess: lastFetchDate, now: Date())
    }
    
    // MARK: - Helper Methods
    
    /// Get all unlistened episodes sorted by date
    func getUnlistenedEpisodes() -> [RSSEpisode] {
        guard let episodes = episodes as? Set<RSSEpisode> else { return [] }
        return episodes
            .filter { !$0.isListened && !$0.hasBeenQueued }
            .sorted { $0.pubDate > $1.pubDate }
    }
    
    /// Get fresh episodes based on update frequency
    func getFreshEpisodes() -> [RSSEpisode] {
        guard let episodes = episodes as? Set<RSSEpisode> else { return [] }
        let maxAge: TimeInterval = updateFrequencyEnum == .hourly ? 7200 : 86400 // 2 hours or 24 hours
        let cutoffDate = Date().addingTimeInterval(-maxAge)
        
        return episodes
            .filter { $0.pubDate > cutoffDate && !$0.isListened }
            .sorted { $0.pubDate > $1.pubDate }
    }
}

// MARK: - RSS Update Frequency
enum RSSUpdateFrequency: String, CaseIterable {
    case hourly = "hourly"
    case daily = "daily"
    
    var displayName: String {
        switch self {
        case .hourly:
            return "Hourly"
        case .daily:
            return "Daily"
        }
    }
    
    var retentionHours: Int {
        switch self {
        case .hourly:
            return 24
        case .daily:
            return 168 // 7 days
        }
    }
    
    var checkInterval: TimeInterval {
        switch self {
        case .hourly:
            return 1800
        case .daily:
            return 21600
        }
    }
}

enum RSSRefreshPolicy {
    static func isStale(_ frequency: RSSUpdateFrequency, lastSuccess: Date?, now: Date) -> Bool {
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) > frequency.checkInterval
    }
}
