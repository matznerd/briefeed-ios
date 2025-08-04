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
    @StateObject private var audioService = BriefeedAudioService.shared
    @StateObject private var featureFlags = FeatureFlagManager.shared
    @State private var isRefreshing = false
    @State private var selectedFeed: RSSFeed?
    @State private var showingAddFeed = false
    @State private var showingFeedDetails = false
    
    // Helper function to play RSS episode using correct service
    private func playRSSEpisode(url: URL, title: String, episode: RSSEpisode?) async {
        // Always use new audio service
        await audioService.playRSSEpisode(url: url, title: title, episode: episode)
    }
    
    // Helper to get current playing state
    private var currentPlayingState: AudioPlayerState {
        return audioService.state.value
    }
    
    // Helper to check if idle or stopped
    private var isIdleOrStopped: Bool {
        return audioService.state.value == .idle || audioService.state.value == .stopped
    }
    
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
                AddRSSFeedView()
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
                    FeedRow(feed: feed) {
                        selectedFeed = feed
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        feedSwipeActions(for: feed)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if let episode = (feed.episodes?.allObjects as? [RSSEpisode])?
                            .sorted(by: { $0.pubDate > $1.pubDate })
                            .first {
                            episodeSwipeActions(for: episode)
                        }
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
    private func episodeSwipeActions(for episode: RSSEpisode) -> some View {
        Button {
            // Add to end of queue
            queueService.addRSSEpisode(episode, isLiveNews: false)
            // Haptic feedback
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Label("Play Later", systemImage: "plus.circle")
        }
        .tint(.blue)
        
        Button {
            Task {
                // Add to queue and play immediately
                queueService.addRSSEpisode(episode, isLiveNews: false, playNext: true)
                
                // If nothing is playing, start playback
                if isIdleOrStopped {
                    if let audioUrl = URL(string: episode.audioUrl) {
                        await playRSSEpisode(url: audioUrl, title: episode.title ?? "Unknown", episode: episode)
                    }
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } label: {
            Label("Play Next", systemImage: "play.circle")
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
    
    private func addAllToQueue() async {
        for feed in feeds where feed.isEnabled {
            if let episodes = feed.episodes?.allObjects as? [RSSEpisode] {
                let freshEpisodes = episodes.filter { episode in
                    rssService.isEpisodeFresh(episode)
                }
                
                for episode in freshEpisodes.prefix(3) {
                    queueService.addRSSEpisode(episode)
                }
            }
        }
    }
    
    private func playAllLiveNews() async {
        print("🎙️ Play Live News pressed")
        
        // Set Live News context
        // No longer needed as BriefeedAudioService handles this internally
        
        // Find the latest episode from each enabled feed
        var episodesToPlay: [(RSSEpisode, Int)] = []
        
        for (index, feed) in feeds.enumerated() where feed.isEnabled {
            if let episodes = feed.episodes?.allObjects as? [RSSEpisode] {
                // Get the most recent episode that hasn't been listened to
                if let latestEpisode = episodes
                    .filter({ !$0.isListened })
                    .sorted(by: { $0.pubDate > $1.pubDate })
                    .first {
                    episodesToPlay.append((latestEpisode, index))
                    print("🎙️ Found episode: \(latestEpisode.title ?? "Unknown") from \(feed.displayName ?? "Unknown feed")")
                }
            }
        }
        
        print("🎙️ Total episodes to play: \(episodesToPlay.count)")
        
        // Sort by feed priority
        episodesToPlay.sort { $0.1 < $1.1 }
        
        // Play the first episode directly (like radio streaming)
        if let firstEpisode = episodesToPlay.first?.0,
           let audioUrl = URL(string: firstEpisode.audioUrl) {
            print("🎙️ Playing first episode directly: \(firstEpisode.title ?? "Unknown")")
            
            // Play directly using the appropriate audio service based on feature flag
            await playRSSEpisode(url: audioUrl, title: firstEpisode.title ?? "Unknown", episode: firstEpisode)
            
            // Add remaining episodes to a "Live News" queue (separate from regular queue)
            // This way they auto-play after the first one without mixing with articles
            for (episode, _) in episodesToPlay.dropFirst() {
                queueService.addRSSEpisode(episode, isLiveNews: true)
            }
        } else {
            print("⚠️ No episodes to play")
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
    @ObservedObject private var audioService = BriefeedAudioService.shared
    @ObservedObject private var featureFlags = FeatureFlagManager.shared
    @ObservedObject private var queueService = QueueService.shared
    @ObservedObject private var stateManager = ArticleStateManager.shared
    
    // Helper functions for audio service
    private func playRSSEpisode(_ episode: RSSEpisode) async {
        if let audioUrl = URL(string: episode.audioUrl) {
            await audioService.playRSSEpisode(episode)
        }
    }
    
    private func pausePlayback() {
        audioService.pause()
    }
    
    private func resumePlayback() {
        audioService.play()
    }
    
    private var latestEpisode: RSSEpisode? {
        (feed.episodes?.allObjects as? [RSSEpisode])?
            .sorted { $0.pubDate > $1.pubDate }
            .first
    }
    
    private var hasNewEpisode: Bool {
        guard let latest = latestEpisode else { return false }
        return !latest.isListened
    }
    
    private var isCurrentlyPlaying: Bool {
        guard let latest = latestEpisode else { return false }
        // Check if this episode is the current playing item
        if let currentItem = audioService.currentPlaybackItem {
            let isPlayingThisEpisode = currentItem.audioUrl?.absoluteString == latest.audioUrl
            return isPlayingThisEpisode && (audioService.state.value == .playing || audioService.state.value == .loading)
        }
        return false
    }
    
    private var isInQueue: Bool {
        guard let latest = latestEpisode else { return false }
        return queueService.enhancedQueue.contains { item in
            item.audioUrl?.absoluteString == latest.audioUrl
        }
    }
    
    private var episodeTimeString: String? {
        guard let latest = latestEpisode else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: latest.pubDate)
    }
    
    private var lastUpdateTimeString: String? {
        guard let lastUpdate = feed.lastFetchDate else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.locale = Locale(identifier: "en_US")
        return "Updated \(formatter.string(from: lastUpdate))"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Inline Play/Pause Button
            if hasNewEpisode || isCurrentlyPlaying {
                Button {
                    let isPlaying = audioService.state.value == .playing
                    
                    if isCurrentlyPlaying && isPlaying {
                        pausePlayback()
                    } else if isCurrentlyPlaying && !isPlaying {
                        resumePlayback()
                    } else if let latest = latestEpisode {
                        Task {
                            await playRSSEpisode(latest)
                        }
                    }
                } label: {
                    let isPlaying = audioService.state.value == .playing
                    Image(systemName: isCurrentlyPlaying && isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.briefeedRed)
                }
                .buttonStyle(.plain)
            }
            
            // Feed Info wrapped in Button for tap action
            Button(action: onTap) {
                
                // Feed Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(feed.displayName)
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
                        Text(latest.title)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 8) {
                        if hasNewEpisode {
                            Image(systemName: "sparkle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        
                        if let timeString = episodeTimeString {
                            Text(timeString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if let updateString = lastUpdateTimeString {
                            Text(updateString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Status indicators
                if isCurrentlyPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 16))
                        .foregroundColor(.briefeedRed)
                        .symbolEffect(.bounce, options: .repeat(.continuous))
                } else if isInQueue {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        // Force refresh when audio state changes
        .onReceive(audioService.$currentPlaybackItem) { _ in
            // Triggers view update
        }
        .onReceive(audioService.$isPlaying) { _ in
            // Triggers view update when playing state changes
        }
    }
}

// MARK: - Add RSS Feed View
private struct AddRSSFeedView: View {
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
            .sorted { $0.pubDate > $1.pubDate }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Feed Info
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(feed.displayName)
                            .font(.headline)
                        
                        // RSS feeds don't have descriptions in our model
                        // if let description = feed.feedDescription {
                        //     Text(description)
                        //         .font(.subheadline)
                        //         .foregroundColor(.secondary)
                        // }
                        
                        // Feed URL is not optional
                        let url = feed.url
                        Link(url, destination: URL(string: url)!)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Feed Information")
                }
                
                // Episodes
                Section {
                    ForEach(episodes.prefix(20)) { episode in
                        EpisodeRow(episode: episode) {
                            queueService.addRSSEpisode(episode)
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
                Text(episode.title)
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
                if episode.pubDate != Date.distantPast {
                    Text(episode.pubDate.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if episode.duration > 0 {
                    Text("• \(formatDuration(episode.duration))")
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