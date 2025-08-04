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
@MainActor
class QueueServiceV2: ObservableObject {
    
    // MARK: - Singleton
    static let shared = QueueServiceV2()
    
    // MARK: - Published Properties
    @Published private(set) var queue: [EnhancedQueueItem] = []
    @Published private(set) var currentIndex: Int = -1
    @Published private(set) var isLoading = false
    
    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    private let queueKey = "EnhancedAudioQueueV2"
    private let indexKey = "EnhancedAudioQueueIndexV2"
    private let audioService = BriefeedAudioService.shared
    private let geminiService = GeminiService()
    private var cancellables = Set<AnyCancellable>()
    
    // Background TTS generation
    private var ttsGenerationTasks: [UUID: Task<Void, Never>] = [:]
    
    // MARK: - Initialization
    private init() {
        loadQueue()
        setupObservers()
    }
    
    // MARK: - Setup
    private func setupObservers() {
        // Observe when BriefeedAudioService finishes playing an item
        audioService.$currentItem
            .sink { [weak self] currentItem in
                self?.updateCurrentIndex(for: currentItem)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Queue Management
    
    /// Add an article to the queue
    func addArticle(_ article: Article, playNext: Bool = false) async {
        guard let articleID = article.id else { return }
        
        // Check if already in queue
        if queue.contains(where: { $0.articleID == articleID }) {
            return
        }
        
        // Create enhanced queue item
        let item = EnhancedQueueItem(from: article)
        
        if playNext && currentIndex >= 0 {
            queue.insert(item, at: currentIndex + 1)
        } else {
            queue.append(item)
        }
        
        saveQueue()
        
        // Start background TTS generation
        startTTSGeneration(for: article)
        
        // Sync with audio service
        await syncToAudioService()
    }
    
    /// Add an RSS episode to the queue
    func addRSSEpisode(_ episode: RSSEpisode, playNext: Bool = false) {
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
        
        // RSS episodes don't need TTS generation
        Task {
            await syncToAudioService()
        }
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
        
        Task {
            await syncToAudioService()
        }
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
        
        Task {
            await syncToAudioService()
        }
    }
    
    /// Clear the entire queue
    func clearQueue() {
        // Cancel all TTS generation tasks
        for task in ttsGenerationTasks.values {
            task.cancel()
        }
        ttsGenerationTasks.removeAll()
        
        queue.removeAll()
        currentIndex = -1
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
                    title: item.title ?? "Unknown",
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
                "dateAdded": item.dateAdded
            ]
            
            if let title = item.title { data["title"] = title }
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
        // Load queue items
        guard let queueData = userDefaults.array(forKey: queueKey) as? [[String: Any]] else {
            return
        }
        
        queue = queueData.compactMap { data -> EnhancedQueueItem? in
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
        
        currentIndex = userDefaults.integer(forKey: indexKey)
        
        // Validate current index
        if currentIndex >= queue.count {
            currentIndex = queue.isEmpty ? -1 : 0
        }
        
        // Sync with audio service on startup
        Task {
            await syncToAudioService()
        }
    }
    
    // MARK: - Core Data Helpers
    
    private func fetchArticle(id: UUID) async -> Article? {
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
    
    private func fetchRSSEpisode(audioUrl: String) async -> RSSEpisode? {
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

// MARK: - Convenience Methods
extension QueueServiceV2 {
    
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