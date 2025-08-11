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
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Audio service is now handled through AppViewModel and AudioPlayerViewModelV2
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
            
            // Queue management is now handled through AudioPlayerViewModelV2
            self.queuedArticles = articles
            
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
        // Playback is now handled through AppViewModel
        // This method can be removed once all UI references are updated
    }
    
    func removeFromQueue(_ article: Article) {
        // Remove from local queue
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
    
    func moveQueueItems(from source: IndexSet, to destination: Int) {
        // Move in local array
        queuedArticles.move(fromOffsets: source, toOffset: destination)
        
        // Queue reordering is now handled through AudioPlayerViewModelV2
    }
    
    func clearQueue() {
        queuedArticles.removeAll()
        // Queue clearing is now handled through AudioPlayerViewModelV2
    }
    
}