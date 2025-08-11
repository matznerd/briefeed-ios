//
//  ArticleViewModel.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import Foundation
import CoreData
import Combine
import SwiftUI
import AVFoundation

@MainActor
class ArticleViewModel: ObservableObject {
    @Published var article: Article
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var articleContent: String?
    @Published var summary: String?
    @Published var structuredSummary: FormattedArticleSummary?
    @Published var isGeneratingSummary = false
    @Published var isLoadingContent = false
    @Published var fontSize: CGFloat = 16
    @Published var isReaderMode = false
    
    // Audio playback properties
    @Published var audioState: AudioPlayerState = .idle
    @Published var audioProgress: Float = 0.0
    @Published var audioRate: Float = Constants.Audio.defaultSpeechRate
    
    private let storageService: StorageServiceProtocol
    private let firecrawlService: FirecrawlServiceProtocol
    private let geminiService: GeminiServiceProtocol
    // Audio service removed - now handled through AppViewModel
    
    private var cancellables: Set<AnyCancellable> = []
    
    init(article: Article,
         storageService: StorageServiceProtocol = StorageService.shared,
         firecrawlService: FirecrawlServiceProtocol = FirecrawlService(),
         geminiService: GeminiServiceProtocol = GeminiService()) {
        self.article = article
        self.storageService = storageService
        self.firecrawlService = firecrawlService
        self.geminiService = geminiService
        
        // Load initial values
        self.articleContent = article.content
        self.summary = article.summary
        
        // Load user preferences
        loadUserPreferences()
        
        // Audio subscriptions now handled through AppViewModel
    }
    
    private func loadUserPreferences() {
        // Load font size from user defaults
        let savedFontSize = UserDefaults.standard.double(forKey: "articleFontSize")
        if savedFontSize > 0 {
            fontSize = CGFloat(savedFontSize)
        } else {
            fontSize = 16 // Default size
        }
    }
    
    private func setupAudioSubscriptions() {
        // Audio subscriptions removed - now handled through AppViewModel
    }
    
    func loadArticleContent() async {
        guard articleContent == nil || articleContent?.isEmpty == true,
              let url = article.url else { return }
        
        isLoadingContent = true
        errorMessage = nil
        
        do {
            // Fetch content using Firecrawl
            let response = try await firecrawlService.fetchArticleContent(from: url)
            let content = response.markdown ?? response.content
            articleContent = content
            
            // Save raw content to Core Data
            article.content = content
            try await storageService.saveContext()
            
            // Automatically generate structured summary
            await generateStructuredSummary()
            
            isLoadingContent = false
        } catch {
            errorMessage = "Failed to load article content: \(error.localizedDescription)"
            isLoadingContent = false
        }
    }
    
    func generateStructuredSummary() async {
        guard !isGeneratingSummary else { return }
        
        // Check if we already have a summary
        if let existingSummary = article.summary, !existingSummary.isEmpty {
            // Parse the existing summary as structured summary if possible
            if existingSummary.contains("whatHappened") || existingSummary.contains("who") {
                // This looks like a structured summary JSON, just use it
                summary = existingSummary
            }
            return
        }
        
        isGeneratingSummary = true
        errorMessage = nil
        
        do {
            let content = articleContent ?? article.content ?? ""
            guard !content.isEmpty else {
                throw NSError(domain: "ArticleViewModel", code: 0, userInfo: [NSLocalizedDescriptionKey: "No content available to summarize"])
            }
            
            // Generate structured summary like the Capacitor app
            let structuredResult = try await geminiService.generateStructuredSummary(
                text: content,
                title: article.title
            )
            
            structuredSummary = structuredResult
            
            // If we got a story, save it as the summary
            if let story = structuredResult.story {
                summary = story
                article.summary = story
                try await storageService.saveContext()
            }
            
            isGeneratingSummary = false
        } catch {
            errorMessage = "Failed to generate summary: \(error.localizedDescription)"
            isGeneratingSummary = false
        }
    }
    
    func generateSummary(length: Constants.Summary.Length = .standard) async {
        guard !isGeneratingSummary else { return }
        
        isGeneratingSummary = true
        errorMessage = nil
        
        do {
            let content = articleContent ?? article.content ?? ""
            guard !content.isEmpty else {
                throw NSError(domain: "ArticleViewModel", code: 0, userInfo: [NSLocalizedDescriptionKey: "No content available to summarize"])
            }
            
            let summaryText = try await geminiService.summarize(
                text: content,
                length: length
            )
            
            summary = summaryText
            article.summary = summaryText
            try await storageService.saveContext()
            
            isGeneratingSummary = false
        } catch {
            errorMessage = "Failed to generate summary: \(error.localizedDescription)"
            isGeneratingSummary = false
        }
    }
    
    func markAsRead() async {
        guard !article.isRead else { return }
        
        do {
            try await storageService.markArticleAsRead(article)
        } catch {
            errorMessage = "Failed to mark article as read: \(error.localizedDescription)"
        }
    }
    
    func toggleSaved() async {
        do {
            try await storageService.toggleArticleSaved(article)
        } catch {
            errorMessage = "Failed to save article: \(error.localizedDescription)"
        }
    }
    
    func deleteArticle() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await storageService.deleteArticle(article)
            isLoading = false
        } catch {
            errorMessage = "Failed to delete article: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    var formattedDate: String {
        if let createdAt = article.createdAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: createdAt, relativeTo: Date())
        }
        return ""
    }
    
    var displayURL: String {
        guard let url = article.url else { return "" }
        
        if let host = URL(string: url)?.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return url
    }
    
    var hasValidThumbnail: Bool {
        guard let thumbnail = article.thumbnail,
              !thumbnail.isEmpty,
              thumbnail != "self",
              thumbnail != "default",
              thumbnail != "nsfw",
              thumbnail != "spoiler" else {
            return false
        }
        return true
    }
    
    // MARK: - Audio Playback Methods
    
    func startAudioPlayback() async {
        // Audio playback is now handled through AppViewModel
        // Generate summary if needed for the audio system
        if summary == nil || summary?.isEmpty == true {
            await generateStructuredSummary()
        }
    }
    
    func toggleAudioPlayback() {
        // Audio playback is now handled through AppViewModel
    }
    
    func stopAudioPlayback() {
        // Audio playback is now handled through AppViewModel
    }
    
    func setAudioRate(_ rate: Float) {
        // Audio rate is now handled through AppViewModel
    }
    
    var isAudioPlaying: Bool {
        if case .playing = audioState {
            return true
        }
        return false
    }
    
    var canPlayAudio: Bool {
        let content = articleContent ?? article.content ?? ""
        return !content.isEmpty
    }
}

