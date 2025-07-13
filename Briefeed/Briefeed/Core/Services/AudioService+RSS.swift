//
//  AudioService+RSS.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import Foundation
import AVFoundation
import MediaPlayer

// MARK: - RSS Audio Extension
extension AudioService {
    
    // MARK: - RSS Properties
    private var currentRSSEpisode: RSSEpisode? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.currentRSSEpisode) as? RSSEpisode
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.currentRSSEpisode, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var rssAudioPlayer: AVPlayer? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.rssAudioPlayer) as? AVPlayer
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.rssAudioPlayer, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var progressObserver: Any? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.progressObserver) as Any?
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.progressObserver, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    // MARK: - RSS Playback Methods
    
    /// Play RSS episode from URL
    @MainActor
    func playRSSEpisode(url: URL, title: String, episode: RSSEpisode? = nil) async {
        print("🎙️ Playing RSS episode: \(title)")
        
        // Stop any current playback
        stop()
        
        // Clean up previous RSS player
        cleanupRSSPlayer()
        
        // Update state
        state.send(.loading)
        currentRSSEpisode = episode
        isUsingGeminiTTS = false // Flag to indicate RSS audio
        
        do {
            // Configure audio session
            try configureBackgroundAudio()
            
            // Create player item
            let playerItem = AVPlayerItem(url: url)
            
            // Create player
            rssAudioPlayer = AVPlayer(playerItem: playerItem)
            rssAudioPlayer?.volume = volume
            
            // Set up progress observer
            setupProgressObserver()
            
            // Update Now Playing info
            updateNowPlayingForRSS(title: title, episode: episode)
            
            // Start playback
            rssAudioPlayer?.play()
            state.send(.playing)
            
            // Observe when playback ends
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(rssPlaybackDidFinish),
                name: .AVPlayerItemDidPlayToEndTime,
                object: playerItem
            )
            
        } catch {
            print("❌ Error playing RSS episode: \(error)")
            state.send(.error(error))
        }
    }
    
    /// Resume RSS playback at saved position
    @MainActor
    func resumeRSSEpisode(_ episode: RSSEpisode) async {
        guard let url = URL(string: episode.audioUrl) else { return }
        
        await playRSSEpisode(url: url, title: episode.title, episode: episode)
        
        // Seek to saved position
        if episode.lastPosition > 0 {
            let duration = rssAudioPlayer?.currentItem?.duration.seconds ?? 0
            let seekTime = duration * episode.lastPosition
            let time = CMTime(seconds: seekTime, preferredTimescale: 1000)
            rssAudioPlayer?.seek(to: time)
        }
    }
    
    /// Check if currently playing RSS
    var isPlayingRSS: Bool {
        return rssAudioPlayer != nil && rssAudioPlayer?.rate ?? 0 > 0
    }
    
    /// Play for RSS
    func playRSS() {
        guard let player = rssAudioPlayer else { return }
        player.play()
        state.send(.playing)
        updateNowPlayingPlaybackState()
    }
    
    /// Pause for RSS
    func pauseRSS() {
        guard let player = rssAudioPlayer else { return }
        player.pause()
        state.send(.paused)
        updateNowPlayingPlaybackState()
        saveRSSProgress()
    }
    
    /// Stop RSS playback
    func stopRSS() {
        saveRSSProgress()
        cleanupRSSPlayer()
        state.send(.stopped)
    }
    
    /// Skip forward in RSS
    func skipForwardRSS(seconds: TimeInterval) {
        guard let player = rssAudioPlayer else { return }
        
        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(currentTime, CMTime(seconds: seconds, preferredTimescale: 1000))
        player.seek(to: newTime)
    }
    
    /// Skip backward in RSS
    func skipBackwardRSS(seconds: TimeInterval) {
        guard let player = rssAudioPlayer else { return }
        
        let currentTime = player.currentTime()
        let newTime = CMTimeSubtract(currentTime, CMTime(seconds: seconds, preferredTimescale: 1000))
        player.seek(to: newTime)
    }
    
    // MARK: - Private Methods
    
    private func setupProgressObserver() {
        // Remove existing observer
        if let observer = progressObserver {
            rssAudioPlayer?.removeTimeObserver(observer)
        }
        
        // Add new observer
        let interval = CMTime(seconds: 1.0, preferredTimescale: 1000)
        progressObserver = rssAudioPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updateRSSProgress(time: time)
        }
    }
    
    private func updateRSSProgress(time: CMTime) {
        guard let duration = rssAudioPlayer?.currentItem?.duration,
              duration.isNumeric && !duration.isIndefinite else { return }
        
        let currentSeconds = time.seconds
        let totalSeconds = duration.seconds
        
        // Update published properties
        currentTime = currentSeconds
        self.duration = totalSeconds
        
        // Update progress (0.0 to 1.0)
        let progressValue = Float(currentSeconds / totalSeconds)
        progress.send(progressValue)
        
        // Update Now Playing info
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentSeconds
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = totalSeconds
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        
        // Save progress periodically (every 10 seconds)
        if Int(currentSeconds) % 10 == 0 {
            saveRSSProgress()
        }
    }
    
    private func saveRSSProgress() {
        guard let episode = currentRSSEpisode,
              let duration = rssAudioPlayer?.currentItem?.duration,
              duration.isNumeric && !duration.isIndefinite else { return }
        
        let currentTime = rssAudioPlayer?.currentTime().seconds ?? 0
        let totalTime = duration.seconds
        let progress = currentTime / totalTime
        
        // Update episode progress
        episode.updateProgress(progress)
        
        // Update queue item progress
        if let queueItem = QueueService.shared.enhancedQueue.first(where: { 
            $0.audioUrl?.absoluteString == episode.audioUrl 
        }) {
            QueueService.shared.updateRSSProgress(itemId: queueItem.id, progress: progress)
        }
        
        // Save Core Data
        try? episode.managedObjectContext?.save()
    }
    
    private func cleanupRSSPlayer() {
        // Remove observer
        if let observer = progressObserver {
            rssAudioPlayer?.removeTimeObserver(observer)
            progressObserver = nil
        }
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        
        // Clean up player
        rssAudioPlayer?.pause()
        rssAudioPlayer = nil
        currentRSSEpisode = nil
    }
    
    @objc private func rssPlaybackDidFinish() {
        print("🎙️ RSS episode finished playing")
        
        // Mark episode as listened
        if let episode = currentRSSEpisode {
            episode.markAsListened()
            try? episode.managedObjectContext?.save()
            
            // Remove from queue
            if let queueItem = QueueService.shared.enhancedQueue.first(where: {
                $0.audioUrl?.absoluteString == episode.audioUrl
            }) {
                QueueService.shared.markRSSListened(itemId: queueItem.id)
            }
        }
        
        // Clean up
        cleanupRSSPlayer()
        
        // Play next if auto-play is enabled
        if UserDefaultsManager.shared.autoPlayNext {
            playNext()
        } else {
            state.send(.stopped)
        }
    }
    
    private func updateNowPlayingForRSS(title: String, episode: RSSEpisode?) {
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyArtist] = episode?.feed?.displayName ?? "Live News"
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "Briefeed"
        
        // Set artwork if available (placeholder for now)
        if let image = UIImage(systemName: "dot.radiowaves.left.and.right") {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // MARK: - Override Methods
    
    /// Override play to handle RSS
    func playWithRSSSupport() {
        if rssAudioPlayer != nil {
            playRSS()
        } else {
            play() // Call original play method
        }
    }
    
    /// Override pause to handle RSS
    func pauseWithRSSSupport() {
        if rssAudioPlayer != nil {
            pauseRSS()
        } else {
            pause() // Call original pause method
        }
    }
    
    /// Override stop to handle RSS
    func stopWithRSSSupport() {
        if rssAudioPlayer != nil {
            stopRSS()
        }
        stop() // Call original stop method
    }
    
    /// Override skip methods
    func skipForwardWithRSSSupport(seconds: TimeInterval) {
        if rssAudioPlayer != nil {
            skipForwardRSS(seconds: seconds)
        } else {
            skipForward(seconds: seconds)
        }
    }
    
    func skipBackwardWithRSSSupport(seconds: TimeInterval) {
        if rssAudioPlayer != nil {
            skipBackwardRSS(seconds: seconds)
        } else {
            skipBackward(seconds: seconds)
        }
    }
}

// MARK: - Associated Keys
private struct AssociatedKeys {
    static var currentRSSEpisode = "currentRSSEpisode"
    static var rssAudioPlayer = "rssAudioPlayer"
    static var progressObserver = "progressObserver"
}