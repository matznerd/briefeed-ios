//
//  FeedListView.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import SwiftUI
import CoreData

struct FeedListView: View {
    @StateObject private var viewModel = FeedViewModel()
    @StateObject private var stateManager = ArticleStateManager.shared
    @State private var showingAddFeed = false
    @State private var selectedFeed: Feed?
    
    var body: some View {
        NavigationStack {
            List {
                if viewModel.feeds.isEmpty {
                    EmptyFeedView()
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(viewModel.feeds) { feed in
                        NavigationLink(value: feed) {
                            FeedRowView(feed: feed)
                        }
                    }
                    .onDelete(perform: deleteFeed)
                    .onMove(perform: moveFeed)
                }
            }
            .navigationTitle("Feeds")
            .navigationDestination(for: Feed.self) { feed in
                ArticleListView(feed: feed)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddFeed = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                
                if !viewModel.feeds.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $showingAddFeed) {
                AddFeedView(viewModel: viewModel)
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.3))
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil), actions: {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
        }
    }
    
    private func deleteFeed(at offsets: IndexSet) {
        for index in offsets {
            let feed = viewModel.feeds[index]
            Task {
                await viewModel.deleteFeed(feed)
            }
        }
    }
    
    private func moveFeed(from source: IndexSet, to destination: Int) {
        Task {
            await viewModel.moveFeed(from: source, to: destination)
        }
    }
}

struct EmptyFeedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "newspaper")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Feeds Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add your favorite subreddits to get started")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    FeedListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}