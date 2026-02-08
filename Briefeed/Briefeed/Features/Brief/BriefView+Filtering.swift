//
//  BriefView+Filtering.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import SwiftUI
import CoreData

// BriefView extension removed - using FilteredBriefView directly

// MARK: - Filtered Brief View
struct FilteredBriefView: View {
    @StateObject private var viewModel = BriefViewModel()
    @EnvironmentObject var audioPlayerViewModel: AudioPlayerViewModelV2
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var editMode = EditMode.inactive
    @State private var showingClearQueueAlert = false
    @State private var currentFilter: QueueFilter = .all
    @State private var selectedArticle: Article?
    
    // Load saved filter preference
    init() {
        let savedFilter = UserDefaultsManager.shared.defaultBriefFilter
        _currentFilter = State(initialValue: QueueFilter(rawValue: savedFilter) ?? .all)
    }
    
    var filteredQueue: [EnhancedQueueItem] {
        // Convert UnifiedQueueItems to EnhancedQueueItems and apply filter
        audioPlayerViewModel.queueItems.toEnhancedQueueItems().filter { item in
            switch currentFilter {
            case .all:
                return true
            case .articles:
                return item.articleID != nil
            case .liveNews:
                return item.audioUrl != nil && item.articleID == nil
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter Picker
                filterPicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                
                // Play All Button when queue has items
                if !filteredQueue.isEmpty && !audioPlayerViewModel.isPlaying {
                    Button {
                        Task {
                            let articles = viewModel.queuedArticles
                            if !articles.isEmpty {
                                await audioPlayerViewModel.playQueue(articles: articles)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play All (\(filteredQueue.count) items)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .accessibilityIdentifier(AccessibilityID.Brief.playAll)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                // Queue Content
                ZStack {
                    if viewModel.isLoading && filteredQueue.isEmpty {
                        loadingView
                    } else if filteredQueue.isEmpty && !viewModel.isLoading {
                        emptyStateView
                    } else {
                        enhancedQueueListView
                    }
                }
            }
            .onAppear {
                Task {
                    await viewModel.loadQueuedArticles()
                    // Sync saved articles to queue without starting playback
                    if !viewModel.queuedArticles.isEmpty && audioPlayerViewModel.queueItems.isEmpty {
                        await audioPlayerViewModel.syncToQueue(articles: viewModel.queuedArticles)
                    }
                }
            }
            .navigationTitle("Brief")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                toolbarContent
            }
            .environment(\.editMode, $editMode)
            .refreshable {
                await refresh()
            }
            .alert("Clear Queue", isPresented: $showingClearQueueAlert) {
                clearQueueAlert
            }
            .navigationDestination(item: $selectedArticle) { article in
                ArticleView(article: article)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var filterPicker: some View {
        Picker("Filter", selection: $currentFilter) {
            ForEach(QueueFilter.allCases, id: \.self) { filter in
                Label(filter.displayName, systemImage: filter.icon)
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(AccessibilityID.Brief.filterPicker)
        .onChange(of: currentFilter) { newValue in
            UserDefaultsManager.shared.defaultBriefFilter = newValue.rawValue
        }
    }
    
    private var enhancedQueueListView: some View {
        List {
            ForEach(filteredQueue, id: \.id) { item in
                EnhancedQueueRow(item: item) {
                    // Navigate to article detail when content is tapped
                    navigateToArticle(item: item)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    swipeActions(for: item)
                }
            }
            .onDelete { indexSet in
                deleteItems(at: indexSet)
            }
            .onMove { source, destination in
                moveItems(from: source, to: destination)
            }
        }
        .listStyle(.plain)
    }

    private func navigateToArticle(item: EnhancedQueueItem) {
        guard let articleID = item.articleID else { return }

        let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", articleID as CVarArg)
        fetchRequest.fetchLimit = 1

        if let article = try? PersistenceController.shared.container.viewContext.fetch(fetchRequest).first {
            selectedArticle = article
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading queue...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.briefeedBackground)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: currentFilter == .liveNews ? "dot.radiowaves.left.and.right" : "tray")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text(emptyStateTitle)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(emptyStateMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.briefeedBackground)
    }
    
    private var emptyStateTitle: String {
        switch currentFilter {
        case .all:
            return "Your Brief is Empty"
        case .liveNews:
            return "No Live News"
        case .articles:
            return "No Articles"
        }
    }
    
    private var emptyStateMessage: String {
        switch currentFilter {
        case .all:
            return "Add articles from your feed or wait for live news to auto-populate"
        case .liveNews:
            return "RSS episodes will appear here when available"
        case .articles:
            return "Swipe articles in your feed to add them here"
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if !filteredQueue.isEmpty {
                Menu {
                    Button {
                        Task {
                            // Play all items in the brief
                            let articles = viewModel.queuedArticles
                            if !articles.isEmpty {
                                await audioPlayerViewModel.playQueue(articles: articles)
                            }
                        }
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        showingClearQueueAlert = true
                    } label: {
                        Label("Clear Queue", systemImage: "trash")
                    }
                    .accessibilityIdentifier(AccessibilityID.Brief.clearQueue)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        
        ToolbarItem(placement: .navigationBarLeading) {
            if !filteredQueue.isEmpty {
                EditButton()
            }
        }
    }
    
    // MARK: - Actions
    
    private func swipeActions(for item: EnhancedQueueItem) -> some View {
        Group {
            Button(role: .destructive) {
                removeItem(item)
            } label: {
                Label("Remove", systemImage: "trash")
            }
            
            if item.source.isLiveNews && item.remainingTime != nil {
                Button {
                    saveItem(item)
                } label: {
                    Label("Keep", systemImage: "bookmark")
                }
                .tint(.blue)
            }
        }
    }
    
    private var clearQueueAlert: some View {
        Group {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                clearQueue()
            }
        }
    }
    
    private func refresh() async {
        await viewModel.refresh()
        
        // Refresh RSS feeds if viewing live news
        if currentFilter == .liveNews || currentFilter == .all {
            await RSSAudioService.shared.refreshAllFeeds()
        }
    }
    
    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = filteredQueue[index]
            removeItem(item)
        }
    }
    
    private func moveItems(from source: IndexSet, to destination: Int) {
        // TODO: Implement reordering in enhanced queue
    }
    
    private func removeItem(_ item: EnhancedQueueItem) {
        // Find the index of the item in the queue by matching IDs
        if let index = audioPlayerViewModel.queueItems.firstIndex(where: { 
            UUID(uuidString: $0.id) == item.id ||
            $0.article?.id == item.articleID ||
            $0.audioURL?.absoluteString == item.audioUrl?.absoluteString
        }) {
            Task {
                await audioPlayerViewModel.removeFromQueue(at: index)
            }
        }
        
        // Update view model if needed
        if let articleID = item.articleID,
           let article = viewModel.queuedArticles.first(where: { $0.id == articleID }) {
            viewModel.removeFromQueue(article)
        }
    }
    
    private func saveItem(_ item: EnhancedQueueItem) {
        // Remove expiration for saved items
        if let index = audioPlayerViewModel.queueItems.firstIndex(where: { 
            UUID(uuidString: $0.id) == item.id ||
            $0.article?.id == item.articleID ||
            $0.audioURL?.absoluteString == item.audioUrl?.absoluteString
        }) {
            // TODO: Add method to update expiration in AudioPlayerViewModelV2
            // For now, items don't expire in the new system
            print("Saving item at index \(index)")
        }
    }
    
    private func clearQueue() {
        Task {
            await audioPlayerViewModel.clearQueue()
            viewModel.clearQueue()
        }
    }
}

// MARK: - Enhanced Queue Row
struct EnhancedQueueRow: View {
    let item: EnhancedQueueItem
    var onTapContent: (() -> Void)?
    @EnvironmentObject var audioPlayerViewModel: AudioPlayerViewModelV2
    
    private var isCurrentlyPlaying: Bool {
        // Check if this item is currently playing
        guard audioPlayerViewModel.currentQueueIndex >= 0,
              audioPlayerViewModel.currentQueueIndex < audioPlayerViewModel.queueItems.count else {
            return false
        }
        
        let currentItem = audioPlayerViewModel.queueItems[audioPlayerViewModel.currentQueueIndex]
        
        // Match by article ID or audio URL
        if let articleID = item.articleID {
            return currentItem.article?.id == articleID
        } else if let audioUrl = item.audioUrl {
            return currentItem.audioURL?.absoluteString == audioUrl.absoluteString
        }
        return false
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause Button with readiness state
            Button(action: item.hasFailed ? retryItem : playItem) {
                ZStack {
                    if item.hasFailed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.red)
                    } else if item.readiness == .generating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: isCurrentlyPlaying && audioPlayerViewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(item.readiness == .ready ? .briefeedRed : .secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            // Tappable content area for navigation
            HStack(spacing: 12) {
                // Source Icon
                Image(systemName: item.source.iconName)
                    .font(.system(size: 18))
                    .foregroundColor(item.source.isLiveNews ? .red : .briefeedRed)
                    .frame(width: 24)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundColor(item.hasFailed ? .red : .primary)

                    HStack(spacing: 8) {
                        if item.hasFailed {
                            Text("Failed")
                                .font(.caption)
                                .foregroundColor(.red)
                            if item.canRetry {
                                Text("• Tap to retry")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text(item.source.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if item.readiness == .generating {
                                Text("• Preparing...")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            } else if item.hasSummary && item.readiness == .ready {
                                Text("• Ready")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else if item.hasSummary && item.readiness == .pending {
                                Text("• Summary ready")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let duration = item.formattedDuration {
                                Text("• \(duration)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if item.source.isLiveNews, let remaining = item.remainingTime {
                                Text("• Expires in \(formatTimeRemaining(remaining))")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }

                Spacer()

                // Trailing: readiness + playing indicator
                HStack(spacing: 6) {
                    // Readiness badge
                    if item.hasFailed {
                        if item.canRetry {
                            Text("Retry")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange)
                                .cornerRadius(4)
                        } else {
                            Text("Skip")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .cornerRadius(4)
                        }
                    } else if isCurrentlyPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 20))
                            .foregroundColor(.briefeedRed)
                            .symbolEffect(.variableColor.iterative)
                    } else {
                        // Readiness indicator
                        Image(systemName: item.readiness.icon)
                            .font(.system(size: 14))
                            .foregroundColor(readinessColor)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let onTap = onTapContent {
                    onTap()
                } else {
                    // Fall back to play if no navigation handler
                    playItem()
                }
            }
        }
        .padding(.vertical, 8)
        .opacity(item.isListened ? 0.6 : 1.0)
        // Progress bar for currently playing item
        .overlay(alignment: .bottom) {
            if isCurrentlyPlaying && audioPlayerViewModel.duration > 0 {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.briefeedRed.opacity(0.6))
                        .frame(width: geometry.size.width * CGFloat(audioPlayerViewModel.progress), height: 2)
                }
                .frame(height: 2)
            }
        }
    }
    
    private var readinessColor: Color {
        switch item.readiness {
        case .pending: return .orange
        case .generating: return .blue
        case .ready: return .green
        case .failed: return .red
        }
    }

    private func formatTimeRemaining(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        if hours > 0 {
            return "\(hours)h"
        } else {
            let minutes = Int(interval) / 60
            return "\(minutes)m"
        }
    }
    
    private func playItem() {
        if item.hasFailed {
            retryItem()
            return
        }
        if isCurrentlyPlaying && audioPlayerViewModel.isPlaying {
            // Pause if currently playing
            audioPlayerViewModel.pause()
        } else if let audioUrl = item.audioUrl {
            // Play RSS episode
            Task {
                if let episode = fetchRSSEpisode(audioUrl: audioUrl) {
                    await audioPlayerViewModel.play(episode: episode)
                }
            }
        } else if let articleID = item.articleID {
            // Play article
            let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", articleID as CVarArg)
            if let article = try? PersistenceController.shared.container.viewContext.fetch(fetchRequest).first {
                Task {
                    await audioPlayerViewModel.play(article: article)
                }
            }
        }
    }

    private func retryItem() {
        // Reset item for retry in QueueCoordinator and trigger re-play
        QueueCoordinator.shared.resetItemForRetry(for: item.id)

        // Try to play the item again
        if let articleID = item.articleID {
            let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", articleID as CVarArg)
            if let article = try? PersistenceController.shared.container.viewContext.fetch(fetchRequest).first {
                Task {
                    await audioPlayerViewModel.play(article: article)
                }
            }
        } else if let audioUrl = item.audioUrl {
            Task {
                if let episode = fetchRSSEpisode(audioUrl: audioUrl) {
                    await audioPlayerViewModel.play(episode: episode)
                }
            }
        }
    }

    private func fetchRSSEpisode(audioUrl: URL) -> RSSEpisode? {
        let fetchRequest: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "audioUrl == %@", audioUrl.absoluteString)
        fetchRequest.fetchLimit = 1
        return try? PersistenceController.shared.container.viewContext.fetch(fetchRequest).first
    }
}