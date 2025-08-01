//
//  MiniAudioPlayer.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import SwiftUI
import Combine

struct MiniAudioPlayer: View {
    @ObservedObject private var audioService = AudioService.shared
    @ObservedObject private var stateManager = ArticleStateManager.shared
    @EnvironmentObject var userDefaultsManager: UserDefaultsManager
    @State private var showExpandedPlayer = false
    
    private let playerHeight: CGFloat = 72
    private let progressBarHeight: CGFloat = 3
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: progressBarHeight)
                    
                    // Progress
                    Rectangle()
                        .fill(Color.briefeedRed)
                        .frame(width: geometry.size.width * CGFloat(audioService.progress.value), height: progressBarHeight)
                        .animation(.linear(duration: 0.1), value: audioService.progress.value)
                }
            }
            .frame(height: progressBarHeight)
            
            // Player content
            HStack(spacing: 0) {
                // Article info (left side)
                VStack(alignment: .leading, spacing: 2) {
                    if let playbackItem = audioService.currentPlaybackItem {
                        Text(playbackItem.title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 4) {
                            if playbackItem.isRSS {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Text(playbackItem.source)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .lineLimit(1)
                    } else if let article = audioService.currentArticle {
                        // Fallback for legacy article playback
                        Text(article.title ?? "Untitled")
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 4) {
                            if let subreddit = article.subreddit {
                                Text("r/\(subreddit)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else if let author = article.author, !author.isEmpty {
                                Text(author)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .lineLimit(1)
                    } else {
                        Text("No story playing")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text("Tap an article to play")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                
                // Center controls
                HStack(spacing: 24) {
                    // Skip backward button
                    Button(action: { audioService.skipBackward(seconds: 15) }) {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 22))
                            .foregroundColor((audioService.currentArticle != nil || audioService.currentPlaybackItem != nil) ? .primary : .secondary.opacity(0.5))
                    }
                    .buttonStyle(ScaledButtonStyle())
                    .disabled(audioService.currentArticle == nil && audioService.currentPlaybackItem == nil)
                    
                    // Play/Pause button
                    Button(action: togglePlayPause) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor((audioService.currentArticle != nil || audioService.currentPlaybackItem != nil) ? .briefeedRed : .secondary.opacity(0.5))
                    }
                    .buttonStyle(ScaledButtonStyle())
                    .disabled(audioService.currentArticle == nil && audioService.currentPlaybackItem == nil)
                    
                    // Skip forward button
                    Button(action: { audioService.skipForward(seconds: 30) }) {
                        Image(systemName: "goforward.30")
                            .font(.system(size: 22))
                            .foregroundColor((audioService.currentArticle != nil || audioService.currentPlaybackItem != nil) ? .primary : .secondary.opacity(0.5))
                    }
                    .buttonStyle(ScaledButtonStyle())
                    .disabled(audioService.currentArticle == nil && audioService.currentPlaybackItem == nil)
                }
                .padding(.horizontal, 20)
                
                // Right side controls
                HStack(spacing: 16) {
                    // Auto-play toggle
                    Button(action: toggleAutoPlay) {
                        Image(systemName: userDefaultsManager.autoPlayEnabled ? "infinity.circle.fill" : "infinity.circle")
                            .font(.system(size: 24))
                            .foregroundColor(userDefaultsManager.autoPlayEnabled ? .briefeedRed : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Expand button
                    Button(action: { showExpandedPlayer = true }) {
                        Image(systemName: "chevron.up.circle")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.trailing, 16)
            }
            .frame(height: playerHeight)
        }
        .background(
            Group {
                if userDefaultsManager.isDarkMode {
                    // Dark mode background
                    ZStack {
                        Color.black
                        VisualEffectBlur(blurStyle: .systemUltraThinMaterialDark)
                    }
                } else {
                    // Light mode background
                    ZStack {
                        Color.white
                        VisualEffectBlur(blurStyle: .systemUltraThinMaterialLight)
                    }
                }
            }
        )
        .onReceive(audioService.$currentArticle) { article in
            // Refresh view when current article changes
        }
        .onReceive(audioService.$queue) { _ in
            // Refresh view when queue changes
        }
        .overlay(
            // Top border
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(height: 0.5),
            alignment: .top
        )
        .shadow(color: Color.black.opacity(userDefaultsManager.isDarkMode ? 0.3 : 0.15), 
                radius: 8, x: 0, y: -2)
        .fullScreenCover(isPresented: $showExpandedPlayer) {
            ExpandedAudioPlayer()
                .environmentObject(userDefaultsManager)
        }
    }
    
    private var isPlaying: Bool {
        (audioService.currentArticle != nil || audioService.currentPlaybackItem != nil) && stateManager.isAudioPlaying
    }
    
    private func togglePlayPause() {
        if isPlaying {
            audioService.pause()
        } else {
            audioService.play()
        }
    }
    
    private func toggleAutoPlay() {
        userDefaultsManager.autoPlayEnabled.toggle()
    }
}

// Visual effect blur for background
struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}

// Custom button style with better touch feedback
struct ScaledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Preview
struct MiniAudioPlayer_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            MiniAudioPlayer()
        }
        .environmentObject(UserDefaultsManager.shared)
    }
}