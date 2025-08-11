//
//  MiniAudioPlayerV4.swift
//  Briefeed
//
//  Unified mini audio player using AudioPlayerViewModelV2
//

import SwiftUI

struct MiniAudioPlayerV4: View {
    @EnvironmentObject var viewModel: AudioPlayerViewModelV2
    @State private var isExpanded = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    private let height: CGFloat = 70
    private let expandThreshold: CGFloat = -50
    private let dismissThreshold: CGFloat = 100
    
    var body: some View {
        VStack(spacing: 0) {
            // Divider
            Divider()
            
            // Player content
            HStack(spacing: 12) {
                // Thumbnail or waveform
                ZStack {
                    if viewModel.isGenerating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 44, height: 44)
                    } else if viewModel.isPlaying {
                        WaveformMiniView(isPlaying: true)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: itemIcon)
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                
                // Title and info - constrained width to prevent overflow
                VStack(alignment: .leading, spacing: 2) {
                    if let title = viewModel.currentTitle {
                        MarqueeText(title, font: .system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    } else {
                        Text("Not Playing")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        if viewModel.isGenerating {
                            Text(viewModel.generationProgress)
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                                .lineLimit(1)
                        } else if let artist = viewModel.currentArtist {
                            Text(artist)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        if viewModel.playbackSpeed != 1.0 {
                            Text("• \(formatSpeed(viewModel.playbackSpeed))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .frame(maxWidth: 120) // Constrain width to prevent overflow
                
                Spacer(minLength: 4)
                
                // Controls - 5 button layout: [⏮️] [-10] [⏸️/▶️] [+10] [⏭️]
                HStack(spacing: 10) {
                    // Previous track button
                    Button(action: {
                        Task { @MainActor in
                            await viewModel.playPrevious()
                        }
                    }) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 20))
                            .foregroundColor(viewModel.currentQueueIndex > 0 ? .primary : .secondary.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .disabled(viewModel.currentQueueIndex <= 0)
                    .accessibilityLabel("Previous track")
                    
                    // Rewind 10 seconds button
                    Button(action: {
                        viewModel.seekBackward()
                    }) {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Rewind 10 seconds")
                    
                    // Play/Pause button (center, larger)
                    Button(action: {
                        if viewModel.isPlaying {
                            viewModel.pause()
                        } else {
                            Task { @MainActor in
                                await viewModel.play()
                            }
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 44, height: 44)
                            
                            if viewModel.isLoading || viewModel.isGenerating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .offset(x: viewModel.isPlaying ? 0 : 1) // Center play icon
                            }
                        }
                    }
                    .disabled(viewModel.queueItems.isEmpty)
                    .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
                    
                    // Forward 10 seconds button
                    Button(action: {
                        viewModel.seekForward()
                    }) {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Forward 10 seconds")
                    
                    // Next track button
                    Button(action: {
                        Task { @MainActor in
                            await viewModel.playNext()
                        }
                    }) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 20))
                            .foregroundColor(viewModel.currentQueueIndex < viewModel.queueItems.count - 1 ? .primary : .secondary.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .disabled(viewModel.currentQueueIndex >= viewModel.queueItems.count - 1)
                    .accessibilityLabel("Next track")
                }
                .padding(.trailing, 8)
            }
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(
                Color(UIColor.secondarySystemBackground)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: -1)
            )
            
            // Progress bar
            if viewModel.duration > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 2)
                        
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * CGFloat(viewModel.progress), height: 2)
                    }
                }
                .frame(height: 2)
            }
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation.height
                    
                    if dragOffset < expandThreshold {
                        HapticManager.shared.lightImpact()
                        isExpanded = true
                    }
                }
                .onEnded { value in
                    isDragging = false
                    
                    withAnimation(.spring()) {
                        if dragOffset < expandThreshold {
                            // Expand to full player
                            isExpanded = true
                        } else if dragOffset > dismissThreshold {
                            // Dismiss player (stop playback)
                            viewModel.stop()
                        }
                        dragOffset = 0
                    }
                }
        )
        .sheet(isPresented: $isExpanded) {
            ExpandedAudioPlayerV2()
                .environmentObject(viewModel)
        }
    }
    
    private var itemIcon: String {
        switch viewModel.currentItemType {
        case .article:
            return "doc.text"
        case .rssEpisode:
            return "mic.fill"
        case .none:
            return "music.note"
        }
    }
    
    private func formatSpeed(_ speed: Float) -> String {
        if speed == 1.0 {
            return "1x"
        } else if speed == floor(speed) {
            return "\(Int(speed))x"
        } else {
            return String(format: "%.1fx", speed)
        }
    }
}

// MARK: - Preview
struct MiniAudioPlayerV4_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            MiniAudioPlayerV4()
                .environmentObject(AudioPlayerViewModelV2())
        }
    }
}