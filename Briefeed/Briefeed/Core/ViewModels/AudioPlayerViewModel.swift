//
//  AudioPlayerViewModel.swift
//  Briefeed
//
//  Created by Briefeed Team on 1/13/25.
//
//  CRITICAL: This ViewModel isolates UI state from the audio service
//  to fix the "Publishing changes from within view updates" error.
//

import Foundation
import Combine
import SwiftUI
import SwiftAudioEx
import MediaPlayer

/// ViewModel that manages audio player UI state
/// This is the ONLY ObservableObject that views should use for audio
final class AudioPlayerViewModel: ObservableObject {
    
    // MARK: - Published UI State
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var playbackRate: Float = 1.0
    @Published var volume: Float = 1.0 {
        didSet {
            // Will connect to service later
            updateVolume()
        }
    }
    
    // Current item info
    @Published private(set) var currentTitle: String = ""
    @Published private(set) var currentArtist: String = ""
    @Published private(set) var currentArtwork: UIImage?
    @Published private(set) var hasCurrentItem = false
    
    // Queue info
    @Published private(set) var queueCount: Int = 0
    @Published private(set) var hasNext: Bool = false
    @Published private(set) var hasPrevious: Bool = false
    
    // Playback state
    @Published private(set) var playerState: AudioPlayerState = .idle
    
    // For compatibility with existing views
    @Published var currentArticle: Article?
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?
    
    // CRITICAL: Do NOT access BriefeedAudioService.shared in init()
    // This would trigger singleton initialization and cause the freeze
    private weak var audioService: BriefeedAudioService?
    
    // Flag to ensure we only connect once
    private var hasConnected = false
    
    // MARK: - Initialization
    init() {
        print("🎵 AudioPlayerViewModel: Initializing...")
        // DO NOT access any singletons here
        // DO NOT set up any subscriptions here
        // Everything must be deferred until after view construction
    }
    
    deinit {
        print("🎵 AudioPlayerViewModel: Deinitializing...")
        updateTimer?.invalidate()
    }
    
    // MARK: - Connection (Must be called after view is rendered)
    
    /// Connect to the audio service - MUST be called after view construction
    /// Use .task or .onAppear in the view
    @MainActor
    func connectToService() async {
        guard !hasConnected else { return }
        hasConnected = true
        
        print("🎵 AudioPlayerViewModel: Connecting to audio service...")
        
        // Safely access the service after view construction
        self.audioService = BriefeedAudioService.shared
        
        // Set up polling instead of subscriptions (safer initially)
        startPolling()
        
        // Initial state update
        await updateStateFromService()
    }
    
    // MARK: - State Updates
    
    private func startPolling() {
        // Poll every 0.5 seconds for state updates
        // This is safer than subscriptions during migration
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateStateFromService()
            }
        }
    }
    
    @MainActor
    private func updateStateFromService() async {
        guard let service = audioService else { return }
        
        // Safely read state without triggering changes
        isPlaying = service.isPlaying
        isLoading = service.isLoading
        currentTime = service.currentTime
        duration = service.duration
        playbackRate = service.playbackRate
        
        // Current item info
        if let item = service.currentItem {
            hasCurrentItem = true
            currentTitle = item.content.title
            // Get artist/author from content
            if let article = item.content as? ArticleAudioContent {
                currentArtist = article.author ?? ""
            } else if let episode = item.content as? RSSEpisodeAudioContent {
                currentArtist = episode.feedTitle ?? ""
            } else {
                currentArtist = ""
            }
            
            // Load artwork if available
            if currentArtwork == nil {
                item.getArtwork { [weak self] image in
                    DispatchQueue.main.async {
                        self?.currentArtwork = image
                    }
                }
            }
        } else {
            hasCurrentItem = false
            currentTitle = ""
            currentArtist = ""
            currentArtwork = nil
        }
        
        // Queue info
        queueCount = service.queue.count
        hasNext = service.queueIndex < service.queue.count - 1
        hasPrevious = service.queueIndex > 0
        
        // Playback state
        playerState = service.state.value
        
        // Compatibility
        currentArticle = service.currentArticle
    }
    
    // MARK: - Public Control Methods
    
    func play() {
        print("🎵 AudioPlayerViewModel: Play requested")
        audioService?.play()
    }
    
    func pause() {
        print("🎵 AudioPlayerViewModel: Pause requested")
        audioService?.pause()
    }
    
    func togglePlayPause() {
        print("🎵 AudioPlayerViewModel: Toggle play/pause requested")
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func next() {
        print("🎵 AudioPlayerViewModel: Next requested")
        Task {
            await audioService?.playNext()
        }
    }
    
    func previous() {
        print("🎵 AudioPlayerViewModel: Previous requested")
        Task {
            await audioService?.playPrevious()
        }
    }
    
    func seek(to time: TimeInterval) {
        print("🎵 AudioPlayerViewModel: Seek to \(time) requested")
        audioService?.seek(to: time)
    }
    
    func setPlaybackRate(_ rate: Float) {
        print("🎵 AudioPlayerViewModel: Set playback rate to \(rate)")
        audioService?.setPlaybackRate(rate)
    }
    
    private func updateVolume() {
        audioService?.volume = volume
    }
    
    // MARK: - Queue Management (Delegate to service)
    
    func clearQueue() {
        audioService?.clearQueue()
    }
    
    func removeFromQueue(at index: Int) {
        audioService?.removeFromQueue(at: index)
    }
    
    // MARK: - Cleanup
    
    func disconnect() {
        print("🎵 AudioPlayerViewModel: Disconnecting...")
        updateTimer?.invalidate()
        updateTimer = nil
        cancellables.removeAll()
        hasConnected = false
    }
}

// MARK: - Safe State Reading Extension
extension AudioPlayerViewModel {
    /// Check if we can safely interact with audio
    var canInteract: Bool {
        hasConnected && audioService != nil
    }
    
    /// Format current time for display
    var formattedCurrentTime: String {
        formatTime(currentTime)
    }
    
    /// Format duration for display
    var formattedDuration: String {
        formatTime(duration)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}