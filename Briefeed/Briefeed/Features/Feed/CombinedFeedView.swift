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
    @EnvironmentObject var appViewModel: AppViewModel
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
                    .accessibilityIdentifier(AccessibilityID.Feed.addFeed)
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
        List {
            ForEach(Array(filteredArticles.enumerated()), id: \.element.id) { index, article in
                ArticleRowView(article: article) {
                    selectedArticle = article
                } onSave: {
                    Task {
                        await viewModel.toggleArticleSaved(article)
                    }
                }
                .id(article.id)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.visible)
                .onAppear {
                    print("📱 Article appeared at index \(index) of \(filteredArticles.count)")
                    if index >= filteredArticles.count - 3 {
                        print("📱 Triggering loadMoreIfNeeded for article at index \(index)")
                        Task {
                            await viewModel.loadMoreIfNeeded(currentArticle: article)
                        }
                    }
                }
            }

            if viewModel.isLoadingMore {
                HStack {
                    ProgressView()
                    Text("Loading more articles...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
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
        // Clear existing articles when switching feeds for cleaner UX
        viewModel.articles = []
        // Clear pagination tokens when switching feeds
        viewModel.feedPaginationTokens.removeAll()
        Task {
            await viewModel.refresh(feedId: feedId)
        }
    }
    
    private var filteredArticles: [Article] {
        let base: [Article]
        if selectedFeedId == "all" {
            base = viewModel.articles
        } else {
            base = viewModel.articles.filter { $0.feed?.id?.uuidString == selectedFeedId }
        }
        return base.filter { !$0.isArchived }
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
        .accessibilityIdentifier(AccessibilityID.Feed.selector(title))
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
    private var afterToken: String?  // For single feed pagination
    var feedPaginationTokens: [String: String] = [:]  // Track pagination per feed
    private var hasMorePages = true
    private var currentFeedId = "all"
    
    @MainActor
    func loadFeeds() async {
        // Fetch all feeds from Core Data
        let fetchRequest: NSFetchRequest<Feed> = Feed.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Feed.sortOrder, ascending: true)]
        
        do {
            feeds = try viewContext.fetch(fetchRequest)
            
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
    
    @MainActor
    func refresh(feedId: String) async {
        isLoading = true
        errorMessage = nil
        
        // Reset pagination when refreshing
        afterToken = nil
        hasMorePages = true
        currentFeedId = feedId
        
        print("🔄 Refreshing feed: \(feedId)")
        print("  📊 Total feeds available: \(feeds.count)")
        
        // Cancel previous task
        currentTask?.cancel()
        
        currentTask = Task {
            do {
                if feedId == "all" {
                    // Load articles from all active feeds
                    var allArticles: [Article] = []
                    
                    print("  📋 Loading articles from all active feeds...")
                    
                    // Reset pagination tokens for all feeds on refresh
                    feedPaginationTokens.removeAll()
                    hasMorePages = true  // Always allow loading more for "all" view
                    
                    for feed in feeds where feed.isActive {
                        guard !Task.isCancelled else { break }
                        
                        print("  🔍 Processing feed: \(feed.name ?? "Unknown") (type: \(feed.type ?? "Unknown"))")
                        
                        if feed.path != nil {
                            // Generate proper URL for the feed
                            let url = DefaultDataService.shared.generateFeedURL(for: feed)
                            
                            do {
                                let response = try await redditService.fetchFeedWithURL(url)
                                
                                // Store pagination token for this feed
                                if let token = response.data.after {
                                    feedPaginationTokens[feed.id?.uuidString ?? ""] = token
                                    print("    📄 Stored pagination token for \(feed.name ?? ""): \(token)")
                                }
                                
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
                    articles = allArticles
                        .filter { article in
                            // Filter out articles with no title or that are invalid
                            guard let title = article.title, !title.isEmpty else { return false }
                            return true
                        }
                        .sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }
                } else {
                    // Load articles from specific feed
                    if let feed = feeds.first(where: { $0.id?.uuidString == feedId }),
                       feed.path != nil {
                        // Generate proper URL for the feed (with no after token for initial load)
                        let url = DefaultDataService.shared.generateFeedURL(for: feed, after: nil)
                        print("📄 Initial load URL for \(feed.name ?? ""): \(url)")
                        let response = try await redditService.fetchFeedWithURL(url)
                        
                        // Set up pagination for next load
                        afterToken = response.data.after
                        hasMorePages = response.data.after != nil
                        print("📄 Feed \(feed.name ?? "") initial load:")
                        print("  - Received \(response.data.children.count) posts")
                        print("  - afterToken: \(afterToken ?? "nil")")
                        print("  - hasMorePages: \(hasMorePages)")
                        
                        articles = response.data.children.map { child in
                            createOrUpdateArticle(from: child.data, feed: feed)
                        }
                        
                        print("📄 Loaded \(articles.count) initial articles from \(feed.name ?? "")")
                    }
                }
                
                try viewContext.save()
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            
            isLoading = false
        }
    }
    
    @MainActor
    func loadMoreIfNeeded(currentArticle: Article) async {
        // Check if we're at the last few articles and should load more
        guard let lastArticle = articles.last,
              let currentIndex = articles.firstIndex(where: { $0.id == currentArticle.id }),
              currentIndex >= articles.count - 3,  // Trigger when we're near the end
              hasMorePages,
              !isLoadingMore,
              !isLoading else { 
            let index = articles.firstIndex(where: { $0.id == currentArticle.id }) ?? -1
            print("📄 loadMoreIfNeeded skipped:")
            print("  - currentIndex: \(index) of \(articles.count)")
            print("  - hasMorePages: \(hasMorePages)")
            print("  - isLoadingMore: \(isLoadingMore)")
            print("  - isLoading: \(isLoading)")
            print("  - afterToken: \(afterToken ?? "nil")")
            print("  - currentFeedId: \(currentFeedId)")
            return 
        }
        
        print("📄 Loading more articles - currentFeedId: \(currentFeedId), afterToken: \(afterToken ?? "nil")")
        isLoadingMore = true
        
        // Support pagination for both "all" and individual feeds
        if currentFeedId == "all" {
            // Load more from all feeds that have pagination tokens
            var newArticles: [Article] = []
            
            for feed in feeds where feed.isActive {
                guard let feedId = feed.id?.uuidString,
                      let token = feedPaginationTokens[feedId] else {
                    print("📄 No more pages for feed: \(feed.name ?? "Unknown")")
                    continue
                }
                
                print("📄 Loading more from feed: \(feed.name ?? "Unknown") with token: \(token)")
                
                do {
                    let url = DefaultDataService.shared.generateFeedURL(for: feed, after: token)
                    let response = try await redditService.fetchFeedWithURL(url)
                    
                    // Update pagination token for this feed
                    if let newToken = response.data.after {
                        feedPaginationTokens[feedId] = newToken
                    } else {
                        // No more pages for this feed
                        feedPaginationTokens.removeValue(forKey: feedId)
                    }
                    
                    let feedArticles = response.data.children.map { child in
                        createOrUpdateArticle(from: child.data, feed: feed)
                    }
                    newArticles.append(contentsOf: feedArticles)
                    print("📄 Loaded \(feedArticles.count) more articles from \(feed.name ?? "")")
                } catch {
                    print("❌ Failed to load more from \(feed.name ?? ""): \(error)")
                    // Remove token for this feed to prevent retrying
                    feedPaginationTokens.removeValue(forKey: feedId)
                }
            }
            
            // Add new articles to existing list
            if !newArticles.isEmpty {
                articles.append(contentsOf: newArticles)
                print("📄 Total articles after loading more: \(articles.count)")
            }
            
            // Check if any feed still has more pages
            hasMorePages = !feedPaginationTokens.isEmpty
            if !hasMorePages {
                print("📄 No more articles available from any feed")
            }
        } else {
            // Load more from specific feed
            if let feed = feeds.first(where: { $0.id?.uuidString == currentFeedId }) {
                print("📄 Loading more from feed: \(feed.name ?? "Unknown")")
                print("📄 Current afterToken: \(afterToken ?? "nil")")
                do {
                    // Make sure we have an afterToken for pagination
                    guard let token = afterToken else {
                        print("❌ No afterToken available for pagination!")
                        hasMorePages = false
                        isLoadingMore = false
                        return
                    }
                    
                    let url = DefaultDataService.shared.generateFeedURL(for: feed, after: token)
                    print("📄 Pagination URL: \(url)")
                    let response = try await redditService.fetchFeedWithURL(url)
                    
                    // Update pagination token
                    afterToken = response.data.after
                    hasMorePages = response.data.after != nil
                    print("📄 New afterToken: \(afterToken ?? "nil"), hasMore: \(hasMorePages)")
                    
                    // Add new articles
                    let newArticles = response.data.children.map { child in
                        createOrUpdateArticle(from: child.data, feed: feed)
                    }
                    
                    // Append to existing articles
                    articles.append(contentsOf: newArticles)
                    
                    print("📄 Loaded \(newArticles.count) more articles. Total: \(articles.count)")
                } catch {
                    print("❌ Failed to load more: \(error)")
                    hasMorePages = false // Stop trying if we hit an error
                }
            } else {
                print("❌ Could not find feed with ID: \(currentFeedId)")
            }
        }
        
        isLoadingMore = false
    }
    
    @MainActor
    func toggleArticleSaved(_ article: Article) async {
        article.isSaved.toggle()
        if article.isSaved {
            article.savedAt = Date()
            // Article saving now handled by the Brief view's queue management
        } else {
            article.savedAt = nil
            // Article removal now handled by the Brief view's queue management
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