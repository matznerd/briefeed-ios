//
//  SavedArticlesView.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import SwiftUI
import CoreData
import Combine

struct SavedArticlesView: View {
    @StateObject private var viewModel = SavedArticlesViewModel()
    @State private var selectedArticle: Article?
    
    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading && viewModel.savedArticles.isEmpty {
                    loadingView
                } else if viewModel.savedArticles.isEmpty && !viewModel.isLoading {
                    emptyStateView
                } else {
                    savedArticlesListView
                }
            }
            .navigationTitle("Saved Articles")
            .navigationBarTitleDisplayMode(.large)
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
    }
    
    // MARK: - Views
    
    private var savedArticlesListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.savedArticles) { article in
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
                    
                    Divider()
                        .padding(.horizontal, Constants.UI.padding)
                }
            }
        }
        .background(Color.briefeedBackground)
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading saved articles...")
                .font(.headline)
                .foregroundColor(.briefeedSecondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.briefeedBackground)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bookmark")
                .font(.system(size: 60))
                .foregroundColor(.briefeedSecondaryLabel)
            
            Text("No Saved Articles")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Articles you save will appear here")
                .font(.body)
                .foregroundColor(.briefeedSecondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.briefeedBackground)
    }
}

// MARK: - SavedArticlesViewModel
@MainActor
class SavedArticlesViewModel: ObservableObject {
    @Published var savedArticles: [Article] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let storageService: StorageServiceProtocol
    private let viewContext: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()
    
    init(storageService: StorageServiceProtocol = StorageService.shared,
         viewContext: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.storageService = storageService
        self.viewContext = viewContext
        
        setupPublishers()
        Task {
            await loadSavedArticles()
        }
    }
    
    private func setupPublishers() {
        // Listen for changes to articles in Core Data
        NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.loadSavedArticles()
                }
            }
            .store(in: &cancellables)
    }
    
    func loadSavedArticles() async {
        isLoading = true
        
        let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isSaved == true")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Article.savedAt, ascending: false)]
        
        do {
            let articles = try viewContext.fetch(fetchRequest)
            self.savedArticles = articles
            isLoading = false
        } catch {
            errorMessage = "Failed to load saved articles: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    func refresh() async {
        await loadSavedArticles()
    }
    
    func toggleArticleSaved(_ article: Article) async {
        do {
            try await storageService.toggleArticleSaved(article)
            // The list will auto-update via Core Data notifications
        } catch {
            errorMessage = "Failed to update article: \(error.localizedDescription)"
        }
    }
    
    func deleteArticle(_ article: Article) async {
        do {
            try await storageService.deleteArticle(article)
            savedArticles.removeAll { $0.id == article.id }
        } catch {
            errorMessage = "Failed to delete article: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SavedArticlesView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}