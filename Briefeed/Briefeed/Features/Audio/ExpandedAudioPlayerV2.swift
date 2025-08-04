//
//  ExpandedAudioPlayerV2.swift
//  Briefeed
//
//  Created by Briefeed Team on 1/8/25.
//

import SwiftUI

/// Expanded audio player using the new BriefeedAudioService
struct ExpandedAudioPlayerV2: View {
    @StateObject private var audioService = AudioServiceAdapter()
    @StateObject private var sleepTimer = SleepTimerManager.shared
    @EnvironmentObject var userDefaultsManager: UserDefaultsManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showSpeedPicker = false
    @State private var showSleepTimer = false
    @State private var showQueue = false
    @State private var showHistory = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        // Artwork/Visualization
                        artworkView
                        
                        // Title and info
                        titleInfoView
                        
                        // Progress view
                        progressView
                        
                        // Main controls
                        mainControlsView
                        
                        // Secondary controls
                        secondaryControlsView
                        
                        // Queue preview
                        if !audioService.queue.isEmpty {
                            queuePreviewView
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
            .background(Color(UIColor.systemBackground))
            .navigationBarHidden(true)
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.1))
                    )
            }
            
            Spacer()
            
            Text("Now Playing")
                .font(.system(size: 16, weight: .medium))
            
            Spacer()
            
            Menu {
                Button(action: { showQueue = true }) {
                    Label("Queue", systemImage: "music.note.list")
                }
                
                Button(action: { showHistory = true }) {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                
                if audioService.currentPlaybackItem != nil {
                    Divider()
                    
                    Button(action: shareContent) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.1))
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
    
    // MARK: - Artwork View
    private var artworkView: some View {
        ZStack {
            if audioService.isPlaying {
                WaveformView(isPlaying: true)
                    .frame(height: 80)
            } else {
                Image(systemName: audioService.currentPlaybackItem?.isRSS == true ? 
                      "dot.radiowaves.left.and.right" : "doc.text")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.primary.opacity(0.05))
        )
    }
    
    // MARK: - Title Info View
    private var titleInfoView: some View {
        VStack(spacing: 8) {
            if let item = audioService.currentPlaybackItem {
                Text(item.title)
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text(item.author ?? item.feedTitle ?? "Unknown")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                
                if item.isRSS {
                    Label("Live Podcast", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 14))
                        .foregroundColor(.briefeedRed)
                }
            } else {
                Text("No audio playing")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Progress View
    private var progressView: some View {
        VStack(spacing: 8) {
            // Progress slider
            Slider(
                value: Binding(
                    get: { audioService.progress.value },
                    set: { newValue in
                        let duration = Double(audioService.progress.currentTime + audioService.progress.remainingTime)
                        audioService.seek(to: newValue * duration)
                    }
                ),
                in: 0...1
            )
            .accentColor(.briefeedRed)
            .disabled(audioService.currentPlaybackItem == nil)
            
            // Time labels
            HStack {
                Text(audioService.progress.currentTimeFormatted)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                
                Spacer()
                
                Text("-\(audioService.progress.remainingTimeFormatted)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
    }
    
    // MARK: - Main Controls View
    private var mainControlsView: some View {
        HStack(spacing: 40) {
            // Previous button
            Button(action: {
                Task { await audioService.playPrevious() }
            }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.primary)
            }
            .disabled(audioService.queue.isEmpty)
            .opacity(audioService.queue.isEmpty ? 0.3 : 1.0)
            
            // Skip backward
            Button(action: {
                audioService.skipBackward()
            }) {
                ZStack {
                    Image(systemName: "gobackward")
                        .font(.system(size: 32))
                    Text("15")
                        .font(.system(size: 12, weight: .semibold))
                        .offset(y: 1)
                }
                .foregroundColor(.primary)
            }
            .disabled(audioService.currentPlaybackItem == nil)
            
            // Play/Pause
            Button(action: {
                audioService.togglePlayPause()
            }) {
                Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
                    .frame(width: 70, height: 70)
                    .background(
                        Circle()
                            .fill(Color.briefeedRed)
                    )
            }
            .disabled(audioService.currentPlaybackItem == nil)
            
            // Skip forward
            Button(action: {
                audioService.skipForward()
            }) {
                ZStack {
                    Image(systemName: "goforward")
                        .font(.system(size: 32))
                    Text(audioService.currentPlaybackItem?.isRSS == true ? "30" : "15")
                        .font(.system(size: 12, weight: .semibold))
                        .offset(y: 1)
                }
                .foregroundColor(.primary)
            }
            .disabled(audioService.currentPlaybackItem == nil)
            
            // Next button
            Button(action: {
                Task { await audioService.playNext() }
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.primary)
            }
            .disabled(audioService.queue.isEmpty)
            .opacity(audioService.queue.isEmpty ? 0.3 : 1.0)
        }
    }
    
    // MARK: - Secondary Controls View
    private var secondaryControlsView: some View {
        HStack(spacing: 30) {
            // Sleep timer
            Button(action: { showSleepTimer = true }) {
                VStack(spacing: 4) {
                    Image(systemName: sleepTimer.isActive ? "moon.zzz.fill" : "moon.zzz")
                        .font(.system(size: 22))
                        .foregroundColor(sleepTimer.isActive ? .briefeedRed : .primary)
                    
                    if sleepTimer.isActive {
                        Text(sleepTimer.formattedRemainingTime())
                            .font(.system(size: 10))
                            .foregroundColor(.briefeedRed)
                    }
                }
            }
            .frame(width: 60, height: 60)
            
            // Playback speed
            Button(action: { showSpeedPicker = true }) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1fx", audioService.playbackSpeed))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text("Speed")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 60, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.1))
            )
            
            // Volume control
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                Slider(value: $audioService.volume, in: 0...1)
                    .frame(width: 100)
                    .accentColor(.briefeedRed)
                
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Queue Preview View
    private var queuePreviewView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Up Next")
                    .font(.system(size: 16, weight: .semibold))
                
                Spacer()
                
                Button("See All") {
                    showQueue = true
                }
                .font(.system(size: 14))
                .foregroundColor(.briefeedRed)
            }
            
            // Show next 2 items
            ForEach(audioService.queue.prefix(2)) { article in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(article.title ?? "Unknown")
                            .font(.system(size: 14))
                            .lineLimit(1)
                        
                        Text(article.author ?? article.feed?.name ?? "")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
            }
        }
        .padding(.top, 20)
    }
    
    // MARK: - Helper Methods
    
    private func shareContent() {
        guard let item = audioService.currentPlaybackItem else { return }
        
        let text = "Listening to: \(item.title)"
        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
}

// MARK: - Speed Picker Sheet
extension ExpandedAudioPlayerV2 {
    private var speedPickerSheet: some View {
        NavigationView {
            VStack(spacing: 0) {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                    Button(action: {
                        audioService.setPlaybackSpeed(Float(speed))
                        showSpeedPicker = false
                    }) {
                        HStack {
                            Text(String(format: "%.2fx", speed))
                                .font(.system(size: 18))
                            
                            Spacer()
                            
                            if Float(speed) == audioService.playbackSpeed {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.briefeedRed)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .foregroundColor(.primary)
                    
                    if speed < 2.0 {
                        Divider()
                            .padding(.leading, 20)
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Playback Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showSpeedPicker = false
                    }
                }
            }
        }
    }
}

// MARK: - Sleep Timer Sheet
extension ExpandedAudioPlayerV2 {
    private var sleepTimerSheet: some View {
        NavigationView {
            VStack(spacing: 0) {
                ForEach(SleepTimerOption.allCases, id: \.self) { option in
                    Button(action: {
                        sleepTimer.startTimer(option: option)
                        showSleepTimer = false
                    }) {
                        HStack {
                            Text(option.displayName)
                                .font(.system(size: 18))
                            
                            Spacer()
                            
                            if sleepTimer.isActive && sleepTimer.selectedOption == option {
                                Text(sleepTimer.formattedRemainingTime())
                                    .font(.system(size: 14))
                                    .foregroundColor(.briefeedRed)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .foregroundColor(.primary)
                    
                    Divider()
                        .padding(.leading, 20)
                }
                
                if sleepTimer.isActive {
                    Button(action: {
                        sleepTimer.stopTimer()
                        showSleepTimer = false
                    }) {
                        HStack {
                            Text("Cancel Timer")
                                .font(.system(size: 18))
                                .foregroundColor(.red)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showSleepTimer = false
                    }
                }
            }
        }
    }
}