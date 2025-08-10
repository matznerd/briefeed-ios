//
//  QueueServiceV2.swift
//  Briefeed
//
//  Fixed architecture: Plain singleton, no ObservableObject, no @MainActor
//

import Foundation
import CoreData
import Combine

// MARK: - QueueServiceV2
// Fixed architecture: Plain singleton service without ObservableObject

final class QueueServiceV2: NSObject {
    
    // MARK: - Types
    struct QueuedItem: Codable {
        let articleID: UUID
        let addedDate: Date
    }
    
    // MARK: - Singleton
    static let shared = QueueServiceV2()
    
    // MARK: - Properties (No @Published!)
    private(set) var queuedItems: [QueuedItem] = [] {
        didSet {
            delegate?.queueItemsChanged(queuedItems)
        }
    }
    
    private(set) var enhancedQueue: [EnhancedQueueItem] = [] {
        didSet {
            delegate?.enhancedQueueChanged(enhancedQueue)
        }
    }
    
    // Dependencies
    private let userDefaults = UserDefaults.standard
    private let queueKey = "AudioQueueItems"
    private let enhancedQueueKey = "EnhancedAudioQueueItems"
    
    // Background processing
    private var audioGenerationTask: Task<Void, Never>?
    
    // Delegate for state changes (instead of @Published)
    weak var delegate: QueueServiceDelegate?
    
    // MARK: - Initialization (LIGHTWEIGHT!)
    private override init() {
        super.init()
        // Only lightweight setup in init
        
        // Safety checks
        SafetyMonitor.shared.checkSingletonNotObservable(self)
        SafetyMonitor.shared.checkNoPublishedInService(self)
    }
    
    // MARK: - Async Initialization (HEAVY WORK HERE)
    func initialize() async {
        SafetyMonitor.shared.assertNotMainThread()
        
        // Load persisted queue
        await loadQueue()
        
        // Start background audio generation
        startBackgroundAudioGeneration()
    }
    
    // MARK: - Queue Management
    
    func addToQueue(article: Article) async {
        let item = QueuedItem(
            articleID: article.objectID.uriRepresentation().uuid ?? UUID(),
            addedDate: Date()
        )
        
        // Insert at beginning for funnel concept (newest at top)
        queuedItems.insert(item, at: 0)
        await saveQueue()
        
        // Create enhanced item
        let enhancedItem = EnhancedQueueItem(
            id: item.articleID,
            title: article.title ?? "Unknown",
            source: .article(source: article.feed?.name ?? "Unknown"),
            addedDate: item.addedDate,
            expiresAt: nil,
            articleID: item.articleID,
            audioUrl: nil,
            duration: nil
        )
        
        // Insert at beginning for funnel concept (newest at top)
        enhancedQueue.insert(enhancedItem, at: 0)
        await saveEnhancedQueue()
    }
    
    func addToQueue(episode: RSSEpisode) async {
        let enhancedItem = EnhancedQueueItem(
            id: UUID(uuidString: episode.id) ?? UUID(),
            title: episode.title,
            source: .rss(feedId: episode.feedId, feedName: episode.feed?.displayName ?? "Unknown Feed"),
            addedDate: Date(),
            expiresAt: nil,
            articleID: nil,
            audioUrl: URL(string: episode.audioUrl),
            duration: Int(episode.duration)
        )
        
        // Insert at beginning for funnel concept (newest at top)
        enhancedQueue.insert(enhancedItem, at: 0)
        await saveEnhancedQueue()
    }
    
    func removeFromQueue(at index: Int) async {
        guard index < enhancedQueue.count else { return }
        
        enhancedQueue.remove(at: index)
        await saveEnhancedQueue()
        
        // Also update legacy queue if it was an article
        if index < queuedItems.count {
            queuedItems.remove(at: index)
            await saveQueue()
        }
    }
    
    func reorderQueue(from source: IndexSet, to destination: Int) async {
        enhancedQueue.move(fromOffsets: source, toOffset: destination)
        await saveEnhancedQueue()
        
        // Also reorder legacy queue
        queuedItems.move(fromOffsets: source, toOffset: destination)
        await saveQueue()
    }
    
    func clearQueue() async {
        queuedItems.removeAll()
        enhancedQueue.removeAll()
        
        await saveQueue()
        await saveEnhancedQueue()
    }
    
    func moveToTop(at index: Int) async {
        guard index < enhancedQueue.count, index > 0 else { return }
        
        let item = enhancedQueue.remove(at: index)
        enhancedQueue.insert(item, at: 0)
        await saveEnhancedQueue()
        
        if index < queuedItems.count {
            let legacyItem = queuedItems.remove(at: index)
            queuedItems.insert(legacyItem, at: 0)
            await saveQueue()
        }
    }
    
    // MARK: - Queue Queries
    
    func isInQueue(article: Article) -> Bool {
        let articleID = article.objectID.uriRepresentation().uuid ?? UUID()
        return queuedItems.contains { $0.articleID == articleID }
    }
    
    func isInQueue(episode: RSSEpisode) -> Bool {
        return enhancedQueue.contains { item in
            if case .rss(let feedId, _) = item.source {
                return feedId == episode.feedId && item.title == episode.title
            }
            return false
        }
    }
    
    func queuePosition(for article: Article) -> Int? {
        let articleID = article.objectID.uriRepresentation().uuid ?? UUID()
        return queuedItems.firstIndex { $0.articleID == articleID }
    }
    
    // MARK: - Persistence
    
    func loadQueue() async {
        // Load legacy queue
        if let data = userDefaults.data(forKey: queueKey),
           let items = try? JSONDecoder().decode([QueuedItem].self, from: data) {
            queuedItems = items
        }
        
        // Load enhanced queue
        if let data = userDefaults.data(forKey: enhancedQueueKey),
           let items = try? JSONDecoder().decode([EnhancedQueueItem].self, from: data) {
            enhancedQueue = items
        }
    }
    
    func saveQueue() async {
        if let data = try? JSONEncoder().encode(queuedItems) {
            userDefaults.set(data, forKey: queueKey)
        }
    }
    
    private func saveEnhancedQueue() async {
        if let data = try? JSONEncoder().encode(enhancedQueue) {
            userDefaults.set(data, forKey: enhancedQueueKey)
        }
    }
    
    // MARK: - Background Audio Generation
    
    private func startBackgroundAudioGeneration() {
        audioGenerationTask?.cancel()
        
        audioGenerationTask = Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled {
                await self.processNextItemForAudioGeneration()
                
                // Wait before checking next item
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            }
        }
    }
    
    private func processNextItemForAudioGeneration() async {
        for (index, item) in enhancedQueue.enumerated() {
            switch item.source {
            case .article:
                // Check if audio already exists
                if item.audioUrl == nil, let articleID = item.articleID {
                    // Need to fetch the article from Core Data
                    if let article = await fetchArticle(with: articleID) {
                        await generateAudioForArticle(article, at: index)
                    }
                }
            case .rss:
                // RSS episodes already have audio URLs
                continue
            }
        }
    }
    
    private func generateAudioForArticle(_ article: Article, at index: Int) async {
        do {
            // Generate summary first
            let geminiService = GeminiService()
            let summary = try await geminiService.summarize(text: article.content ?? "", length: .standard)
            
            // Generate TTS
            let result = await GeminiTTSService.shared.generateSpeech(
                text: summary,
                voiceName: nil,
                useRandomVoice: true
            )
            
            if let audioURL = result.audioURL {
                // Update the enhanced queue item with new audioUrl
                // Since audioUrl is immutable, we need to create a new item
                if index < enhancedQueue.count {
                    let oldItem = enhancedQueue[index]
                    let updatedItem = EnhancedQueueItem(
                        id: oldItem.id,
                        title: oldItem.title,
                        source: oldItem.source,
                        addedDate: oldItem.addedDate,
                        expiresAt: oldItem.expiresAt,
                        articleID: oldItem.articleID,
                        audioUrl: audioURL,  // New audio URL
                        duration: oldItem.duration
                    )
                    enhancedQueue[index] = updatedItem
                    await saveEnhancedQueue()
                }
            }
        } catch {
            print("Failed to generate audio for article: \(error)")
        }
    }
    
    private func fetchArticle(with id: UUID) async -> Article? {
        // Fetch article from Core Data
        // This would need to be implemented with proper Core Data context
        return nil // Placeholder
    }
    
    // MARK: - Cleanup
    
    deinit {
        audioGenerationTask?.cancel()
    }
}

// MARK: - Delegate Protocol

protocol QueueServiceDelegate: AnyObject {
    func queueItemsChanged(_ items: [QueueServiceV2.QueuedItem])
    func enhancedQueueChanged(_ items: [EnhancedQueueItem])
}

// MARK: - Extension Support

extension QueueServiceV2 {
    // Internal methods for extensions (if needed)
    func appendToEnhancedQueue(_ item: EnhancedQueueItem) {
        enhancedQueue.append(item)
    }
    
    func insertIntoEnhancedQueue(_ item: EnhancedQueueItem, at index: Int) {
        enhancedQueue.insert(item, at: index)
    }
    
    func updateEnhancedQueue(_ newQueue: [EnhancedQueueItem]) {
        enhancedQueue = newQueue
    }
}

// MARK: - UUID Extension

extension URL {
    var uuid: UUID? {
        guard let uuidString = self.pathComponents.last else { return nil }
        return UUID(uuidString: uuidString)
    }
}