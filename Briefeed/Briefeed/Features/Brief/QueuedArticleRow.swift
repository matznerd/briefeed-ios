//
//  QueuedArticleRow.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import SwiftUI

struct QueuedArticleRow: View {
    let article: Article
    let queuePosition: Int
    let isCurrentlyPlaying: Bool
    let audioState: AudioPlayerState
    let isNextToPlay: Bool
    
    private var isPlaying: Bool {
        isCurrentlyPlaying && audioState == .playing
    }
    
    private var isPaused: Bool {
        isCurrentlyPlaying && audioState == .paused
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Queue position or waveform
            ZStack {
                if isCurrentlyPlaying {
                    WaveformMiniView(
                        isPlaying: isPlaying,
                        color: .accentColor
                    )
                    .frame(width: 25, height: 16)
                } else {
                    Text("\(queuePosition)")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.briefeedSecondaryLabel)
                        .frame(width: 25)
                }
            }
            .frame(width: 30)
            
            // Article info
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title ?? "Untitled")
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(isCurrentlyPlaying ? .accentColor : .briefeedLabel)
                
                HStack(spacing: 4) {
                    if let author = article.author {
                        Text(author)
                            .font(.caption)
                            .foregroundColor(.briefeedSecondaryLabel)
                    }
                    
                    if article.author != nil && article.subreddit != nil {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.briefeedSecondaryLabel)
                    }
                    
                    if let subreddit = article.subreddit {
                        Text("r/\(subreddit)")
                            .font(.caption)
                            .foregroundColor(.briefeedSecondaryLabel)
                    }
                }
                
                if isCurrentlyPlaying {
                    Text(isPaused ? "Paused" : "Now Playing")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(10)
                } else if isNextToPlay {
                    Text("Up Next")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(10)
                }
            }
            
            Spacer()
            
            // Drag handle for reordering
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16))
                .foregroundColor(.briefeedTertiaryLabel)
                .opacity(0.5)
        }
        .padding(.horizontal, Constants.UI.padding)
        .padding(.vertical, 12)
        .background(
            isCurrentlyPlaying ?
                Color.accentColor.opacity(0.05) :
                isNextToPlay ?
                    Color.orange.opacity(0.05) :
                    Color.briefeedBackground
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Preview
struct QueuedArticleRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            // Normal article
            QueuedArticleRow(
                article: createSampleArticle(title: "Understanding SwiftUI Layout System", author: "John Doe", subreddit: "SwiftUI"),
                queuePosition: 1,
                isCurrentlyPlaying: false,
                audioState: .idle,
                isNextToPlay: false
            )
            
            Divider()
            
            // Currently playing
            QueuedArticleRow(
                article: createSampleArticle(title: "The Future of AI in Mobile Development", author: "Jane Smith", subreddit: "iOSProgramming"),
                queuePosition: 2,
                isCurrentlyPlaying: true,
                audioState: .playing,
                isNextToPlay: false
            )
            
            Divider()
            
            // Currently paused
            QueuedArticleRow(
                article: createSampleArticle(title: "Building Efficient Core Data Models", author: "Tech Writer", subreddit: "swift"),
                queuePosition: 3,
                isCurrentlyPlaying: true,
                audioState: .paused,
                isNextToPlay: false
            )
        }
        .background(Color.briefeedBackground)
    }
    
    static func createSampleArticle(title: String, author: String?, subreddit: String?) -> Article {
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = title
        article.author = author
        article.subreddit = subreddit
        article.createdAt = Date()
        article.isSaved = true
        return article
    }
}