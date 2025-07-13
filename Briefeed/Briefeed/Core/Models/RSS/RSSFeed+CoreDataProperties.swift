//
//  RSSFeed+CoreDataProperties.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import Foundation
import CoreData

extension RSSFeed {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<RSSFeed> {
        return NSFetchRequest<RSSFeed>(entityName: "RSSFeed")
    }
    
    @NSManaged public var id: String
    @NSManaged public var url: String
    @NSManaged public var displayName: String
    @NSManaged public var updateFrequency: String?
    @NSManaged public var priority: Int16
    @NSManaged public var isEnabled: Bool
    @NSManaged public var lastFetchDate: Date?
    @NSManaged public var createdDate: Date
    @NSManaged public var episodes: NSSet?
    
}

// MARK: Generated accessors for episodes
extension RSSFeed {
    
    @objc(addEpisodesObject:)
    @NSManaged public func addToEpisodes(_ value: RSSEpisode)
    
    @objc(removeEpisodesObject:)
    @NSManaged public func removeFromEpisodes(_ value: RSSEpisode)
    
    @objc(addEpisodes:)
    @NSManaged public func addToEpisodes(_ values: NSSet)
    
    @objc(removeEpisodes:)
    @NSManaged public func removeFromEpisodes(_ values: NSSet)
    
}

extension RSSFeed : Identifiable {
}