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

        // Validate cached audio file still exists on disk before trusting it.
        // Library/Caches/ can be purged by iOS under storage pressure.
        let candidateURL = queueItem.cachedAudioURL ?? queueItem.streamURL
        let audioFileExists: Bool
        if let url = candidateURL, url.isFileURL {
            audioFileExists = FileManager.default.fileExists(atPath: url.path)
        } else {
            // Remote stream URLs are assumed available
            audioFileExists = candidateURL != nil
        }
        self.cachedAudioURL = audioFileExists ? candidateURL : nil

        // Map QueueItem state to audio generation state.
        // For playback, "ready" means we have a verified audio URL.
        switch queueItem.summaryState {
        case .failed:
            self.generationState = .failed(NSError(domain: "QueueItem", code: -1))
        case .generating:
            self.generationState = .generating
        case .pending, .ready:
            self.generationState = audioFileExists ? .ready : .pending
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
    case downloadingModels(progress: Double)
    case initializingOnDevice
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
        case .downloadingModels(let progress):
            let percent = Int(progress * 100)
            return "Downloading TTS models... \(percent)%"
        case .initializingOnDevice:
            return "Initializing on-device TTS..."
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
        case .downloadingModels(let progress):
            return "Models \(Int(progress * 100))%..."
        case .initializingOnDevice:
            return "Initializing TTS..."
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

enum ActivePlaybackMode: Equatable {
    case none
    case brief
    case radio
}

@MainActor
final class UnifiedAudioPlayer: ObservableObject {

    // MARK: - Singleton

    static let shared = UnifiedAudioPlayer()

    // MARK: - Services

    private let ttsGenerator = TTSGeneratorService.shared
    private let openAITTS = OpenAITTSServiceSimple.shared
    private let fluidAudioService = FluidAudioTTSService.shared
    private let audioPlayer: AudioPlaybackTransporting
    private let cacheManager = AudioCacheManager.shared
    private let queueCoordinator: BriefQueueCoordinating
    private let radioCoordinator: RadioSessionCoordinating
    private let pipelineTimer = PipelineTimer.shared
    private let context: NSManagedObjectContext
    private let persistPlaybackRate: @MainActor (Float) -> Void
    private let briefCompletionDelay: @MainActor () async -> Void

    var radioSessionCoordinator: RadioSessionCoordinating { radioCoordinator }

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

    @Published private(set) var activeMode: ActivePlaybackMode = .none
    @Published private(set) var radioQueue: [UnifiedQueueItem] = []
    @Published private(set) var radioIndex: Int = -1

    /// A restored Radio episode is usable before the audio transport is loaded,
    /// so `.none` can still present and route as Radio.
    var effectivePlaybackMode: ActivePlaybackMode {
        guard activeMode == .none else { return activeMode }
        if hasResumableRadioEpisode { return .radio }
        return queue.isEmpty ? .none : .brief
    }

    var presentationPosition: TimeInterval {
        effectiveControlPosition
    }

    var presentationDuration: TimeInterval {
        effectivePlaybackMode == .radio ? (radioControlDuration ?? 0) : finiteNonnegative(duration)
    }

    // MARK: - Current Item

    var currentItem: UnifiedQueueItem? {
        switch effectivePlaybackMode {
        case .radio:
            guard radioIndex >= 0 && radioIndex < radioQueue.count else { return nil }
            return radioQueue[radioIndex]
        case .brief, .none:
            guard currentIndex >= 0 && currentIndex < queue.count else { return nil }
            return queue[currentIndex]
        }
    }

    /// Get current QueueItem from coordinator (only valid when not streaming Live News)
    var currentQueueItem: QueueItem? {
        effectivePlaybackMode == .radio ? nil : queueCoordinator.currentItem
    }

    // MARK: - Private Properties

    private var preGenerationTask: Task<Void, Never>?
    private var playbackProgressTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var pendingSeekTime: TimeInterval?
    private var activePlaybackID: TransportPlaybackID?
    private var activeRadioKey: RadioEpisodeKey?
    private var consumedPlaybackIDs = Set<TransportPlaybackID>()
    private var briefInterruptionResumeEligible = false

    private struct RadioEventContext: Equatable {
        let playbackID: TransportPlaybackID
        let key: RadioEpisodeKey
    }

    /// Cache of Article/Episode Core Data objects by ID for queue rebuilding
    private var articleCache: [UUID: Article] = [:]
    private var episodeCache: [String: RSSEpisode] = [:]

    // MARK: - Initialization

    private convenience init() {
        self.init(
            audioPlayer: SwiftAudioExService(),
            queueCoordinator: QueueCoordinator.shared,
            radioCoordinator: RadioServiceContainer.shared.coordinator,
            context: PersistenceController.shared.container.viewContext
        )
    }

    init(
        audioPlayer: AudioPlaybackTransporting,
        queueCoordinator: BriefQueueCoordinating,
        radioCoordinator: RadioSessionCoordinating,
        context: NSManagedObjectContext,
        persistPlaybackRate: @escaping @MainActor (Float) -> Void = {
            UserDefaultsManager.shared.playbackSpeed = $0
        },
        briefCompletionDelay: @escaping @MainActor () async -> Void = {
            try? await Task.sleep(for: .milliseconds(500))
        }
    ) {
        self.audioPlayer = audioPlayer
        self.queueCoordinator = queueCoordinator
        self.radioCoordinator = radioCoordinator
        self.context = context
        self.persistPlaybackRate = persistPlaybackRate
        self.briefCompletionDelay = briefCompletionDelay
        setupAudioPlayer()
        setupQueueCoordinatorBindings()
        setupRadioBindings()
    }

    // MARK: - Setup

    private func setupAudioPlayer() {
        audioPlayer.delegate = self
    }

    /// Subscribe to QueueCoordinator changes - QueueCoordinator is the single source of truth
    private func setupQueueCoordinatorBindings() {
        // Sync current index from coordinator (with bounds clamping)
        queueCoordinator.currentIndexPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in
                guard let self = self else { return }
                if self.queue.isEmpty {
                    self.currentIndex = -1
                } else if index >= 0 && index < self.queue.count {
                    self.currentIndex = index
                } else {
                    self.currentIndex = max(-1, min(index, self.queue.count - 1))
                }
                self.updateRemoteAvailability()
            }
            .store(in: &cancellables)

        // Rebuild queue when QueueCoordinator queue changes
        queueCoordinator.queuePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coordinatorQueue in
                guard let self = self else { return }
                self.rebuildQueueFromCoordinator(coordinatorQueue)
                self.updateRemoteAvailability()
            }
            .store(in: &cancellables)
    }

    private func setupRadioBindings() {
        radioCoordinator.entriesPublisher
            .combineLatest(radioCoordinator.currentEpisodePublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.rebuildRadioProjection() }
            .store(in: &cancellables)

        radioCoordinator.canPlayNextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateRemoteAvailability() }
            .store(in: &cancellables)

        radioCoordinator.pendingNetworkIntentPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] intent in
                Task { @MainActor [weak self] in
                    guard let self, self.effectivePlaybackMode == .radio else { return }
                    await self.execute(intent)
                }
            }
            .store(in: &cancellables)

        rebuildRadioProjection()
    }

    private func rebuildRadioProjection() {
        radioQueue = radioCoordinator.entries.compactMap { entry in
            fetchEpisode(feedID: entry.key.feedID, episodeID: entry.key.episodeID).map(UnifiedQueueItem.init(episode:))
        }
        if let currentKey = radioCoordinator.currentKey {
            radioIndex = radioCoordinator.entries.firstIndex { $0.key == currentKey } ?? -1
        } else {
            radioIndex = -1
        }
    }

    /// Rebuild local queue from QueueCoordinator, hydrating Core Data objects by ID
    /// NOTE: This must work after app restart when in-memory caches are empty
    private func rebuildQueueFromCoordinator(_ coordinatorQueue: [QueueItem]) {
        queue = coordinatorQueue.map { queueItem -> UnifiedQueueItem in
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

    private func fetchEpisode(feedID: String, episodeID: String) -> RSSEpisode? {
        let request: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
        request.predicate = NSPredicate(format: "feedId == %@ AND id == %@", feedID, episodeID)
        request.fetchLimit = 1
        return try? context.fetch(request).first
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
    /// Set `replace` to true (used by "Play All") to clear existing queue first
    func loadQueue(from articles: [Article], replace: Bool = false) async {
        // Clear existing queue if replacing (e.g. "Play All")
        if replace {
            queueCoordinator.clearQueue()
        }

        // Cache Core Data objects for queue rebuilding
        cacheObjects(articles: articles)

        // Add to QueueCoordinator (single source of truth)
        // The Combine subscription will rebuild local queue
        for article in articles {
            queueCoordinator.addArticle(article, playNow: false, playNext: false)
        }

        // Do not generate audio just because the queue was hydrated.
        // Generation starts when playback starts, then only the immediate next item is warmed.
    }

    /// Load queue from RSS episodes for Brief - adds to QueueCoordinator, queue syncs via Combine
    func loadQueue(from episodes: [RSSEpisode]) async {
        // Cache Core Data objects for queue rebuilding
        cacheObjects(episodes: episodes)

        // Add to QueueCoordinator (single source of truth)
        for episode in episodes {
            queueCoordinator.addEpisode(episode, playNow: false, playNext: false)
        }

        // RSS episodes don't need TTS generation - mark ready in local queue
        // (handled in rebuildQueueFromCoordinator via UnifiedQueueItem init)
    }

    /// Load mixed queue - adds to QueueCoordinator, queue syncs via Combine
    func loadMixedQueue(items: [Any]) async {
        // Separate articles and episodes for caching
        let articles = items.compactMap { $0 as? Article }
        let episodes = items.compactMap { $0 as? RSSEpisode }
        cacheObjects(articles: articles, episodes: episodes)

        // Add to QueueCoordinator (single source of truth)
        for article in articles {
            queueCoordinator.addArticle(article, playNow: false, playNext: false)
        }
        for episode in episodes {
            queueCoordinator.addEpisode(episode, playNow: false, playNext: false)
        }

        // Do not generate audio just because mixed content was queued.
        // Generation starts when playback starts, then only the immediate next item is warmed.
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

            if playNext && isPlaying {
                await preGenerateNextItems()
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
        if wasCurrentItem, activeMode == .brief {
            stop()
        }
    }

    /// Clear queue (delegates to QueueCoordinator - single source of truth)
    func clearQueue() {
        if activeMode == .brief { stop() }
        queueCoordinator.clearQueue()
        // Local queue clears via Combine subscription
    }
    
    // MARK: - Playback Control

    /// Play item at index
    func play(at index: Int) async {
        guard index >= 0 && index < queue.count else { return }

        if activeMode == .radio {
            let shouldPersistActiveRadioTransport = activeRadioKey == radioCoordinator.currentKey
                && activePlaybackID.map { !consumedPlaybackIDs.contains($0) } == true
            if shouldPersistActiveRadioTransport {
                _ = radioCoordinator.pauseByUser(positionSeconds: currentTime, duration: duration > 0 ? duration : nil)
            }
            audioPlayer.stop()
        } else if activePlaybackID != nil {
            queueCoordinator.updateCurrentPosition(currentTime)
            queueCoordinator.saveStateNow()
            audioPlayer.stop()
        }

        activeMode = .brief
        currentIndex = index
        // Sync to QueueCoordinator
        queueCoordinator.setCurrentIndex(index)
        pendingSeekTime = queueCoordinator.currentPosition > 0 ? queueCoordinator.currentPosition : nil

        let item = queue[index]

        // Yield to allow UI to update before heavy generation work
        await Task.yield()

        // Ensure audio is ready — reset failed items so they can retry
        if case .failed = item.generationState {
            item.generationState = .pending
        }
        // Skip if already generating (avoids double-trigger from addToQueue + play)
        if item.generationState != .ready && item.generationState != .generating {
            await generateAudioForItem(item)
        }

        // Play if generation succeeded
        if let audioURL = item.cachedAudioURL {
            print("[UnifiedPlayer] Attempting to play audio from: \(audioURL.path)")
            print("[UnifiedPlayer] File exists: \(FileManager.default.fileExists(atPath: audioURL.path))")

            do {
                // Pass title and artist info for lock screen display
                let artist = item.type == .article ? (item.article?.author ?? "Article") : (item.episode?.feed?.displayName ?? "Podcast")
                let playbackID = TransportPlaybackID()
                activePlaybackID = playbackID
                activeRadioKey = nil
                consumedPlaybackIDs.remove(playbackID)
                updateRemoteAvailability()
                try await audioPlayer.play(id: playbackID, url: audioURL, title: item.title, artist: artist)
                audioPlayer.setRate(playbackRate)
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
        cancelDeferredAutoplay()
        if effectivePlaybackMode == .radio {
            await execute(radioCoordinator.manualNext(positionSeconds: radioControlPosition, duration: radioControlDuration))
        } else {
            if currentIndex < queue.count - 1 {
                await play(at: currentIndex + 1)
            }
        }
    }

    /// Handle natural track completion: auto-remove played items (processing chamber)
    /// Only called when a track finishes naturally, NOT on manual skip-next.
    private func handleTrackFinished() async {
        let finishedIndex = currentIndex
        guard finishedIndex >= 0 && finishedIndex < queue.count else {
            return
        }

        // Check if the finished item is bookmarked
        let isBookmarked = queueCoordinator.queue[safe: finishedIndex]?.isBookmarked ?? false

        if isBookmarked {
            // Bookmarked items stay in queue — just advance
            await playNext()
        } else {
            // Briefly leave the completed state visible before removing the row.
            await briefCompletionDelay()

            // Guard: verify state hasn't changed during the delay
            guard currentIndex == finishedIndex,
                  finishedIndex < queueCoordinator.queue.count else {
                return
            }

            // Auto-remove the listened item
            let _ = queueCoordinator.autoRemoveIfListened(at: finishedIndex)

            // After removal, sync from QueueCoordinator before deciding what
            // to play next. The published local queue can still contain the
            // removed item until the Combine subscription catches up.
            rebuildQueueFromCoordinator(queueCoordinator.queue)
            currentIndex = queueCoordinator.currentIndex

            if currentIndex >= 0 && currentIndex < queueCoordinator.queue.count {
                await play(at: currentIndex)
            } else {
                activeMode = .none
                activePlaybackID = nil
                activeRadioKey = nil
                isPlaying = false
                currentTime = 0
                duration = 0
                pendingSeekTime = nil
                updateRemoteAvailability()
            }
        }
    }

    /// Play previous item
    func playPrevious() async {
        cancelDeferredAutoplay()
        if effectivePlaybackMode != .radio {
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
        cancelDeferredAutoplay()
        if effectivePlaybackMode == .radio {
            let intent = radioCoordinator.pauseByUser(positionSeconds: radioControlPosition, duration: radioControlDuration)
            if intent == .pause, activeMode == .radio { audioPlayer.pause() }
        } else {
            queueCoordinator.updateCurrentPosition(currentTime)
            queueCoordinator.saveStateNow()
            audioPlayer.pause()
        }
        isPlaying = false
        updateRemoteAvailability()
    }
    
    /// Resume playback
    func resume() {
        Task { @MainActor in await beginEffectiveCurrent() }
    }

    /// Starts the logical current item, loading it first when a restored session
    /// has no active transport item yet.
    func beginEffectiveCurrent() async {
        cancelDeferredAutoplay()
        switch effectivePlaybackMode {
        case .radio:
            await execute(radioCoordinator.beginCurrent())
        case .brief:
            if activeMode == .brief, activePlaybackID != nil {
                audioPlayer.resume()
                isPlaying = true
            } else {
                let index = currentIndex >= 0 ? currentIndex : 0
                guard queue.indices.contains(index) else { return }
                await play(at: index)
            }
        case .none:
            break
        }
    }
    
    /// Stop playback
    func stop() {
        if effectivePlaybackMode == .radio {
            _ = radioCoordinator.pauseByUser(positionSeconds: radioControlPosition, duration: radioControlDuration)
        } else if activeMode == .brief {
            queueCoordinator.updateCurrentPosition(currentTime)
            queueCoordinator.saveStateNow()
        }
        audioPlayer.stop()
        activePlaybackID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        pendingSeekTime = nil
    }
    
    /// Set playback rate
    func setRate(_ rate: Float) {
        cancelDeferredAutoplay()
        let normalized = PlaybackSpeedPolicy.normalize(rate)
        playbackRate = normalized
        audioPlayer.setRate(normalized)
        
        persistPlaybackRate(normalized)
    }
    
    /// Seek to time
    func seek(to time: TimeInterval) {
        cancelDeferredAutoplay()
        let knownDuration = effectivePlaybackMode == .radio ? (radioControlDuration ?? 0) : duration
        let bounded = finiteNonnegative(knownDuration > 0 ? min(time, knownDuration) : time)
        if effectivePlaybackMode == .radio {
            _ = radioCoordinator.seekEnded(positionSeconds: bounded, duration: radioControlDuration)
        } else {
            queueCoordinator.updateCurrentPosition(bounded)
            queueCoordinator.saveStateNow()
        }
        if activeMode != .none, activePlaybackID != nil {
            audioPlayer.seek(to: bounded)
        }
        currentTime = bounded
    }
    
    /// Skip forward
    func skipForward(_ seconds: TimeInterval = 10) {
        let position = effectiveControlPosition
        let knownDuration = effectivePlaybackMode == .radio ? (radioControlDuration ?? 0) : duration
        seek(to: min(position + seconds, knownDuration > 0 ? knownDuration : position + seconds))
    }
    
    /// Skip backward
    func skipBackward(_ seconds: TimeInterval = 10) {
        let position = effectiveControlPosition
        seek(to: max(position - seconds, 0))
    }

    // MARK: - Radio Playback

    func playRadio() async {
        cancelDeferredAutoplay()
        await execute(radioCoordinator.beginCurrent())
    }

    func playRadioEpisode(_ key: RadioEpisodeKey) async {
        cancelDeferredAutoplay()
        await execute(radioCoordinator.selectEpisode(key))
    }

    func retryRadio() async {
        cancelDeferredAutoplay()
        await execute(radioCoordinator.retry())
    }

    func setRadioSleepTimer(_ timer: RadioSleepTimer) {
        radioCoordinator.setSleepTimer(timer)
    }

    func cancelRadioSleepTimer() {
        radioCoordinator.setSleepTimer(.off)
    }

    func execute(_ intent: RadioPlaybackIntent?) async {
        guard let intent else {
            if activeMode == .none, let key = radioCoordinator.currentKey {
                activeMode = .radio
                activeRadioKey = key
                currentTime = radioCoordinator.entries.first(where: { $0.key == key })?.positionSeconds ?? 0
                duration = radioCoordinator.currentEpisode?.durationSeconds ?? 0
            }
            rebuildRadioProjection()
            updateRemoteAvailability()
            return
        }

        switch intent {
        case .pause:
            audioPlayer.pause()
            isPlaying = false
            updateRemoteAvailability()

        case .play(let request):
            if activeMode == .brief, activePlaybackID != nil {
                queueCoordinator.updateCurrentPosition(currentTime)
                queueCoordinator.saveStateNow()
            }

            if activeMode == .radio,
               activeRadioKey == request.key,
               let activePlaybackID,
               !consumedPlaybackIDs.contains(activePlaybackID) {
                pendingSeekTime = request.positionSeconds > 0 ? request.positionSeconds : nil
                if let pendingSeekTime {
                    audioPlayer.seek(to: pendingSeekTime)
                    self.pendingSeekTime = nil
                }
                audioPlayer.resume()
                return
            }
            if activePlaybackID != nil { audioPlayer.stop() }

            let playbackID = TransportPlaybackID()
            activePlaybackID = playbackID
            activeRadioKey = request.key
            consumedPlaybackIDs.remove(playbackID)
            activeMode = .radio
            pendingSeekTime = request.positionSeconds > 0 ? request.positionSeconds : nil
            currentTime = request.positionSeconds
            duration = radioCoordinator.currentEpisode?.durationSeconds ?? 0
            rebuildRadioProjection()
            updateRemoteAvailability()

            do {
                let url = preferredRadioURL(for: request.key) ?? request.url
                try await audioPlayer.play(
                    id: playbackID,
                    url: url,
                    title: request.title,
                    artist: request.source
                )
                audioPlayer.setRate(playbackRate)
            } catch {
                guard playbackID == activePlaybackID else { return }
                audioPlayer.stop()
                activePlaybackID = nil
                activeRadioKey = nil
                pendingSeekTime = nil
                isPlaying = false
                consumedPlaybackIDs.remove(playbackID)
                let next = radioCoordinator.playbackFailed(
                    for: request.key,
                    message: error.localizedDescription,
                    positionSeconds: currentTime,
                    duration: duration > 0 ? duration : nil,
                    connectivity: radioCoordinator.currentConnectivityStatus
                )
                await execute(next)
            }
        }
    }

    private func preferredRadioURL(for key: RadioEpisodeKey) -> URL? {
        guard let path = fetchEpisode(feedID: key.feedID, episodeID: key.episodeID)?.downloadedFilePath,
              !path.isEmpty,
              FileManager.default.isReadableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func cancelDeferredAutoplay() {
        radioCoordinator.cancelPendingColdLaunchAutoplay()
    }

    private func radioEventContext(callbackID: TransportPlaybackID?) -> RadioEventContext? {
        guard activeMode == .radio,
              let playbackID = activePlaybackID,
              let key = activeRadioKey,
              callbackID == nil || callbackID == playbackID else { return nil }
        return RadioEventContext(playbackID: playbackID, key: key)
    }

    private func isCurrent(_ context: RadioEventContext) -> Bool {
        activeMode == .radio
            && activePlaybackID == context.playbackID
            && activeRadioKey == context.key
    }

    private func scheduleRadioEvent(
        _ context: RadioEventContext,
        operation: @escaping @MainActor (RadioSessionCoordinating) -> RadioPlaybackIntent?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.isCurrent(context) else { return }
            let intent = operation(self.radioCoordinator)
            await self.execute(intent)
        }
    }

    private func scheduleRadioIntent(_ intent: RadioPlaybackIntent?, for context: RadioEventContext) {
        Task { @MainActor [weak self] in
            guard let self, self.isCurrent(context) else { return }
            await self.execute(intent)
        }
    }

    private func updateRemoteAvailability() {
        switch effectivePlaybackMode {
        case .radio:
            audioPlayer.applyRemoteCommandAvailability(.radio(canPlayNext: radioCoordinator.canPlayNext))
        case .brief, .none:
            audioPlayer.applyRemoteCommandAvailability(
                .brief(canPlayPrevious: currentIndex > 0, canPlayNext: currentIndex >= 0 && currentIndex < queue.count - 1)
            )
        }
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
            pipelineTimer.beginRun()

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
                        let fetchStepIdx = pipelineTimer.startStep("content_fetch")
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
                        pipelineTimer.endStep(fetchStepIdx)
                    }

                    if !contentToSummarize.isEmpty {
                        // Yield before heavy summarization work
                        await Task.yield()

                        // Calculate word count for display
                        let wordCount = contentToSummarize.split(separator: " ").count
                        generationPhase = .summarizing(wordCount: wordCount, provider: "Gemini")
                        let summarizeStepIdx = pipelineTimer.startStep("summarize")
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
                        pipelineTimer.endStep(summarizeStepIdx)
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

                // Generate audio file - local-first TTS provider chain
                let ttsStepIdx = pipelineTimer.startStep("tts_generate")
                var audioURL: URL

                // Tier 1: On-device PocketTTS. First Play Now may download/compile models.
                if UserDefaultsManager.shared.preferOnDeviceTTS {
                    generationPhase = .initializingOnDevice
                    if await fluidAudioService.ensureReadyForPlayback(
                        voice: UserDefaultsManager.shared.fluidAudioVoice
                    ) {
                        generationPhase = .generatingAudio(provider: "PocketTTS (On-Device)")
                        print("[UnifiedPlayer] Using PocketTTS (on-device, \(text.count) chars)")
                        do {
                            audioURL = try await fluidAudioService.synthesizeToFile(
                                text: text,
                                voice: UserDefaultsManager.shared.fluidAudioVoice,
                                voiceSpeed: UserDefaultsManager.shared.fluidAudioVoiceSpeed
                            )
                        } catch {
                            print("[UnifiedPlayer] On-device TTS failed: \(error), falling back to cloud TTS")
                            audioURL = try await fallbackToCloudTTS(text: text, article: article)
                        }
                    } else {
                        print("[UnifiedPlayer] On-device TTS unavailable, falling back to cloud TTS")
                        audioURL = try await fallbackToCloudTTS(text: text, article: article)
                    }
                }
                // Tier 2: OpenAI TTS (low latency, paid)
                else if let apiKey = UserDefaultsManager.shared.openAIAPIKey, !apiKey.isEmpty {
                    generationPhase = .generatingAudio(provider: "OpenAI")
                    print("[UnifiedPlayer] Using OpenAI TTS for audio generation")
                    do {
                        audioURL = try await openAITTS.generateAudioForArticle(
                            title: article.title,
                            content: text,
                            useStreaming: UserDefaultsManager.shared.useOpenAIStreaming
                        )
                    } catch {
                        print("[UnifiedPlayer] OpenAI TTS failed: \(error), falling back to Gemini")
                        generationPhase = .generatingAudio(provider: "Gemini")
                        audioURL = try await ttsGenerator.generateAudioFile(
                            from: text,
                            trackingIn: context,
                            for: article
                        )
                    }
                }
                // Tier 3: Gemini TTS (high latency ~26s, free with quota)
                else {
                    generationPhase = .generatingAudio(provider: "Gemini")
                    print("[UnifiedPlayer] Using Gemini TTS (no OpenAI key, on-device not ready)")
                    do {
                        audioURL = try await ttsGenerator.generateAudioFile(
                            from: text,
                            trackingIn: context,
                            for: article
                        )
                    } catch {
                        print("[UnifiedPlayer] Gemini TTS failed: \(error)")
                        if error.localizedDescription.contains("quota") || error.localizedDescription.contains("limit") {
                            print("[UnifiedPlayer] Likely hit Gemini 100/day limit. Configure OpenAI API key or download on-device models.")
                        }
                        throw error
                    }
                }

                pipelineTimer.endStep(ttsStepIdx)

                generationPhase = .finalizing
                let audioLoadStepIdx = pipelineTimer.startStep("audio_load")
                item.cachedAudioURL = audioURL
                item.generationState = .ready
                if let uuid = UUID(uuidString: item.id) {
                    queueCoordinator.updateCachedAudioURL(for: uuid, url: audioURL)
                }

                // Get duration if possible
                if let player = try? AVAudioPlayer(contentsOf: audioURL) {
                    item.duration = player.duration
                }
                pipelineTimer.endStep(audioLoadStepIdx)

                print("[UnifiedPlayer] Generated audio for: \(item.title)")
                print("[UnifiedPlayer] Audio URL: \(audioURL.path)")
                let _ = pipelineTimer.report()
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
    
    /// Fallback to cloud TTS when on-device fails
    private func fallbackToCloudTTS(text: String, article: Article) async throws -> URL {
        // Try OpenAI first
        if let apiKey = UserDefaultsManager.shared.openAIAPIKey, !apiKey.isEmpty {
            generationPhase = .generatingAudio(provider: "OpenAI")
            do {
                return try await openAITTS.generateAudioForArticle(
                    title: article.title,
                    content: text,
                    useStreaming: UserDefaultsManager.shared.useOpenAIStreaming
                )
            } catch {
                print("[UnifiedPlayer] OpenAI fallback also failed: \(error)")
            }
        }

        // Fall back to Gemini
        generationPhase = .generatingAudio(provider: "Gemini")
        return try await ttsGenerator.generateAudioFile(
            from: text,
            trackingIn: context,
            for: article
        )
    }

    /// Pre-generate audio for next items
    private func preGenerateNextItems() async {
        // Cancel existing pre-generation
        preGenerationTask?.cancel()
        
        preGenerationTask = Task {
            // Pre-generate the immediate next item only. This keeps playback smooth without
            // spending summary/TTS calls on items the user may never reach.
            let indicesToGenerate = [
                currentIndex + 1
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
        
        let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Ensure we have something meaningful to speak
        if finalText.count < 50 {
            print("[UnifiedPlayer] Warning: Article text too short (\(text.count) chars)")
        }

        return truncateForBriefing(finalText, maxCharacters: 1_200)
    }

    private func truncateForBriefing(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else {
            return text
        }

        let truncated = String(text.prefix(maxCharacters))
        let sentenceEndings = CharacterSet(charactersIn: ".!?")

        if let sentenceBoundary = truncated.rangeOfCharacter(from: sentenceEndings, options: .backwards) {
            let end = truncated.index(after: sentenceBoundary.lowerBound)
            let briefing = String(truncated[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if briefing.count >= 300 {
                print("[UnifiedPlayer] Truncated TTS briefing from \(text.count) to \(briefing.count) characters")
                return briefing
            }
        }

        let briefing = truncated.trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        print("[UnifiedPlayer] Truncated TTS briefing from \(text.count) to \(briefing.count) characters")
        return briefing
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
    
    func handleAppBackground() {
        saveAppLifecycleState(isTermination: false)
    }

    func handleAppTermination() {
        saveAppLifecycleState(isTermination: true)
    }

    func handleAppForeground() {
        if isPlaying {
            startProgressTimer()
        }
    }

    private func saveAppLifecycleState(isTermination: Bool) {
        if activeMode == .brief {
            queueCoordinator.updateCurrentPosition(validLifecyclePosition(audioPlayer.currentTime))
        }
        queueCoordinator.saveStateNow()

        let radioPosition: TimeInterval
        let radioDuration: TimeInterval?
        if activeMode == .radio, activeRadioKey == radioCoordinator.currentKey {
            radioPosition = validLifecyclePosition(audioPlayer.currentTime)
            let transportDuration = audioPlayer.duration
            radioDuration = transportDuration.isFinite && transportDuration > 0
                ? transportDuration
                : radioCoordinator.currentEpisode?.durationSeconds
        } else {
            radioPosition = radioCoordinator.currentKey.flatMap { key in
                radioCoordinator.entries.first(where: { $0.key == key })?.positionSeconds
            } ?? 0
            radioDuration = radioCoordinator.currentEpisode?.durationSeconds
        }

        if isTermination {
            _ = radioCoordinator.handleTermination(
                positionSeconds: radioPosition,
                duration: radioDuration
            )
        } else {
            _ = radioCoordinator.handleBackground(
                positionSeconds: radioPosition,
                duration: radioDuration
            )
        }
    }

    private func validLifecyclePosition(_ position: TimeInterval) -> TimeInterval {
        position.isFinite ? max(0, position) : 0
    }

    private var hasResumableRadioEpisode: Bool {
        guard let key = radioCoordinator.currentKey,
              radioCoordinator.currentEpisode != nil,
              let entry = radioCoordinator.entries.first(where: { $0.key == key }),
              entry.disposition != .failedThisSession else { return false }
        switch radioCoordinator.state {
        case .exhausted, .noSources:
            return false
        default:
            return true
        }
    }

    private var radioControlPosition: TimeInterval {
        if activeMode == .radio { return finiteNonnegative(currentTime) }
        guard let key = radioCoordinator.currentKey else { return 0 }
        return finiteNonnegative(
            radioCoordinator.entries.first(where: { $0.key == key })?.positionSeconds ?? 0
        )
    }

    private var effectiveControlPosition: TimeInterval {
        switch effectivePlaybackMode {
        case .radio:
            return radioControlPosition
        case .brief where activeMode == .none:
            return finiteNonnegative(queueCoordinator.currentPosition)
        case .brief, .none:
            return finiteNonnegative(currentTime)
        }
    }

    private var radioControlDuration: TimeInterval? {
        let candidate = activeMode == .radio && duration.isFinite && duration > 0
            ? duration
            : radioCoordinator.currentEpisode?.durationSeconds
        guard let candidate, candidate.isFinite, candidate > 0 else { return nil }
        return candidate
    }

    private func finiteNonnegative(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? max(0, value) : 0
    }
    
    private func startProgressTimer() {
        playbackProgressTimer?.invalidate()
        playbackProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateProgress()
            }
        }
    }
    
    private func updateProgress() {
        currentTime = audioPlayer.currentTime
        duration = audioPlayer.duration

        if activeMode == .brief, Int(currentTime) % 5 == 0 {
            queueCoordinator.updateCurrentPosition(currentTime)
        } else if activeMode == .radio, let activeRadioKey {
            radioCoordinator.recordProgress(
                for: activeRadioKey,
                positionSeconds: currentTime,
                duration: duration > 0 ? duration : nil
            )
        }
    }
}

// MARK: - SwiftAudioExService Delegate

extension UnifiedAudioPlayer: SwiftAudioExServiceDelegate {
    func audioItemReady(id: TransportPlaybackID, duration: TimeInterval) {
        guard id == activePlaybackID else { return }
        self.duration = duration
        if let seekTime = pendingSeekTime {
            audioPlayer.seek(to: seekTime)
            currentTime = seekTime
            pendingSeekTime = nil
        }
    }

    func audioStateChanged(id: TransportPlaybackID, to newState: SwiftAudioPlayerState, from oldState: SwiftAudioPlayerState) {
        guard id == activePlaybackID else { return }
        switch newState {
        case .playing:
            isPlaying = true
            if activeMode == .radio, let activeRadioKey {
                radioCoordinator.transportDidStart(for: activeRadioKey)
            }
            startProgressTimer()
        case .paused, .stopped, .error:
            isPlaying = false
            playbackProgressTimer?.invalidate()
        case .idle, .loading:
            break
        }
        updateRemoteAvailability()
    }

    func audioProgressUpdated(id: TransportPlaybackID, progress: Float, currentTime: TimeInterval, duration: TimeInterval) {
        guard id == activePlaybackID else { return }
        self.currentTime = currentTime
        self.duration = duration
        switch activeMode {
        case .radio:
            guard let key = activeRadioKey else { return }
            radioCoordinator.recordProgress(for: key, positionSeconds: currentTime, duration: duration > 0 ? duration : nil)
            if let intent = radioCoordinator.evaluateSleepTimer(
                at: Date(),
                positionSeconds: currentTime,
                duration: duration > 0 ? duration : nil
            ) {
                guard let context = radioEventContext(callbackID: id) else { return }
                scheduleRadioEvent(context) { _ in intent }
            }
        case .brief:
            queueCoordinator.updateCurrentPosition(currentTime)
        case .none:
            break
        }
    }

    func audioDidFinishPlaying(id: TransportPlaybackID, successfully: Bool) {
        guard id == activePlaybackID, consumedPlaybackIDs.insert(id).inserted else { return }
        isPlaying = false
        if let context = radioEventContext(callbackID: id) {
            let completedAt = Date()
            let position = currentTime
            let knownDuration = duration > 0 ? duration : nil
            let intent = successfully
                ? radioCoordinator.playbackCompleted(for: context.key, at: completedAt)
                : radioCoordinator.playbackFailed(
                    for: context.key,
                    message: "Audio playback failed",
                    positionSeconds: position,
                    duration: knownDuration,
                    connectivity: radioCoordinator.currentConnectivityStatus
                )
            scheduleRadioIntent(intent, for: context)
        } else if successfully, activeMode == .brief {
            Task { @MainActor [weak self] in
                guard let self, self.activeMode == .brief, self.activePlaybackID == id else { return }
                await self.handleTrackFinished()
            }
        }
    }

    func audioInterruptionBegan(id: TransportPlaybackID?) {
        guard id == nil || id == activePlaybackID else { return }
        if let context = radioEventContext(callbackID: id) {
            let position = currentTime
            let knownDuration = duration > 0 ? duration : nil
            scheduleRadioEvent(context) { coordinator in
                coordinator.handleInterruptionBegan(positionSeconds: position, duration: knownDuration)
            }
        } else if activeMode == .brief {
            briefInterruptionResumeEligible = isPlaying
            queueCoordinator.updateCurrentPosition(currentTime)
            queueCoordinator.saveStateNow()
            audioPlayer.pause()
        }
    }

    func audioInterruptionEnded(id: TransportPlaybackID?, shouldResume: Bool) {
        guard id == nil || id == activePlaybackID else { return }
        if let context = radioEventContext(callbackID: id) {
            scheduleRadioEvent(context) { coordinator in
                coordinator.handleInterruptionEnded(shouldResume: shouldResume)
            }
        } else if activeMode == .brief {
            let resumeEligible = briefInterruptionResumeEligible
            briefInterruptionResumeEligible = false
            if shouldResume, resumeEligible { audioPlayer.resume() }
        }
    }

    func audioRouteWasRemoved(id: TransportPlaybackID?) {
        guard id == nil || id == activePlaybackID else { return }
        if let context = radioEventContext(callbackID: id) {
            let position = currentTime
            let knownDuration = duration > 0 ? duration : nil
            scheduleRadioEvent(context) { coordinator in
                coordinator.handleRouteRemoval(positionSeconds: position, duration: knownDuration)
            }
        } else if activeMode == .brief {
            queueCoordinator.updateCurrentPosition(currentTime)
            queueCoordinator.saveStateNow()
            audioPlayer.pause()
            isPlaying = false
        }
    }

    func audioRequestPlay() { Task { @MainActor in await beginEffectiveCurrent() } }
    func audioRequestPause() { pause() }
    func audioRequestSeek(to seconds: TimeInterval) { seek(to: seconds) }
    func audioRequestSkipBackward(seconds: TimeInterval) { skipBackward(seconds) }
    func audioRequestSkipForward(seconds: TimeInterval) { skipForward(seconds) }
    func audioRequestNextTrack() { Task { @MainActor in await playNext() } }
    func audioRequestRate(_ rate: Float) { setRate(rate) }
}

// MARK: - Convenience Methods

extension UnifiedAudioPlayer {
    
    /// Get progress percentage
    var progressPercentage: Double {
        let duration = presentationDuration
        guard duration > 0 else { return 0 }
        return presentationPosition / duration
    }
    
    /// Get formatted current time
    var formattedCurrentTime: String {
        formatTime(presentationPosition)
    }
    
    /// Get formatted duration
    var formattedDuration: String {
        formatTime(presentationDuration)
    }
    
    /// Get formatted remaining time
    var formattedRemainingTime: String {
        formatTime(presentationDuration - presentationPosition)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(finiteNonnegative(time).rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Check if can play next
    var canPlayNext: Bool {
        effectivePlaybackMode == .radio
            ? radioCoordinator.canPlayNext
            : currentIndex >= 0 && currentIndex < queue.count - 1
    }

    /// Check if can play previous
    var canPlayPrevious: Bool {
        effectivePlaybackMode == .radio ? false : currentIndex > 0
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
