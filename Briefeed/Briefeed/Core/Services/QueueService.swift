//
//  QueueService.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import Foundation
import CoreData
import Combine

/// Service responsible for managing the persistent audio queue
@MainActor
class QueueService: ObservableObject {
    
    // MARK: - Types
    struct QueuedItem: Codable {
        let articleID: UUID
        let addedDate: Date
    }
    
    // MARK: - Singleton
    static let shared = QueueService()
    
    // MARK: - Properties
    @Published private(set) var queuedItems: [QueuedItem] = []
    internal let userDefaults = UserDefaults.standard
    private let queueKey = "AudioQueueItems"
    internal let audioService = AudioService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Enhanced Queue Properties for RSS
    @Published private(set) var enhancedQueue: [EnhancedQueueItem] = []
    private let enhancedQueueKey = "EnhancedAudioQueueItems"
    
    // Background audio generation
    private var audioGenerationTask: Task<Void, Never>?
    private let geminiService = GeminiService()
    
    // MARK: - Internal Methods for Extensions
    internal func appendToEnhancedQueue(_ item: EnhancedQueueItem) {
        enhancedQueue.append(item)
    }
    
    internal func updateEnhancedQueue(_ newQueue: [EnhancedQueueItem]) {
        enhancedQueue = newQueue
    }
    
    internal func removeFromEnhancedQueue(where predicate: (EnhancedQueueItem) -> Bool) {
        enhancedQueue.removeAll(where: predicate)
    }
    
    internal func modifyEnhancedQueueItem(at index: Int, transform: (inout EnhancedQueueItem) -> Void) {
        guard index >= 0 && index < enhancedQueue.count else { return }
        transform(&enhancedQueue[index])
    }
    
    internal func getEnhancedQueueKey() -> String {
        return enhancedQueueKey
    }
    
    // MARK: - Initialization
    private init() {
        loadQueue()
        setupObservers()
        restoreQueueToAudioService()
    }
    
    // MARK: - Setup
    private func setupObservers() {
        // Observe audio service queue changes
        audioService.$queue
            .sink { [weak self] articles in
                self?.syncQueueFromAudioService(articles)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Adds an article to the queue
    func addToQueue(_ article: Article) {
        guard let articleID = article.id else { return }
        
        // Check if already in queue
        if queuedItems.contains(where: { $0.articleID == articleID }) {
            return
        }
        
        // Add to queue
        let queueItem = QueuedItem(articleID: articleID, addedDate: Date())
        queuedItems.append(queueItem)
        saveQueue()
        
        // Add to audio service
        audioService.addToQueue(article)
        
        // Start background audio generation
        generateAudioInBackground(for: article)
    }
    
    /// Removes an article from the queue
    func removeFromQueue(articleID: UUID) {
        queuedItems.removeAll { $0.articleID == articleID }
        saveQueue()
        
        // Find and remove from audio service
        if let index = audioService.queue.firstIndex(where: { $0.id == articleID }) {
            audioService.removeFromQueue(at: index)
        }
    }
    
    /// Reorders the queue
    func reorderQueue(from source: IndexSet, to destination: Int) {
        queuedItems.move(fromOffsets: source, toOffset: destination)
        saveQueue()
        
        // Reorder in audio service
        audioService.reorderQueue(from: source, to: destination)
    }
    
    /// Clears the entire queue
    func clearQueue() {
        queuedItems.removeAll()
        saveQueue()
        audioService.clearQueue()
        
        // Cancel any ongoing audio generation
        audioGenerationTask?.cancel()
    }
    
    /// Restores the queue on app launch
    func restoreQueueOnAppLaunch() {
        restoreQueueToAudioService()
    }
    
    /// Gets the queue position for an article
    func queuePosition(for articleID: UUID) -> Int? {
        queuedItems.firstIndex(where: { $0.articleID == articleID })
    }
    
    /// Checks if an article is in the queue
    func isInQueue(articleID: UUID) -> Bool {
        queuedItems.contains(where: { $0.articleID == articleID })
    }
    
    // MARK: - Private Methods
    
    /// Loads the queue from UserDefaults
    private func loadQueue() {
        guard let data = userDefaults.data(forKey: queueKey),
              let decoded = try? JSONDecoder().decode([QueuedItem].self, from: data) else {
            return
        }
        queuedItems = decoded
    }
    
    /// Saves the queue to UserDefaults
    private func saveQueue() {
        guard let encoded = try? JSONEncoder().encode(queuedItems) else { return }
        userDefaults.set(encoded, forKey: queueKey)
    }
    
    /// Syncs queue from audio service changes
    private func syncQueueFromAudioService(_ articles: [Article]) {
        // Update our queue based on audio service queue
        let articleIDs = articles.compactMap { $0.id }
        
        // Remove items not in audio service queue
        queuedItems.removeAll { item in
            !articleIDs.contains(item.articleID)
        }
        
        // Add new items from audio service queue
        for article in articles {
            guard let articleID = article.id else { continue }
            if !queuedItems.contains(where: { $0.articleID == articleID }) {
                let queueItem = QueuedItem(articleID: articleID, addedDate: Date())
                queuedItems.append(queueItem)
            }
        }
        
        // Reorder to match audio service queue
        queuedItems.sort { item1, item2 in
            guard let index1 = articleIDs.firstIndex(of: item1.articleID),
                  let index2 = articleIDs.firstIndex(of: item2.articleID) else {
                return false
            }
            return index1 < index2
        }
        
        saveQueue()
    }
    
    /// Restores the queue to the audio service
    private func restoreQueueToAudioService() {
        guard !queuedItems.isEmpty else { return }
        
        // Fetch articles from Core Data
        let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
        let articleIDs = queuedItems.map { $0.articleID }
        fetchRequest.predicate = NSPredicate(format: "id IN %@", articleIDs)
        
        do {
            let articles = try PersistenceController.shared.container.viewContext.fetch(fetchRequest)
            
            // Sort articles to match queue order
            let sortedArticles = queuedItems.compactMap { queueItem in
                articles.first { $0.id == queueItem.articleID }
            }
            
            // Clear and restore audio service queue
            audioService.clearQueue()
            for article in sortedArticles {
                audioService.addToQueue(article)
            }
        } catch {
            print("Error restoring queue: \(error)")
        }
    }
    
    /// Generates audio in the background for queued articles
    private func generateAudioInBackground(for article: Article) {
        // Cancel previous task if any
        audioGenerationTask?.cancel()
        
        audioGenerationTask = Task {
            // Wait a bit to batch multiple additions
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            guard !Task.isCancelled else { return }
            
            // Process queue items that don't have audio yet
            for queueItem in queuedItems {
                guard !Task.isCancelled else { break }
                
                // Fetch article
                let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", queueItem.articleID as CVarArg)
                fetchRequest.fetchLimit = 1
                
                do {
                    guard let article = try PersistenceController.shared.container.viewContext.fetch(fetchRequest).first else {
                        continue
                    }
                    
                    // Check if article already has summary
                    if article.summary == nil || article.summary?.isEmpty == true {
                        // Generate summary
                        if let url = article.url {
                            let summary = await geminiService.generateSummary(from: url)
                            
                            guard !Task.isCancelled else { break }
                            
                            // Update article with summary
                            article.summary = summary
                            try PersistenceController.shared.container.viewContext.save()
                        }
                    }
                } catch {
                    print("Error processing queued article: \(error)")
                }
            }
        }
    }
}

// MARK: - App Lifecycle Integration
extension QueueService {
    /// Call this when the app becomes active
    func handleAppDidBecomeActive() {
        restoreQueueOnAppLaunch()
    }
    
    /// Call this when the app will resign active
    func handleAppWillResignActive() {
        saveQueue()
    }
}