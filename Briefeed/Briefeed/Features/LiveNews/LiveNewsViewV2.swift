//
//  LiveNewsViewV2.swift
//  Briefeed
//
//  Updated to use AudioPlayerViewModelV2
//

import SwiftUI
import CoreData

struct LiveNewsViewV2: View {
    @EnvironmentObject var audioPlayerViewModel: AudioPlayerViewModelV2
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var isRefreshing = false
    @State private var selectedFeed: RSSFeed?
    @State private var showingAddFeed = false
    @State private var showingFeedDetails = false
    @State private var editMode = EditMode.inactive
    
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
                    .accessibilityIdentifier(AccessibilityID.LiveNews.playAll)

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
                .onMove { source, destination in
                    moveFeeds(from: source, to: destination)
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)
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
        ToolbarItem(placement: .navigationBarLeading) {
            if !feeds.isEmpty {
                EditButton()
                    .environment(\.editMode, $editMode)
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showingAddFeed = true
            } label: {
                Image(systemName: "plus.circle")
            }
            .accessibilityIdentifier(AccessibilityID.LiveNews.addFeed)
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
                await appViewModel.playRadioEpisode(
                    RadioEpisodeKey(feedID: episode.feedId, episodeID: episode.id)
                )
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
        await audioPlayerViewModel.refreshRadio()
        isRefreshing = false
    }
    
    private func playAllLiveNews() async {
        await audioPlayerViewModel.playRadio()
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

    private func moveFeeds(from source: IndexSet, to destination: Int) {
        // Convert FetchedResults to mutable array
        var feedsArray = Array(feeds)
        feedsArray.move(fromOffsets: source, toOffset: destination)

        // Update priorities based on new order
        let context = PersistenceController.shared.container.viewContext
        for (index, feed) in feedsArray.enumerated() {
            feed.priority = Int16(index)
        }

        do {
            try context.save()
            print("[LiveNews] Reordered feeds - new priorities saved")
        } catch {
            print("Failed to save feed order: \(error)")
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
                        Text(feed.displayName)
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
                        Text(latestEpisode.title)
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
        .accessibilityIdentifier(AccessibilityID.LiveNews.feedRow(feed.displayName))
    }
}

// MARK: - Feed Details View
struct FeedDetailsViewV2: View {
    let feed: RSSFeed
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            FeedDetailsContentViewV2(feed: feed)
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

struct FeedDetailsContentViewV2: View {
    let feed: RSSFeed
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
        List {
            Section {
                ForEach(episodes) { episode in
                    EpisodeRowV2(episode: episode)
                }
            }
        }
        .navigationTitle(feed.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(AccessibilityID.Radio.sourceDetails)
    }
}

// MARK: - Episode Row
struct EpisodeRowV2: View {
    let episode: RSSEpisode
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        Button {
            Task {
                await appViewModel.playRadioEpisode(
                    RadioEpisodeKey(feedID: episode.feedId, episodeID: episode.id)
                )
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
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
struct AddRSSFeedWorkflow {
    private let addFeed: @MainActor (String) async throws -> Void

    init(addFeed: @escaping @MainActor (String) async throws -> Void = { urlString in
        try await RSSAudioService.shared.addFeed(from: urlString)
    }) {
        self.addFeed = addFeed
    }

    @MainActor
    func perform(
        urlString: String,
        onAdded: (@MainActor () async -> Void)?
    ) async throws {
        try await addFeed(urlString)
        await onAdded?()
    }
}

struct AddRSSFeedViewV2: View {
    @State private var feedURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) var dismiss
    private let onAdded: (@MainActor () async -> Void)?
    private let workflow: AddRSSFeedWorkflow

    init(
        onAdded: (@MainActor () async -> Void)? = nil,
        workflow: AddRSSFeedWorkflow = AddRSSFeedWorkflow()
    ) {
        self.onAdded = onAdded
        self.workflow = workflow
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Feed URL", text: $feedURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier(AccessibilityID.AddRSSFeed.urlField)
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
                    .accessibilityIdentifier(AccessibilityID.AddRSSFeed.cancel)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        Task {
                            await addFeed()
                        }
                    }
                    .disabled(feedURL.isEmpty || isLoading)
                    .accessibilityIdentifier(AccessibilityID.AddRSSFeed.add)
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
            try await workflow.perform(urlString: feedURL, onAdded: onAdded)
            dismiss()
        } catch {
            errorMessage = "Failed to add feed: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

// Date extension removed - using existing Date+Extensions.swift
