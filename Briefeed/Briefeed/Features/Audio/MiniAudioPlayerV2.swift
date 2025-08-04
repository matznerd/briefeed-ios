//
//  MiniAudioPlayerV2.swift
//  Briefeed
//
//  Created by Briefeed Team on 1/8/25.
//

import SwiftUI
import Combine

/// Updated mini audio player using the new BriefeedAudioService
struct MiniAudioPlayerV2: View {
    @StateObject private var audioService = AudioServiceAdapter()
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
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(playbackItem.author ?? playbackItem.feedTitle ?? "Unknown")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            if !audioService.queue.isEmpty {
                                Text("• \(audioService.queue.count) in queue")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("No audio playing")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                
                // Loading indicator
                if audioService.isLoading || audioService.isGeneratingAudio {
                    HStack(spacing: 8) {
                        if audioService.isGeneratingAudio {
                            Text("Generating...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 20, height: 20)
                    }
                    .padding(.horizontal, 8)
                }
                
                // Control buttons (right side)
                HStack(spacing: 16) {
                    // Skip backward button
                    Button(action: {
                        audioService.skipBackward()
                    }) {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 20))
                            .foregroundColor(.primary)
                    }
                    .disabled(audioService.currentPlaybackItem == nil || audioService.isLoading)
                    .opacity(audioService.currentPlaybackItem == nil ? 0.3 : 1.0)
                    
                    // Play/Pause button
                    Button(action: {
                        audioService.togglePlayPause()
                    }) {
                        Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.1))
                            )
                    }
                    .disabled(audioService.currentPlaybackItem == nil || audioService.isLoading)
                    
                    // Skip forward button
                    Button(action: {
                        audioService.skipForward()
                    }) {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 20))
                            .foregroundColor(.primary)
                    }
                    .disabled(audioService.currentPlaybackItem == nil || audioService.isLoading)
                    .opacity(audioService.currentPlaybackItem == nil ? 0.3 : 1.0)
                }
                .padding(.trailing, 16)
            }
            .frame(height: playerHeight - progressBarHeight)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .onTapGesture {
                if audioService.currentPlaybackItem != nil {
                    showExpandedPlayer = true
                }
            }
        }
        .frame(height: playerHeight)
        .background(
            Color(UIColor.systemBackground)
                .shadow(color: Color.black.opacity(0.1), radius: 4, y: -2)
        )
        .sheet(isPresented: $showExpandedPlayer) {
            ExpandedAudioPlayerV2()
                .environmentObject(userDefaultsManager)
        }
        .accessibility(label: Text("Audio Player"))
        .accessibility(hint: Text("Tap to expand player"))
    }
}


// MARK: - Preview
struct MiniAudioPlayerV2_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            MiniAudioPlayerV2()
                .environmentObject(UserDefaultsManager.shared)
        }
    }
}