//
//  UnifiedAudioPlayer.swift
//  Briefeed
//
//  Bridge between TTS generation and SwiftAudioEx playback
//  Orchestrates the complete audio pipeline
//

import Foundation
import SwiftUI
import AVFoundation
import CoreData
import Combine

// MARK: - Unified Queue Item

/// Unified representation of a queue item (Article or RSS Episode)
@MainActor
class UnifiedQueueItem: ObservableObject, Identifiable {
    let id: String
    let type: QueueItemType
    let title: String
    let content: String?
    let audioURL: URL?
    let article: Article?
    let episode: RSSEpisode?
    
    @Published var generationState: GenerationState = .pending
    @Published var cachedAudioURL: URL?
    @Published var duration: TimeInterval = 0
    
    enum QueueItemType {
        case article
        case rssEpisode
    }
    
    enum GenerationState: Equatable {
        case pending
        case generating
        case ready
        case failed(Error)
        
        static func == (lhs: GenerationState, rhs: GenerationState) -> Bool {
            switch (lhs, rhs) {
            case (.pending, .pending), 
                 (.generating, .generating), 
                 (.ready, .ready):
                return true
            case (.failed(_), .failed(_)):
                return true
            default:
                return false
            }
        }
    }
    
    init(article: Article) {
        self.id = article.objectID.uriRepresentation().absoluteString
        self.type = .article
        self.title = article.title ?? "Untitled"
        self.content = article.summary ?? article.content
        self.audioURL = nil
        self.article = article
        self.episode = nil
    }
    
    init(episode: RSSEpisode) {
        self.id = episode.id ?? UUID().uuidString
        self.type = .rssEpisode
        self.title = episode.title ?? "Untitled Episode"
        self.content = episode.episodeDescription
        self.audioURL = URL(string: episode.audioUrl)
        self.article = nil
        self.episode = episode
    }
}

// MARK: - Unified Audio Player

@MainActor
final class UnifiedAudioPlayer: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = UnifiedAudioPlayer()
    
    // MARK: - Services
    
    private let ttsGenerator = TTSGeneratorService.shared
    private let openAITTS = OpenAITTSServiceSimple.shared
    private let audioPlayer = SwiftAudioExService()
    private let cacheManager = AudioCacheManager.shared
    private var useOpenAITTS: Bool = false  // Toggle for TTS service selection
    
    // MARK: - Published Properties
    
    @Published var queue: [UnifiedQueueItem] = []
    @Published var currentIndex: Int = -1
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var isGenerating: Bool = false
    @Published var generationProgress: String = ""
    
    // MARK: - Current Item
    
    var currentItem: UnifiedQueueItem? {
        guard currentIndex >= 0 && currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }
    
    // MARK: - Private Properties
    
    private var preGenerationTask: Task<Void, Never>?
    private var playbackProgressTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let context = PersistenceController.shared.container.viewContext
    
    // MARK: - Initialization
    
    private init() {
        setupAudioPlayer()
        setupNotifications()
    }
    
    // MARK: - Setup
    
    private func setupAudioPlayer() {
        audioPlayer.delegate = self
    }
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.handleEnterBackground()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.handleEnterForeground()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Queue Management
    
    /// Load queue from articles
    func loadQueue(from articles: [Article]) async {
        queue = articles.map { UnifiedQueueItem(article: $0) }
        currentIndex = -1
        
        // Start pre-generation for first items
        await preGenerateNextItems()
    }
    
    /// Load queue from RSS episodes
    func loadQueue(from episodes: [RSSEpisode]) async {
        queue = episodes.map { UnifiedQueueItem(episode: $0) }
        currentIndex = -1
        
        // RSS episodes don't need TTS generation
        for item in queue {
            if item.audioURL != nil {
                item.generationState = .ready
                item.cachedAudioURL = item.audioURL
            }
        }
    }
    
    /// Load mixed queue
    func loadMixedQueue(items: [Any]) async {
        queue = items.compactMap { item in
            if let article = item as? Article {
                return UnifiedQueueItem(article: article)
            } else if let episode = item as? RSSEpisode {
                return UnifiedQueueItem(episode: episode)
            }
            return nil
        }
        currentIndex = -1
        
        await preGenerateNextItems()
    }
    
    /// Add item to queue
    func addToQueue(_ item: Any) async {
        if let article = item as? Article {
            let queueItem = UnifiedQueueItem(article: article)
            queue.append(queueItem)
            
            // Pre-generate if it's one of the next items
            if queue.count <= 3 {
                await generateAudioForItem(queueItem)
            }
        } else if let episode = item as? RSSEpisode {
            let queueItem = UnifiedQueueItem(episode: episode)
            if queueItem.audioURL != nil {
                queueItem.generationState = .ready
                queueItem.cachedAudioURL = queueItem.audioURL
            }
            queue.append(queueItem)
        }
    }
    
    /// Remove item from queue
    func removeFromQueue(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        
        queue.remove(at: index)
        
        // Adjust current index if needed
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            // Current item was removed, stop playback
            stop()
        }
    }
    
    /// Clear queue
    func clearQueue() {
        stop()
        queue.removeAll()
        currentIndex = -1
    }
    
    // MARK: - Playback Control
    
    /// Play item at index
    func play(at index: Int) async {
        guard index >= 0 && index < queue.count else { return }
        
        currentIndex = index
        let item = queue[index]
        
        // Ensure audio is ready
        if item.generationState != .ready {
            await generateAudioForItem(item)
        }
        
        // Play if generation succeeded
        if let audioURL = item.cachedAudioURL {
            print("[UnifiedPlayer] Attempting to play audio from: \(audioURL.path)")
            print("[UnifiedPlayer] File exists: \(FileManager.default.fileExists(atPath: audioURL.path))")
            
            do {
                // Pass title and artist info for lock screen display
                let artist = item.type == .article ? (item.article?.author ?? "Article") : (item.episode?.feed?.displayName ?? "Podcast")
                try await audioPlayer.play(url: audioURL, title: item.title, artist: artist)
                isPlaying = true
                print("[UnifiedPlayer] Successfully started playback")
                
                // Start pre-generation for next items
                await preGenerateNextItems()
                
                // Update Core Data if it's an article
                if let article = item.article {
                    await markArticleAsListened(article)
                }
                
                // Update RSS episode if needed
                if let episode = item.episode {
                    await markEpisodeAsListened(episode)
                }
            } catch {
                print("[UnifiedPlayer] Failed to play audio: \(error)")
                print("[UnifiedPlayer] Error type: \(type(of: error))")
                item.generationState = .failed(error)
            }
        } else {
            print("[UnifiedPlayer] No cached audio URL available for item: \(item.title)")
        }
    }
    
    /// Play next item
    func playNext() async {
        if currentIndex < queue.count - 1 {
            await play(at: currentIndex + 1)
        }
    }
    
    /// Play previous item
    func playPrevious() async {
        if currentIndex > 0 {
            await play(at: currentIndex - 1)
        }
    }
    
    /// Toggle play/pause
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }
    
    /// Pause playback
    func pause() {
        audioPlayer.pause()
        isPlaying = false
    }
    
    /// Resume playback
    func resume() {
        audioPlayer.resume()
        isPlaying = true
    }
    
    /// Stop playback
    func stop() {
        audioPlayer.stop()
        isPlaying = false
        currentTime = 0
        duration = 0
    }
    
    /// Set playback rate
    func setRate(_ rate: Float) {
        playbackRate = rate
        audioPlayer.setRate(rate)
        
        // Save preference
        UserDefaultsManager.shared.playbackSpeed = rate
    }
    
    /// Seek to time
    func seek(to time: TimeInterval) {
        audioPlayer.seek(to: time)
        currentTime = time
    }
    
    /// Skip forward
    func skipForward(_ seconds: TimeInterval = 30) {
        audioPlayer.skipForward(seconds)
    }
    
    /// Skip backward
    func skipBackward(_ seconds: TimeInterval = 15) {
        audioPlayer.skipBackward(seconds)
    }
    
    // MARK: - TTS Generation
    
    /// Generate audio for a queue item
    private func generateAudioForItem(_ item: UnifiedQueueItem) async {
        // Skip if already ready or generating
        guard item.generationState == .pending else { return }
        
        // RSS episodes don't need generation
        if item.type == .rssEpisode && item.audioURL != nil {
            item.generationState = .ready
            item.cachedAudioURL = item.audioURL
            return
        }
        
        // Generate TTS for articles
        if let article = item.article {
            item.generationState = .generating
            isGenerating = true
            generationProgress = "Generating summary for \(item.title)..."
            
            do {
                print("[UnifiedPlayer] Starting audio generation for article: \(article.title ?? "Unknown")")
                print("[UnifiedPlayer] Article has summary: \(article.summary != nil), summary length: \(article.summary?.count ?? 0)")
                
                // Check if article needs summary generation
                if article.summary == nil || article.summary?.isEmpty == true || article.summary == "Unable to generate summary. The article content may be incomplete or unavailable." {
                    print("[UnifiedPlayer] Article needs summary generation")
                    // Generate summary first
                    generationProgress = "Generating summary..."
                    
                    // Get article content for summarization
                    var contentToSummarize = ""
                    if let content = article.content, !content.isEmpty {
                        contentToSummarize = content.stripHTML
                        print("[UnifiedPlayer] Using existing article content: \(contentToSummarize.count) characters")
                    } else if let url = article.url {
                        print("[UnifiedPlayer] No content stored, fetching from URL: \(url)")
                        // Fetch content from URL if needed
                        generationProgress = "Fetching article content..."
                        let firecrawlService = FirecrawlService()
                        do {
                            let firecrawlData = try await firecrawlService.fetchArticleContent(from: url)
                            // Use best available content (prefers markdown over html over plain)
                            contentToSummarize = firecrawlData.bestContent
                            print("[UnifiedPlayer] Fetched \(contentToSummarize.count) characters from article")
                            
                            // Check if content is too short (might be an error page or paywall)
                            if contentToSummarize.count < 100 {
                                print("[UnifiedPlayer] WARNING: Fetched content is very short, might be incomplete")
                                print("[UnifiedPlayer] Short content: \(contentToSummarize)")
                            }
                        } catch {
                            print("[UnifiedPlayer] Failed to fetch article content: \(error)")
                            // Try to use article description as fallback
                            contentToSummarize = article.content ?? ""
                        }
                    }
                    
                    if !contentToSummarize.isEmpty {
                        // Generate summary using Gemini
                        generationProgress = "Creating summary..."
                        let geminiService = GeminiService()
                        
                        // Smart truncation to avoid token limit while preserving article quality
                        // Gemini 2.5 Flash has ~32k token context, but we'll be conservative
                        // Roughly 4 chars per token, so 20,000 chars ≈ 5,000 tokens
                        // This leaves plenty of room for prompt and response
                        let maxContentLength = 20000
                        
                        let processedContent: String
                        if contentToSummarize.count > maxContentLength {
                            // Try to truncate at a sentence boundary for better context
                            let truncated = String(contentToSummarize.prefix(maxContentLength))
                            if let lastPeriod = truncated.lastIndex(of: ".") {
                                processedContent = String(truncated[...lastPeriod])
                            } else {
                                processedContent = truncated + "..."
                            }
                            print("[UnifiedPlayer] Content truncated from \(contentToSummarize.count) to \(processedContent.count) characters")
                        } else {
                            processedContent = contentToSummarize
                        }
                        
                        // The summarize function now returns plain text
                        print("[UnifiedPlayer] Generating summary from \(processedContent.count) characters of content (original: \(contentToSummarize.count))")
                        print("[UnifiedPlayer] Content to summarize preview: \(processedContent.prefix(500))...")
                        
                        let summaryText: String
                        do {
                            summaryText = try await geminiService.summarize(
                                text: processedContent,
                                length: .standard
                            )
                            print("[UnifiedPlayer] Received summary: \(summaryText.count) characters")
                            print("[UnifiedPlayer] Summary preview: \(summaryText.prefix(200))...")
                        } catch {
                            print("[UnifiedPlayer] Gemini summarization failed: \(error)")
                            // Fallback: Create a simple excerpt from the article
                            let words = processedContent.split(separator: " ").prefix(100).joined(separator: " ")
                            summaryText = "Article excerpt: \(words)..."
                            print("[UnifiedPlayer] Using fallback excerpt instead of summary")
                        }
                        
                        // Check if Gemini couldn't generate a summary
                        if summaryText.contains("cannot provide a summary") || summaryText.contains("I cannot") || summaryText.contains("cannot summarize") {
                            print("[UnifiedPlayer] WARNING: Gemini couldn't generate summary, using fallback")
                            // Log the problematic content for debugging
                            print("[UnifiedPlayer] Problematic content was: \(contentToSummarize.prefix(1000))")
                            
                            // Don't save error message as summary
                            await MainActor.run {
                                article.summary = "Unable to generate summary. The article content may be incomplete or unavailable."
                                try? context.save()
                            }
                            
                            // Mark as failed so it doesn't play
                            item.generationState = .failed(TTSError.generationFailed)
                            throw TTSError.generationFailed
                        }
                        
                        // Remove title from summary if it starts with it
                        var cleanedSummaryText = summaryText
                        if let title = article.title, !title.isEmpty {
                            // Check if summary starts with the title (case insensitive)
                            let titleLower = title.lowercased()
                            let summaryLower = summaryText.lowercased()
                            if summaryLower.hasPrefix(titleLower) {
                                // Remove the title from the beginning
                                let startIndex = summaryText.index(summaryText.startIndex, offsetBy: title.count)
                                cleanedSummaryText = String(summaryText[startIndex...])
                                    .trimmingCharacters(in: CharacterSet(charactersIn: ".:,- "))
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                print("[UnifiedPlayer] Removed duplicate title from summary beginning")
                            }
                        }
                        
                        // Save summary to article
                        if !cleanedSummaryText.isEmpty {
                            await MainActor.run {
                                article.summary = cleanedSummaryText
                                print("[UnifiedPlayer] Saved summary to article: \(cleanedSummaryText.count) characters")
                                try? context.save()
                            }
                        }
                    }
                }
                
                // Now format text for TTS (will include the summary)
                generationProgress = "Generating audio..."
                print("[UnifiedPlayer] Formatting article for TTS...")
                print("[UnifiedPlayer] Article summary status: \(article.summary?.count ?? 0) characters")
                let text = formatArticleForTTS(article)
                print("[UnifiedPlayer] Text for TTS (\(text.count) chars): \(String(text.prefix(200)))...")
                
                // Check if we only have title
                if text.count < 100 && article.title != nil {
                    print("[UnifiedPlayer] WARNING: TTS text is very short, likely only title")
                }
                
                // Generate audio file - try OpenAI first if configured, fallback to Gemini
                let audioURL: URL
                
                if UserDefaultsManager.shared.openAIAPIKey != nil && !UserDefaultsManager.shared.openAIAPIKey!.isEmpty {
                    // Use OpenAI TTS if API key is configured
                    print("[UnifiedPlayer] Using OpenAI TTS for audio generation")
                    do {
                        audioURL = try await openAITTS.generateAudioForArticle(
                            title: article.title,
                            content: text,
                            useStreaming: UserDefaultsManager.shared.useOpenAIStreaming
                        )
                        print("[UnifiedPlayer] OpenAI TTS generated audio successfully")
                    } catch {
                        print("[UnifiedPlayer] OpenAI TTS failed: \(error), falling back to Gemini")
                        // Fallback to Gemini TTS
                        audioURL = try await ttsGenerator.generateAudioFile(
                            from: text,
                            trackingIn: context,
                            for: article
                        )
                    }
                } else {
                    // Use Gemini TTS as primary (but may hit 100/day limit)
                    print("[UnifiedPlayer] Using Gemini TTS (no OpenAI key configured)")
                    do {
                        audioURL = try await ttsGenerator.generateAudioFile(
                            from: text,
                            trackingIn: context,
                            for: article
                        )
                    } catch {
                        // If Gemini fails (possibly due to quota), try to inform user
                        print("[UnifiedPlayer] Gemini TTS failed: \(error)")
                        if error.localizedDescription.contains("quota") || error.localizedDescription.contains("limit") {
                            print("[UnifiedPlayer] Likely hit Gemini 100 generations/day limit. Configure OpenAI API key for unlimited TTS.")
                        }
                        throw error
                    }
                }
                
                item.cachedAudioURL = audioURL
                item.generationState = .ready
                
                // Get duration if possible
                if let player = try? AVAudioPlayer(contentsOf: audioURL) {
                    item.duration = player.duration
                }
                
                print("[UnifiedPlayer] Generated audio for: \(item.title)")
                print("[UnifiedPlayer] Audio URL: \(audioURL.path)")
            } catch {
                print("[UnifiedPlayer] Failed to generate audio: \(error)")
                print("[UnifiedPlayer] Error details: \(error.localizedDescription)")
                item.generationState = .failed(error)
            }
            
            isGenerating = false
            generationProgress = ""
        }
    }
    
    /// Pre-generate audio for next items
    private func preGenerateNextItems() async {
        // Cancel existing pre-generation
        preGenerationTask?.cancel()
        
        preGenerationTask = Task {
            // Generate for current + next 2 items
            let indicesToGenerate = [
                currentIndex,
                currentIndex + 1,
                currentIndex + 2
            ].filter { $0 >= 0 && $0 < queue.count }
            
            for index in indicesToGenerate {
                guard !Task.isCancelled else { break }
                
                let item = queue[index]
                if item.generationState == .pending {
                    await generateAudioForItem(item)
                }
            }
        }
    }
    
    /// Format article for TTS
    private func formatArticleForTTS(_ article: Article) -> String {
        var text = ""
        
        // Add title
        if let title = article.title {
            text += "\(title). "
            print("[UnifiedPlayer] formatArticleForTTS - Added title: \(title)")
        }
        
        // Check if we have a pre-generated summary
        if let summary = article.summary, !summary.isEmpty {
            print("[UnifiedPlayer] formatArticleForTTS - Found summary: \(summary.count) chars")
            // Skip the fallback summary message
            if !summary.contains("Unable to generate summary") && !summary.contains("cannot provide a summary") {
                // Check if summary is JSON and parse it
                if summary.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") ||
                   summary.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```json") {
                    // Parse JSON summary
                    let cleanJson = summary
                        .replacingOccurrences(of: "```json", with: "")
                        .replacingOccurrences(of: "```", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if let jsonData = cleanJson.data(using: .utf8),
                       let summaryResponse = try? JSONDecoder().decode(ArticleSummaryResponse.self, from: jsonData) {
                        // Extract the story text from the parsed JSON
                        if let story = summaryResponse.theStory, !story.isEmpty {
                            text += story
                            print("[UnifiedPlayer] formatArticleForTTS - Parsed and added story from JSON summary")
                        } else if let quickFacts = summaryResponse.quickFacts {
                            // Fallback to quick facts if no story
                            var factsText = ""
                            if quickFacts.whatHappened != "N/A" { factsText += quickFacts.whatHappened + ". " }
                            if quickFacts.who != "N/A" { factsText += "Involving " + quickFacts.who + ". " }
                            if quickFacts.whenWhere != "N/A" { factsText += "This occurred " + quickFacts.whenWhere + ". " }
                            if quickFacts.mostStrikingDetail != "N/A" { factsText += quickFacts.mostStrikingDetail + ". " }
                            text += factsText
                            print("[UnifiedPlayer] formatArticleForTTS - Added quick facts from JSON summary")
                        }
                    } else {
                        // If JSON parsing fails, use the raw summary (might be plain text)
                        text += summary
                        print("[UnifiedPlayer] formatArticleForTTS - Using raw summary (JSON parsing failed)")
                    }
                } else {
                    // Summary is plain text, use directly
                    text += summary
                    print("[UnifiedPlayer] formatArticleForTTS - Added plain text summary to TTS text")
                }
            } else {
                // Use article content as fallback
                if let content = article.content, !content.isEmpty {
                    let cleanContent = content.stripHTML
                        .replacingOccurrences(of: "\n\n", with: ". ")
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Limit content length for TTS
                    if cleanContent.count > 3000 {
                        text += String(cleanContent.prefix(3000)) + "... Content truncated for speech."
                    } else {
                        text += cleanContent
                    }
                } else {
                    text += "Article content not available."
                }
            }
        } else if let content = article.content, !content.isEmpty {
            // No summary, use content directly
            let cleanContent = content.stripHTML
                .replacingOccurrences(of: "\n\n", with: ". ")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Limit content length for TTS
            if cleanContent.count > 3000 {
                text += String(cleanContent.prefix(3000)) + "... Content truncated for speech."
            } else {
                text += cleanContent
            }
        } else {
            // No content available at all
            text += "Article content not available for text-to-speech."
        }
        
        // Ensure we have something meaningful to speak
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 50 {
            print("[UnifiedPlayer] Warning: Article text too short (\(text.count) chars)")
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Core Data Updates
    
    private func markArticleAsListened(_ article: Article) async {
        await context.perform {
            article.isRead = true
            try? self.context.save()
        }
    }
    
    private func markEpisodeAsListened(_ episode: RSSEpisode) async {
        await context.perform {
            episode.isListened = true
            episode.listenedDate = Date()
            try? self.context.save()
        }
    }
    
    // MARK: - Background Handling
    
    private func handleEnterBackground() {
        // Continue playback in background
        if isPlaying {
            // Audio session is already configured for background
        }
    }
    
    private func handleEnterForeground() {
        // Resume UI updates
        if isPlaying {
            startProgressTimer()
        }
    }
    
    private func startProgressTimer() {
        playbackProgressTimer?.invalidate()
        playbackProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                self.updateProgress()
            }
        }
    }
    
    private func updateProgress() {
        currentTime = audioPlayer.currentTime
        duration = audioPlayer.duration
    }
}

// MARK: - SwiftAudioExService Delegate

extension UnifiedAudioPlayer: @preconcurrency SwiftAudioExServiceDelegate {
    
    nonisolated func audioStateChanged(to newState: SwiftAudioPlayerState, from oldState: SwiftAudioPlayerState) {
        Task { @MainActor in
            switch newState {
            case .playing:
                isPlaying = true
                startProgressTimer()
            case .paused:
                isPlaying = false
                playbackProgressTimer?.invalidate()
            case .stopped:
                isPlaying = false
                playbackProgressTimer?.invalidate()
            case .error(let error):
                isPlaying = false
                playbackProgressTimer?.invalidate()
                print("[UnifiedPlayer] Audio error: \(error)")
            default:
                break
            }
        }
    }
    
    nonisolated func audioProgressUpdated(progress: Float, currentTime: TimeInterval, duration: TimeInterval) {
        Task { @MainActor in
            self.currentTime = currentTime
            self.duration = duration
        }
    }
    
    nonisolated func audioRateChanged(to rate: Float) {
        Task { @MainActor in
            self.playbackRate = rate
        }
    }
    
    nonisolated func audioDidFinishPlaying(successfully: Bool) {
        if successfully {
            // Auto-play next item
            Task {
                await playNext()
            }
        }
    }
}

// MARK: - Convenience Methods

extension UnifiedAudioPlayer {
    
    /// Get progress percentage
    var progressPercentage: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    /// Get formatted current time
    var formattedCurrentTime: String {
        formatTime(currentTime)
    }
    
    /// Get formatted duration
    var formattedDuration: String {
        formatTime(duration)
    }
    
    /// Get formatted remaining time
    var formattedRemainingTime: String {
        formatTime(duration - currentTime)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Check if can play next
    var canPlayNext: Bool {
        currentIndex < queue.count - 1
    }
    
    /// Check if can play previous
    var canPlayPrevious: Bool {
        currentIndex > 0
    }
}

// MARK: - Testing Support

#if DEBUG
extension UnifiedAudioPlayer {
    /// Reset for testing
    func resetForTesting() {
        stop()
        clearQueue()
        preGenerationTask?.cancel()
        playbackProgressTimer?.invalidate()
    }
    
    /// Load test queue
    func loadTestQueue() async {
        // Create test articles
        let testArticles = (1...5).map { index in
            let article = Article(context: context)
            article.title = "Test Article \(index)"
            article.summary = "This is test article number \(index). It contains sample content for testing the audio player."
            article.id = UUID()
            return article
        }
        
        await loadQueue(from: testArticles)
    }
}
#endif