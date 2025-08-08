//
//  CombinedFeedViewV2.swift
//  Briefeed
//
//  Fixed version without singleton @StateObject references
//

import SwiftUI
import CoreData

struct CombinedFeedViewV2: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
        animation: .default)
    private var feeds: FetchedResults<Feed>
    
    @State private var selectedFeed: Feed?
    @State private var showingAddFeed = false
    
    var body: some View {
        NavigationView {
            VStack {
                if appViewModel.isLoadingArticles {
                    ProgressView("Loading articles...")
                        .padding()
                } else if appViewModel.articles.isEmpty {
                    Text("No articles yet")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    List(appViewModel.articles) { article in
                        ArticleRowViewV2(article: article)
                            .environmentObject(appViewModel)
                    }
                }
            }
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddFeed = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddFeed) {
                Text("Add Feed View")
            }
            .task {
                await appViewModel.loadArticles()
            }
        }
    }
}

// Stub for ArticleRowViewV2
struct ArticleRowViewV2: View {
    let article: Article
    @EnvironmentObject var appViewModel: AppViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(article.title ?? "Untitled")
                .font(.headline)
                .lineLimit(2)
            
            Text(article.summary ?? "No summary")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack {
                if let feedName = article.feed?.name {
                    Text(feedName)
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        await appViewModel.addToQueue(article: article)
                    }
                }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }
}