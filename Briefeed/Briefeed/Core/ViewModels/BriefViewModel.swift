//
//  BriefViewModel.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import Foundation
import CoreData
import Combine
import SwiftUI

@MainActor
class BriefViewModel: ObservableObject {
    @Published var queuedArticles: [Article] = []
    @Published var queue: [EnhancedQueueItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let audioService = BriefeedAudioService.shared
    private let queueService = QueueServiceV2.shared
    private let storageService: StorageServiceProtocol
    private let viewContext: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()
    
    init(storageService: StorageServiceProtocol = StorageService.shared,
         viewContext: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.storageService = storageService
        self.viewContext = viewContext
        
        setupPublishers()
        Task {
            await loadQueuedArticles()
        }
    }
    
    private func setupPublishers() {
        // Sync with QueueServiceV2 queue
        queueService.$queue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enhancedQueue in
                self?.queue = enhancedQueue
            }
            .store(in: &cancellables)
        
        // Listen for changes to saved articles in Core Data
        NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.loadQueuedArticles()
                }
            }
            .store(in: &cancellables)
    }
    
    func loadQueuedArticles() async {
        isLoading = true
        
        // Load saved articles as the queue (Brief = playlist)
        let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isSaved == true AND isArchived == false")
        // Sort by savedAt descending (newest at top, oldest at bottom)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Article.savedAt, ascending: false)]
        
        do {
            let articles = try viewContext.fetch(fetchRequest)
            
            // Always sync with saved articles (Brief IS the queue)
            self.queuedArticles = articles
            
            // Clear and rebuild queue
            queueService.clearQueue()
            for article in articles {
                await queueService.addArticle(article)
            }
            
            isLoading = false
        } catch {
            errorMessage = "Failed to load queue: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    func refresh() async {
        await loadQueuedArticles()
    }
    
    func playArticle(_ article: Article) {
        Task {
            await audioService.playNow(article)
        }
    }
    
    func addToQueue(_ article: Article) async {
        await queueService.addArticle(article)
    }
    
    func removeFromQueue(_ article: Article) {
        // Find and remove from queue
        if let index = queue.firstIndex(where: { $0.articleID == article.id }) {
            queueService.removeItem(at: index)
        }
        
        // Remove from local articles list
        queuedArticles.removeAll { $0.id == article.id }
        
        // Optionally unsave the article
        Task {
            do {
                try await storageService.toggleArticleSaved(article)
            } catch {
                errorMessage = "Failed to remove article: \(error.localizedDescription)"
            }
        }
    }
    
    func removeFromQueue(at index: Int) {
        queueService.removeItem(at: index)
    }
    
    func moveQueueItems(from source: IndexSet, to destination: Int) {
        // Move in queue service
        queueService.moveItem(from: source, to: destination)
    }
    
    func clearQueue() {
        queuedArticles.removeAll()
        queueService.clearQueue()
    }
    
    func playItemAt(index: Int) async {
        await queueService.playItem(at: index)
    }
}