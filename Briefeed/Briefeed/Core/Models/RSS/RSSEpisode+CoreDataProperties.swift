//
//  RSSEpisode+CoreDataProperties.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import Foundation
import CoreData

extension RSSEpisode {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<RSSEpisode> {
        return NSFetchRequest<RSSEpisode>(entityName: "RSSEpisode")
    }
    
    @NSManaged public var id: String
    @NSManaged public var feedId: String
    @NSManaged public var title: String
    @NSManaged public var audioUrl: String
    @NSManaged public var pubDate: Date
    @NSManaged public var duration: Int32
    @NSManaged public var episodeDescription: String?
    @NSManaged public var isListened: Bool
    @NSManaged public var listenedDate: Date?
    @NSManaged public var lastPosition: Double
    @NSManaged public var hasBeenQueued: Bool
    @NSManaged public var downloadedFilePath: String?
    @NSManaged public var feed: RSSFeed?
    
    // Computed property for update frequency from parent feed
    var updateFrequency: String {
        return feed?.updateFrequency ?? "daily"
    }
}

extension RSSEpisode : Identifiable {
}