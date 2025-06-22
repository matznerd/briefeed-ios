//
//  ExpandedAudioPlayer.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import SwiftUI
import Combine

struct ExpandedAudioPlayer: View {
    @ObservedObject private var audioService = AudioService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isDraggingSlider = false
    @State private var draggedProgress: Float = 0
    @State private var showQueue = false
    
    private var isPlaying: Bool {
        audioService.state.value == .playing
    }
    
    private var currentProgress: Float {
        isDraggingSlider ? draggedProgress : audioService.progress.value
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
            AudioQueueView()
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
                    
                    if audioService.queue.count > 1 {
                        Text("\(audioService.queue.count)")
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
            if let article = audioService.currentArticle {
                Text(article.title ?? "Untitled")
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                
                Text(article.author ?? "Unknown Author")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
                
                if let subreddit = article.subreddit {
                    Text("r/\(subreddit)")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
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
                        audioService.seek(to: audioService.duration * Double(progress))
                        isDraggingSlider = false
                    }
            )
            
            // Time labels
            HStack {
                Text(AudioService.formatTime(audioService.currentTime))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                
                Spacer()
                
                Text(AudioService.formatTimeRemaining(audioService.currentTime, audioService.duration))
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
                Task {
                    try? await audioService.playPrevious()
                }
            }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(audioService.queueIndex > 0 ? .primary : .gray)
            }
            .disabled(audioService.queueIndex == 0)
            
            // Skip backward 15s
            Button(action: {
                audioService.skipBackward(seconds: 15)
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
            Button(action: togglePlayPause) {
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
            
            // Skip forward 15s
            Button(action: {
                audioService.skipForward(seconds: 15)
            }) {
                ZStack {
                    Image(systemName: "goforward")
                        .font(.system(size: 32))
                    Text("15")
                        .font(.system(size: 11, weight: .bold))
                        .offset(y: 1)
                }
                .foregroundColor(.primary)
            }
            
            // Next button
            Button(action: {
                Task {
                    try? await audioService.playNext()
                }
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(audioService.queueIndex < audioService.queue.count - 1 ? .primary : .gray)
            }
            .disabled(audioService.queueIndex >= audioService.queue.count - 1)
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
                }
                
                CompactSpeedPicker(selectedSpeed: Binding(
                    get: { audioService.currentRate.value },
                    set: { audioService.setSpeechRate($0) }
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
                    
                    Slider(value: $audioService.volume, in: 0...1)
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
    private func togglePlayPause() {
        if isPlaying {
            audioService.pause()
        } else {
            audioService.play()
        }
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Audio Queue View
struct AudioQueueView: View {
    @ObservedObject private var audioService = AudioService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(audioService.queue.indices, id: \.self) { index in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(audioService.queue[index].title ?? "Untitled")
                                .font(.system(size: 16, weight: .medium))
                                .lineLimit(2)
                            
                            Text(audioService.queue[index].author ?? "Unknown")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if index == audioService.queueIndex {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if index != audioService.queueIndex {
                            audioService.queueIndex = index
                            Task {
                                try? await audioService.playArticle(audioService.queue[index])
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        audioService.removeFromQueue(at: index)
                    }
                }
            }
            .navigationTitle("Queue (\(audioService.queue.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    if audioService.queue.count > 1 {
                        Button("Clear All") {
                            audioService.clearQueue()
                            dismiss()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

// MARK: - Preview
struct ExpandedAudioPlayer_Previews: PreviewProvider {
    static var previews: some View {
        ExpandedAudioPlayer()
    }
}