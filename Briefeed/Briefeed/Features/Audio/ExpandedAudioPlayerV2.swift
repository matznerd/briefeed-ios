//
//  ExpandedAudioPlayerV2.swift
//  Briefeed
//
//  Full-screen audio player using AudioPlayerViewModelV2
//  Supports up to 20x playback speed with SwiftAudioEx
//

import SwiftUI

struct ExpandedAudioPlayerV2: View {
    @EnvironmentObject var viewModel: AudioPlayerViewModelV2
    @Environment(\.dismiss) var dismiss
    @State private var isDraggingSlider = false
    @State private var dragProgress: Float = 0
    @State private var showSpeedPicker = false
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
            
            Button(action: { showQueue = true }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.queue)
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
        VStack(spacing: 8) {
            // Progress Slider
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 6)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor)
                    .frame(width: progressWidth, height: 6)
                
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 16, height: 16)
                    .offset(x: progressWidth - 8)
            }
            .frame(height: 16)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDraggingSlider = true
                        let progress = Float(value.location.x / UIScreen.main.bounds.width - 48)
                        dragProgress = max(0, min(1, progress))
                    }
                    .onEnded { _ in
                        viewModel.seek(to: dragProgress)
                        isDraggingSlider = false
                    }
            )
            
            // Time Labels
            HStack {
                Text(viewModel.formattedCurrentTime)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(viewModel.formattedRemainingTime)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Main Controls
    private var mainControls: some View {
        HStack(spacing: 40) {
            // Skip Backward
            Button(action: {
                viewModel.skipBackward(15)
            }) {
                VStack(spacing: 2) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 32))
                    Text("15s")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.primary)
            }
            .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.skipBackward)
            
            // Previous
            Button(action: {
                Task {
                    await viewModel.playPrevious()
                }
            }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(viewModel.canPlayPrevious ? .primary : .secondary.opacity(0.5))
            }
            .disabled(!viewModel.canPlayPrevious)
            .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.previous)

            // Play/Pause
            Button(action: {
                viewModel.togglePlayPause()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 72, height: 72)
                    
                    if viewModel.isLoading || viewModel.isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                    } else {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: viewModel.isPlaying ? 0 : 2)
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.playPause)

            // Next
            Button(action: {
                Task {
                    await viewModel.playNext()
                }
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(viewModel.canPlayNext ? .primary : .secondary.opacity(0.5))
            }
            .disabled(!viewModel.canPlayNext)
            .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.next)

            // Skip Forward
            Button(action: {
                viewModel.skipForward(30)
            }) {
                VStack(spacing: 2) {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 32))
                    Text("30s")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.primary)
            }
            .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.skipForward)
        }
    }
    
    // MARK: - Speed Control
    private var speedControl: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Playback Speed")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { showSpeedPicker.toggle() }) {
                    HStack(spacing: 4) {
                        Text(formatSpeed(viewModel.playbackSpeed))
                            .font(.system(size: 16, weight: .semibold))

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .rotationEffect(.degrees(showSpeedPicker ? 90 : 0))
                    }
                    .foregroundColor(.accentColor)
                }
                .accessibilityIdentifier(AccessibilityID.ExpandedPlayer.speed)
            }
            
            if showSpeedPicker {
                HorizontalSpeedSelector(selectedSpeed: $viewModel.playbackSpeed)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Queue Info
    private var queueInfo: some View {
        Group {
            if !viewModel.queueItems.isEmpty {
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
                .cornerRadius(12)
                .onTapGesture {
                    showQueue = true
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var progressWidth: CGFloat {
        let totalWidth = UIScreen.main.bounds.width - 48
        let progress = isDraggingSlider ? dragProgress : viewModel.progress
        return totalWidth * CGFloat(progress)
    }
    
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
    
    private func formatSpeed(_ speed: Float) -> String {
        if speed == 1.0 {
            return "1×"
        } else if speed == floor(speed) {
            return "\(Int(speed))×"
        } else {
            return String(format: "%.1f×", speed)
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