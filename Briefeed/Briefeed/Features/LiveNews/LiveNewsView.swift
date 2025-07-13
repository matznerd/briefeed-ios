//
//  LiveNewsView.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import SwiftUI
import CoreData

struct LiveNewsView: View {
    @StateObject private var rssService = RSSAudioService.shared
    @StateObject private var queueService = QueueService.shared
    @State private var isRefreshing = false
    @State private var selectedFeed: RSSFeed?
    @State private var showingAddFeed = false
    @State private var showingFeedDetails = false
    
    @FetchRequest(
        entity: RSSFeed.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \RSSFeed.priority, ascending: true),
            NSSortDescriptor(keyPath: \RSSFeed.title, ascending: true)
        ]
    ) private var feeds: FetchedResults<RSSFeed>
    
    var body: some View {
        NavigationStack {
            ZStack {
                if feeds.isEmpty && !isRefreshing {
                    emptyStateView
                } else {
                    feedsListView
                }
            }
            .navigationTitle("Live News")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                toolbarContent
            }
            .refreshable {
                await refreshFeeds()
            }
            .sheet(isPresented: $showingAddFeed) {
                AddFeedView()
            }
            .sheet(item: $selectedFeed) { feed in
                FeedDetailsView(feed: feed)
            }
            .onAppear {
                Task {
                    if UserDefaultsManager.shared.autoRefreshLiveNewsOnOpen {
                        await refreshFeeds()
                    }
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var feedsListView: some View {
        List {
            ForEach(feeds) { feed in
                FeedRow(feed: feed) {
                    selectedFeed = feed
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    feedSwipeActions(for: feed)
                }
            }
            .onMove { source, destination in
                moveFeed(from: source, to: destination)
            }
            
            // Add padding at bottom for mini player
            Color.clear
                .frame(height: 100)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(feeds.count > 1 ? .inactive : .inactive))
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No News Feeds")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add RSS feeds to get live audio news")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: {
                showingAddFeed = true
            }) {
                Label("Add Feed", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(25)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.briefeedBackground)
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    showingAddFeed = true
                } label: {
                    Label("Add Feed", systemImage: "plus")
                }
                
                if !feeds.isEmpty {
                    Button {
                        Task {
                            await addAllToQueue()
                        }
                    } label: {
                        Label("Add All to Queue", systemImage: "text.badge.plus")
                    }
                    
                    Divider()
                    
                    Button {
                        Task {
                            await refreshFeeds()
                        }
                    } label: {
                        Label("Refresh All", systemImage: "arrow.clockwise")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        
        if feeds.count > 1 {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
        }
    }
    
    // MARK: - Actions
    
    @ViewBuilder
    private func feedSwipeActions(for feed: RSSFeed) -> some View {
        Button(role: .destructive) {
            deleteFeed(feed)
        } label: {
            Label("Delete", systemImage: "trash")
        }
        
        Button {
            toggleEnabled(feed)
        } label: {
            Label(feed.isEnabled ? "Disable" : "Enable", 
                  systemImage: feed.isEnabled ? "pause.circle" : "play.circle")
        }
        .tint(feed.isEnabled ? .orange : .green)
    }
    
    private func refreshFeeds() async {
        isRefreshing = true
        await rssService.refreshAllFeeds()
        isRefreshing = false
    }
    
    private func addAllToQueue() async {
        for feed in feeds where feed.isEnabled {
            if let episodes = feed.episodes?.allObjects as? [RSSEpisode] {
                let freshEpisodes = episodes.filter { episode in
                    rssService.isEpisodeFresh(episode)
                }
                
                for episode in freshEpisodes.prefix(3) {
                    await queueService.addRSSEpisode(episode)
                }
            }
        }
    }
    
    private func deleteFeed(_ feed: RSSFeed) {
        rssService.deleteFeed(feed)
    }
    
    private func toggleEnabled(_ feed: RSSFeed) {
        feed.isEnabled.toggle()
        rssService.saveFeed(feed)
    }
    
    private func moveFeed(from source: IndexSet, to destination: Int) {
        // Update priorities based on new order
        var feeds = Array(self.feeds)
        feeds.move(fromOffsets: source, toOffset: destination)
        
        for (index, feed) in feeds.enumerated() {
            feed.priority = Int16(index)
        }
        
        try? PersistenceController.shared.container.viewContext.save()
    }
}

// MARK: - Feed Row
private struct FeedRow: View {
    @ObservedObject var feed: RSSFeed
    let onTap: () -> Void
    
    private var latestEpisode: RSSEpisode? {
        (feed.episodes?.allObjects as? [RSSEpisode])?
            .sorted { $0.publishedDate ?? Date.distantPast > $1.publishedDate ?? Date.distantPast }
            .first
    }
    
    private var freshEpisodeCount: Int {
        (feed.episodes?.allObjects as? [RSSEpisode])?
            .filter { RSSAudioService.shared.isEpisodeFresh($0) }
            .count ?? 0
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Feed Icon
                ZStack {
                    Circle()
                        .fill(feed.isEnabled ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 22))
                        .foregroundColor(feed.isEnabled ? .red : .gray)
                }
                
                // Feed Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(feed.title ?? "Unknown Feed")
                            .font(.headline)
                            .lineLimit(1)
                        
                        if !feed.isEnabled {
                            Text("DISABLED")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray)
                                .cornerRadius(4)
                        }
                    }
                    
                    if let latest = latestEpisode {
                        Text(latest.title ?? "")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 8) {
                        if freshEpisodeCount > 0 {
                            Label("\(freshEpisodeCount) new", systemImage: "sparkle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        
                        if let lastUpdate = feed.lastUpdated {
                            Text("Updated \(lastUpdate.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Feed View
private struct AddFeedView: View {
    @Environment(\.dismiss) var dismiss
    @State private var feedURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Feed URL or Player.fm URL", text: $feedURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            addFeed()
                        }
                } header: {
                    Text("RSS Feed URL")
                } footer: {
                    Text("Enter a podcast RSS feed URL or a Player.fm podcast page URL")
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addFeed()
                    }
                    .disabled(feedURL.isEmpty || isLoading)
                }
            }
            .disabled(isLoading)
            .overlay {
                if isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
        }
    }
    
    private func addFeed() {
        guard !feedURL.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await RSSAudioService.shared.addFeed(from: feedURL)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Feed Details View
private struct FeedDetailsView: View {
    @ObservedObject var feed: RSSFeed
    @Environment(\.dismiss) var dismiss
    @StateObject private var queueService = QueueService.shared
    
    private var episodes: [RSSEpisode] {
        (feed.episodes?.allObjects as? [RSSEpisode] ?? [])
            .sorted { $0.publishedDate ?? Date.distantPast > $1.publishedDate ?? Date.distantPast }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Feed Info
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(feed.title ?? "Unknown Feed")
                            .font(.headline)
                        
                        if let description = feed.feedDescription {
                            Text(description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let url = feed.url {
                            Link(url, destination: URL(string: url)!)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Feed Information")
                }
                
                // Episodes
                Section {
                    ForEach(episodes.prefix(20)) { episode in
                        EpisodeRow(episode: episode) {
                            Task {
                                await queueService.addRSSEpisode(episode)
                            }
                        }
                    }
                } header: {
                    Text("Recent Episodes")
                } footer: {
                    if episodes.count > 20 {
                        Text("Showing 20 most recent episodes")
                    }
                }
            }
            .navigationTitle("Feed Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Episode Row
private struct EpisodeRow: View {
    let episode: RSSEpisode
    let onAddToQueue: () -> Void
    
    private var isFresh: Bool {
        RSSAudioService.shared.isEpisodeFresh(episode)
    }
    
    private var isInQueue: Bool {
        QueueService.shared.enhancedQueue.contains { item in
            item.audioUrl?.absoluteString == episode.audioUrl
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(episode.title ?? "Unknown Episode")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                Spacer()
                
                if isInQueue {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 16))
                } else if isFresh {
                    Button(action: onAddToQueue) {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.briefeedRed)
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            HStack(spacing: 8) {
                if let date = episode.publishedDate {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let duration = episode.duration, duration > 0 {
                    Text("• \(formatDuration(duration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if isFresh {
                    Text("• Fresh")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(isFresh ? 1.0 : 0.6)
    }
    
    private func formatDuration(_ seconds: Int32) -> String {
        let minutes = Int(seconds) / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

#Preview {
    LiveNewsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}