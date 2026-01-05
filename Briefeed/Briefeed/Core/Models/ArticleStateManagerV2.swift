//
//  ArticleStateManagerV2.swift
//  Briefeed
//
//  Fixed architecture: Plain singleton, no ObservableObject, no @MainActor
//

import Foundation
import Combine

// MARK: - ArticleStateManagerV2
// Fixed architecture: Plain singleton service without ObservableObject

final class ArticleStateManagerV2: NSObject {
    
    // MARK: - Singleton
    static let shared = ArticleStateManagerV2()
    
    // MARK: - Properties (No @Published!)
    private(set) var currentlyPlayingArticleID: UUID? {
        didSet {
            delegate?.currentlyPlayingArticleChanged(currentlyPlayingArticleID)
        }
    }
    
    private(set) var archivedArticleIDs: Set<UUID> = [] {
        didSet {
            delegate?.archivedArticlesChanged(archivedArticleIDs)
        }
    }
    
    private(set) var queuedArticleIDs: [UUID] = [] {
        didSet {
            delegate?.queuedArticlesChanged(queuedArticleIDs)
        }
    }
    
    // Delegate for state changes (instead of @Published)
    weak var delegate: ArticleStateManagerDelegate?
    
    // MARK: - Initialization (LIGHTWEIGHT!)
    private override init() {
        super.init()
        // Only lightweight setup in init
        
        // Safety checks
        SafetyMonitor.shared.checkSingletonNotObservable(self)
        SafetyMonitor.shared.checkNoPublishedInService(self)
    }
    
    // MARK: - Async Initialization (HEAVY WORK HERE)
    func initialize() async {
        SafetyMonitor.shared.assertNotMainThread()
        
        // Load archived articles
        await loadArchivedArticles()
        
        // Load queue state
        await loadQueueState()
    }
    
    // MARK: - State Updates
    
    func setCurrentlyPlaying(articleID: UUID?) {
        currentlyPlayingArticleID = articleID
    }
    
    func addToArchived(articleID: UUID) {
        archivedArticleIDs.insert(articleID)
        saveArchivedArticles()
    }
    
    func removeFromArchived(articleID: UUID) {
        archivedArticleIDs.remove(articleID)
        saveArchivedArticles()
    }
    
    func updateQueue(articleIDs: [UUID]) {
        queuedArticleIDs = articleIDs
    }
    
    func addToQueue(articleID: UUID) {
        if !queuedArticleIDs.contains(articleID) {
            queuedArticleIDs.append(articleID)
        }
    }
    
    func removeFromQueue(articleID: UUID) {
        queuedArticleIDs.removeAll { $0 == articleID }
    }
    
    func moveInQueue(from source: IndexSet, to destination: Int) {
        queuedArticleIDs.move(fromOffsets: source, toOffset: destination)
    }
    
    func clearQueue() {
        queuedArticleIDs.removeAll()
    }
    
    // MARK: - State Queries
    
    func isPlaying(articleID: UUID) -> Bool {
        return currentlyPlayingArticleID == articleID
    }
    
    func isArchived(articleID: UUID) -> Bool {
        return archivedArticleIDs.contains(articleID)
    }
    
    func isQueued(articleID: UUID) -> Bool {
        return queuedArticleIDs.contains(articleID)
    }
    
    func queuePosition(for articleID: UUID) -> Int? {
        return queuedArticleIDs.firstIndex(of: articleID)
    }
    
    // MARK: - Persistence
    
    private func loadArchivedArticles() async {
        if let data = UserDefaults.standard.data(forKey: "ArchivedArticleIDs"),
           let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            archivedArticleIDs = ids
        }
    }
    
    private func saveArchivedArticles() {
        if let data = try? JSONEncoder().encode(archivedArticleIDs) {
            UserDefaults.standard.set(data, forKey: "ArchivedArticleIDs")
        }
    }
    
    private func loadQueueState() async {
        // Queue state is managed by QueueCoordinator
        // This just tracks the IDs for quick lookup
        await MainActor.run {
            updateQueueFromCoordinator()
        }
    }

    @MainActor
    private func updateQueueFromCoordinator() {
        let coordinator = QueueCoordinator.shared
        queuedArticleIDs = coordinator.queue.compactMap { item in
            if item.isArticle {
                return item.articleID
            }
            return nil
        }
    }
    
    // MARK: - Batch Operations
    
    func archiveMultiple(articleIDs: [UUID]) {
        archivedArticleIDs.formUnion(articleIDs)
        saveArchivedArticles()
    }
    
    func unarchiveMultiple(articleIDs: [UUID]) {
        archivedArticleIDs.subtract(articleIDs)
        saveArchivedArticles()
    }
    
    func queueMultiple(articleIDs: [UUID]) {
        for id in articleIDs where !queuedArticleIDs.contains(id) {
            queuedArticleIDs.append(id)
        }
    }
    
    // MARK: - Statistics
    
    func getStatistics() -> ArticleStatistics {
        return ArticleStatistics(
            totalQueued: queuedArticleIDs.count,
            totalArchived: archivedArticleIDs.count,
            isPlaying: currentlyPlayingArticleID != nil
        )
    }
}

// MARK: - Delegate Protocol

protocol ArticleStateManagerDelegate: AnyObject {
    func currentlyPlayingArticleChanged(_ articleID: UUID?)
    func archivedArticlesChanged(_ articleIDs: Set<UUID>)
    func queuedArticlesChanged(_ articleIDs: [UUID])
}

// MARK: - Statistics Model

struct ArticleStatistics {
    let totalQueued: Int
    let totalArchived: Int
    let isPlaying: Bool
}