//
//  BriefView+Filtering.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import SwiftUI

// MARK: - Brief View Filter Extension
extension BriefView {
    
    /// Create a filtered version of BriefView with RSS support
    static func createFilteredBriefView() -> some View {
        FilteredBriefView()
    }
}

// MARK: - Filtered Brief View
struct FilteredBriefView: View {
    @StateObject private var viewModel = BriefViewModel()
    @StateObject private var audioService = AudioService.shared
    @StateObject private var queueService = QueueService.shared
    @State private var editMode = EditMode.inactive
    @State private var showingClearQueueAlert = false
    @State private var currentFilter: QueueFilter = .all
    
    // Load saved filter preference
    init() {
        let savedFilter = UserDefaultsManager.shared.defaultBriefFilter
        _currentFilter = State(initialValue: QueueFilter(rawValue: savedFilter) ?? .all)
    }
    
    var filteredQueue: [EnhancedQueueItem] {
        queueService.getFilteredQueue(filter: currentFilter)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter Picker
                filterPicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                
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
                    queueService.loadEnhancedQueue()
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
        .onChange(of: currentFilter) { newValue in
            UserDefaultsManager.shared.defaultBriefFilter = newValue.rawValue
        }
    }
    
    private var enhancedQueueListView: some View {
        List {
            ForEach(filteredQueue, id: \.id) { item in
                EnhancedQueueRow(item: item)
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
        queueService.removeFromEnhancedQueue { $0.id == item.id }
        queueService.saveEnhancedQueue()
        
        // Update audio service if needed
        if let articleID = item.articleID,
           let article = viewModel.queuedArticles.first(where: { $0.id == articleID }) {
            viewModel.removeFromQueue(article)
        }
    }
    
    private func saveItem(_ item: EnhancedQueueItem) {
        // Remove expiration for saved items
        if let index = queueService.enhancedQueue.firstIndex(where: { $0.id == item.id }) {
            // Create a new item with nil expiration since EnhancedQueueItem has let properties
            let currentItem = queueService.enhancedQueue[index]
            let newItem = EnhancedQueueItem(
                id: currentItem.id,
                title: currentItem.title,
                source: currentItem.source,
                addedDate: currentItem.addedDate,
                expiresAt: nil,
                articleID: currentItem.articleID,
                audioUrl: currentItem.audioUrl,
                duration: currentItem.duration,
                isListened: currentItem.isListened,
                lastPosition: currentItem.lastPosition
            )
            queueService.updateEnhancedQueue(
                queueService.enhancedQueue.enumerated().map { i, item in
                    i == index ? newItem : item
                }
            )
            queueService.saveEnhancedQueue()
        }
    }
    
    private func clearQueue() {
        queueService.updateEnhancedQueue([])
        queueService.saveEnhancedQueue()
        viewModel.clearQueue()
    }
}

// MARK: - Enhanced Queue Row
struct EnhancedQueueRow: View {
    let item: EnhancedQueueItem
    @StateObject private var audioService = AudioService.shared
    
    private var isCurrentlyPlaying: Bool {
        // Check if this item is currently playing
        if let articleID = item.articleID {
            return audioService.currentArticle?.id == articleID
        } else if let audioUrl = item.audioUrl {
            return audioService.isPlayingRSS && 
                   audioService.currentArticle?.url == audioUrl.absoluteString
        }
        return false
    }
    
    var body: some View {
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
                
                HStack(spacing: 8) {
                    Text(item.source.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
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
            
            Spacer()
            
            // Playing Indicator
            if isCurrentlyPlaying {
                Image(systemName: "waveform")
                    .font(.system(size: 20))
                    .foregroundColor(.briefeedRed)
                    .symbolEffect(.variableColor.iterative)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .opacity(item.isListened ? 0.6 : 1.0)
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
}