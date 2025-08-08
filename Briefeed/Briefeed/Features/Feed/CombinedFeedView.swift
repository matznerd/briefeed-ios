//
//  CombinedFeedView.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import SwiftUI
import CoreData

struct CombinedFeedView: View {
    @StateObject private var viewModel = CombinedFeedViewModel()
    @StateObject private var stateManager = ArticleStateManager.shared
    @State private var selectedFeedId: String = "all"
    @State private var selectedArticle: Article?
    @State private var showingAddFeed = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Horizontal feed selector
                feedSelector
                    .background(Color.briefeedSecondaryBackground)
                
                Divider()
                
                // Article list
                if viewModel.isLoading && viewModel.articles.isEmpty {
                    loadingView
                } else if viewModel.articles.isEmpty && !viewModel.isLoading {
                    emptyStateView
                } else {
                    articleListView
                }
            }
            .navigationTitle("Briefeed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddFeed = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .sheet(isPresented: $showingAddFeed) {
                AddFeedView(viewModel: FeedViewModel())
            }
            .navigationDestination(item: $selectedArticle) { article in
                ArticleView(article: article)
            }
            .refreshable {
                await viewModel.refresh(feedId: selectedFeedId)
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onAppear {
                Task {
                    await viewModel.loadFeeds()
                }
            }
        }
    }
    
    // MARK: - Views
    
    private var feedSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // All feeds button
                FeedSelectorButton(
                    title: "All",
                    isSelected: selectedFeedId == "all",
                    action: {
                        selectFeed("all")
                    }
                )
                
                // Individual feed buttons
                ForEach(viewModel.feeds) { feed in
                    FeedSelectorButton(
                        title: feed.name ?? "Unknown",
                        isSelected: selectedFeedId == feed.id?.uuidString ?? "",
                        action: {
                            selectFeed(feed.id?.uuidString ?? "")
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    private var articleListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredArticles) { article in
                    ArticleRowView(article: article) {
                        selectedArticle = article
                    } onSave: {
                        Task {
                            await viewModel.toggleArticleSaved(article)
                        }
                    } onDelete: {
                        Task {
                            await viewModel.archiveArticle(article)
                        }
                    }
                    .onAppear {
                        Task {
                            await viewModel.loadMoreIfNeeded(currentArticle: article)
                        }
                    }
                    
                    Divider()
                        .padding(.horizontal, Constants.UI.padding)
                }
                
                if viewModel.isLoadingMore {
                    ProgressView()
                        .padding()
                }
            }
        }
        .background(Color.briefeedBackground)
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading articles...")
                .font(.headline)
                .foregroundColor(.briefeedSecondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.briefeedBackground)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.briefeedSecondaryLabel)
            
            Text("No articles found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Pull to refresh or add some feeds to get started")
                .font(.body)
                .foregroundColor(.briefeedSecondaryLabel)
                .multilineTextAlignment(.center)
            
            Button("Refresh") {
                Task {
                    await viewModel.refresh(feedId: selectedFeedId)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.briefeedRed)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.briefeedBackground)
    }
    
    // MARK: - Methods
    
    private func selectFeed(_ feedId: String) {
        selectedFeedId = feedId
        Task {
            await viewModel.refresh(feedId: feedId)
        }
    }
    
    private var filteredArticles: [Article] {
        if selectedFeedId == "all" {
            return viewModel.articles
        } else {
            return viewModel.articles.filter { $0.feed?.id?.uuidString == selectedFeedId }
        }
    }
}

// MARK: - Feed Selector Button
struct FeedSelectorButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : .briefeedLabel)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.briefeedRed : Color.briefeedSecondaryBackground)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Combined Feed View Model
class CombinedFeedViewModel: ObservableObject {
    @Published var articles: [Article] = []
    @Published var feeds: [Feed] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    
    private let redditService = RedditService()
    private let viewContext = PersistenceController.shared.container.viewContext
    private var currentTask: Task<Void, Never>?
    
    func loadFeeds() async {
        // Fetch all feeds from Core Data
        let fetchRequest: NSFetchRequest<Feed> = Feed.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Feed.sortOrder, ascending: true)]
        
        do {
            let fetchedFeeds = try viewContext.fetch(fetchRequest)
            await MainActor.run {
                feeds = fetchedFeeds
            }
            
            // Debug logging
            print("📱 Loading feeds from Core Data:")
            print("📱 Total feeds found: \(feeds.count)")
            for feed in feeds {
                print("📱 Feed: \(feed.name ?? "Unknown") - Active: \(feed.isActive) - Type: \(feed.type ?? "unknown")")
            }
            
            // If no feeds exist, create default feeds
            if feeds.isEmpty {
                print("📱 No feeds found, creating defaults...")
                await createDefaultFeeds()
            } else {
                // Load articles from all feeds
                print("📱 Loading articles from all active feeds...")
                await refresh(feedId: "all")
            }
        } catch {
            errorMessage = "Failed to load feeds: \(error.localizedDescription)"
            print("❌ Failed to load feeds: \(error)")
        }
    }
    
    func refresh(feedId: String) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        // Cancel previous task
        currentTask?.cancel()
        
        currentTask = Task {
            defer {
                Task { @MainActor in
                    isLoading = false
                }
            }
            do {
                if feedId == "all" {
                    // Load articles from all active feeds
                    var allArticles: [Article] = []
                    
                    print("  📋 Loading articles from all active feeds...")
                    
                    for feed in feeds where feed.isActive {
                        guard !Task.isCancelled else { break }
                        
                        print("  🔍 Processing feed: \(feed.name ?? "Unknown") (type: \(feed.type ?? "Unknown"))")
                        
                        if feed.path != nil {
                            // Generate proper URL for the feed
                            let url = DefaultDataService.shared.generateFeedURL(for: feed)
                            
                            do {
                                let response = try await redditService.fetchFeedWithURL(url)
                                
                                let feedArticles = response.data.children.map { child in
                                    createOrUpdateArticle(from: child.data, feed: feed)
                                }
                                allArticles.append(contentsOf: feedArticles)
                                print("    ✅ Loaded \(feedArticles.count) articles from \(feed.name ?? "Unknown")")
                            } catch {
                                print("    ❌ Failed to load \(feed.name ?? "Unknown"): \(error)")
                            }
                        }
                    }
                    
                    // Filter out invalid articles and sort by date
                    let filteredArticles = allArticles
                        .filter { article in
                            // Filter out articles with no title or that are invalid
                            guard let title = article.title, !title.isEmpty else { return false }
                            return true
                        }
                        .sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }
                    
                    await MainActor.run {
                        articles = filteredArticles
                    }
                } else {
                    // Load articles from specific feed
                    if let feed = feeds.first(where: { $0.id?.uuidString == feedId }),
                       feed.path != nil {
                        // Generate proper URL for the feed
                        let url = DefaultDataService.shared.generateFeedURL(for: feed)
                        let response = try await redditService.fetchFeedWithURL(url)
                        
                        let feedArticles = response.data.children.map { child in
                            createOrUpdateArticle(from: child.data, feed: feed)
                        }
                        await MainActor.run {
                            articles = feedArticles
                        }
                    }
                }
                
                try viewContext.save()
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                    }
                    print("  ❌ Error during refresh: \(error)")
                }
            }
        }
    }
    
    @MainActor
    func loadMoreIfNeeded(currentArticle: Article) async {
        // Implement pagination if needed
    }
    
    @MainActor
    func toggleArticleSaved(_ article: Article) async {
        article.isSaved.toggle()
        if article.isSaved {
            article.savedAt = Date()
            // Add to audio queue when saving
            Task {
                await BriefeedAudioService.shared.addToQueue(article)
            }
        } else {
            article.savedAt = nil
            // Remove from audio queue when unsaving
            let queue = BriefeedAudioService.shared.queue
            if let index = queue.firstIndex(where: { $0.content.id == article.id }) {
                BriefeedAudioService.shared.removeFromQueue(at: index)
            }
        }
        do {
            try viewContext.save()
        } catch {
            errorMessage = "Failed to save article: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    func archiveArticle(_ article: Article) async {
        article.isArchived = true
        do {
            try viewContext.save()
        } catch {
            errorMessage = "Failed to archive article: \(error.localizedDescription)"
        }
    }
    
    private func createOrUpdateArticle(from post: RedditPost, feed: Feed) -> Article {
        // Check if article already exists
        let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "url == %@ AND title == %@", post.url ?? "", post.title)
        
        if let existingArticle = try? viewContext.fetch(fetchRequest).first {
            // Update existing article
            updateArticle(existingArticle, from: post)
            return existingArticle
        } else {
            // Create new article
            let article = Article(context: viewContext)
            article.id = UUID()
            // Reddit ID is stored in the URL and title combination for uniqueness
            article.feed = feed
            updateArticle(article, from: post)
            return article
        }
    }
    
    private func updateArticle(_ article: Article, from post: RedditPost) {
        article.title = post.title
        article.author = post.author
        article.subreddit = post.subreddit
        article.url = post.url
        article.thumbnail = post.thumbnail
        article.content = post.selftext
        article.createdAt = Date(timeIntervalSince1970: TimeInterval(post.created))
    }
    
    @MainActor
    private func createDefaultFeeds() async {
        do {
            // Use DefaultDataService to create feeds (this prevents duplicates)
            try await DefaultDataService.shared.createDefaultFeedsIfNeeded()
            
            // Reload feeds after creation
            await loadFeeds()
        } catch {
            errorMessage = "Failed to create default feeds: \(error.localizedDescription)"
            print("  ❌ Failed to create feeds: \(error)")
        }
    }
}

#Preview {
    CombinedFeedView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}