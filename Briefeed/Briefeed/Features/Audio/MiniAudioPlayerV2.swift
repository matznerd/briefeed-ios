//
//  MiniAudioPlayerV2.swift
//  Briefeed
//
//  Test version using AudioPlayerViewModel to fix UI freeze
//

import SwiftUI
import Combine

struct MiniAudioPlayerV2: View {
    // CRITICAL CHANGE: Using ViewModel instead of service directly
    @StateObject private var viewModel = AudioPlayerViewModel()
    @StateObject private var queueService = QueueServiceV2.shared
    @StateObject private var stateManager = ArticleStateManager.shared
    @EnvironmentObject var userDefaultsManager: UserDefaultsManager
    @State private var showExpandedPlayer = false
    @State private var progress: Float = 0
    
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
                    if viewModel.hasCurrentItem {
                        Text(viewModel.currentTitle)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        
                        Text(viewModel.currentArtist)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Not Playing")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text("Queue: \(queueService.queue.count) items")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                
                // Playback controls (right side)
                HStack(spacing: 20) {
                    // Previous button
                    Button(action: {
                        viewModel.previous()
                    }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20))
                            .foregroundColor(viewModel.hasPrevious ? .primary : .secondary.opacity(0.5))
                    }
                    .disabled(!viewModel.hasPrevious)
                    
                    // Play/Pause button
                    Button(action: {
                        viewModel.togglePlayPause()
                    }) {
                        ZStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.primary)
                            }
                        }
                        .frame(width: 44, height: 44)
                    }
                    .disabled(!viewModel.hasCurrentItem && queueService.queue.isEmpty)
                    
                    // Next button
                    Button(action: {
                        viewModel.next()
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20))
                            .foregroundColor(viewModel.hasNext ? .primary : .secondary.opacity(0.5))
                    }
                    .disabled(!viewModel.hasNext)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: playerHeight)
            .background(Color(UIColor.systemBackground))
            .onTapGesture {
                if viewModel.hasCurrentItem {
                    showExpandedPlayer = true
                }
            }
        }
        .background(Color(UIColor.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 0.5),
            alignment: .top
        )
        .sheet(isPresented: $showExpandedPlayer) {
            ExpandedAudioPlayer()
        }
        // CRITICAL: Connect to service AFTER view is constructed
        .task {
            print("🎵 MiniAudioPlayerV2: Connecting to audio service...")
            await viewModel.connectToService()
            print("✅ MiniAudioPlayerV2: Connected successfully")
        }
        .onDisappear {
            viewModel.disconnect()
        }
        .onChange(of: viewModel.currentTime) { _ in
            updateProgress()
        }
        .onAppear {
            print("🎵 MiniAudioPlayerV2: View appeared")
            // Auto-play disabled for testing
        }
    }
    
    private func updateProgress() {
        if viewModel.duration > 0 {
            progress = Float(viewModel.currentTime / viewModel.duration)
        } else {
            progress = 0
        }
    }
}

// MARK: - Preview
struct MiniAudioPlayerV2_Previews: PreviewProvider {
    static var previews: some View {
        MiniAudioPlayerV2()
            .environmentObject(UserDefaultsManager.shared)
    }
}