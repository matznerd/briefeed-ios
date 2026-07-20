//
//  MiniAudioPlayerV4.swift
//  Briefeed
//
//  Unified mini audio player using AudioPlayerViewModelV2
//

import SwiftUI

struct MiniAudioPlayerV4: View {
    @EnvironmentObject var viewModel: AudioPlayerViewModelV2
    @State private var showTranscript = false
    @State private var showExpandedPlayer = false

    var body: some View {
        VStack(spacing: 0) {
            // Divider
            Divider()
            
            // Full-width title at the top
            HStack {
                if let title = viewModel.currentTitle {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityIdentifier(AccessibilityID.MiniPlayer.title)
                } else {
                    Text("Not Playing")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()

                Button {
                    showExpandedPlayer = true
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open player")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground))
            .contentShape(Rectangle())
            .onTapGesture {
                if viewModel.currentItemType == .article {
                    showTranscript = true
                }
            }

            // Player content
            HStack(spacing: 12) {
                // Thumbnail or waveform
                ZStack {
                    if viewModel.isGenerating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 44, height: 44)
                    } else if viewModel.isPlaying {
                        WaveformMiniView(isPlaying: viewModel.isPlaying)
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
                
                // Source and speed info only (title is now at top)
                VStack(alignment: .leading, spacing: 2) {
                    if viewModel.isGenerating {
                        HStack(spacing: 4) {
                            // Phase-appropriate icon
                            Image(systemName: phaseIcon)
                                .font(.system(size: 10))
                                .foregroundColor(phaseColor)

                            Text(viewModel.generationPhase.shortMessage)
                                .font(.system(size: 11))
                                .foregroundColor(phaseColor)
                                .lineLimit(1)
                        }
                    } else if let artist = viewModel.currentArtist {
                        HStack(spacing: 4) {
                            Text(artist)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            if viewModel.playbackSpeed != 1.0 {
                                Text("• \(formatSpeed(viewModel.playbackSpeed))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    
                    // Time remaining or progress
                    if viewModel.duration > 0 {
                        Text("\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.duration))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
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
                            .foregroundColor(viewModel.canPlayPrevious ? .primary : .secondary.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .disabled(!viewModel.canPlayPrevious)
                    .accessibilityLabel("Previous track")
                    .accessibilityIdentifier(AccessibilityID.MiniPlayer.previous)
                    
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
                    .accessibilityIdentifier(AccessibilityID.MiniPlayer.rewind)
                    
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
                            
                            if viewModel.isLoading {
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
                    .disabled(viewModel.radioEntries.isEmpty && viewModel.queueItems.isEmpty)
                    .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
                    .accessibilityIdentifier(AccessibilityID.MiniPlayer.playPause)
                    
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
                    .accessibilityIdentifier(AccessibilityID.MiniPlayer.forward)
                    
                    // Next track button
                    Button(action: {
                        Task { @MainActor in
                            await viewModel.playNext()
                        }
                    }) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 20))
                            .foregroundColor(viewModel.canPlayNext ? .primary : .secondary.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .disabled(!viewModel.canPlayNext)
                    .accessibilityLabel("Next track")
                    .accessibilityIdentifier(AccessibilityID.MiniPlayer.next)
                }
                .padding(.trailing, 8)
            }
            .padding(.horizontal, 16)
            .frame(height: 54) // Controls section height
            .background(
                Color(UIColor.systemBackground)
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: -2)
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
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                viewModel.seek(to: progress(for: value.location.x, width: geometry.size.width))
                            }
                    )
                }
                .frame(height: 12)
            }
        }
        .accessibilityIdentifier(AccessibilityID.MiniPlayer.container)
        .sheet(isPresented: $showTranscript) {
            TranscriptReaderView()
                .environmentObject(viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showExpandedPlayer) {
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

    /// Icon for the current generation phase
    private var phaseIcon: String {
        switch viewModel.generationPhase {
        case .idle:
            return "circle"
        case .checkingCache:
            return "magnifyingglass"
        case .fetchingContent:
            return "arrow.down.doc"
        case .summarizing:
            return "text.badge.star"
        case .downloadingModels:
            return "arrow.down.to.line"
        case .initializingOnDevice:
            return "cpu"
        case .generatingAudio:
            return "waveform"
        case .downloadingAudio:
            return "arrow.down.circle"
        case .finalizing:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    /// Color for the current generation phase
    private var phaseColor: Color {
        switch viewModel.generationPhase {
        case .idle:
            return .secondary
        case .checkingCache:
            return .blue
        case .fetchingContent:
            return .blue
        case .summarizing:
            return .purple
        case .downloadingModels:
            return .blue
        case .initializingOnDevice:
            return .orange
        case .generatingAudio:
            return .orange
        case .downloadingAudio:
            return .green
        case .finalizing:
            return .green
        case .failed:
            return .red
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
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func progress(for xPosition: CGFloat, width: CGFloat) -> Float {
        guard width > 0 else { return 0 }
        return Float(max(0, min(1, xPosition / width)))
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
