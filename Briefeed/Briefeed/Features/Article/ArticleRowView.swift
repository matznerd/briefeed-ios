//
//  ArticleRowView.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import SwiftUI

struct ArticleRowView: View {
    let article: Article
    let onTap: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    
    @StateObject private var stateManager = ArticleStateManager.shared
    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    @State private var hasTriggeredHaptic = false
    @State private var isDragging = false
    @State private var waveformPhase: CGFloat = 0
    @State private var showActionButtons = false
    @State private var actionButtonsTimer: Timer?
    @State private var timeRemaining = 5
    
    private let swipeThreshold: CGFloat = 100
    private let actionIconSize: CGFloat = 24
    
    // Computed properties for swipe state
    private var swipeProgress: CGFloat {
        abs(offset) / swipeThreshold
    }
    
    private var isSwipingRight: Bool {
        offset > 0
    }
    
    private var isSwipingLeft: Bool {
        offset < 0
    }
    
    private var hasReachedThreshold: Bool {
        abs(offset) >= swipeThreshold
    }
    
    var body: some View {
        ZStack {
            // Background actions
            HStack(spacing: 0) {
                // Save action (left side - revealed when swiping right)
                saveActionBackground
                
                Spacer()
                
                // Archive action (right side - revealed when swiping left)
                archiveActionBackground
            }
            
            // Main content
            articleContent
                .background(Color.briefeedBackground)
                .offset(x: offset)
                .opacity(stateManager.isArchived(article) ? 0.5 : 1.0)
                .simultaneousGesture(swipeGesture)
                .allowsHitTesting(!isDragging) // Disable tap while dragging
            
            // Action buttons overlay (Play Now / Play Next)
            if showActionButtons {
                actionButtonsOverlay
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0), value: offset)
        .animation(.easeInOut(duration: 0.2), value: stateManager.isArchived(article))
        .animation(.easeInOut(duration: 0.2), value: showActionButtons)
        .onAppear {
            startWaveformAnimation()
        }
        .onDisappear {
            actionButtonsTimer?.invalidate()
        }
    }
    
    // MARK: - Views
    
    private var articleContent: some View {
        Button(action: {
            // Only trigger tap if we're not swiping
            if !isDragging && offset == 0 {
                onTap()
            }
        }) {
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail
                if let thumbnailURL = article.thumbnail, !thumbnailURL.isEmpty, thumbnailURL != "self", thumbnailURL != "default" {
                    AsyncImage(url: URL(string: thumbnailURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.briefeedSecondaryBackground)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.briefeedSecondaryLabel)
                            )
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // Article info
                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    Text(article.title ?? "Untitled")
                        .font(.headline)
                        .foregroundColor(article.isRead ? .briefeedSecondaryLabel : .briefeedLabel)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    
                    // Metadata
                    HStack(spacing: 8) {
                        // Subreddit
                        Text(article.subreddit ?? "")
                            .font(.caption)
                            .foregroundColor(.briefeedSecondaryLabel)
                        
                        // Author
                        if let author = article.author {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.briefeedSecondaryLabel)
                            
                            Text("u/\(author)")
                                .font(.caption)
                                .foregroundColor(.briefeedSecondaryLabel)
                        }
                        
                        // Time
                        if let createdAt = article.createdAt {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.briefeedSecondaryLabel)
                            
                            Text(createdAt.timeAgoDisplay)
                                .font(.caption)
                                .foregroundColor(.briefeedSecondaryLabel)
                        }
                    }
                    
                    // Indicators
                    HStack(spacing: 12) {
                        // Playing indicator
                        if stateManager.isPlaying(article) {
                            HStack(spacing: 4) {
                                if stateManager.isPlaying(article, withState: .playing) {
                                    WaveformAnimationView(phase: $waveformPhase)
                                        .frame(width: 16, height: 12)
                                } else if stateManager.isPlaying(article, withState: .paused) {
                                    Image(systemName: "pause.fill")
                                        .font(.caption2)
                                        .foregroundColor(.briefeedRed)
                                } else if stateManager.isPlaying(article, withState: .loading) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                }
                                Text("Playing")
                                    .font(.caption2)
                                    .foregroundColor(.briefeedRed)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        if !article.isRead && !stateManager.isPlaying(article) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.briefeedRed)
                                    .frame(width: 8, height: 8)
                                Text("Unread")
                                    .font(.caption2)
                                    .foregroundColor(.briefeedRed)
                            }
                        }
                        
                        if article.isSaved {
                            HStack(spacing: 4) {
                                Image(systemName: "bookmark.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text("Saved")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        if stateManager.isQueued(article) && !stateManager.isPlaying(article) {
                            if let position = stateManager.queuePosition(for: article) {
                                HStack(spacing: 4) {
                                    Image(systemName: "list.number")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                    Text("Queue #\(position + 1)")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        
                        if stateManager.isArchived(article) {
                            HStack(spacing: 4) {
                                Image(systemName: "archivebox.fill")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Text("Archived")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: stateManager.isPlaying(article))
                    .animation(.easeInOut(duration: 0.2), value: stateManager.isQueued(article))
                }
                
                Spacer()
            }
            .padding(.horizontal, Constants.UI.padding)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var saveActionBackground: some View {
        ZStack {
            // Green background that expands as you swipe
            Color.green
                .opacity(isSwipingRight ? min(swipeProgress, 1.0) : 0)
            
            HStack {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: actionIconSize))
                        .foregroundColor(.white)
                        .scaleEffect(isSwipingRight ? min(1.0, swipeProgress) : 0.5)
                        .opacity(isSwipingRight ? min(1.0, swipeProgress * 2) : 0)
                    
                    if hasReachedThreshold && isSwipingRight {
                        Text("Save")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.leading, 20)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: swipeProgress)
                
                Spacer()
            }
        }
        .frame(width: abs(offset))
        .clipped()
    }
    
    private var archiveActionBackground: some View {
        ZStack {
            // Red background that expands as you swipe
            Color.red
                .opacity(isSwipingLeft ? min(swipeProgress, 1.0) : 0)
            
            HStack {
                Spacer()
                
                VStack(spacing: 8) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: actionIconSize))
                        .foregroundColor(.white)
                        .scaleEffect(isSwipingLeft ? min(1.0, swipeProgress) : 0.5)
                        .opacity(isSwipingLeft ? min(1.0, swipeProgress * 2) : 0)
                    
                    if hasReachedThreshold && isSwipingLeft {
                        Text("Archive")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.trailing, 20)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: swipeProgress)
            }
        }
        .frame(width: abs(offset))
        .clipped()
    }
    
    // MARK: - Gestures
    
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onChanged { value in
                // Only respond to horizontal swipes
                let horizontalAmount = value.translation.width
                let verticalAmount = value.translation.height
                
                // Require a more horizontal gesture to avoid interfering with scroll
                if abs(horizontalAmount) > abs(verticalAmount) * 1.5 && abs(horizontalAmount) > 30 {
                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 1.0)) {
                        isDragging = true
                        
                        // Apply elastic resistance when swiping beyond threshold
                        if abs(horizontalAmount) > swipeThreshold {
                            let excess = abs(horizontalAmount) - swipeThreshold
                            let resistance = 1 - min(excess / 200, 0.8)
                            offset = horizontalAmount > 0 
                                ? swipeThreshold + (excess * resistance)
                                : -swipeThreshold - (excess * resistance)
                        } else {
                            offset = horizontalAmount
                        }
                        
                        // Haptic feedback when reaching threshold
                        if hasReachedThreshold && !hasTriggeredHaptic {
                            HapticManager.shared.swipeThresholdReached()
                            hasTriggeredHaptic = true
                        } else if !hasReachedThreshold && hasTriggeredHaptic {
                            hasTriggeredHaptic = false
                        }
                    }
                }
            }
            .onEnded { value in
                // Only process if we were dragging horizontally
                if isDragging {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isDragging = false
                        
                        // Determine action based on final offset and velocity
                        let velocity = value.predictedEndLocation.x - value.location.x
                        let shouldTriggerAction = hasReachedThreshold || abs(velocity) > 200
                        
                        if shouldTriggerAction {
                            if offset > 0 {
                                // Save action
                                performSaveAction()
                            } else {
                                // Archive action
                                performArchiveAction()
                            }
                        }
                        
                        // Reset position
                        resetSwipe()
                    }
                } else {
                    // Reset if we weren't dragging
                    resetSwipe()
                }
            }
    }
    
    private func resetSwipe() {
        offset = 0
        isSwiped = false
        hasTriggeredHaptic = false
    }
    
    private func performSaveAction() {
        // Haptic feedback
        HapticManager.shared.saveAction()
        
        // Check if article is being saved (not already saved)
        let isBeingSaved = !article.isSaved
        
        // Toggle saved state
        onSave()
        
        // Add to audio queue if article is being saved
        if isBeingSaved {
            Task { @MainActor in
                await QueueServiceV2.shared.addArticle(article)
            }
        }
        
        // Don't show action buttons - swipe should just add to queue
        // Users can tap the article to open it and see play options there
    }
    
    private func performArchiveAction() {
        // Haptic feedback
        HapticManager.shared.archiveAction()
        
        // Archive the article
        Task { @MainActor in
            stateManager.toggleArchiveState(for: article)
        }
    }
    
    private func startWaveformAnimation() {
        guard stateManager.isPlaying(article, withState: .playing) else { return }
        
        withAnimation(.linear(duration: 0.5).repeatForever(autoreverses: false)) {
            waveformPhase = 1.0
        }
    }
    
    // MARK: - Action Buttons Overlay
    
    private var actionButtonsOverlay: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.6)
                .allowsHitTesting(false)
            
            VStack(spacing: 20) {
                // Buttons
                HStack(spacing: 20) {
                    // Play Now button
                    Button(action: handlePlayNow) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18))
                            Text("Play Now")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(25)
                    }
                    
                    // Play Next button
                    Button(action: handlePlayNext) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18))
                            Text("Play Next")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .cornerRadius(25)
                    }
                }
                
                // Timer
                Text("\(timeRemaining)s")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .transition(.opacity)
    }
    
    private func handlePlayNow() {
        showActionButtons = false
        actionButtonsTimer?.invalidate()
        
        Task { @MainActor in
            do {
                await BriefeedAudioService.shared.playNow(article)
            } catch {
                print("Failed to play article: \(error)")
            }
        }
    }
    
    private func handlePlayNext() {
        showActionButtons = false
        actionButtonsTimer?.invalidate()
        
        Task { @MainActor in
            await BriefeedAudioService.shared.playAfterCurrent(article)
        }
    }
}

// MARK: - Waveform Animation View
struct WaveformAnimationView: View {
    @Binding var phase: CGFloat
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.briefeedRed)
                    .frame(width: 3, height: waveHeight(for: index))
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                        value: phase
                    )
            }
        }
    }
    
    private func waveHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 4
        let maxHeight: CGFloat = 12
        let heightVariation = sin(phase * .pi * 2 + Double(index) * .pi / 3)
        return baseHeight + (maxHeight - baseHeight) * CGFloat((heightVariation + 1) / 2)
    }
}

#Preview {
    VStack(spacing: 0) {
        ArticleRowView(
            article: {
                let context = PersistenceController.preview.container.viewContext
                let article = Article(context: context)
                article.id = UUID()
                article.title = "SwiftUI 5.0 introduces new navigation APIs and performance improvements"
                article.author = "apple_developer"
                article.subreddit = "iOSProgramming"
                article.createdAt = Date().addingTimeInterval(-3600)
                article.isRead = false
                article.isSaved = true
                article.isArchived = false
                article.thumbnail = "https://via.placeholder.com/150"
                return article
            }(),
            onTap: { print("Tapped") },
            onSave: { print("Saved") },
            onDelete: { print("Deleted") }
        )
        
        Divider()
        
        ArticleRowView(
            article: {
                let context = PersistenceController.preview.container.viewContext
                let article = Article(context: context)
                article.id = UUID()
                article.title = "Understanding async/await in Swift"
                article.author = "swiftlang"
                article.subreddit = "swift"
                article.createdAt = Date().addingTimeInterval(-7200)
                article.isRead = true
                article.isSaved = false
                article.isArchived = true
                return article
            }(),
            onTap: { print("Tapped") },
            onSave: { print("Saved") },
            onDelete: { print("Deleted") }
        )
    }
    .background(Color.briefeedBackground)
}