//
//  UnifiedAudioPlayer.swift
//  Briefeed
//
//  Bridge between TTS generation and SwiftAudioEx playback
//  Orchestrates the complete audio pipeline
//
//  NOTE: Queue state is managed by QueueCoordinator (single source of truth).
//  This player focuses on playback and audio generation.
//

import Foundation
import SwiftUI
import AVFoundation
import CoreData
import Combine

// MARK: - Unified Queue Item (Legacy - kept for compatibility)

/// Unified representation of a queue item (Article or RSS Episode)
/// NOTE: Consider migrating to use QueueItem from QueueCoordinator directly
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
        let episodeID = episode.id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = episodeID.isEmpty ? episode.objectID.uriRepresentation().absoluteString : episodeID
        self.type = .rssEpisode
        let title = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.isEmpty ? "Untitled Episode" : title
        self.content = episode.episodeDescription
        self.audioURL = URL(string: episode.audioUrl)
        self.article = nil
        self.episode = episode
    }

    /// Create from QueueItem (for compatibility with QueueCoordinator)
    init(from queueItem: QueueItem, article: Article? = nil, episode: RSSEpisode? = nil) {
        self.id = queueItem.id.uuidString
        self.type = queueItem.isArticle ? .article : .rssEpisode
        self.title = queueItem.title
        self.content = nil
        self.audioURL = queueItem.streamURL
        self.article = article
        self.episode = episode

        let resolvedAudioURL = queueItem.cachedAudioURL ?? queueItem.streamURL
        self.cachedAudioURL = resolvedAudioURL

        // Map QueueItem state to audio generation state.
        // For playback, "ready" means we have an audio URL (cached or stream).
        switch queueItem.summaryState {
        case .failed:
            self.generationState = .failed(NSError(domain: "QueueItem", code: -1))
        case .generating:
            self.generationState = .generating
        case .pending, .ready:
            self.generationState = resolvedAudioURL != nil ? .ready : .pending
        }
    }
}

// MARK: - Generation Phase

/// Detailed generation phase tracking for better user feedback
/// Provides granular status during the TTS pipeline
enum GenerationPhase: Equatable {
    case idle
    case checkingCache(title: String)
    case fetchingContent(domain: String)
    case summarizing(wordCount: Int, provider: String)
    case generatingAudio(provider: String)
    case downloadingAudio(progress: Double)  // 0.0 to 1.0
    case finalizing
    case failed(message: String)

    /// Human-readable status message for display
    var displayMessage: String {
        switch self {
        case .idle:
            return ""
        case .checkingCache(let title):
            return "Checking cache for \(title.prefix(30))..."
        case .fetchingContent(let domain):
            return "Fetching from \(domain)..."
        case .summarizing(let wordCount, let provider):
            let wordStr = wordCount > 0 ? "\(wordCount) words" : "content"
            return "Summarizing \(wordStr) via \(provider)..."
        case .generatingAudio(let provider):
            return "Generating audio via \(provider)..."
        case .downloadingAudio(let progress):
            let percent = Int(progress * 100)
            return "Downloading audio... \(percent)%"
        case .finalizing:
            return "Preparing playback..."
        case .failed(let message):
            return "Error: \(message)"
        }
    }

    /// Short status for compact display
    var shortMessage: String {
        switch self {
        case .idle:
            return ""
        case .checkingCache:
            return "Checking cache..."
        case .fetchingContent:
            return "Fetching article..."
        case .summarizing(_, let provider):
            return "Summarizing (\(provider))..."
        case .generatingAudio(let provider):
            return "Audio (\(provider))..."
        case .downloadingAudio(let progress):
            return "Downloading \(Int(progress * 100))%..."
        case .finalizing:
            return "Preparing..."
        case .failed:
            return "Failed"
        }
    }

    /// Whether this phase indicates active work
    var isActive: Bool {
        switch self {
        case .idle, .failed:
            return false
        default:
            return true
        }
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
    private let queueCoordinator = QueueCoordinator.shared

    // MARK: - Published Properties

    /// Queue items - derived from QueueCoordinator with Core Data objects attached
    /// NOTE: This is a cached view, rebuilt when QueueCoordinator.queue changes
    @Published private(set) var queue: [UnifiedQueueItem] = []

    /// Current index - synced from QueueCoordinator
    @Published private(set) var currentIndex: Int = -1

    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var isGenerating: Bool = false
    @Published var generationPhase: GenerationPhase = .idle

    /// Display string for generation progress (derived from generationPhase)
    var generationProgress: String {
        generationPhase.displayMessage
    }

    // MARK: - Live News Streaming (temporary, not persisted)

    /// Temporary streaming queue for Live News (not persisted to Brief)
    @Published private(set) var liveNewsStreamQueue: [UnifiedQueueItem] = []
    @Published private(set) var isStreamingLiveNews: Bool = false
    @Published private(set) var liveNewsStreamIndex: Int = -1

    // MARK: - Current Item

    var currentItem: UnifiedQueueItem? {
        if isStreamingLiveNews {
            // Use Live News stream queue
            guard liveNewsStreamIndex >= 0 && liveNewsStreamIndex < liveNewsStreamQueue.count else { return nil }
            return liveNewsStreamQueue[liveNewsStreamIndex]
        } else {
            // Use Brief queue
            guard currentIndex >= 0 && currentIndex < queue.count else { return nil }
            return queue[currentIndex]
        }
    }

    /// Get current QueueItem from coordinator (only valid when not streaming Live News)
    var currentQueueItem: QueueItem? {
        isStreamingLiveNews ? nil : queueCoordinator.currentItem
    }

    // MARK: - Private Properties

    private var preGenerationTask: Task<Void, Never>?
    private var playbackProgressTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let context = PersistenceController.shared.container.viewContext

    private var pendingSeekTime: TimeInterval?

    /// Cache of Article/Episode Core Data objects by ID for queue rebuilding
    private var articleCache: [UUID: Article] = [:]
    private var episodeCache: [String: RSSEpisode] = [:]

    // MARK: - Initialization

    private init() {
        setupAudioPlayer()
        setupNotifications()
        setupQueueCoordinatorBindings()
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

    /// Subscribe to QueueCoordinator changes - QueueCoordinator is the single source of truth
    private func setupQueueCoordinatorBindings() {
        // Sync current index from coordinator
        queueCoordinator.$currentIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in
                guard let self = self else { return }
                self.currentIndex = index
            }
            .store(in: &cancellables)

        // Rebuild queue when QueueCoordinator queue changes
        queueCoordinator.$queue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coordinatorQueue in
                guard let self = self else { return }
                self.rebuildQueueFromCoordinator(coordinatorQueue)
            }
            .store(in: &cancellables)
    }

    /// Rebuild local queue from QueueCoordinator, hydrating Core Data objects by ID
    /// NOTE: This must work after app restart when in-memory caches are empty
    private func rebuildQueueFromCoordinator(_ coordinatorQueue: [QueueItem]) {
        queue = coordinatorQueue.compactMap { queueItem -> UnifiedQueueItem? in
            // First try cached Core Data object, then fetch from database
            var article: Article? = queueItem.articleID.flatMap { articleCache[$0] }
            var episode: RSSEpisode? = queueItem.episodeID.flatMap { episodeCache[$0] }

            // If not in cache, fetch from Core Data (needed after app restart)
            if article == nil, let articleID = queueItem.articleID {
                article = fetchArticle(by: articleID)
                if let article = article {
                    articleCache[articleID] = article
                }
            }

            if episode == nil, let episodeID = queueItem.episodeID {
                episode = fetchEpisode(by: episodeID)
                if let episode = episode {
                    episodeCache[episodeID] = episode
                }
            }

            return UnifiedQueueItem(from: queueItem, article: article, episode: episode)
        }
    }

    /// Fetch Article from Core Data by ID
    private func fetchArticle(by id: UUID) -> Article? {
        let request: NSFetchRequest<Article> = Article.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        do {
            return try context.fetch(request).first
        } catch {
            print("[UnifiedPlayer] Failed to fetch article by ID: \(error)")
            return nil
        }
    }

    /// Fetch RSSEpisode from Core Data by ID
    private func fetchEpisode(by id: String) -> RSSEpisode? {
        let request: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        do {
            return try context.fetch(request).first
        } catch {
            print("[UnifiedPlayer] Failed to fetch episode by ID: \(error)")
            return nil
        }
    }

    /// Cache Core Data objects for queue rebuilding
    private func cacheObjects(articles: [Article] = [], episodes: [RSSEpisode] = []) {
        for article in articles {
            if let id = article.id {
                articleCache[id] = article
            }
        }
        for episode in episodes {
            episodeCache[episode.id] = episode
        }
    }
    
    // MARK: - Queue Management (delegates to QueueCoordinator)

    /// Load queue from articles - adds to QueueCoordinator, queue syncs via Combine
    func loadQueue(from articles: [Article]) async {
        // Exit Live News streaming mode if active
        stopLiveNewsStream()

        // Cache Core Data objects for queue rebuilding
        cacheObjects(articles: articles)

        // Add to QueueCoordinator (single source of truth)
        // The Combine subscription will rebuild local queue
        for article in articles {
            queueCoordinator.addArticle(article)
        }

        // Start pre-generation for first items
        await preGenerateNextItems()
    }

    /// Load queue from RSS episodes for Brief - adds to QueueCoordinator, queue syncs via Combine
    /// NOTE: For immediate Live News playback (no queuing), use playLiveNewsStream() instead
    func loadQueue(from episodes: [RSSEpisode]) async {
        // Exit Live News streaming mode if active
        stopLiveNewsStream()

        // Cache Core Data objects for queue rebuilding
        cacheObjects(episodes: episodes)

        // Add to QueueCoordinator (single source of truth)
        for episode in episodes {
            queueCoordinator.addEpisode(episode)
        }

        // RSS episodes don't need TTS generation - mark ready in local queue
        // (handled in rebuildQueueFromCoordinator via UnifiedQueueItem init)
    }

    /// Load mixed queue - adds to QueueCoordinator, queue syncs via Combine
    func loadMixedQueue(items: [Any]) async {
        // Exit Live News streaming mode if active
        stopLiveNewsStream()

        // Separate articles and episodes for caching
        let articles = items.compactMap { $0 as? Article }
        let episodes = items.compactMap { $0 as? RSSEpisode }
        cacheObjects(articles: articles, episodes: episodes)

        // Add to QueueCoordinator (single source of truth)
        for article in articles {
            queueCoordinator.addArticle(article)
        }
        for episode in episodes {
            queueCoordinator.addEpisode(episode)
        }

        await preGenerateNextItems()
    }

    // MARK: - Live News Streaming (immediate play, no queuing)

    /// Play Live News episodes immediately WITHOUT adding to Brief queue
    /// Per PRD: "Play Live News" streams immediately and doesn't queue
    func playLiveNewsStream(episodes: [RSSEpisode]) async {
        guard !episodes.isEmpty else { return }

        // Stop any current playback
        stop()

        // Enter Live News streaming mode
        isStreamingLiveNews = true
        liveNewsStreamIndex = -1

        // Build temporary stream queue (not persisted)
        liveNewsStreamQueue = episodes.map { episode in
            let item = UnifiedQueueItem(episode: episode)
            if item.audioURL != nil {
                item.generationState = .ready
                item.cachedAudioURL = item.audioURL
            }
            return item
        }

        print("[UnifiedPlayer] Started Live News stream with \(episodes.count) episodes (not queued to Brief)")

        // Start playing first episode
        await playLiveNewsStreamItem(at: 0)
    }

    /// Play item in Live News stream
    private func playLiveNewsStreamItem(at index: Int) async {
        guard index >= 0 && index < liveNewsStreamQueue.count else {
            // Stream finished
            stopLiveNewsStream()
            return
        }

        liveNewsStreamIndex = index
        let item = liveNewsStreamQueue[index]

        // Play if audio is ready
        if let audioURL = item.cachedAudioURL ?? item.audioURL {
            do {
                let artist = item.episode?.feed?.displayName ?? "Live News"
                try await audioPlayer.play(url: audioURL, title: item.title, artist: artist)
                isPlaying = true

                // Mark episode as listened
                if let episode = item.episode {
                    await markEpisodeAsListened(episode)
                }
            } catch {
                print("[UnifiedPlayer] Failed to play Live News stream: \(error)")
                // Try next episode
                await playNextLiveNewsStreamItem()
            }
        } else {
            // No audio URL, skip to next
            await playNextLiveNewsStreamItem()
        }
    }

    /// Play next item in Live News stream
    func playNextLiveNewsStreamItem() async {
        guard isStreamingLiveNews else { return }
        await playLiveNewsStreamItem(at: liveNewsStreamIndex + 1)
    }

    /// Stop Live News streaming and return to normal queue mode
    func stopLiveNewsStream() {
        if isStreamingLiveNews {
            isStreamingLiveNews = false
            liveNewsStreamIndex = -1
            liveNewsStreamQueue.removeAll()
            print("[UnifiedPlayer] Exited Live News streaming mode")
        }
    }

    /// Add item to queue (delegates to QueueCoordinator - single source of truth)
    /// Local queue is rebuilt via Combine subscription
	    func addToQueue(_ item: Any, playNow: Bool = false, playNext: Bool = false) async {
	        if let article = item as? Article {
	            // Cache the Core Data object
	            if let id = article.id {
	                articleCache[id] = article
	            }
	            // Add to QueueCoordinator (single source of truth)
	            // Local queue rebuilds via Combine subscription
	            queueCoordinator.addArticle(article, playNow: playNow, playNext: playNext)
	            rebuildQueueFromCoordinator(queueCoordinator.queue)
	            currentIndex = queueCoordinator.currentIndex

	            // Pre-generate if queue is small
	            if queueCoordinator.itemCount <= 3 {
	                // Find the item in rebuilt queue and generate
	                if let queueItem = queue.first(where: { $0.article?.id == article.id }) {
                    await generateAudioForItem(queueItem)
                }
            }
	        } else if let episode = item as? RSSEpisode {
	            // Cache the Core Data object
	            episodeCache[episode.id] = episode
	            // Add to QueueCoordinator (single source of truth)
	            queueCoordinator.addEpisode(episode, playNow: playNow, playNext: playNext)
	            rebuildQueueFromCoordinator(queueCoordinator.queue)
	            currentIndex = queueCoordinator.currentIndex
	        }
	    }

    /// Remove item from queue (delegates to QueueCoordinator - single source of truth)
    /// Local queue is rebuilt via Combine subscription
    func removeFromQueue(at index: Int) {
        guard index >= 0 && index < queueCoordinator.itemCount else { return }

        let wasCurrentItem = (index == currentIndex)

        // Remove from QueueCoordinator (single source of truth)
        // Local queue and currentIndex sync via Combine
        queueCoordinator.removeItem(at: index)

        // Stop playback if current item was removed
        if wasCurrentItem {
            stop()
        }
    }

    /// Clear queue (delegates to QueueCoordinator - single source of truth)
    func clearQueue() {
        stop()
        stopLiveNewsStream()
        queueCoordinator.clearQueue()
        // Local queue clears via Combine subscription
    }
    
    // MARK: - Playback Control

    /// Play item at index
    func play(at index: Int) async {
        // If we're in Live News streaming mode, explicitly exit it before playing from the Brief queue.
        if isStreamingLiveNews {
            stop()
            stopLiveNewsStream()
        }

        guard index >= 0 && index < queue.count else { return }

        currentIndex = index
        // Sync to QueueCoordinator
        queueCoordinator.setCurrentIndex(index)
        pendingSeekTime = queueCoordinator.currentPosition > 0 ? queueCoordinator.currentPosition : nil

        let item = queue[index]

        // Yield to allow UI to update before heavy generation work
        await Task.yield()

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

                // Mark as listened in coordinator
                queueCoordinator.markCurrentAsListened()
            } catch {
                print("[UnifiedPlayer] Failed to play audio: \(error)")
                print("[UnifiedPlayer] Error type: \(type(of: error))")
                item.generationState = .failed(error)
                // Track playback error for UI visibility
                if let uuid = UUID(uuidString: item.id) {
                    queueCoordinator.markItemFailed(for: uuid, error: "Playback failed: \(error.localizedDescription)")
                }
            }
        } else {
            print("[UnifiedPlayer] No cached audio URL available for item: \(item.title)")
            // Track missing audio error
            if let uuid = UUID(uuidString: item.id) {
                queueCoordinator.markItemFailed(for: uuid, error: "Audio not available")
            }
        }
    }
    
    /// Play next item
    func playNext() async {
        if isStreamingLiveNews {
            // Live News streaming mode
            await playNextLiveNewsStreamItem()
        } else {
            // Brief queue mode
            if currentIndex < queue.count - 1 {
                await play(at: currentIndex + 1)
            }
        }
    }
    
    /// Play previous item
    func playPrevious() async {
        if isStreamingLiveNews {
            // Live News streaming mode
            if liveNewsStreamIndex > 0 {
                await playLiveNewsStreamItem(at: liveNewsStreamIndex - 1)
            }
        } else {
            // Brief queue mode
            if currentIndex > 0 {
                await play(at: currentIndex - 1)
            }
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
        pendingSeekTime = nil
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
        // Only sync position to QueueCoordinator in Brief queue mode (not Live News streaming)
        if !isStreamingLiveNews {
            queueCoordinator.updateCurrentPosition(time)
        }
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
            generationPhase = .checkingCache(title: item.title)

            do {
                print("[UnifiedPlayer] Starting audio generation for article: \(article.title ?? "Unknown")")
                print("[UnifiedPlayer] Article has summary: \(article.summary != nil), summary length: \(article.summary?.count ?? 0)")

                // Check if article needs summary generation
                if article.summary == nil || article.summary?.isEmpty == true || article.summary == "Unable to generate summary. The article content may be incomplete or unavailable." {
                    print("[UnifiedPlayer] Article needs summary generation")

                    // Get article content for summarization
                    var contentToSummarize = ""
                    if let content = article.content, !content.isEmpty {
                        contentToSummarize = content.stripHTML
                        print("[UnifiedPlayer] Using existing article content: \(contentToSummarize.count) characters")
                    } else if let url = article.url {
                        print("[UnifiedPlayer] No content stored, fetching from URL: \(url)")
                        // Fetch content from URL if needed
                        let domain = URL(string: url)?.host ?? "article"
                        generationPhase = .fetchingContent(domain: domain)
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
                        // Yield before heavy summarization work
                        await Task.yield()

                        // Calculate word count for display
                        let wordCount = contentToSummarize.split(separator: " ").count
                        generationPhase = .summarizing(wordCount: wordCount, provider: "Gemini")
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
                            // Use retry-enabled summarization with exponential backoff
                            summaryText = try await geminiService.summarizeWithRetry(
                                text: processedContent,
                                length: .standard,
                                config: .default
                            )
                            print("[UnifiedPlayer] Received summary: \(summaryText.count) characters")
                            print("[UnifiedPlayer] Summary preview: \(summaryText.prefix(200))...")
                        } catch {
                            print("[UnifiedPlayer] Gemini summarization failed after retries: \(error)")
                            // Track error in QueueCoordinator for UI visibility
                            if let uuid = UUID(uuidString: item.id) {
                                queueCoordinator.markItemFailed(for: uuid, error: error.localizedDescription)
                            }
                            // Re-throw to surface error - no silent fallback
                            throw error
                        }
                        
                        // Check if Gemini couldn't generate a summary (model refused)
                        if summaryText.contains("cannot provide a summary") || summaryText.contains("I cannot") || summaryText.contains("cannot summarize") {
                            print("[UnifiedPlayer] WARNING: Gemini couldn't generate summary")
                            print("[UnifiedPlayer] Problematic content was: \(contentToSummarize.prefix(1000))")

                            let errorMsg = "Unable to generate summary. The article content may be incomplete or unavailable."
                            if let uuid = UUID(uuidString: item.id) {
                                queueCoordinator.markItemFailed(for: uuid, error: errorMsg)
                            }

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
                print("[UnifiedPlayer] Formatting article for TTS...")
                print("[UnifiedPlayer] Article summary status: \(article.summary?.count ?? 0) characters")
                let text = formatArticleForTTS(article)
                print("[UnifiedPlayer] Text for TTS (\(text.count) chars): \(String(text.prefix(200)))...")

                // Check if we only have title
                if text.count < 100 && article.title != nil {
                    print("[UnifiedPlayer] WARNING: TTS text is very short, likely only title")
                }

                // Yield before heavy TTS generation work
                await Task.yield()

                // Generate audio file - try OpenAI first if configured, fallback to Gemini
                let audioURL: URL

                if UserDefaultsManager.shared.openAIAPIKey != nil && !UserDefaultsManager.shared.openAIAPIKey!.isEmpty {
                    // Use OpenAI TTS if API key is configured
                    generationPhase = .generatingAudio(provider: "OpenAI")
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
                        generationPhase = .generatingAudio(provider: "Gemini")
                        audioURL = try await ttsGenerator.generateAudioFile(
                            from: text,
                            trackingIn: context,
                            for: article
                        )
                    }
                } else {
                    // Use Gemini TTS as primary (but may hit 100/day limit)
                    generationPhase = .generatingAudio(provider: "Gemini")
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

                generationPhase = .finalizing
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
                // Track in QueueCoordinator for UI visibility
                if let uuid = UUID(uuidString: item.id) {
                    queueCoordinator.markItemFailed(for: uuid, error: error.localizedDescription)
                }
                generationPhase = .failed(message: error.localizedDescription)
            }

            isGenerating = false
            generationPhase = .idle
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
        
        // DON'T add title - it's already shown in UI and announced separately
        let articleTitle = article.title ?? ""
        print("[UnifiedPlayer] formatArticleForTTS - Article title: \(articleTitle) (NOT adding to TTS)")
        
        // Check if we have a pre-generated summary
        if let summary = article.summary, !summary.isEmpty {
            print("[UnifiedPlayer] formatArticleForTTS - Found summary: \(summary.count) chars")
            print("[UnifiedPlayer] formatArticleForTTS - Summary first 200 chars: \(summary.prefix(200))")
            
            // Check if summary starts with the title (to avoid duplication)
            var cleanedSummary = summary
            if !articleTitle.isEmpty {
                // Remove title if it appears at the beginning of the summary
                let titleVariations = [
                    articleTitle,
                    articleTitle + ".",
                    articleTitle + ":",
                    articleTitle + " -",
                    articleTitle + ","
                ]
                
                for variation in titleVariations {
                    if cleanedSummary.lowercased().hasPrefix(variation.lowercased()) {
                        cleanedSummary = String(cleanedSummary.dropFirst(variation.count))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: ".:,- "))
                        print("[UnifiedPlayer] Removed duplicate title from summary")
                        break
                    }
                }
            }
            
            // Skip the fallback summary message
            if !cleanedSummary.contains("Unable to generate summary") && !cleanedSummary.contains("cannot provide a summary") {
                // Check if summary is JSON and parse it
                if cleanedSummary.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") ||
                   cleanedSummary.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```json") {
                    // Parse JSON summary
                    let cleanJson = cleanedSummary
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
                        // If JSON parsing fails, don't use the raw JSON
                        print("[UnifiedPlayer] formatArticleForTTS - JSON parsing failed, skipping JSON summary")
                        // Try to extract meaningful text from the article
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
                            text += "Summary format error. Unable to process article content."
                        }
                    }
                } else {
                    // Summary is plain text, use cleaned version directly
                    text += cleanedSummary
                    print("[UnifiedPlayer] formatArticleForTTS - Added cleaned plain text summary to TTS text")
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

        // Only sync position to QueueCoordinator in Brief queue mode (not Live News streaming)
        // Periodically sync (every ~5 seconds to reduce writes)
        if !isStreamingLiveNews && Int(currentTime) % 5 == 0 {
            queueCoordinator.updateCurrentPosition(currentTime)
        }
    }
}

// MARK: - SwiftAudioExService Delegate

extension UnifiedAudioPlayer: @preconcurrency SwiftAudioExServiceDelegate {
    
    nonisolated func audioStateChanged(to newState: SwiftAudioPlayerState, from oldState: SwiftAudioPlayerState) {
        Task { @MainActor in
            switch newState {
            case .playing:
                isPlaying = true
                if let seekTime = pendingSeekTime, seekTime > 0 {
                    audioPlayer.seek(to: seekTime)
                    currentTime = seekTime
                    pendingSeekTime = nil
                }
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

    nonisolated func audioRequestNextTrack() {
        Task {
            await playNext()
        }
    }

    nonisolated func audioRequestPreviousTrack() {
        Task {
            await playPrevious()
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
        if isStreamingLiveNews {
            return liveNewsStreamIndex < liveNewsStreamQueue.count - 1
        } else {
            return currentIndex < queue.count - 1
        }
    }

    /// Check if can play previous
    var canPlayPrevious: Bool {
        if isStreamingLiveNews {
            return liveNewsStreamIndex > 0
        } else {
            return currentIndex > 0
        }
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
