//
//  BriefView.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import SwiftUI
import CoreData

struct BriefView: View {
    @StateObject private var viewModel = BriefViewModel()
    @StateObject private var audioService = AudioService.shared
    @StateObject private var stateManager = ArticleStateManager.shared
    @State private var editMode = EditMode.inactive
    @State private var showingClearQueueAlert = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading && viewModel.queuedArticles.isEmpty {
                    loadingView
                } else if viewModel.queuedArticles.isEmpty && !viewModel.isLoading {
                    emptyStateView
                } else {
                    queueListView
                }
            }
            .onAppear {
                // Sync with saved articles on appear
                Task {
                    await viewModel.loadQueuedArticles()
                }
            }
            .navigationTitle("Brief")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.queuedArticles.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                showingClearQueueAlert = true
                            } label: {
                                Label("Clear Queue", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    if !viewModel.queuedArticles.isEmpty {
                        EditButton()
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .refreshable {
                await viewModel.refresh()
            }
            .alert("Clear Queue", isPresented: $showingClearQueueAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    viewModel.clearQueue()
                }
            } message: {
                Text("Remove all articles from the queue? This action cannot be undone.")
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
    
    private var queueListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.queuedArticles.enumerated()), id: \.element.id) { index, article in
                    QueuedArticleRow(
                        article: article,
                        queuePosition: viewModel.queuedArticles.count - index,  // Reverse numbering: bottom is #1
                        isCurrentlyPlaying: audioService.currentArticle?.id == article.id,
                        audioState: stateManager.audioState,
                        isNextToPlay: audioService.queueIndex > 0 && index == audioService.queueIndex - 1
                    )
                    .onTapGesture {
                        viewModel.playArticle(article)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation {
                                viewModel.removeFromQueue(article)
                            }
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    }
                    
                    if index < viewModel.queuedArticles.count - 1 {
                        Divider()
                            .padding(.horizontal, Constants.UI.padding)
                    }
                }
                .onMove { indices, newOffset in
                    viewModel.moveQueueItems(from: indices, to: newOffset)
                }
            }
            .padding(.bottom, 100) // Space for mini player
        }
        .background(Color.briefeedBackground)
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading queue...")
                .font(.headline)
                .foregroundColor(.briefeedSecondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.briefeedBackground)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.briefeedSecondaryLabel)
            
            Text("Your Brief is Empty")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add articles to your listening queue from the feed")
                .font(.body)
                .foregroundColor(.briefeedSecondaryLabel)
                .multilineTextAlignment(.center)
            
            Button(action: {
                // Navigate to feed - handled by parent
            }) {
                Text("Browse Articles")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(25)
            }
            .padding(.top, 10)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.briefeedBackground)
    }
}

#Preview {
    BriefView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}