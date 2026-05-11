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

    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var audioPlayerViewModel: AudioPlayerViewModelV2
    @State private var waveformPhase: CGFloat = 0

    private var isArticlePlaying: Bool { appViewModel.isArticlePlaying(article) }
    private var isArticleQueued: Bool { appViewModel.isArticleQueued(article) }
    private var queuePosition: Int? { appViewModel.queuePosition(for: article) }

    var body: some View {
        articleContent
            .opacity(appViewModel.isArticleArchived(article) ? 0.5 : 1.0)
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    Task { @MainActor in
                        await audioPlayerViewModel.play(article: article)
                    }
                } label: {
                    Label("Play Now", systemImage: "play.fill")
                }
                .accessibilityIdentifier(AccessibilityID.ArticleRow.playNow)
                .tint(.blue)

                Button {
                    Task { @MainActor in
                        await audioPlayerViewModel.addToQueue(article, playNext: true)
                    }
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .accessibilityIdentifier(AccessibilityID.ArticleRow.playNext)
                .tint(.orange)

                Button {
                    Task { @MainActor in
                        await audioPlayerViewModel.addToQueue(article)
                    }
                } label: {
                    Label("Queue", systemImage: "plus")
                }
                .accessibilityIdentifier(AccessibilityID.ArticleRow.queue)
                .tint(.green)
            }
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

    private func startWaveformAnimation() {
        guard isArticlePlaying && audioPlayerViewModel.isPlaying else { return }

        withAnimation(.linear(duration: 0.5).repeatForever(autoreverses: false)) {
            waveformPhase = 1.0
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
