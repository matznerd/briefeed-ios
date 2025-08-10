//
//  ExpandedAudioPlayerV2.swift
//  Briefeed
//
//  Migrated version using AudioPlayerViewModel
//

import SwiftUI
import Combine
import CoreData

struct ExpandedAudioPlayerV2: View {
    @EnvironmentObject var audioPlayerViewModel: AudioPlayerViewModel
    @EnvironmentObject var userDefaultsManager: UserDefaultsManager
    @Environment(\.dismiss) private var dismiss
    @State private var isDraggingSlider = false
    @State private var draggedProgress: Float = 0
    @State private var showQueue = false
    
    private var isPlaying: Bool {
        audioPlayerViewModel.isPlaying
    }
    
    private var currentProgress: Float {
        isDraggingSlider ? draggedProgress : audioPlayerViewModel.progress
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(UIColor.systemBackground),
                        Color(UIColor.secondarySystemBackground)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Navigation bar
                    navigationBar
                    
                    ScrollView {
                        VStack(spacing: 32) {
                            // Waveform visualization
                            waveformSection
                            
                            // Article info
                            articleInfoSection
                            
                            // Progress slider
                            progressSection
                            
                            // Playback controls
                            playbackControlsSection
                            
                            // Speed and volume controls
                            secondaryControlsSection
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showQueue) {
            AudioQueueViewV2()
                .environmentObject(audioPlayerViewModel)
                .environmentObject(userDefaultsManager)
        }
    }
    
    // MARK: - Navigation Bar
    private var navigationBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text("Now Playing")
                .font(.system(size: 17, weight: .semibold))
            
            Spacer()
            
            Button(action: { showQueue = true }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                    
                    if audioPlayerViewModel.queueItems.count > 1 {
                        Text("\(audioPlayerViewModel.queueItems.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(UIColor.systemBackground).opacity(0.95))
    }
    
    // MARK: - Waveform Section
    private var waveformSection: some View {
        VStack(spacing: 16) {
            // Animated waveform
            WaveformView(isPlaying: isPlaying)
                .frame(height: 120)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.accentColor.opacity(0.05),
                                    Color.accentColor.opacity(0.1)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                )
        }
        .padding(.top, 20)
    }
    
    // MARK: - Article Info Section
    private var articleInfoSection: some View {
        VStack(spacing: 12) {
            if let title = audioPlayerViewModel.currentTitle {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                
                if let artist = audioPlayerViewModel.currentArtist {
                    Text(artist)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                // Show source indicator for RSS content
                if audioPlayerViewModel.currentURL != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("RSS Podcast")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("No story playing")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(spacing: 8) {
            // Progress slider
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 8)
                
                // Progress
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor)
                    .frame(width: UIScreen.main.bounds.width * CGFloat(currentProgress) * 0.85, height: 8)
                
                // Thumb
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 20, height: 20)
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .offset(x: UIScreen.main.bounds.width * CGFloat(currentProgress) * 0.85 - 10)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDraggingSlider = true
                        let progress = min(max(0, value.location.x / (UIScreen.main.bounds.width * 0.85)), 1)
                        draggedProgress = Float(progress)
                    }
                    .onEnded { value in
                        let progress = min(max(0, value.location.x / (UIScreen.main.bounds.width * 0.85)), 1)
                        audioPlayerViewModel.seek(to: Double(progress))
                        isDraggingSlider = false
                    }
            )
            
            // Time labels
            HStack {
                Text(formatTime(audioPlayerViewModel.currentTime))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                
                Spacer()
                
                Text(formatTimeRemaining(audioPlayerViewModel.currentTime, audioPlayerViewModel.duration))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
    }
    
    // MARK: - Playback Controls Section
    private var playbackControlsSection: some View {
        HStack(spacing: 40) {
            // Previous button
            Button(action: {
                audioPlayerViewModel.playPreviousInQueue()
            }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(audioPlayerViewModel.canPlayPrevious ? .primary : .gray)
            }
            .disabled(!audioPlayerViewModel.canPlayPrevious)
            
            // Skip backward 15s
            Button(action: {
                audioPlayerViewModel.skipBackward()
            }) {
                ZStack {
                    Image(systemName: "gobackward")
                        .font(.system(size: 32))
                    Text("15")
                        .font(.system(size: 11, weight: .bold))
                        .offset(y: 1)
                }
                .foregroundColor(.primary)
            }
            
            // Play/Pause button
            Button(action: { audioPlayerViewModel.togglePlayPause() }) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 72, height: 72)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                        .offset(x: isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(ScaleButtonStyle())
            
            // Skip forward 30s
            Button(action: {
                audioPlayerViewModel.skipForward()
            }) {
                ZStack {
                    Image(systemName: "goforward")
                        .font(.system(size: 32))
                    Text("30")
                        .font(.system(size: 11, weight: .bold))
                        .offset(y: 1)
                }
                .foregroundColor(.primary)
            }
            
            // Next button
            Button(action: {
                audioPlayerViewModel.playNextInQueue()
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(audioPlayerViewModel.canPlayNext ? .primary : .gray)
            }
            .disabled(!audioPlayerViewModel.canPlayNext)
        }
    }
    
    // MARK: - Secondary Controls Section
    private var secondaryControlsSection: some View {
        VStack(spacing: 24) {
            // Speed control
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "speedometer")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                    
                    Text("Playback Speed")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(String(format: "%.1fx", audioPlayerViewModel.playbackSpeed))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
                
                CompactSpeedPicker(selectedSpeed: Binding(
                    get: { audioPlayerViewModel.playbackSpeed },
                    set: { audioPlayerViewModel.setSpeed($0) }
                ))
            }
            
            // Volume control
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                    
                    Text("Volume")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                
                HStack(spacing: 16) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    Slider(value: Binding(
                        get: { audioPlayerViewModel.volume },
                        set: { audioPlayerViewModel.setVolume($0) }
                    ), in: 0...1)
                    .accentColor(.accentColor)
                    
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.05))
        )
    }
    
    // MARK: - Helper Functions
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatTimeRemaining(_ current: TimeInterval, _ duration: TimeInterval) -> String {
        let remaining = max(0, duration - current)
        return "-" + formatTime(remaining)
    }
}

// MARK: - Audio Queue View V2
struct AudioQueueViewV2: View {
    @EnvironmentObject var audioPlayerViewModel: AudioPlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        NavigationView {
            List {
                ForEach(0..<audioPlayerViewModel.queueItems.count, id: \.self) { index in
                    queueRow(at: index)
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet {
                            await audioPlayerViewModel.removeFromQueue(at: index)
                        }
                    }
                }
            }
            .navigationTitle("Queue (\(audioPlayerViewModel.queueItems.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    if audioPlayerViewModel.queueItems.count > 1 {
                        Button("Clear All") {
                            Task {
                                await audioPlayerViewModel.clearQueue()
                            }
                            dismiss()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func queueRow(at index: Int) -> some View {
        let item = audioPlayerViewModel.queueItems[index]
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(2)
                
                HStack(spacing: 4) {
                    Image(systemName: item.source.iconName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(item.source.displayName)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Check if this is the currently playing item
            if index == audioPlayerViewModel.currentQueueIndex {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if index != audioPlayerViewModel.currentQueueIndex {
                Task {
                    await audioPlayerViewModel.playItemAt(index: index)
                }
            }
        }
    }
}

// MARK: - Preview
struct ExpandedAudioPlayerV2_Previews: PreviewProvider {
    static var previews: some View {
        ExpandedAudioPlayerV2()
            .environmentObject(AudioPlayerViewModel())
            .environmentObject(UserDefaultsManager.shared)
    }
}