//
//  FeedRowView.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import SwiftUI

struct FeedRowView: View {
    let feed: Feed
    @StateObject private var viewModel = FeedViewModel()
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(feed.name ?? "Unknown Feed")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(feed.type ?? "subreddit")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !feed.isActive {
                Text("Inactive")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(4)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                Task {
                    await viewModel.toggleFeedActive(feed)
                }
            } label: {
                Label(feed.isActive ? "Deactivate" : "Activate", 
                      systemImage: feed.isActive ? "pause.circle" : "play.circle")
            }
            
            Button(role: .destructive) {
                Task {
                    await viewModel.deleteFeed(feed)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    List {
        FeedRowView(feed: {
            let feed = Feed(context: PersistenceController.preview.container.viewContext)
            feed.id = UUID()
            feed.name = "r/technology"
            feed.type = "subreddit"
            feed.path = "/r/technology"
            feed.isActive = true
            return feed
        }())
    }
}