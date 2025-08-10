//
//  MiniAudioPlayerV3.swift
//  Briefeed
//
//  Fixed architecture version using AudioPlayerViewModel
//

import SwiftUI
import Combine

struct MiniAudioPlayerV3: View {
    @EnvironmentObject var audioPlayerViewModel: AudioPlayerViewModel
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
                        .frame(width: geometry.size.width * CGFloat(audioPlayerViewModel.progress), height: progressBarHeight)
                        .animation(.linear(duration: 0.1), value: audioPlayerViewModel.progress)
                }
            }
            .frame(height: progressBarHeight)
            
            // Player content
            HStack(spacing: 0) {
                // Article info (left side)
                VStack(alignment: .leading, spacing: 2) {
                    if let title = audioPlayerViewModel.currentTitle {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        
                        if let artist = audioPlayerViewModel.currentArtist {
                            HStack(spacing: 4) {
                                if audioPlayerViewModel.currentURL != nil {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text(artist)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .lineLimit(1)
                        }
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
                    Button(action: { audioPlayerViewModel.skipBackward() }) {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 22))
                            .foregroundColor(audioPlayerViewModel.currentTitle != nil ? .primary : .secondary.opacity(0.5))
                    }
                    .buttonStyle(ScaledButtonStyleV3())
                    .disabled(audioPlayerViewModel.currentTitle == nil)
                    
                    // Play/Pause button
                    Button(action: { audioPlayerViewModel.togglePlayPause() }) {
                        Image(systemName: audioPlayerViewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(audioPlayerViewModel.currentTitle != nil ? .briefeedRed : .secondary.opacity(0.5))
                    }
                    .buttonStyle(ScaledButtonStyleV3())
                    .disabled(audioPlayerViewModel.currentTitle == nil)
                    
                    // Skip forward button
                    Button(action: { audioPlayerViewModel.skipForward() }) {
                        Image(systemName: "goforward.30")
                            .font(.system(size: 22))
                            .foregroundColor(audioPlayerViewModel.currentTitle != nil ? .primary : .secondary.opacity(0.5))
                    }
                    .buttonStyle(ScaledButtonStyleV3())
                    .disabled(audioPlayerViewModel.currentTitle == nil)
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
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.briefeedRed.opacity(0.05),
                                Color.clear
                            ]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    }
                } else {
                    // Light mode background
                    ZStack {
                        Color.white
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.briefeedRed.opacity(0.03),
                                Color.clear
                            ]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    }
                }
            }
        )
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: -2)
        .sheet(isPresented: $showExpandedPlayer) {
            ExpandedAudioPlayerV2()
                .environmentObject(audioPlayerViewModel)
                .environmentObject(userDefaultsManager)
        }
        .onAppear {
            // Auto-play on app launch if enabled
            if userDefaultsManager.autoPlayEnabled && 
               !audioPlayerViewModel.isPlaying && 
               !audioPlayerViewModel.queueItems.isEmpty {
                audioPlayerViewModel.playNextInQueue()
            }
        }
    }
    
    private func toggleAutoPlay() {
        userDefaultsManager.autoPlayEnabled.toggle()
        // Settings are automatically saved via didSet
    }
}

// MARK: - Scaled Button Style V3
struct ScaledButtonStyleV3: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
    }
}

struct MiniAudioPlayerV3_Previews: PreviewProvider {
    static var previews: some View {
        MiniAudioPlayerV3()
            .environmentObject(AudioPlayerViewModel())
            .environmentObject(UserDefaultsManager.shared)
    }
}