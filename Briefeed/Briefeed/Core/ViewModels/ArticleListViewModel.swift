//
//  ArticleListViewModel.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import Foundation
import CoreData
import Combine

@MainActor
class ArticleListViewModel: ObservableObject {
    @Published var articles: [Article] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var hasMorePages = true
    
    private let feed: Feed
    private let redditService: RedditServiceProtocol
    private let storageService: StorageServiceProtocol
    private let viewContext: NSManagedObjectContext
    private var afterToken: String?
    private var cancellables = Set<AnyCancellable>()
    private let defaultDataService = DefaultDataService.shared
    
    init(feed: Feed,
         redditService: RedditServiceProtocol = RedditService(),
         storageService: StorageServiceProtocol = StorageService.shared,
         viewContext: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.feed = feed
        self.redditService = redditService
        self.storageService = storageService
        self.viewContext = viewContext
        
        setupPublishers()
        
        // Restore pagination token for this feed
        if let feedID = feed.id {
            afterToken = defaultDataService.getPaginationToken(for: feedID)
        }
        
        Task {
            await loadCachedArticles()
            if articles.isEmpty {
                await fetchArticles()
            }
        }
    }
    
    private func setupPublishers() {
        // Listen for changes to articles in Core Data
        NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.loadCachedArticles()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    
    func loadCachedArticles() async {
        let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "feed == %@", feed)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Article.createdAt, ascending: false)]
        
        do {
            let cachedArticles = try viewContext.fetch(fetchRequest)
            self.articles = cachedArticles
        } catch {
            print("Failed to fetch cached articles: \(error)")
        }
    }
    
    func fetchArticles(isRefresh: Bool = false) async {
        guard !isLoading && !isRefreshing && !isLoadingMore else { return }
        
        if isRefresh {
            isRefreshing = true
            afterToken = nil
            hasMorePages = true
            // Clear pagination token on refresh
            if let feedID = feed.id {
                defaultDataService.clearPaginationToken(for: feedID)
            }
        } else if articles.isEmpty {
            isLoading = true
        } else {
            guard hasMorePages else { return }
            isLoadingMore = true
        }
        
        errorMessage = nil
        
        do {
            let response: RedditResponse
            let limit = articles.isEmpty && !isRefresh ? Constants.Reddit.initialLoadLimit : Constants.Reddit.loadMoreLimit
            let sort = UserDefaultsManager.shared.currentFeedSort
            
            // Generate URL with sort parameter
            let feedURL = feed.generateURL(sort: sort, after: isRefresh ? nil : afterToken, limit: limit)
            
            // Use the URL-based fetch method
            response = try await redditService.fetchFeedWithURL(feedURL)
            
            // Update pagination token
            afterToken = response.data.after
            hasMorePages = response.data.after != nil
            
            // Save pagination token for this feed
            if let feedID = feed.id, let token = afterToken {
                defaultDataService.setPaginationToken(token, for: feedID)
            }
            
            // Convert Reddit posts to Articles
            let newArticles = response.data.children.map { child in
                let article = child.data.toArticle(feedID: feed.id)
                article.feed = feed
                return article
            }
            
            // Save to Core Data
            if isRefresh {
                // Delete old articles for this feed (except saved ones)
                let deleteRequest: NSFetchRequest<Article> = Article.fetchRequest()
                deleteRequest.predicate = NSPredicate(format: "feed == %@ AND isSaved == false", feed)
                
                let articlesToDelete = try viewContext.fetch(deleteRequest)
                articlesToDelete.forEach { viewContext.delete($0) }
            }
            
            // Save new articles
            try await storageService.saveContext()
            
            // Reload from cache to get the updated list
            await loadCachedArticles()
            
            isLoading = false
            isRefreshing = false
            isLoadingMore = false
            
        } catch {
            errorMessage = "Failed to fetch articles: \(error.localizedDescription)"
            isLoading = false
            isRefreshing = false
            isLoadingMore = false
        }
    }
    
    func refresh() async {
        await fetchArticles(isRefresh: true)
    }
    
    func loadMoreIfNeeded(currentArticle: Article) async {
        guard let lastArticle = articles.last,
              lastArticle.id == currentArticle.id,
              hasMorePages,
              !isLoadingMore else { return }
        
        await fetchArticles()
    }
    
    // MARK: - Article Actions
    
    func markArticleAsRead(_ article: Article) async {
        guard !article.isRead else { return }
        
        do {
            try await storageService.markArticleAsRead(article)
        } catch {
            errorMessage = "Failed to mark article as read: \(error.localizedDescription)"
        }
    }
    
    func toggleArticleSaved(_ article: Article) async {
        do {
            try await storageService.toggleArticleSaved(article)
        } catch {
            errorMessage = "Failed to save article: \(error.localizedDescription)"
        }
    }
    
    func deleteArticle(_ article: Article) async {
        do {
            try await storageService.deleteArticle(article)
            articles.removeAll { $0.id == article.id }
        } catch {
            errorMessage = "Failed to delete article: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Filtering
    
    func filterArticles(showSavedOnly: Bool, showUnreadOnly: Bool) -> [Article] {
        var filtered = articles
        
        if showSavedOnly {
            filtered = filtered.filter { $0.isSaved }
        }
        
        if showUnreadOnly {
            filtered = filtered.filter { !$0.isRead }
        }
        
        return filtered
    }
}