//
//  ArticleRowView.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ArticleRowView: View {
    let article: Article
    let onTap: () -> Void
    let onSave: () -> Void

    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var audioPlayerViewModel: AudioPlayerViewModelV2
    @State private var waveformPhase: CGFloat = 0
    @State private var swipeOffset: CGFloat = 0
    @State private var activeSwipeTier: SwipeActionTier?
    @State private var hapticSwipeTier: SwipeActionTier?

    private var isArticlePlaying: Bool { appViewModel.isArticlePlaying(article) }
    private var isArticleQueued: Bool { appViewModel.isArticleQueued(article) }
    private var queuePosition: Int? { appViewModel.queuePosition(for: article) }

    var body: some View {
        ZStack(alignment: .leading) {
            progressiveSwipeBackground

            articleContent
                .offset(x: swipeOffset)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(progressiveSwipeGesture)
        .accessibilityAction(named: "Save") {
            Task { @MainActor in
                await performSwipeAction(.save)
            }
        }
        .accessibilityAction(named: "Play Next") {
            Task { @MainActor in
                await performSwipeAction(.playNext)
            }
        }
        .accessibilityAction(named: "Play Now") {
            Task { @MainActor in
                await performSwipeAction(.playNow)
            }
        }
        .accessibilityAction(named: "Queue") {
            Task { @MainActor in
                await audioPlayerViewModel.addToQueue(article)
            }
        }
        .opacity(appViewModel.isArticleArchived(article) ? 0.5 : 1.0)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                if appViewModel.isArticleArchived(article) {
                    appViewModel.unarchiveArticle(article)
                } else {
                    appViewModel.archiveArticle(article)
                }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appViewModel.isArticleArchived(article))
    }

    // MARK: - Views

    private var progressiveSwipeBackground: some View {
        let previewTier = activeSwipeTier ?? (swipeOffset > SwipeMetrics.previewThreshold ? SwipeActionTier.save : nil)
        let tier = previewTier ?? .save
        let progress = min(1, max(0, swipeOffset / SwipeMetrics.saveThreshold))

        return HStack(spacing: 10) {
            Image(systemName: tier.systemImage)
                .font(.system(size: 18, weight: .bold))

            Text(tier.title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.leading, Constants.UI.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(tier.color.opacity(swipeOffset > 0 ? 0.92 : 0))
        .opacity(previewTier == nil ? 0 : progress)
    }

    private var articleContent: some View {
        Button(action: {
            onTap()
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

                        // Domain
                        if let url = article.url, let domain = url.extractedDomain {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.briefeedSecondaryLabel)

                            Text(domain)
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
                        if isArticlePlaying {
                            HStack(spacing: 4) {
                                if audioPlayerViewModel.isPlaying {
                                    WaveformAnimationView(phase: $waveformPhase)
                                        .frame(width: 16, height: 12)
                                        .onAppear {
                                            startWaveformAnimation()
                                        }
                                } else {
                                    Image(systemName: "pause.fill")
                                        .font(.caption2)
                                        .foregroundColor(.briefeedRed)
                                        .onAppear {
                                            waveformPhase = 0
                                        }
                                }
                                Text("Playing")
                                    .font(.caption2)
                                    .foregroundColor(.briefeedRed)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }

                        if !article.isRead && !isArticlePlaying {
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

                        if isArticleQueued && !isArticlePlaying {
                            if let position = queuePosition {
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

                        if appViewModel.isArticleArchived(article) {
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
                    .animation(.easeInOut(duration: 0.2), value: isArticlePlaying)
                    .animation(.easeInOut(duration: 0.2), value: isArticleQueued)
                }

                Spacer()
            }
            .padding(.horizontal, Constants.UI.padding)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(AccessibilityID.ArticleRow.row(article.id?.uuidString ?? "unknown"))
    }

    private var progressiveSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                let horizontalDrag = value.translation.width
                let verticalDrag = abs(value.translation.height)

                guard horizontalDrag > 0, horizontalDrag > verticalDrag else {
                    return
                }

                swipeOffset = resistedOffset(for: horizontalDrag)
                let tier = swipeTier(for: horizontalDrag)

                if tier != activeSwipeTier {
                    activeSwipeTier = tier
                    if tier == nil {
                        hapticSwipeTier = nil
                    }
                    if let tier, hapticSwipeTier != tier {
                        fireThresholdHaptic(for: tier)
                        hapticSwipeTier = tier
                    }
                }
            }
            .onEnded { value in
                let horizontalDrag = max(0, value.translation.width)
                let tier = swipeTier(for: horizontalDrag)

                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    swipeOffset = 0
                    activeSwipeTier = nil
                    hapticSwipeTier = nil
                }

                if let tier {
                    Task { @MainActor in
                        await performSwipeAction(tier)
                    }
                }
            }
    }

    private func resistedOffset(for drag: CGFloat) -> CGFloat {
        guard drag > SwipeMetrics.playNowThreshold else {
            return drag
        }

        let overflow = drag - SwipeMetrics.playNowThreshold
        return SwipeMetrics.playNowThreshold + min(overflow * 0.28, SwipeMetrics.elasticOverflow)
    }

    private func swipeTier(for drag: CGFloat) -> SwipeActionTier? {
        if drag >= SwipeMetrics.playNowThreshold {
            return .playNow
        } else if drag >= SwipeMetrics.playNextThreshold {
            return .playNext
        } else if drag >= SwipeMetrics.saveThreshold {
            return .save
        } else {
            return nil
        }
    }

    @MainActor
    private func performSwipeAction(_ tier: SwipeActionTier) async {
        saveArticleIfNeeded()

        switch tier {
        case .save:
            break
        case .playNext:
            await audioPlayerViewModel.addToQueue(article, playNext: true)
        case .playNow:
            await audioPlayerViewModel.play(article: article)
        }
    }

    @MainActor
    private func saveArticleIfNeeded() {
        guard !article.isSaved else {
            return
        }

        article.isSaved = true
        article.savedAt = Date()

        guard let context = article.managedObjectContext, context.hasChanges else {
            return
        }

        do {
            try context.save()
        } catch {
            print("[ArticleRowView] Failed to save article from swipe action: \(error)")
        }
    }

    private func fireThresholdHaptic(for tier: SwipeActionTier) {
        #if os(iOS)
        let style: UIImpactFeedbackGenerator.FeedbackStyle

        switch tier {
        case .save:
            style = .light
        case .playNext:
            style = .medium
        case .playNow:
            style = .heavy
        }

        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }

    private func startWaveformAnimation() {
        guard isArticlePlaying && audioPlayerViewModel.isPlaying else { return }

        withAnimation(.linear(duration: 0.5).repeatForever(autoreverses: false)) {
            waveformPhase = 1.0
        }
    }

    private enum SwipeMetrics {
        static let previewThreshold: CGFloat = 24
        static let saveThreshold: CGFloat = 80
        static let playNextThreshold: CGFloat = 150
        static let playNowThreshold: CGFloat = 220
        static let elasticOverflow: CGFloat = 44
    }

    private enum SwipeActionTier {
        case save
        case playNext
        case playNow

        var title: String {
            switch self {
            case .save:
                return "Save"
            case .playNext:
                return "Play Next"
            case .playNow:
                return "Play Now"
            }
        }

        var systemImage: String {
            switch self {
            case .save:
                return "bookmark.fill"
            case .playNext:
                return "list.number"
            case .playNow:
                return "play.fill"
            }
        }

        var color: Color {
            switch self {
            case .save:
                return Color.green.opacity(0.55)
            case .playNext:
                return Color.green.opacity(0.72)
            case .playNow:
                return Color.green
            }
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
            onSave: { print("Saved") }
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
            onSave: { print("Saved") }
        )
    }
    .background(Color.briefeedBackground)
    .environmentObject(AudioPlayerViewModelV2())
}
