//
//  ArticleStateManager.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import Foundation
import SwiftUI
import Combine

/// Singleton manager that tracks the real-time state of articles across the app
@MainActor
class ArticleStateManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = ArticleStateManager()
    
    // MARK: - Published Properties
    @Published private(set) var currentlyPlayingArticleID: UUID?
    @Published private(set) var archivedArticleIDs: Set<UUID> = []
    @Published private(set) var queuedArticleIDs: [UUID] = []
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private let audioService = AudioService.shared
    private let archivedService = ArchivedArticlesService.shared
    
    // MARK: - Initialization
    private init() {
        setupObservers()
    }
    
    // MARK: - Setup
    private func setupObservers() {
        // Observe audio service for currently playing article
        audioService.$currentArticle
            .map { $0?.id }
            .assign(to: &$currentlyPlayingArticleID)
        
        // Observe audio service for queue
        audioService.$queue
            .map { articles in
                articles.compactMap { $0.id }
            }
            .assign(to: &$queuedArticleIDs)
        
        // Observe archived articles service
        archivedService.$archivedArticleIDs
            .assign(to: &$archivedArticleIDs)
        
        // Observe audio state changes
        audioService.state
            .sink { [weak self] state in
                // Force UI update when state changes
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Checks if an article is currently playing
    func isPlaying(_ article: Article) -> Bool {
        guard let articleID = article.id else { return false }
        return currentlyPlayingArticleID == articleID
    }
    
    /// Checks if an article is currently playing with a specific state
    func isPlaying(_ article: Article, withState state: AudioPlayerState) -> Bool {
        guard isPlaying(article) else { return false }
        return audioService.state.value == state
    }
    
    /// Checks if an article is archived
    func isArchived(_ article: Article) -> Bool {
        guard let articleID = article.id else { return false }
        return archivedArticleIDs.contains(articleID)
    }
    
    /// Checks if an article is in the queue
    func isQueued(_ article: Article) -> Bool {
        guard let articleID = article.id else { return false }
        return queuedArticleIDs.contains(articleID)
    }
    
    /// Gets the queue position of an article (returns nil if not in queue)
    func queuePosition(for article: Article) -> Int? {
        guard let articleID = article.id else { return nil }
        return queuedArticleIDs.firstIndex(of: articleID)
    }
    
    /// Checks if audio is currently playing
    var isAudioPlaying: Bool {
        audioService.state.value == .playing
    }
    
    /// Checks if audio is currently paused
    var isAudioPaused: Bool {
        audioService.state.value == .paused
    }
    
    /// Checks if audio is currently loading
    var isAudioLoading: Bool {
        audioService.state.value == .loading
    }
    
    /// Gets the current audio state
    var audioState: AudioPlayerState {
        audioService.state.value
    }
    
    /// Updates an article's playing state
    func updatePlayingState(for article: Article) async throws {
        if isPlaying(article) {
            // If playing, pause or stop
            if isAudioPlaying {
                audioService.pause()
            } else {
                audioService.play()
            }
        } else {
            // Start playing this article
            try await audioService.playArticle(article)
        }
    }
    
    /// Toggles an article's archived state
    func toggleArchiveState(for article: Article) {
        archivedService.toggleArchiveStatus(article)
    }
    
    /// Adds an article to the queue
    func addToQueue(_ article: Article) {
        audioService.addToQueue(article)
    }
    
    /// Removes an article from the queue
    func removeFromQueue(at index: Int) {
        audioService.removeFromQueue(at: index)
    }
    
    /// Clears all states (useful for logout/reset)
    func reset() {
        audioService.clearQueue()
        currentlyPlayingArticleID = nil
        // Note: archived articles are managed by ArchivedArticlesService
    }
}

// MARK: - Convenience Extensions
extension Article {
    /// Check if this article is currently playing
    @MainActor
    var isPlaying: Bool {
        ArticleStateManager.shared.isPlaying(self)
    }
    
    /// Check if this article is in the queue
    @MainActor
    var isQueued: Bool {
        ArticleStateManager.shared.isQueued(self)
    }
    
    /// Get the queue position of this article
    @MainActor
    var queuePosition: Int? {
        ArticleStateManager.shared.queuePosition(for: self)
    }
}