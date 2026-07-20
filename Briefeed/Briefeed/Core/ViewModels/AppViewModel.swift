//
//  AppViewModel.swift
//  Briefeed
//
//  Central ViewModel for app-wide state management
//  This replaces direct service access throughout the app
//

import Foundation
import SwiftUI
import Combine
import CoreData

@MainActor
final class AppViewModel: ObservableObject {
    
    // MARK: - Published State
    
    // Audio Player State
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTitle: String?
    @Published private(set) var currentArtist: String?
    @Published private(set) var progress: Float = 0
    @Published private(set) var playbackSpeed: Float = 1.0
    @Published private(set) var activePlaybackMode: ActivePlaybackMode = .none
    @Published private(set) var radioState: RadioSessionState = .idle
    @Published private(set) var radioEntries: [RadioQueueEntry] = []
    @Published private(set) var radioSleepTimer: RadioSleepTimer = .off
    @Published private(set) var radioSourceFailures: [String: String] = [:]
    
    // Queue State
    @Published private(set) var queueItems: [UnifiedQueueItem] = []
    @Published private(set) var queueCount: Int = 0
    
    // Article State
    @Published private(set) var currentlyPlayingArticleID: UUID?
    @Published private(set) var queuedArticleIDs: Set<UUID> = []
    @Published private(set) var archivedArticleIDs: Set<UUID> = []
    
    // Loading State
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?
    
    // MARK: - Private Properties
    
    private let audioPlayerViewModel: AudioPlayerViewModelV2
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(audioPlayerViewModel: AudioPlayerViewModelV2) {
        self.audioPlayerViewModel = audioPlayerViewModel
        setupBindings()
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Bind audio player state
        audioPlayerViewModel.$isPlaying
            .assign(to: &$isPlaying)
        
        audioPlayerViewModel.$currentTitle
            .assign(to: &$currentTitle)
        
        audioPlayerViewModel.$currentArtist
            .assign(to: &$currentArtist)
        
        audioPlayerViewModel.$progress
            .assign(to: &$progress)
        
        audioPlayerViewModel.$playbackSpeed
            .assign(to: &$playbackSpeed)

        audioPlayerViewModel.$activeMode.assign(to: &$activePlaybackMode)
        audioPlayerViewModel.$radioState.assign(to: &$radioState)
        audioPlayerViewModel.$radioEntries.assign(to: &$radioEntries)
        audioPlayerViewModel.$sleepTimer.assign(to: &$radioSleepTimer)
        audioPlayerViewModel.$sourceFailures.assign(to: &$radioSourceFailures)
        
        audioPlayerViewModel.$queueItems
            .sink { [weak self] items in
                self?.queueItems = items
                self?.queuedArticleIDs = Set(items.compactMap { $0.article?.id })
            }
            .store(in: &cancellables)
        
        audioPlayerViewModel.$queueItems
            .map { $0.count }
            .assign(to: &$queueCount)
        
        audioPlayerViewModel.$isLoading
            .assign(to: &$isLoading)

        audioPlayerViewModel.$lastError
            .assign(to: &$lastError)

        // Derive currently playing article ID from queue index changes
        audioPlayerViewModel.$currentQueueIndex
            .combineLatest(audioPlayerViewModel.$queueItems)
            .map { index, items -> UUID? in
                guard index >= 0, index < items.count else { return nil }
                return items[index].article?.id
            }
            .assign(to: &$currentlyPlayingArticleID)
    }
    
    // MARK: - Audio Playback
    
    func play(article: Article) async {
        await audioPlayerViewModel.play(article: article)
    }
    
    func play(episode: RSSEpisode) async {
        await audioPlayerViewModel.play(episode: episode)
    }

    func playRadio() async {
        await audioPlayerViewModel.playRadio()
    }

    func playRadioEpisode(_ key: RadioEpisodeKey) async {
        await audioPlayerViewModel.playRadioEpisode(key)
    }

    func retryRadio() async {
        await audioPlayerViewModel.retryRadio()
    }

    func refreshRadio() async {
        await audioPlayerViewModel.refreshRadio()
    }

    func setRadioSleepTimer(_ timer: RadioSleepTimer) {
        audioPlayerViewModel.setSleepTimer(timer)
    }

    func cancelRadioSleepTimer() {
        audioPlayerViewModel.cancelSleepTimer()
    }
    
    func togglePlayPause() {
        audioPlayerViewModel.togglePlayPause()
    }
    
    func pause() {
        audioPlayerViewModel.pause()
    }
    
    func stop() {
        audioPlayerViewModel.stop()
    }
    
    func skipForward() {
        audioPlayerViewModel.skipForward()
    }
    
    func skipBackward() {
        audioPlayerViewModel.skipBackward()
    }
    
    func setSpeed(_ speed: Float) {
        audioPlayerViewModel.setSpeed(speed)
    }
    
    // MARK: - Queue Management
    
    func queueArticle(_ article: Article) async {
        await audioPlayerViewModel.queueArticle(article)

        // Update queued article IDs
        if let articleID = article.id {
            queuedArticleIDs.insert(articleID)
        }
    }
    
    func queueEpisode(_ episode: RSSEpisode) async {
        await audioPlayerViewModel.queueEpisode(episode)
    }
    
    func removeFromQueue(at index: Int) async {
        if index < queueItems.count {
            let item = queueItems[index]
            if let articleID = item.articleID {
                queuedArticleIDs.remove(articleID)
            }
        }
        await audioPlayerViewModel.removeFromQueue(at: index)
    }
    
    func clearQueue() async {
        queuedArticleIDs.removeAll()
        await audioPlayerViewModel.clearQueue()
    }
    
    func playNextInQueue() {
        audioPlayerViewModel.playNextInQueue()
    }
    
    func playPreviousInQueue() {
        audioPlayerViewModel.playPreviousInQueue()
    }
    
    func reorderQueue(from source: IndexSet, to destination: Int) async {
        await audioPlayerViewModel.reorderQueue(from: source, to: destination)
    }
    
    // MARK: - Article State Management
    
    func isArticleQueued(_ article: Article) -> Bool {
        guard let articleID = article.id else { return false }
        return queuedArticleIDs.contains(articleID) || queueItems.contains { $0.article?.id == articleID }
    }

    func isArticleArchived(_ article: Article) -> Bool {
        guard let articleID = article.id else { return false }
        return archivedArticleIDs.contains(articleID)
    }

    func isArticlePlaying(_ article: Article) -> Bool {
        guard let articleID = article.id else { return false }
        return currentlyPlayingArticleID == articleID
    }

    func archiveArticle(_ article: Article) {
        guard let articleID = article.id else { return }
        archivedArticleIDs.insert(articleID)
        article.isArchived = true
        try? article.managedObjectContext?.save()
        ArticleStateManagerV2.shared.addToArchived(articleID: articleID)
    }

    func unarchiveArticle(_ article: Article) {
        guard let articleID = article.id else { return }
        archivedArticleIDs.remove(articleID)
        article.isArchived = false
        try? article.managedObjectContext?.save()
        ArticleStateManagerV2.shared.removeFromArchived(articleID: articleID)
    }
    
    // MARK: - Queue Position
    
    func queuePosition(for article: Article) -> Int? {
        guard let articleID = article.id else { return nil }
        return queueItems.firstIndex { $0.articleID == articleID }
    }
    
    // MARK: - Error Handling
    
    func clearError() {
        // Clear error through retry method since lastError is read-only
        lastError = nil
    }
    
    func retry() async {
        // Clear error and try to resume playback if needed
        lastError = nil
        if !isPlaying && currentTitle != nil {
            audioPlayerViewModel.togglePlayPause()
        }
    }
    
    // MARK: - Connection
    
    func connect() async {
        // AudioPlayerViewModelV2 doesn't need connect - it's lightweight
        // Just load initial article state
        await loadArticleState()
    }
    
    private func loadArticleState() async {
        let stateManager = ArticleStateManagerV2.shared
        await stateManager.initialize()
        
        queuedArticleIDs = Set(stateManager.queuedArticleIDs)
        archivedArticleIDs = stateManager.archivedArticleIDs
        currentlyPlayingArticleID = stateManager.currentlyPlayingArticleID
    }
    
    // MARK: - Helpers
    
    var hasCurrentItem: Bool {
        currentTitle != nil
    }
    
    var canSkip: Bool {
        hasCurrentItem
    }
    
    var isQueueEmpty: Bool {
        queueItems.isEmpty
    }
    
    var nextInQueue: UnifiedQueueItem? {
        guard audioPlayerViewModel.currentQueueIndex + 1 < queueItems.count else { return nil }
        return queueItems[audioPlayerViewModel.currentQueueIndex + 1]
    }
}
