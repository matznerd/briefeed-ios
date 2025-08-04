//
//  MockBriefeedAudioService.swift
//  BriefeedTests
//
//  Created by Briefeed Team on 1/8/25.
//

import Foundation
import Combine
@testable import Briefeed

/// Mock implementation of BriefeedAudioService for testing
@MainActor
class MockBriefeedAudioService: ObservableObject {
    // Published properties matching BriefeedAudioService
    @Published var currentItem: BriefeedAudioItem?
    @Published var currentPlaybackItem: CurrentPlaybackItem?
    @Published var playbackContext: PlaybackContext = .direct
    @Published var isLoading = false
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var volume: Float = 1.0
    @Published var queue: [BriefeedAudioItem] = []
    @Published var queueIndex = -1
    @Published var lastError: Error?
    
    // Test control properties
    var playArticleCalled = false
    var playRSSEpisodeCalled = false
    var togglePlayPauseCalled = false
    var playCalled = false
    var pauseCalled = false
    var stopCalled = false
    var seekCalled = false
    var seekToPosition: TimeInterval?
    var skipForwardCalled = false
    var skipBackwardCalled = false
    var setPlaybackRateCalled = false
    var setPlaybackRateValue: Float?
    
    // Queue tracking
    var addToQueueArticleCalled = false
    var addToQueueEpisodeCalled = false
    var lastAddedArticle: Article?
    var lastAddedEpisode: RSSEpisode?
    var playNextCalled = false
    var playPreviousCalled = false
    var removeFromQueueCalled = false
    var clearQueueCalled = false
    
    // History tracking
    var resumeFromHistoryCalled = false
    var lastResumedHistoryItem: PlaybackHistoryItem?
    
    // Sleep timer tracking
    var startSleepTimerCalled = false
    var stopSleepTimerCalled = false
    var lastSleepTimerOption: SleepTimerOption?
    
    // Test helpers
    func reset() {
        playArticleCalled = false
        playRSSEpisodeCalled = false
        togglePlayPauseCalled = false
        playCalled = false
        pauseCalled = false
        stopCalled = false
        seekCalled = false
        seekToPosition = nil
        skipForwardCalled = false
        skipBackwardCalled = false
        setPlaybackRateCalled = false
        setPlaybackRateValue = nil
        addToQueueArticleCalled = false
        addToQueueEpisodeCalled = false
        lastAddedArticle = nil
        lastAddedEpisode = nil
        playNextCalled = false
        playPreviousCalled = false
        removeFromQueueCalled = false
        clearQueueCalled = false
        resumeFromHistoryCalled = false
        lastResumedHistoryItem = nil
        startSleepTimerCalled = false
        stopSleepTimerCalled = false
        lastSleepTimerOption = nil
        
        currentItem = nil
        currentPlaybackItem = nil
        isLoading = false
        isPlaying = false
        currentTime = 0
        duration = 0
        playbackRate = 1.0
        queue = []
        queueIndex = -1
        lastError = nil
    }
    
    // Simulate successful playback
    func simulatePlaybackStart(item: BriefeedAudioItem, duration: TimeInterval = 180) {
        currentItem = item
        currentPlaybackItem = CurrentPlaybackItem(from: item)
        isLoading = false
        isPlaying = true
        self.duration = duration
        currentTime = 0
    }
    
    // Simulate playback progress
    func simulateProgress(to time: TimeInterval) {
        currentTime = min(time, duration)
    }
    
    // Simulate playback error
    func simulateError(_ error: Error) {
        isLoading = false
        isPlaying = false
        lastError = error
    }
}

// MARK: - BriefeedAudioService Interface Implementation
extension MockBriefeedAudioService {
    func playArticle(_ article: Article, context: PlaybackContext = .direct) async {
        playArticleCalled = true
        playbackContext = context
        isLoading = true
        
        // Simulate successful TTS generation and playback
        let audioContent = ArticleAudioContent(article: article)
        let audioItem = BriefeedAudioItem(
            content: audioContent,
            audioURL: URL(string: "file:///mock/audio.m4a"),
            isTemporary: false
        )
        
        simulatePlaybackStart(item: audioItem)
    }
    
    func playRSSEpisode(_ episode: RSSEpisode, context: PlaybackContext = .direct) async {
        playRSSEpisodeCalled = true
        playbackContext = context
        isLoading = true
        
        // Simulate RSS playback
        if let audioURL = URL(string: episode.audioUrl) {
            let audioContent = RSSEpisodeAudioContent(episode: episode)
            let audioItem = BriefeedAudioItem(
                content: audioContent,
                audioURL: audioURL,
                isTemporary: false
            )
            
            simulatePlaybackStart(item: audioItem, duration: TimeInterval(episode.duration))
        }
    }
    
    func togglePlayPause() {
        togglePlayPauseCalled = true
        isPlaying.toggle()
    }
    
    func play() {
        playCalled = true
        isPlaying = true
    }
    
    func pause() {
        pauseCalled = true
        isPlaying = false
    }
    
    func stop() {
        stopCalled = true
        isPlaying = false
        currentTime = 0
        currentItem = nil
        currentPlaybackItem = nil
    }
    
    func seek(to position: TimeInterval) {
        seekCalled = true
        seekToPosition = position
        currentTime = min(max(0, position), duration)
    }
    
    func skipForward() {
        skipForwardCalled = true
        let interval: TimeInterval = currentItem?.content.contentType == .article ? 15 : 30
        seek(to: currentTime + interval)
    }
    
    func skipBackward() {
        skipBackwardCalled = true
        let interval: TimeInterval = currentItem?.content.contentType == .article ? 15 : 30
        seek(to: max(0, currentTime - interval))
    }
    
    func setPlaybackRate(_ rate: Float) {
        setPlaybackRateCalled = true
        setPlaybackRateValue = rate
        playbackRate = max(0.5, min(2.0, rate))
    }
    
    func addToQueue(_ article: Article) async {
        addToQueueArticleCalled = true
        lastAddedArticle = article
        
        let audioContent = ArticleAudioContent(article: article)
        let audioItem = BriefeedAudioItem(content: audioContent)
        queue.append(audioItem)
    }
    
    func addToQueue(_ episode: RSSEpisode) {
        addToQueueEpisodeCalled = true
        lastAddedEpisode = episode
        
        if let audioURL = URL(string: episode.audioUrl) {
            let audioContent = RSSEpisodeAudioContent(episode: episode)
            let audioItem = BriefeedAudioItem(
                content: audioContent,
                audioURL: audioURL,
                isTemporary: false
            )
            queue.append(audioItem)
        }
    }
    
    func playNext() async {
        playNextCalled = true
        
        guard queueIndex + 1 < queue.count else { return }
        queueIndex += 1
        let nextItem = queue[queueIndex]
        simulatePlaybackStart(item: nextItem)
    }
    
    func playPrevious() async {
        playPreviousCalled = true
        
        guard queueIndex > 0 else { return }
        queueIndex -= 1
        let previousItem = queue[queueIndex]
        simulatePlaybackStart(item: previousItem)
    }
    
    func removeFromQueue(at index: Int) {
        removeFromQueueCalled = true
        
        guard index >= 0 && index < queue.count else { return }
        queue.remove(at: index)
        
        if index < queueIndex {
            queueIndex -= 1
        } else if index == queueIndex {
            stop()
            queueIndex = min(queueIndex, queue.count - 1)
        }
    }
    
    func clearQueue() {
        clearQueueCalled = true
        queue.removeAll()
        queueIndex = -1
        stop()
    }
    
    func resumeFromHistory(_ historyItem: PlaybackHistoryItem) async {
        resumeFromHistoryCalled = true
        lastResumedHistoryItem = historyItem
        
        // Simulate resuming playback
        // In real implementation, this would fetch the article/episode and resume
    }
    
    func startSleepTimer(option: SleepTimerOption) {
        startSleepTimerCalled = true
        lastSleepTimerOption = option
    }
    
    func stopSleepTimer() {
        stopSleepTimerCalled = true
    }
}