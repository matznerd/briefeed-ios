//
//  MiniAudioPlayerV3.swift
//  Briefeed
//
//  Fixed version using AppViewModel - no singleton @StateObject references
//

import SwiftUI

struct MiniAudioPlayerV3: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var userDefaultsManager: UserDefaultsManager
    @State private var showExpandedPlayer = false
    
    private let playerHeight: CGFloat = 72
    private let progressBarHeight: CGFloat = 3
    
    private var progress: Float {
        if appViewModel.duration > 0 {
            let prog = Float(appViewModel.currentTime / appViewModel.duration)
            // Only log significant changes to avoid spam
            if Int(prog * 100) % 10 == 0 {
                perfLog.log("MiniAudioPlayerV3.progress computed: \(String(format: "%.2f", prog))", category: .view)
            }
            return prog
        }
        return 0
    }
    
    var body: some View {
        let _ = perfLog.logView("MiniAudioPlayerV3", event: .bodyExecuted)
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
                    if appViewModel.isConnectingServices {
                        Text("Connecting...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(height: 12)
                    } else if !appViewModel.currentAudioTitle.isEmpty {
                        Text(appViewModel.currentAudioTitle)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        
                        Text(appViewModel.currentAudioArtist)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Not Playing")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text("Queue: \(appViewModel.queueCount) items")
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
                        print("👆 MiniAudioPlayerV3: Previous button tapped")
                        print("  hasPrevious: \(appViewModel.hasPrevious)")
                        print("  currentIndex: \(appViewModel.currentQueueIndex)")
                        appViewModel.playPrevious()
                    }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20))
                            .foregroundColor(appViewModel.hasPrevious ? .primary : .secondary.opacity(0.5))
                    }
                    .disabled(!appViewModel.hasPrevious)
                    
                    // Play/Pause button
                    Button(action: {
                        print("👆 MiniAudioPlayerV3: Play/Pause button tapped")
                        print("  isPlaying: \(appViewModel.isPlaying)")
                        print("  queueCount: \(appViewModel.queueCount)")
                        print("  currentTitle: \(appViewModel.currentAudioTitle)")
                        appViewModel.togglePlayPause()
                    }) {
                        ZStack {
                            if appViewModel.isAudioLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: appViewModel.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.primary)
                            }
                        }
                        .frame(width: 44, height: 44)
                    }
                    // Fixed: Only disable when queue is truly empty and nothing is playing
                    .disabled(appViewModel.queueCount == 0 && !appViewModel.isPlaying)
                    
                    // Next button
                    Button(action: {
                        print("👆 MiniAudioPlayerV3: Next button tapped")
                        print("  hasNext: \(appViewModel.hasNext)")
                        print("  currentIndex: \(appViewModel.currentQueueIndex)")
                        appViewModel.playNext()
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20))
                            .foregroundColor(appViewModel.hasNext ? .primary : .secondary.opacity(0.5))
                    }
                    .disabled(!appViewModel.hasNext)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: playerHeight)
            .background(Color(UIColor.systemBackground))
            .onTapGesture {
                print("👆 MiniAudioPlayerV3: Main area tapped")
                print("  currentTitle: \(appViewModel.currentAudioTitle)")
                if !appViewModel.currentAudioTitle.isEmpty {
                    print("  Opening expanded player...")
                    showExpandedPlayer = true
                } else {
                    print("  No current title - not opening expanded player")
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
            ExpandedAudioPlayerV2()
                .environmentObject(appViewModel)
        }
        .onAppear {
            perfLog.logView("MiniAudioPlayerV3", event: .appeared)
            perfLog.startOperation("MiniAudioPlayerV3.onAppear")
            print("🎵 MiniAudioPlayerV3: View appeared - Using AppViewModel")
            
            // DEBUG check removed - was causing 10+ second hang
            // Use console logs instead for debugging
            perfLog.endOperation("MiniAudioPlayerV3.onAppear")
        }
        .onDisappear {
            perfLog.logView("MiniAudioPlayerV3", event: .disappeared)
        }
    }
}