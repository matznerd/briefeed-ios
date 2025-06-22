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
    
    private let audioService = AudioService.shared
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
        // Sync with AudioService queue
        audioService.$queue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] audioQueue in
                self?.syncWithAudioQueue(audioQueue)
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
            audioService.queue = articles
            
            // Restore queue state if app was restarted
            audioService.restoreQueueState(articles: articles)
            
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
            do {
                try await audioService.playNow(article)
            } catch {
                errorMessage = "Failed to play article: \(error.localizedDescription)"
            }
        }
    }
    
    func removeFromQueue(_ article: Article) {
        // Remove from local queue
        queuedArticles.removeAll { $0.id == article.id }
        
        // Remove from audio service queue
        if let index = audioService.queue.firstIndex(where: { $0.id == article.id }) {
            audioService.removeFromQueue(at: index)
        }
        
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
        
        // Update audio service queue with reorder method
        audioService.reorderQueue(from: source, to: destination)
    }
    
    func clearQueue() {
        queuedArticles.removeAll()
        audioService.clearQueue()
    }
    
    private func syncWithAudioQueue(_ audioQueue: [Article]) {
        // Don't sync back from audio queue - Brief (saved articles) IS the source of truth
        // Audio queue follows saved articles, not the other way around
    }
}