//
//  ArchivedArticlesService.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import Foundation
import CoreData
import Combine

/// Service responsible for managing archived articles
@MainActor
class ArchivedArticlesService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = ArchivedArticlesService()
    
    // MARK: - Properties
    @Published private(set) var archivedArticleIDs: Set<UUID> = []
    private let userDefaults = UserDefaults.standard
    private let archivedArticlesKey = "ArchivedArticleIDs"
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    private init() {
        loadArchivedArticles()
        
        // Save to UserDefaults whenever the set changes
        $archivedArticleIDs
            .dropFirst() // Skip initial value
            .sink { [weak self] ids in
                self?.saveArchivedArticles(ids)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Archives an article
    func archiveArticle(_ article: Article) {
        guard let articleID = article.id else { return }
        
        // Update Core Data
        article.isArchived = true
        
        // Update local set
        archivedArticleIDs.insert(articleID)
        
        // Save context
        saveContext()
        
        // Send haptic feedback
        HapticManager.shared.archiveAction()
    }
    
    /// Unarchives an article
    func unarchiveArticle(_ article: Article) {
        guard let articleID = article.id else { return }
        
        // Update Core Data
        article.isArchived = false
        
        // Update local set
        archivedArticleIDs.remove(articleID)
        
        // Save context
        saveContext()
        
        // Send haptic feedback
        HapticManager.shared.mediumImpact()
    }
    
    /// Toggles the archive status of an article
    func toggleArchiveStatus(_ article: Article) {
        if article.isArchived {
            unarchiveArticle(article)
        } else {
            archiveArticle(article)
        }
    }
    
    /// Checks if an article is archived
    func isArchived(_ article: Article) -> Bool {
        guard let articleID = article.id else { return false }
        return archivedArticleIDs.contains(articleID)
    }
    
    /// Archives multiple articles
    func archiveArticles(_ articles: [Article]) {
        for article in articles {
            guard let articleID = article.id else { continue }
            article.isArchived = true
            archivedArticleIDs.insert(articleID)
        }
        
        // Save context once for all changes
        saveContext()
        
        // Send haptic feedback
        HapticManager.shared.notificationSuccess()
    }
    
    /// Unarchives all articles
    func unarchiveAllArticles() {
        // Fetch all archived articles
        let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isArchived == %@", NSNumber(value: true))
        
        do {
            let archivedArticles = try PersistenceController.shared.container.viewContext.fetch(fetchRequest)
            
            // Unarchive each article
            for article in archivedArticles {
                article.isArchived = false
            }
            
            // Clear the set
            archivedArticleIDs.removeAll()
            
            // Save context
            saveContext()
            
            // Send haptic feedback
            HapticManager.shared.notificationSuccess()
        } catch {
            print("Error fetching archived articles: \(error)")
        }
    }
    
    /// Returns the count of archived articles
    var archivedCount: Int {
        archivedArticleIDs.count
    }
    
    // MARK: - Private Methods
    
    /// Loads archived article IDs from UserDefaults
    private func loadArchivedArticles() {
        if let data = userDefaults.data(forKey: archivedArticlesKey),
           let decodedIDs = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            archivedArticleIDs = decodedIDs
        }
        
        // Sync with Core Data
        syncWithCoreData()
    }
    
    /// Saves archived article IDs to UserDefaults
    private func saveArchivedArticles(_ ids: Set<UUID>) {
        if let encoded = try? JSONEncoder().encode(ids) {
            userDefaults.set(encoded, forKey: archivedArticlesKey)
        }
    }
    
    /// Syncs the archived state with Core Data
    private func syncWithCoreData() {
        let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
        
        do {
            let articles = try PersistenceController.shared.container.viewContext.fetch(fetchRequest)
            
            // Update archived state based on Core Data
            for article in articles {
                guard let articleID = article.id else { continue }
                
                if article.isArchived {
                    archivedArticleIDs.insert(articleID)
                } else {
                    archivedArticleIDs.remove(articleID)
                }
            }
            
            // Save the updated set
            saveArchivedArticles(archivedArticleIDs)
        } catch {
            print("Error syncing with Core Data: \(error)")
        }
    }
    
    /// Saves the Core Data context
    private func saveContext() {
        let context = PersistenceController.shared.container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Error saving context: \(error)")
            }
        }
    }
}

// MARK: - Convenience Extensions
extension Article {
    /// Convenience method to archive this article
    func archive() {
        Task { @MainActor in
            ArchivedArticlesService.shared.archiveArticle(self)
        }
    }
    
    /// Convenience method to unarchive this article
    func unarchive() {
        Task { @MainActor in
            ArchivedArticlesService.shared.unarchiveArticle(self)
        }
    }
    
    /// Convenience method to toggle archive status
    func toggleArchive() {
        Task { @MainActor in
            ArchivedArticlesService.shared.toggleArchiveStatus(self)
        }
    }
}