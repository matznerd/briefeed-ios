//
//  AppViewModel.swift
//  Briefeed
//
//  Central ViewModel that properly wraps ALL singleton services
//  This fixes the "Publishing changes from within view updates" UI freeze
//

import Foundation
import SwiftUI
import Combine
import CoreData

/// The ONE AND ONLY ViewModel that views should use as @StateObject
/// This wraps all singleton services and provides reactive UI updates
@MainActor
final class AppViewModel: ObservableObject {
    
    // MARK: - Audio State
    @Published private(set) var isPlaying = false {
        didSet {
            if oldValue != isPlaying {
                perfLog.logPublisher("AppViewModel.isPlaying", value: "\(oldValue) -> \(isPlaying)")
            }
        }
    }
    @Published private(set) var isAudioLoading = false {
        didSet {
            if oldValue != isAudioLoading {
                perfLog.logPublisher("AppViewModel.isAudioLoading", value: "\(oldValue) -> \(isAudioLoading)")
            }
        }
    }
    @Published private(set) var currentAudioTitle = "" {
        didSet {
            if oldValue != currentAudioTitle {
                perfLog.logPublisher("AppViewModel.currentAudioTitle", value: "changed to: \(currentAudioTitle)")
            }
        }
    }
    @Published private(set) var currentAudioArtist = "" {
        didSet {
            if oldValue != currentAudioArtist {
                perfLog.logPublisher("AppViewModel.currentAudioArtist", value: "changed")
            }
        }
    }
    @Published private(set) var currentTime: TimeInterval = 0 {
        didSet {
            // Only log significant changes (> 0.5 seconds) to avoid spam
            if abs(oldValue - currentTime) > 0.5 {
                perfLog.logPublisher("AppViewModel.currentTime", value: String(format: "%.1f", currentTime))
            }
        }
    }
    @Published private(set) var duration: TimeInterval = 0 {
        didSet {
            if oldValue != duration {
                perfLog.logPublisher("AppViewModel.duration", value: String(format: "%.1f", duration))
            }
        }
    }
    @Published private(set) var playbackRate: Float = 1.0 {
        didSet {
            if oldValue != playbackRate {
                perfLog.logPublisher("AppViewModel.playbackRate", value: "\(playbackRate)")
            }
        }
    }
    @Published var volume: Float = 1.0 {
        didSet {
            if oldValue != volume {
                perfLog.logPublisher("AppViewModel.volume", value: "\(volume)")
            }
        }
    }
    
    // MARK: - Queue State
    @Published private(set) var queueItems: [EnhancedQueueItem] = [] {
        didSet {
            if oldValue.count != queueItems.count {
                perfLog.logPublisher("AppViewModel.queueItems", value: "count: \(oldValue.count) -> \(queueItems.count)")
            }
        }
    }
    @Published private(set) var queueCount = 0 {
        didSet {
            if oldValue != queueCount {
                perfLog.logPublisher("AppViewModel.queueCount", value: "\(oldValue) -> \(queueCount)")
            }
        }
    }
    @Published private(set) var currentQueueIndex = -1 {
        didSet {
            if oldValue != currentQueueIndex {
                perfLog.logPublisher("AppViewModel.currentQueueIndex", value: "\(oldValue) -> \(currentQueueIndex)")
            }
        }
    }
    @Published private(set) var hasNext = false {
        didSet {
            if oldValue != hasNext {
                perfLog.logPublisher("AppViewModel.hasNext", value: "\(oldValue) -> \(hasNext)")
            }
        }
    }
    @Published private(set) var hasPrevious = false {
        didSet {
            if oldValue != hasPrevious {
                perfLog.logPublisher("AppViewModel.hasPrevious", value: "\(oldValue) -> \(hasPrevious)")
            }
        }
    }
    
    // MARK: - Article State
    @Published private(set) var articles: [Article] = []
    @Published private(set) var isLoadingArticles = false
    @Published private(set) var articlesError: String?
    @Published var selectedFeedFilter: String = "all"
    
    // MARK: - Processing Status
    @Published private(set) var showStatusBanner = false
    @Published private(set) var statusMessage = ""
    @Published private(set) var processingProgress: Double = 0
    
    // MARK: - RSS State
    @Published private(set) var rssFeeds: [RSSFeed] = []
    @Published private(set) var rssEpisodes: [RSSEpisode] = []
    @Published private(set) var isLoadingRSS = false
    
    // MARK: - Service Connection State
    @Published private(set) var isConnectingServices = false
    @Published private(set) var servicesConnected = false
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?
    private var progressTimer: Timer?
    private var lastSyncTime = Date()
    
    // Services - accessed after init to avoid triggering during construction
    private var audioService: BriefeedAudioService?
    private var queueService: QueueServiceV2?
    private var stateManager: ArticleStateManager?
    private var statusService: ProcessingStatusService?
    private var rssService: RSSAudioService?
    
    // Core Data
    let viewContext: NSManagedObjectContext
    
    // Prevent multiple subscriptions
    private var hasSetupSubscriptions = false
    
    // MARK: - Initialization
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        perfLog.startOperation("AppViewModel.init")
        self.viewContext = context
        print("🚀 AppViewModel: Initializing...")
        perfLog.logService("AppViewModel", method: "init", detail: "Started")
        // DO NOT access any singletons here!
        // Everything is deferred to connectToServices()
        perfLog.endOperation("AppViewModel.init")
    }
    
    deinit {
        print("🚀 AppViewModel: Deinitializing...")
        perfLog.logService("AppViewModel", method: "deinit", detail: "Cleaning up")
        updateTimer?.invalidate()
        progressTimer?.invalidate()
    }
    
    // MARK: - Combine Subscriptions
    
    private func setupCombineSubscriptions() {
        guard !hasSetupSubscriptions else {
            print("⚠️ AppViewModel: Subscriptions already set up, skipping...")
            return
        }
        hasSetupSubscriptions = true
        
        print("🔄 AppViewModel: Setting up Combine subscriptions...")
        
        // Subscribe to audio service changes with throttling
        if let audio = audioService {
            print("  📡 Subscribing to audio service changes...")
            
            // Only update when playback state actually changes
            audio.$isPlaying
                .removeDuplicates()
                .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] isPlaying in
                    guard let self = self else { return }
                    // Only update if actually changed
                    if self.isPlaying != isPlaying {
                        print("    🔊 isPlaying changed: \(isPlaying)")
                        self.isPlaying = isPlaying
                        // Start/stop progress timer based on playback state
                        if isPlaying {
                            self.startProgressTimer()
                        } else {
                            self.stopProgressTimer()
                        }
                    }
                }
                .store(in: &cancellables)
            
            audio.$currentItem
                .removeDuplicates { $0?.content.id == $1?.content.id }
                .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] item in
                    print("    🎵 currentItem changed: \(item?.content.title ?? "nil")")
                    guard let self = self else { return }
                    if let item = item {
                        self.currentAudioTitle = item.content.title
                        if let article = item.content as? ArticleAudioContent {
                            self.currentAudioArtist = article.author ?? ""
                        } else if let episode = item.content as? RSSEpisodeAudioContent {
                            self.currentAudioArtist = episode.feedTitle ?? ""
                        } else {
                            self.currentAudioArtist = ""
                        }
                    } else {
                        self.currentAudioTitle = ""
                        self.currentAudioArtist = ""
                    }
                }
                .store(in: &cancellables)
            
            // DISABLED: Time updates cause continuous UI updates and freezes
            // Even with throttling, this fires every second and causes hangs
            // audio.$currentTime
            //     .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            //     .sink { [weak self] time in
            //         print("    ⏱️ currentTime updated: \(time)")
            //         self?.currentTime = time
            //     }
            //     .store(in: &cancellables)
            
            audio.$duration
                .removeDuplicates()
                .sink { [weak self] duration in
                    print("    ⏱️ duration changed: \(duration)")
                    self?.duration = duration
                }
                .store(in: &cancellables)
        } else {
            print("  ⚠️ No audio service available")
        }
        
        // Subscribe to queue changes with throttling
        if let queue = queueService {
            print("  📡 Subscribing to queue service changes...")
            
            queue.$queue
                .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] items in
                    guard let self = self else { return }
                    // Only update if actually changed
                    if self.queueItems.count != items.count || 
                       !self.queueItems.elementsEqual(items, by: { $0.id == $1.id }) {
                        print("    📋 queue updated: \(items.count) items")
                        self.queueItems = items
                        self.queueCount = items.count
                    }
                }
                .store(in: &cancellables)
            
            queue.$currentIndex
                .removeDuplicates()
                .sink { [weak self] index in
                    print("    📍 currentIndex changed: \(index)")
                    guard let self = self else { return }
                    self.currentQueueIndex = index
                    self.hasNext = index < self.queueItems.count - 1
                    self.hasPrevious = index > 0
                }
                .store(in: &cancellables)
        } else {
            print("  ⚠️ No queue service available")
        }
        
        print("✅ AppViewModel: Combine subscriptions setup complete")
    }
    
    // MARK: - Service Connection
    
    /// Connect to services AFTER view construction
    /// Call this from ContentView's .task modifier
    /// Runs heavy operations on background thread
    func connectToServices() async {
        perfLog.startOperation("AppViewModel.connectToServices")
        
        guard !servicesConnected else {
            print("⚠️ Services already connected")
            perfLog.log("Services already connected, skipping", category: .warning)
            perfLog.endOperation("AppViewModel.connectToServices")
            return
        }
        
        isConnectingServices = true
        print("🚀 AppViewModel: Connecting to services...")
        perfLog.logService("AppViewModel", method: "connectToServices", detail: "Starting service connections")
        
        // Get services (singletons are already initialized)
        perfLog.startOperation("Get BriefeedAudioService")
        print("  🎵 Getting BriefeedAudioService...")
        audioService = BriefeedAudioService.shared
        perfLog.endOperation("Get BriefeedAudioService")
        
        perfLog.startOperation("Get QueueServiceV2")
        print("  📋 Getting QueueServiceV2...")
        queueService = QueueServiceV2.shared
        perfLog.endOperation("Get QueueServiceV2")
        
        perfLog.startOperation("Get ArticleStateManager")
        print("  📊 Getting ArticleStateManager...")
        stateManager = ArticleStateManager.shared
        perfLog.endOperation("Get ArticleStateManager")
        
        perfLog.startOperation("Get ProcessingStatusService")
        print("  ⚙️ Getting ProcessingStatusService...")
        statusService = ProcessingStatusService.shared
        perfLog.endOperation("Get ProcessingStatusService")
        
        perfLog.startOperation("Get RSSAudioService")
        print("  📻 Getting RSSAudioService...")
        rssService = RSSAudioService.shared
        perfLog.endOperation("Get RSSAudioService")
        
        // Initialize services (these are lightweight operations)
        perfLog.startOperation("Initialize services")
        queueService?.initialize()
        stateManager?.initialize()
        rssService?.initialize()
        perfLog.endOperation("Initialize services")
        
        // DISABLED: Polling causes UI freezes
        // startPolling()
        
        // Initial state sync only
        perfLog.startOperation("Initial state sync")
        await syncState()
        perfLog.endOperation("Initial state sync")
        
        // TEMPORARILY DISABLED to test if this causes freeze
        // setupCombineSubscriptions()
        
        // Load initial data on background thread
        await Task.detached(priority: .userInitiated) {
            perfLog.startOperation("Load initial data")
            await self.loadArticles()
            await self.loadRSSFeeds()
            perfLog.endOperation("Load initial data")
            
            // Initialize RSS features (moved from BriefeedApp.init)
            perfLog.startOperation("Initialize RSS features")
            await self.initializeRSSFeatures()
            perfLog.endOperation("Initialize RSS features")
        }.value
        
        servicesConnected = true
        isConnectingServices = false
        print("✅ AppViewModel: Connected and initialized")
        perfLog.logService("AppViewModel", method: "connectToServices", detail: "Completed successfully")
        perfLog.endOperation("AppViewModel.connectToServices")
    }
    
    // MARK: - State Synchronization
    
    private func startPolling() {
        // DISABLED: Polling causes continuous UI updates and freezes
        // We'll use Combine subscriptions instead once stable
        return
        
        // updateTimer?.invalidate()
        // updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        //     Task { @MainActor [weak self] in
        //         await self?.syncState()
        //     }
        // }
    }
    
    // MARK: - Progress Timer Management
    
    private func startProgressTimer() {
        // Stop any existing timer
        stopProgressTimer()
        
        // Update immediately
        updatePlaybackProgress()
        
        // Then update every 0.5 seconds (less frequent than before)
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePlaybackProgress()
            }
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func updatePlaybackProgress() {
        if let audio = audioService {
            // Only update if actually changed significantly (more than 0.1 second difference)
            let newTime = audio.currentTime
            if abs(newTime - currentTime) > 0.1 {
                currentTime = newTime
            }
        }
    }
    
    private func syncState() async {
        // Audio state
        if let audio = audioService {
            isPlaying = audio.isPlaying
            isAudioLoading = audio.isLoading
            // DISABLED: Don't sync currentTime here as it changes every second
            // currentTime = audio.currentTime
            duration = audio.duration
            playbackRate = audio.playbackRate
            
            if let item = audio.currentItem {
                currentAudioTitle = item.content.title
                // Get artist based on content type
                if let article = item.content as? ArticleAudioContent {
                    currentAudioArtist = article.author ?? ""
                } else if let episode = item.content as? RSSEpisodeAudioContent {
                    currentAudioArtist = episode.feedTitle ?? ""
                } else {
                    currentAudioArtist = ""
                }
            } else {
                currentAudioTitle = ""
                currentAudioArtist = ""
            }
        }
        
        // Queue state
        if let queue = queueService {
            queueItems = queue.queue
            queueCount = queue.queue.count
            currentQueueIndex = queue.currentIndex
            hasNext = queue.currentIndex < queue.queue.count - 1
            hasPrevious = queue.currentIndex > 0
        }
        
        // Article state
        if stateManager != nil {
            // ArticleStateManager doesn't expose these, set defaults
            isLoadingArticles = false
            articlesError = nil
        }
        
        // Status state
        if let status = statusService {
            showStatusBanner = status.showStatusBanner
            // Get message from current status
            switch status.currentStatus {
            case .idle:
                statusMessage = ""
            case .fetchingContent:
                statusMessage = "Fetching content..."
            case .contentFetched:
                statusMessage = "Content fetched"
            case .generatingSummary:
                statusMessage = "Generating summary..."
            case .summaryGenerated:
                statusMessage = "Summary generated"
            case .generatingAudio:
                statusMessage = "Generating audio..."
            case .audioReady:
                statusMessage = "Audio ready"
            case .completed:
                statusMessage = "Completed"
            case .error(let msg):
                statusMessage = "Error: \(msg)"
            @unknown default:
                statusMessage = ""
            }
            processingProgress = 0
        }
    }
    
    // MARK: - Audio Controls
    
    func play() {
        audioService?.play()
    }
    
    func pause() {
        audioService?.pause()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func playNext() {
        Task {
            await audioService?.playNext()
        }
    }
    
    func playPrevious() {
        Task {
            await audioService?.playPrevious()
        }
    }
    
    func seek(to time: TimeInterval) {
        audioService?.seek(to: time)
    }
    
    func setPlaybackRate(_ rate: Float) {
        audioService?.setPlaybackRate(rate)
    }
    
    // MARK: - Queue Management
    
    func addToQueue(article: Article, playNext: Bool = false) async {
        await queueService?.addArticle(article, playNext: playNext)
    }
    
    func addToQueue(episode: RSSEpisode, playNext: Bool = false) async {
        queueService?.addRSSEpisode(episode, playNext: playNext)
    }
    
    func removeFromQueue(at index: Int) {
        queueService?.removeItem(at: index)
    }
    
    func clearQueue() {
        queueService?.clearQueue()
    }
    
    func moveInQueue(from: Int, to: Int) {
        queueService?.moveItem(from: IndexSet(integer: from), to: to)
    }
    
    // MARK: - Article Management
    
    func loadArticles() async {
        // ArticleStateManager doesn't have loadArticles method
        
        // Fetch from Core Data
        let request: NSFetchRequest<Article> = Article.fetchRequest()
        // Article entity only has createdAt field, not pubDate or publishedDate
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        if selectedFeedFilter != "all" {
            request.predicate = NSPredicate(format: "feed.id == %@", selectedFeedFilter)
        }
        
        do {
            articles = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch articles: \(error)")
            articles = []
        }
    }
    
    func markArticleAsRead(_ article: Article) {
        // ArticleStateManager handles this internally through article properties
        article.isRead = true
        try? viewContext.save()
    }
    
    func toggleArticleSaved(_ article: Article) {
        // ArticleStateManager handles this internally through article properties
        article.isSaved.toggle()
        try? viewContext.save()
    }
    
    // MARK: - RSS Management
    
    func loadRSSFeeds() async {
        isLoadingRSS = true
        defer { isLoadingRSS = false }
        
        // RSSAudioService doesn't have these methods, use Core Data directly
        let request: NSFetchRequest<RSSFeed> = RSSFeed.fetchRequest()
        do {
            rssFeeds = try viewContext.fetch(request)
        } catch {
            print("Failed to fetch RSS feeds: \(error)")
        }
    }
    
    func loadRSSEpisodes(for feed: RSSFeed? = nil) async {
        isLoadingRSS = true
        defer { isLoadingRSS = false }
        
        let request: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
        if let feed = feed {
            request.predicate = NSPredicate(format: "feed == %@", feed)
        }
        
        do {
            rssEpisodes = try viewContext.fetch(request)
        } catch {
            print("Failed to fetch RSS episodes: \(error)")
        }
    }
    
    func playLiveNews() async {
        // This would need to be implemented
        print("Play Live News requested")
    }
    
    // MARK: - RSS Initialization
    
    private func initializeRSSFeatures() async {
        print("📡 Initializing RSS features from AppViewModel...")
        
        // Register RSS defaults
        UserDefaultsManager.shared.registerRSSDefaults()
        UserDefaultsManager.shared.loadRSSSettings()
        
        // Initialize default RSS feeds if needed
        if let rss = rssService {
            await rss.initializeDefaultFeedsIfNeeded()
            print("✅ RSS feeds initialized")
        }
        
        // Handle auto-play if enabled
        if UserDefaultsManager.shared.autoPlayLiveNewsOnOpen {
            // Refresh feeds if needed
            if let rss = rssService {
                await rss.refreshAllFeeds()
            }
        }
    }
    
    // MARK: - Debug Methods
    
    /// Debug method to check queue state
    func debugQueueState() {
        print("🧪 DEBUG: Queue State Check")
        print("  Services connected: \(servicesConnected)")
        print("  Queue count: \(queueCount)")
        print("  Current index: \(currentQueueIndex)")
        print("  Has next: \(hasNext)")
        print("  Has previous: \(hasPrevious)")
        print("  Is playing: \(isPlaying)")
        print("  Current title: \(currentAudioTitle)")
        
        if let queue = queueService {
            print("  QueueService exists: ✅")
            print("  Actual queue count: \(queue.queue.count)")
            print("  Actual current index: \(queue.currentIndex)")
        } else {
            print("  QueueService exists: ❌")
        }
        
        if let audio = audioService {
            print("  AudioService exists: ✅")
            print("  Audio is playing: \(audio.isPlaying)")
            print("  Audio current item: \(audio.currentItem?.content.title ?? "None")")
        } else {
            print("  AudioService exists: ❌")
        }
    }
    
    // MARK: - Cleanup
    
    func disconnect() {
        updateTimer?.invalidate()
        updateTimer = nil
        progressTimer?.invalidate()
        progressTimer = nil
        cancellables.removeAll()
    }
}