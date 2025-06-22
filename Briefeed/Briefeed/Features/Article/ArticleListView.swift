//
//  ArticleListView.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import SwiftUI

struct ArticleListView: View {
    let feed: Feed
    @StateObject private var viewModel: ArticleListViewModel
    @StateObject private var stateManager = ArticleStateManager.shared
    @State private var showSavedOnly = false
    @State private var showUnreadOnly = false
    @State private var selectedArticle: Article?
    
    init(feed: Feed) {
        self.feed = feed
        self._viewModel = StateObject(wrappedValue: ArticleListViewModel(feed: feed))
    }
    
    var body: some View {
        ZStack {
            if viewModel.isLoading && viewModel.articles.isEmpty {
                loadingView
            } else if viewModel.articles.isEmpty && !viewModel.isLoading {
                emptyStateView
            } else {
                articleListView
            }
        }
        .navigationTitle(feed.name ?? "Articles")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                filterMenu
            }
        }
        .navigationDestination(item: $selectedArticle) { article in
            ArticleView(article: article)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    // MARK: - Views
    
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
                            await viewModel.deleteArticle(article)
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
            
            Text("Pull to refresh or check back later")
                .font(.body)
                .foregroundColor(.briefeedSecondaryLabel)
                .multilineTextAlignment(.center)
            
            Button("Refresh") {
                Task {
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.briefeedRed)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.briefeedBackground)
    }
    
    private var filterMenu: some View {
        Menu {
            Toggle("Saved Only", isOn: $showSavedOnly)
            Toggle("Unread Only", isOn: $showUnreadOnly)
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .symbolVariant(filtersActive ? .fill : .none)
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredArticles: [Article] {
        viewModel.filterArticles(showSavedOnly: showSavedOnly, showUnreadOnly: showUnreadOnly)
    }
    
    private var filtersActive: Bool {
        showSavedOnly || showUnreadOnly
    }
}

#Preview {
    NavigationStack {
        ArticleListView(feed: {
            let context = PersistenceController.preview.container.viewContext
            let feed = Feed(context: context)
            feed.id = UUID()
            feed.name = "r/technology"
            feed.type = "subreddit"
            feed.path = "/r/technology"
            
            // Add sample articles
            for i in 0..<5 {
                let article = Article(context: context)
                article.id = UUID()
                article.title = "Sample Article \(i + 1)"
                article.author = "user\(i)"
                article.subreddit = "technology"
                article.createdAt = Date().addingTimeInterval(TimeInterval(-i * 3600))
                article.isRead = i % 2 == 0
                article.isSaved = i == 0
                article.feed = feed
                article.thumbnail = "https://via.placeholder.com/150"
            }
            
            return feed
        }())
    }
}