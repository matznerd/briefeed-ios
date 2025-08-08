//
//  MiniAudioPlayer.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import SwiftUI
import Combine

struct MiniAudioPlayer: View {
    @StateObject private var audioService = BriefeedAudioService.shared
    @StateObject private var queueService = QueueServiceV2.shared
    @StateObject private var stateManager = ArticleStateManager.shared
    @EnvironmentObject var userDefaultsManager: UserDefaultsManager
    @State private var showExpandedPlayer = false
    @State private var progress: Float = 0
    @State private var progressTimer: Timer?
    
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
                        .frame(width: geometry.size.width * CGFloat(progress), height: progressBarHeight)
                }
            }
            .frame(height: progressBarHeight)
            
            // Player content
            HStack(spacing: 0) {
                // Article info (left side)
                VStack(alignment: .leading, spacing: 2) {
                    if let currentItem = audioService.currentItem {
                        Text(currentItem.content.title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 4) {
                            if currentItem.content.contentType == .rssEpisode {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Text(currentItem.content.author ?? "")
                                .font(.caption2)
                                .foregroundColor(.secondary)
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
                    Button(action: { audioService.skipBackward() }) {
                        Image(systemName: skipBackwardIconName)
                            .font(.system(size: 22))
                            .foregroundColor(audioService.currentItem != nil ? .primary : .secondary.opacity(0.5))
                    }
                    .buttonStyle(ScaledButtonStyle())
                    .disabled(audioService.currentItem == nil)
                    
                    // Play/Pause button
                    Button(action: togglePlayPause) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(audioService.currentItem != nil ? .briefeedRed : .secondary.opacity(0.5))
                    }
                    .buttonStyle(ScaledButtonStyle())
                    .disabled(audioService.currentItem == nil)
                    
                    // Skip forward button
                    Button(action: { audioService.skipForward() }) {
                        Image(systemName: skipForwardIconName)
                            .font(.system(size: 22))
                            .foregroundColor(audioService.currentItem != nil ? .primary : .secondary.opacity(0.5))
                    }
                    .buttonStyle(ScaledButtonStyle())
                    .disabled(audioService.currentItem == nil)
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
        .onAppear {
            startProgressTimer()
        }
        .onDisappear {
            stopProgressTimer()
        }
    }
    
    private var isPlaying: Bool {
        audioService.isPlaying
    }
    
    private var skipBackwardIconName: String {
        // Use 15s for articles, 30s for RSS
        if let currentItem = audioService.currentItem {
            return currentItem.content.contentType == .article ? "gobackward.15" : "gobackward.30"
        }
        return "gobackward.15"
    }
    
    private var skipForwardIconName: String {
        // Use 15s for articles, 30s for RSS
        if let currentItem = audioService.currentItem {
            return currentItem.content.contentType == .article ? "goforward.15" : "goforward.30"
        }
        return "goforward.30"
    }
    
    private func togglePlayPause() {
        audioService.togglePlayPause()
    }
    
    private func toggleAutoPlay() {
        userDefaultsManager.autoPlayEnabled.toggle()
    }
    
    private func startProgressTimer() {
        // Update progress periodically instead of continuously
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if audioService.currentItem != nil {
                let newProgress = audioService.progress.value
                if abs(progress - newProgress) > 0.001 { // Only update if changed significantly
                    progress = newProgress
                }
            }
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
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