//
//  QueueServiceV2.swift
//  Briefeed
//
//  Refactored queue service that properly coordinates with BriefeedAudioService
//

import Foundation
import CoreData
import Combine

/// Modern queue service that manages the app's playback queue
class QueueServiceV2: ObservableObject {
    
    // MARK: - Singleton
    private static var _shared: QueueServiceV2?
    static var shared: QueueServiceV2 {
        if _shared == nil {
            _shared = QueueServiceV2()
        }
        return _shared!
    }
    
    // MARK: - Published Properties
    @Published private(set) var queue: [EnhancedQueueItem] = []
    @Published private(set) var currentIndex: Int = -1
    @Published private(set) var isLoading = false
    
    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    private let queueKey = "EnhancedAudioQueueV2"
    private let indexKey = "EnhancedAudioQueueIndexV2"
    private lazy var audioService = BriefeedAudioService.shared
    private let geminiService = GeminiService()
    private var cancellables = Set<AnyCancellable>()
    
    // Background TTS generation
    private var ttsGenerationTasks: [UUID: Task<Void, Never>] = [:]
    
    // Deferred sync timer to avoid UI freezes
    private var deferredSyncTimer: Timer?
    private var needsSync = false
    
    // MARK: - Initialization
    private var hasInitialized = false
    
    private init() {
        perfLog.logService("QueueServiceV2", method: "init", detail: "Started")
        // Don't do ANY initialization here
        // Everything will be done in initialize() method
    }
    
    /// Call this after views are rendered
    func initialize() {
        guard !hasInitialized else { 
            perfLog.log("QueueServiceV2.initialize: Already initialized", category: .warning)
            return 
        }
        hasInitialized = true
        
        perfLog.startOperation("QueueServiceV2.initialize")
        
        // Setup observers immediately
        setupObservers()
        
        // Load queue asynchronously to avoid blocking
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.loadQueue()
        }
        
        perfLog.endOperation("QueueServiceV2.initialize")
    }
    
    // MARK: - Setup
    private func setupObservers() {
        // Observe when BriefeedAudioService finishes playing an item
        audioService.$currentItem
            .dropFirst() // Skip initial value to avoid immediate update
            .sink { [weak self] currentItem in
                self?.updateCurrentIndex(for: currentItem)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Queue Management
    
    /// Add an article to the queue
    func addArticle(_ article: Article, playNext: Bool = false) async {
        print("📥 QueueServiceV2: Adding article to queue")
        print("  Title: \(article.title ?? "Unknown")")
        print("  PlayNext: \(playNext)")
        guard let articleID = article.id else { return }
        
        // Check if already in queue
        if await MainActor.run(body: { queue.contains(where: { $0.articleID == articleID }) }) {
            return
        }
        
        // Create enhanced queue item
        let item = EnhancedQueueItem(from: article)
        
        await MainActor.run {
            if playNext && currentIndex >= 0 {
                queue.insert(item, at: currentIndex + 1)
            } else {
                queue.append(item)
            }
        }
        
        saveQueue()
        
        // Start background TTS generation
        startTTSGeneration(for: article)
        
        // Schedule deferred sync to avoid UI freeze
        await MainActor.run {
            scheduleDeferredSync()
        }
    }
    
    /// Add an RSS episode to the queue
    func addRSSEpisode(_ episode: RSSEpisode, playNext: Bool = false) {
        print("📥 QueueServiceV2: Adding RSS episode to queue")
        print("  Title: \(episode.title)")
        print("  PlayNext: \(playNext)")
        // Check if already in queue
        if queue.contains(where: { $0.audioUrl?.absoluteString == episode.audioUrl }) {
            return
        }
        
        // Create enhanced queue item
        let item = EnhancedQueueItem(from: episode)
        
        if playNext && currentIndex >= 0 {
            queue.insert(item, at: currentIndex + 1)
        } else {
            queue.append(item)
        }
        
        saveQueue()
        
        // Schedule deferred sync to avoid UI freeze
        scheduleDeferredSync()
    }
    
    /// Remove an item from the queue
    func removeItem(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        
        let item = queue[index]
        
        // Cancel TTS generation if in progress
        if let task = ttsGenerationTasks[item.id] {
            task.cancel()
            ttsGenerationTasks.removeValue(forKey: item.id)
        }
        
        queue.remove(at: index)
        
        // Adjust current index
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            currentIndex = min(currentIndex, queue.count - 1)
        }
        
        saveQueue()
        
        // Schedule deferred sync to avoid UI freeze
        scheduleDeferredSync()
    }
    
    /// Reorder the queue
    func moveItem(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        
        // Adjust current index
        for index in source {
            if index == currentIndex {
                currentIndex = destination > index ? destination - 1 : destination
            }
        }
        
        saveQueue()
        
        // Schedule deferred sync to avoid UI freeze
        scheduleDeferredSync()
    }
    
    /// Clear the entire queue
    func clearQueue() {
        Task { @MainActor in
            print("🗑️ QueueServiceV2: Clearing queue")
            print("  Previous size: \(queue.count)")
            // Cancel all TTS generation tasks
            for task in ttsGenerationTasks.values {
                task.cancel()
            }
            ttsGenerationTasks.removeAll()
            
            queue.removeAll()
            currentIndex = -1
        }
        saveQueue()
        
        audioService.clearQueue()
    }
    
    // MARK: - Playback Control
    
    /// Play a specific item in the queue
    func playItem(at index: Int) async {
        guard index >= 0 && index < queue.count else { return }
        
        currentIndex = index
        let item = queue[index]
        
        await playEnhancedItem(item)
    }
    
    /// Play the next item in the queue
    func playNext() async {
        print("⏭️ QueueServiceV2: playNext() called")
        print("  Queue size: \(queue.count)")
        print("  Current index: \(currentIndex)")
        guard currentIndex + 1 < queue.count else { return }
        
        currentIndex += 1
        let item = queue[currentIndex]
        
        await playEnhancedItem(item)
    }
    
    /// Play the previous item in the queue
    func playPrevious() async {
        guard currentIndex > 0 else { return }
        
        currentIndex -= 1
        let item = queue[currentIndex]
        
        await playEnhancedItem(item)
    }
    
    /// Play an item immediately (adds to queue if needed)
    func playNow(_ item: EnhancedQueueItem) async {
        // Add to queue if not already there
        if !queue.contains(where: { $0.id == item.id }) {
            queue.insert(item, at: 0)
            currentIndex = 0
        } else if let index = queue.firstIndex(where: { $0.id == item.id }) {
            currentIndex = index
        }
        
        saveQueue()
        await playEnhancedItem(item)
    }
    
    // MARK: - Private Playback Methods
    
    private func playEnhancedItem(_ item: EnhancedQueueItem) async {
        if let articleID = item.articleID {
            // Playing an article - fetch from Core Data
            if let article = await fetchArticle(id: articleID) {
                await audioService.playArticle(article, context: .brief)
            }
        } else if let audioUrl = item.audioUrl {
            // Playing an RSS episode
            if let episode = await fetchRSSEpisode(audioUrl: audioUrl.absoluteString) {
                await audioService.playRSSEpisode(episode, context: .liveNews)
            } else {
                // Play directly from URL if episode not found
                await audioService.playRSSEpisode(
                    url: audioUrl,
                    title: item.title,
                    episode: nil
                )
            }
        }
    }
    
    // MARK: - Audio Service Sync
    
    /// Sync queue to BriefeedAudioService
    private func syncToAudioService() async {
        // Clear audio service queue
        audioService.clearQueue()
        
        // Add all items to audio service queue
        for item in queue {
            if let articleID = item.articleID {
                if let article = await fetchArticle(id: articleID) {
                    await audioService.addToQueue(article)
                }
            } else if let episode = await fetchRSSEpisode(audioUrl: item.audioUrl?.absoluteString ?? "") {
                audioService.addToQueue(episode)
            }
        }
    }
    
    private func updateCurrentIndex(for audioItem: BriefeedAudioItem?) {
        guard let audioItem = audioItem else {
            return
        }
        
        // Find matching item in our queue
        if let index = queue.firstIndex(where: { item in
            if let articleID = item.articleID {
                return audioItem.content.id == articleID
            } else if let audioUrl = item.audioUrl {
                return audioItem.audioURL?.absoluteString == audioUrl.absoluteString
            }
            return false
        }) {
            currentIndex = index
        }
    }
    
    // MARK: - TTS Generation
    
    private func startTTSGeneration(for article: Article) {
        guard let articleID = article.id else { return }
        
        // Cancel existing task if any
        ttsGenerationTasks[articleID]?.cancel()
        
        // Start new generation task
        let task = Task {
            // Wait a bit to batch multiple additions
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            guard !Task.isCancelled else { return }
            
            // Generate TTS
            _ = await TTSGenerator.shared.generateAudio(for: article)
        }
        
        ttsGenerationTasks[articleID] = task
    }
    
    // MARK: - Persistence
    
    private func saveQueue() {
        // Save queue items
        let queueData = queue.map { item -> [String: Any] in
            var data: [String: Any] = [
                "id": item.id.uuidString,
                "type": item.type.rawValue,
                "dateAdded": item.addedDate
            ]
            
            data["title"] = item.title
            if let author = item.author { data["author"] = author }
            if let articleID = item.articleID { data["articleID"] = articleID.uuidString }
            if let audioUrl = item.audioUrl { data["audioUrl"] = audioUrl.absoluteString }
            if let feedTitle = item.feedTitle { data["feedTitle"] = feedTitle }
            
            return data
        }
        
        userDefaults.set(queueData, forKey: queueKey)
        userDefaults.set(currentIndex, forKey: indexKey)
    }
    
    private func loadQueue() {
        perfLog.startOperation("QueueServiceV2.loadQueue")
        print("📋 QueueServiceV2: Loading queue from UserDefaults...")
        
        // Load queue items from UserDefaults
        guard let queueData = self.userDefaults.array(forKey: self.queueKey) as? [[String: Any]] else {
            print("  ⚠️ No saved queue data found")
            perfLog.log("No saved queue data found", category: .queue)
            perfLog.endOperation("QueueServiceV2.loadQueue")
            return
        }
        
        perfLog.log("Found \(queueData.count) items in saved queue", category: .queue)
        print("  📦 Found \(queueData.count) items in saved queue")
        
        let loadedQueue = queueData.compactMap { data -> EnhancedQueueItem? in
            guard let idString = data["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let typeString = data["type"] as? String,
                  let type = EnhancedQueueItem.ItemType(rawValue: typeString),
                  let dateAdded = data["dateAdded"] as? Date else {
                return nil
            }
            
            let title = data["title"] as? String
            let author = data["author"] as? String
            let articleID = (data["articleID"] as? String).flatMap { UUID(uuidString: $0) }
            let audioUrl = (data["audioUrl"] as? String).flatMap { URL(string: $0) }
            let feedTitle = data["feedTitle"] as? String
            
            return EnhancedQueueItem(
                id: id,
                type: type,
                title: title,
                author: author,
                dateAdded: dateAdded,
                articleID: articleID,
                audioUrl: audioUrl,
                feedTitle: feedTitle
            )
        }
        
        let loadedIndex = self.userDefaults.integer(forKey: self.indexKey)
        
        // Update on main thread if needed
        if Thread.isMainThread {
            self.queue = loadedQueue
            self.currentIndex = loadedIndex
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.queue = loadedQueue
                self.currentIndex = loadedIndex
            }
        }
        
        print("  ✅ Loaded \(loadedQueue.count) items into queue")
        print("  📍 Current index from storage: \(loadedIndex)")
        
        // Validate current index
        var finalIndex = loadedIndex
        if !loadedQueue.isEmpty && loadedIndex == -1 {
            // If we have items but no current index, set to first item
            finalIndex = 0
            print("  🔧 Setting current index to 0 since queue has items")
        } else if loadedIndex >= loadedQueue.count {
            finalIndex = loadedQueue.isEmpty ? -1 : 0
            print("  🔧 Adjusted current index to: \(finalIndex)")
        }
        
        if finalIndex != loadedIndex {
            if Thread.isMainThread {
                self.currentIndex = finalIndex
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.currentIndex = finalIndex
                }
            }
        }
        
        // Schedule initial sync after UI is ready
        DispatchQueue.main.async { [weak self] in
            self?.scheduleDeferredSync(delay: 2.0)
        }
        
        perfLog.endOperation("QueueServiceV2.loadQueue")
    }
    
    // MARK: - Core Data Helpers
    
    private func fetchArticle(id: UUID) async -> Article? {
        return await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            let request: NSFetchRequest<Article> = Article.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            
            do {
                let articles = try context.fetch(request)
                return articles.first
            } catch {
                print("Failed to fetch article: \(error)")
                return nil
            }
        }
    }
    
    private func fetchRSSEpisode(audioUrl: String) async -> RSSEpisode? {
        return await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            let request: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
            request.predicate = NSPredicate(format: "audioUrl == %@", audioUrl)
            request.fetchLimit = 1
            
            do {
                let episodes = try context.fetch(request)
                return episodes.first
            } catch {
                print("Failed to fetch RSS episode: \(error)")
                return nil
            }
        }
    }
}

// MARK: - Convenience Methods
// MARK: - Deferred Sync

extension QueueServiceV2 {
    
    /// Schedule a deferred sync to avoid UI freezes
    private func scheduleDeferredSync(delay: TimeInterval = 0.5) {
        perfLog.log("QueueServiceV2.scheduleDeferredSync: Scheduling sync with delay \(delay)s", category: .queue)
        needsSync = true
        
        // Cancel existing timer
        if deferredSyncTimer != nil {
            perfLog.log("QueueServiceV2.scheduleDeferredSync: Cancelling existing timer", category: .queue)
        }
        deferredSyncTimer?.invalidate()
        
        // Schedule new sync
        deferredSyncTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            perfLog.log("QueueServiceV2.deferredSyncTimer fired", category: .queue)
            guard let self = self, self.needsSync else { 
                perfLog.log("QueueServiceV2.deferredSyncTimer: No sync needed", category: .queue)
                return 
            }
            
            Task {
                await self.performDeferredSync()
            }
        }
    }
    
    /// Perform the actual sync in a way that won't freeze UI
    private func performDeferredSync() async {
        guard needsSync else { 
            perfLog.log("QueueServiceV2.performDeferredSync: No sync needed", category: .queue)
            return 
        }
        needsSync = false
        
        perfLog.startOperation("QueueServiceV2.performDeferredSync")
        // Perform sync on background queue WITHOUT blocking with .value
        Task.detached(priority: .background) {
            await self.syncToAudioService()
        }
        perfLog.endOperation("QueueServiceV2.performDeferredSync")
    }
    
    /// Check if an article is in the queue
    func isArticleInQueue(_ articleID: UUID) -> Bool {
        queue.contains { $0.articleID == articleID }
    }
    
    /// Check if an RSS episode is in the queue
    func isEpisodeInQueue(_ audioUrl: String) -> Bool {
        queue.contains { $0.audioUrl?.absoluteString == audioUrl }
    }
    
    /// Get queue position for an item
    func queuePosition(for itemID: UUID) -> Int? {
        queue.firstIndex { $0.id == itemID }
    }
    
    /// Get current playing item
    var currentItem: EnhancedQueueItem? {
        guard currentIndex >= 0 && currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }
    
    /// Check if queue has next item
    var hasNext: Bool {
        currentIndex + 1 < queue.count
    }
    
    /// Check if queue has previous item
    var hasPrevious: Bool {
        currentIndex > 0
    }
}