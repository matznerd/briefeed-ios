//
//  ExpandedAudioPlayerV2.swift
//  Briefeed
//
//  Full-screen audio player using AudioPlayerViewModelV2
//  Shares the Radio transport, speed, sleep, and progress semantics.
//

import SwiftUI

struct ExpandedAudioPlayerV2: View {
    @EnvironmentObject var viewModel: AudioPlayerViewModelV2
    @Environment(\.dismiss) var dismiss
    @State private var showQueue = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                header
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Artwork/Waveform
                        artworkSection
                            .padding(.top, 20)
                        
                        // Title and Artist
                        titleSection
                        
                        // Progress Bar
                        progressSection
                        
                        // Main Controls
                        mainControls
                        
                        // Speed Control
                        speedControl
                        
                        // Queue Info
                        queueInfo
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .background(Color(UIColor.systemBackground))
            .sheet(isPresented: $showQueue) {
                QueueView()
                    .environmentObject(viewModel)
            }
        }
    }
    
    // MARK: - Header
    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.dismiss)
            
            Spacer()
            
            Text("Now Playing")
                .font(.system(size: 16, weight: .semibold))
            
            Spacer()
            
            if viewModel.activeMode == .radio {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            } else {
                Button(action: { showQueue = true }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Queue")
                .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.queue)
            }
        }
        .padding(.horizontal, 4)
        .overlay(
            Divider()
                .background(Color.gray.opacity(0.3)),
            alignment: .bottom
        )
    }
    
    // MARK: - Artwork Section
    private var artworkSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.1))
                .frame(height: 320)
            
            if viewModel.isGenerating {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    
                    Text("Generating Audio...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    if !viewModel.generationProgress.isEmpty {
                        Text(viewModel.generationProgress)
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                }
            } else if viewModel.isPlaying {
                WaveformView(isPlaying: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            } else {
                Image(systemName: itemIcon)
                    .font(.system(size: 80))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
    }
    
    // MARK: - Title Section
    private var titleSection: some View {
        VStack(spacing: 8) {
            Text(viewModel.currentTitle ?? "Not Playing")
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            if let artist = viewModel.currentArtist {
                Text(artist)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            
            if viewModel.currentItemType != .none {
                Label(itemTypeText, systemImage: itemIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Progress Section
    private var progressSection: some View {
        PlayerScrubber(
            position: viewModel.currentTime,
            duration: viewModel.duration,
            identifier: AccessibilityID.ExpandedPlayer.progress,
            onSeek: viewModel.seek(to:)
        )
    }
    
    // MARK: - Main Controls
    private var mainControls: some View {
        HStack(spacing: 8) {
            if PlayerPresentationPolicy.showsPrevious(for: viewModel.activeMode) {
                Button {
                    Task { await viewModel.playPrevious() }
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canPlayPrevious)
                .accessibilityLabel("Previous")
                .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.previous)
            }

            Button {
                viewModel.skipBackward(10)
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(.title, design: .rounded, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back 10 seconds")
            .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.skipBackward)

            // Play/Pause
            Button {
                viewModel.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.briefeedRed)
                        .frame(width: 64, height: 64)
                    
                    if viewModel.isLoading || viewModel.isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                    } else {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: viewModel.isPlaying ? 0 : 2)
                    }
                }
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.playPause)

            Button {
                viewModel.skipForward(10)
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(.title, design: .rounded, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Forward 10 seconds")
            .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.skipForward)

            Button {
                Task { await viewModel.playNext() }
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canPlayNext)
            .accessibilityLabel("Next")
            .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.next)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Speed Control
    private var speedControl: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Playback")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PlayerSpeedMenu(viewModel: viewModel)
                    .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.speed)
            }

            if viewModel.activeMode == .radio {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sleep")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    RadioSleepMenu(viewModel: viewModel)
                        .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.sleep)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    // MARK: - Queue Info
    private var queueInfo: some View {
        Group {
            if viewModel.activeMode != .radio, !viewModel.queueItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Queue")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(viewModel.currentQueueIndex + 1) of \(viewModel.queueItems.count)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    if viewModel.canPlayNext,
                       viewModel.currentQueueIndex + 1 < viewModel.queueItems.count {
                        HStack {
                            Text("Next:")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            
                            Text(viewModel.queueItems[viewModel.currentQueueIndex + 1].title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onTapGesture {
                    showQueue = true
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var itemIcon: String {
        switch viewModel.currentItemType {
        case .article:
            return "doc.text.fill"
        case .rssEpisode:
            return "mic.fill"
        case .none:
            return "music.note"
        }
    }
    
    private var itemTypeText: String {
        switch viewModel.currentItemType {
        case .article:
            return "Article"
        case .rssEpisode:
            return "Podcast"
        case .none:
            return "Audio"
        }
    }
    
}

// MARK: - Queue View

struct QueueView: View {
    @EnvironmentObject var viewModel: AudioPlayerViewModelV2
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.queueItems.indices, id: \.self) { index in
                    HStack {
                        // Playing indicator
                        if index == viewModel.currentQueueIndex {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.accentColor)
                                .frame(width: 20)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                        }
                        
                        // Item info
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.queueItems[index].title)
                                .font(.system(size: 14, weight: index == viewModel.currentQueueIndex ? .semibold : .regular))
                                .lineLimit(2)
                            
                            if let source = viewModel.queueItems[index].article?.author ?? 
                                           viewModel.queueItems[index].episode?.feed?.displayName {
                                Text(source)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        Spacer()
                        
                        // Generation state
                        switch viewModel.queueItems[index].generationState {
                        case .ready:
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.green)
                        case .generating:
                            ProgressView()
                                .scaleEffect(0.7)
                        case .failed:
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                        case .pending:
                            Image(systemName: "circle")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task {
                            await viewModel.playItemAt(index: index)
                            dismiss()
                        }
                    }
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet {
                            await viewModel.removeFromQueue(at: index)
                        }
                    }
                }
                .onMove { source, destination in
                    Task {
                        await viewModel.reorderQueue(from: source, to: destination)
                    }
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
    }
}

// MARK: - Preview

struct ExpandedAudioPlayerV2_Previews: PreviewProvider {
    static var previews: some View {
        ExpandedAudioPlayerV2()
            .environmentObject(AudioPlayerViewModelV2())
    }
}
