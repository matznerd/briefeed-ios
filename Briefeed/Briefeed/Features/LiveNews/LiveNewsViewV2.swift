//
//  LiveNewsViewV2.swift
//  Briefeed
//
//  Updated to use AudioPlayerViewModelV2
//

import SwiftUI
import CoreData

struct LiveNewsViewV2: View {
    @StateObject private var rssService = RSSAudioService.shared
    @EnvironmentObject var audioPlayerViewModel: AudioPlayerViewModelV2
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var isRefreshing = false
    @State private var selectedFeed: RSSFeed?
    @State private var showingAddFeed = false
    @State private var showingFeedDetails = false
    
    @FetchRequest(
        entity: RSSFeed.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \RSSFeed.priority, ascending: true),
            NSSortDescriptor(keyPath: \RSSFeed.displayName, ascending: true)
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
                AddRSSFeedViewV2()
            }
            .sheet(item: $selectedFeed) { feed in
                FeedDetailsViewV2(feed: feed)
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
        VStack(spacing: 0) {
            // Play All Button
            if feeds.contains(where: { $0.isEnabled }) {
                VStack(spacing: 0) {
                    Button(action: {
                        Task {
                            await playAllLiveNews()
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 24))
                            Text("Play Live News")
                                .font(.headline)
                            Spacer()
                            Text("Auto-plays latest episodes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.briefeedRed.opacity(0.1))
                        .foregroundColor(.briefeedRed)
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                }
            }
            
            List {
                ForEach(feeds) { feed in
                    FeedRowV2(feed: feed) {
                        selectedFeed = feed
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        feedSwipeActions(for: feed)
                    }
                }
                .onDelete { indexSet in
                    deleteFeeds(at: indexSet)
                }
            }
            .listStyle(.plain)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No RSS Feeds")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add RSS podcast feeds to stream the latest episodes")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                showingAddFeed = true
            } label: {
                Label("Add Feed", systemImage: "plus.circle")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.briefeedRed)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showingAddFeed = true
            } label: {
                Image(systemName: "plus.circle")
            }
        }
    }
    
    // MARK: - Actions
    
    @ViewBuilder
    private func episodeSwipeActions(for episode: RSSEpisode) -> some View {
        Button {
            // Add to end of queue
            Task {
                await appViewModel.queueEpisode(episode)
            }
            // Haptic feedback
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Label("Play Later", systemImage: "plus.circle")
        }
        .tint(.blue)
        
        Button {
            Task {
                // Play episode immediately
                await appViewModel.play(episode: episode)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } label: {
            Label("Play Now", systemImage: "play.circle")
        }
        .tint(.orange)
    }
    
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
    
    private func playAllLiveNews() async {
        print("🎙️ Play Live News pressed")
        
        // Find the latest episode from each enabled feed
        var episodesToPlay: [RSSEpisode] = []
        
        for feed in feeds where feed.isEnabled {
            if let episodes = feed.episodes?.allObjects as? [RSSEpisode] {
                // Get the most recent episode that hasn't been listened to
                if let latestEpisode = episodes
                    .filter({ !$0.isListened })
                    .sorted(by: { $0.pubDate > $1.pubDate })
                    .first {
                    episodesToPlay.append(latestEpisode)
                    print("🎙️ Found episode: \(latestEpisode.title ?? "Unknown") from \(feed.displayName ?? "Unknown feed")")
                }
            }
        }
        
        print("🎙️ Total episodes to play: \(episodesToPlay.count)")
        
        // Play all episodes using new audio system
        if !episodesToPlay.isEmpty {
            await audioPlayerViewModel.playQueue(episodes: episodesToPlay)
        }
    }
    
    private func deleteFeeds(at indexSet: IndexSet) {
        for index in indexSet {
            let feed = feeds[index]
            deleteFeed(feed)
        }
    }
    
    private func deleteFeed(_ feed: RSSFeed) {
        let context = PersistenceController.shared.container.viewContext
        context.delete(feed)
        do {
            try context.save()
        } catch {
            print("Failed to delete feed: \(error)")
        }
    }
    
    private func toggleEnabled(_ feed: RSSFeed) {
        feed.isEnabled.toggle()
        let context = PersistenceController.shared.container.viewContext
        do {
            try context.save()
        } catch {
            print("Failed to toggle feed: \(error)")
        }
    }
}

// MARK: - Feed Row View
struct FeedRowV2: View {
    let feed: RSSFeed
    let onTap: () -> Void
    
    @FetchRequest private var episodes: FetchedResults<RSSEpisode>
    
    init(feed: RSSFeed, onTap: @escaping () -> Void) {
        self.feed = feed
        self.onTap = onTap
        
        self._episodes = FetchRequest(
            entity: RSSEpisode.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \RSSEpisode.pubDate, ascending: false)],
            predicate: NSPredicate(format: "feedId == %@", feed.id)
        )
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(feed.displayName ?? "Unknown Feed")
                            .font(.headline)
                            .lineLimit(1)
                        
                        if !feed.isEnabled {
                            Text("Disabled")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    
                    if let latestEpisode = episodes.first {
                        Text(latestEpisode.title ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 8) {
                        if let lastFetch = feed.lastFetchDate {
                            Text("Updated \(lastFetch.timeAgoDisplay)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("\(episodes.filter { !$0.isListened }.count) new")
                            .font(.caption2)
                            .foregroundColor(.briefeedRed)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Feed Details View
struct FeedDetailsViewV2: View {
    let feed: RSSFeed
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appViewModel: AppViewModel
    
    @FetchRequest private var episodes: FetchedResults<RSSEpisode>
    
    init(feed: RSSFeed) {
        self.feed = feed
        
        self._episodes = FetchRequest(
            entity: RSSEpisode.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \RSSEpisode.pubDate, ascending: false)],
            predicate: NSPredicate(format: "feedId == %@", feed.id)
        )
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(episodes) { episode in
                        EpisodeRowV2(episode: episode)
                    }
                }
            }
            .navigationTitle(feed.displayName ?? "Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Episode Row
struct EpisodeRowV2: View {
    let episode: RSSEpisode
    @EnvironmentObject var appViewModel: AppViewModel
    
    var body: some View {
        Button {
            Task {
                await appViewModel.play(episode: episode)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title ?? "Unknown Episode")
                    .font(.headline)
                    .lineLimit(2)
                
                if let description = episode.episodeDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack {
                    Text(episode.pubDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if episode.isListened {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add RSS Feed View
struct AddRSSFeedViewV2: View {
    @State private var feedURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Feed URL", text: $feedURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                } header: {
                    Text("RSS Feed URL")
                } footer: {
                    Text("Enter the URL of an RSS podcast feed")
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add RSS Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        Task {
                            await addFeed()
                        }
                    }
                    .disabled(feedURL.isEmpty || isLoading)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.3))
                }
            }
        }
    }
    
    private func addFeed() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await RSSAudioService.shared.addFeed(from: feedURL)
            dismiss()
        } catch {
            errorMessage = "Failed to add feed: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

// Date extension removed - using existing Date+Extensions.swift