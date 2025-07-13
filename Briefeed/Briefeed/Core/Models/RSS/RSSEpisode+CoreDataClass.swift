//
//  RSSEpisode+CoreDataClass.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import Foundation
import CoreData

@objc(RSSEpisode)
public class RSSEpisode: NSManagedObject {
    
    // MARK: - Computed Properties
    
    /// Unique identifier for the episode
    var uniqueId: String {
        return id.isEmpty ? "\(feedId)-\(pubDate.timeIntervalSince1970)" : id
    }
    
    /// Check if episode is fresh based on feed update frequency
    var isFresh: Bool {
        guard let feed = feed else { return false }
        let maxAge: TimeInterval = feed.updateFrequencyEnum == .hourly ? 7200 : 86400 // 2 hours or 24 hours
        return Date().timeIntervalSince(pubDate) < maxAge
    }
    
    /// Check if episode has expired
    var isExpired: Bool {
        guard let feed = feed else { return false }
        let retentionPeriod = TimeInterval(feed.updateFrequencyEnum.retentionHours * 3600)
        return Date().timeIntervalSince(pubDate) > retentionPeriod
    }
    
    /// Get formatted duration string
    var formattedDuration: String? {
        guard duration > 0 else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        
        if minutes > 0 {
            return "\(minutes) min"
        } else {
            return "\(seconds) sec"
        }
    }
    
    /// Progress percentage (0.0 to 1.0)
    var progress: Double {
        get { return lastPosition }
        set { lastPosition = max(0.0, min(1.0, newValue)) }
    }
    
    /// Check if episode is partially listened
    var isPartiallyListened: Bool {
        return lastPosition > 0.0 && lastPosition < 0.95
    }
    
    // MARK: - Helper Methods
    
    /// Mark episode as listened
    func markAsListened() {
        isListened = true
        listenedDate = Date()
        lastPosition = 1.0
    }
    
    /// Update playback progress
    func updateProgress(_ progress: Double) {
        lastPosition = progress
        
        // Auto-mark as listened if > 95% complete
        if progress > 0.95 {
            markAsListened()
        }
    }
    
    /// Get remaining time in seconds
    func getRemainingTime() -> Int? {
        guard duration > 0 else { return nil }
        let playedDuration = Double(duration) * lastPosition
        return Int(Double(duration) - playedDuration)
    }
    
    /// Check if should be cleaned up
    func shouldCleanup() -> Bool {
        // Keep if partially listened
        if isPartiallyListened { return false }
        
        // Keep if recently added to queue
        if hasBeenQueued && !isListened { return false }
        
        // Otherwise check if expired
        return isExpired
    }
}