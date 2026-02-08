//
//  QueueCoordinator.swift
//  Briefeed
//
//  Single source of truth for queue management.
//  Replaces fragmented queue systems (QueueServiceV2, UnifiedAudioPlayer queue, etc.)
//

import Foundation
import Combine
import CoreData

// MARK: - Queue Item

/// Unified queue item supporting both Articles and Live News episodes
struct QueueItem: Codable, Identifiable, Equatable {
    let id: UUID
    let type: QueueItemType
    let title: String
    let source: String
    let addedAt: Date
    let expiresAt: Date?  // Only for Live News

    // Article-specific
    let articleID: UUID?
    var summaryState: SummaryState
    var cachedAudioURL: URL?

    // Live News-specific
    let episodeID: String?
    let streamURL: URL?

    // Playback state
    var lastPosition: TimeInterval
    var isListened: Bool

    // Error tracking (Phase 2)
    var errorMessage: String?
    var retryCount: Int

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() > expiresAt
    }

    var isArticle: Bool {
        type == .article
    }

    var isLiveNews: Bool {
        type == .liveNews
    }

    var hasFailed: Bool {
        summaryState == .failed && errorMessage != nil
    }

    var canRetry: Bool {
        summaryState == .failed && retryCount < 3
    }

    static func == (lhs: QueueItem, rhs: QueueItem) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Backward-Compatible Decoding

    private enum CodingKeys: String, CodingKey {
        case id, type, title, source, addedAt, expiresAt
        case articleID, summaryState, cachedAudioURL
        case episodeID, streamURL
        case lastPosition, isListened
        case errorMessage, retryCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(QueueItemType.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        source = try container.decode(String.self, forKey: .source)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)

        articleID = try container.decodeIfPresent(UUID.self, forKey: .articleID)
        summaryState = try container.decode(SummaryState.self, forKey: .summaryState)
        cachedAudioURL = try container.decodeIfPresent(URL.self, forKey: .cachedAudioURL)

        episodeID = try container.decodeIfPresent(String.self, forKey: .episodeID)
        streamURL = try container.decodeIfPresent(URL.self, forKey: .streamURL)

        lastPosition = try container.decode(TimeInterval.self, forKey: .lastPosition)
        isListened = try container.decode(Bool.self, forKey: .isListened)

        // Backward-compatible: default to nil/0 if missing from old persisted data
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
    }

    // Standard memberwise init for new items
    init(
        id: UUID,
        type: QueueItemType,
        title: String,
        source: String,
        addedAt: Date,
        expiresAt: Date?,
        articleID: UUID?,
        summaryState: SummaryState,
        cachedAudioURL: URL?,
        episodeID: String?,
        streamURL: URL?,
        lastPosition: TimeInterval,
        isListened: Bool,
        errorMessage: String? = nil,
        retryCount: Int = 0
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.source = source
        self.addedAt = addedAt
        self.expiresAt = expiresAt
        self.articleID = articleID
        self.summaryState = summaryState
        self.cachedAudioURL = cachedAudioURL
        self.episodeID = episodeID
        self.streamURL = streamURL
        self.lastPosition = lastPosition
        self.isListened = isListened
        self.errorMessage = errorMessage
        self.retryCount = retryCount
    }
}

enum QueueItemType: String, Codable {
    case article
    case liveNews
}

enum SummaryState: String, Codable {
    case pending
    case generating
    case ready
    case failed
}

// MARK: - Persisted Queue State

struct PersistedQueueState: Codable {
    let items: [QueueItem]
    let currentIndex: Int
    let currentPosition: TimeInterval
    let savedAt: Date
}

// MARK: - Queue Coordinator

@MainActor
final class QueueCoordinator: ObservableObject {

    // MARK: - Singleton

    static let shared = QueueCoordinator()

    // MARK: - Published Properties

    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var currentIndex: Int = -1
    @Published private(set) var currentPosition: TimeInterval = 0

    // MARK: - Computed Properties

    var currentItem: QueueItem? {
        guard currentIndex >= 0 && currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    var hasItems: Bool {
        !queue.isEmpty
    }

    var itemCount: Int {
        queue.count
    }

    var articleCount: Int {
        queue.filter { $0.isArticle }.count
    }

    var liveNewsCount: Int {
        queue.filter { $0.isLiveNews }.count
    }

    // Filtered queues
    var articles: [QueueItem] {
        queue.filter { $0.isArticle }
    }

    var liveNews: [QueueItem] {
        queue.filter { $0.isLiveNews }
    }

    // MARK: - Private Properties

    private let persistenceKey = "briefeed_queue_state_v2"
    private var expirationTimer: Timer?
    private var positionPersistTimer: Timer?
    private var lastPersistedPosition: TimeInterval = 0
    private let positionPersistInterval: TimeInterval = 10.0  // Persist every 10 seconds
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        loadPersistedState()
        startExpirationTimer()
    }

    // MARK: - Add to Queue

    private func ensureStableArticleID(_ article: Article) -> UUID {
        if let id = article.id {
            return id
        }

        let newID = UUID()
        if let context = article.managedObjectContext {
            context.performAndWait {
                article.id = newID
                if context.hasChanges {
                    do {
                        try context.save()
                    } catch {
                        print("[QueueCoordinator] Failed to persist generated Article.id: \(error)")
                    }
                }
            }
        } else {
            article.id = newID
        }

        return newID
    }

    private func ensureStableEpisodeID(_ episode: RSSEpisode) -> String {
        let existingID = episode.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if !existingID.isEmpty {
            return existingID
        }

        let newID = UUID().uuidString
        if let context = episode.managedObjectContext {
            context.performAndWait {
                episode.id = newID
                if context.hasChanges {
                    do {
                        try context.save()
                    } catch {
                        print("[QueueCoordinator] Failed to persist generated RSSEpisode.id: \(error)")
                    }
                }
            }
        } else {
            episode.id = newID
        }

        return newID
    }

    /// Add an article to the queue (at bottom for FIFO)
    func addArticle(
        _ article: Article,
        playNow: Bool = false,
        playNext: Bool = false
    ) {
        let articleID = ensureStableArticleID(article)

        // Check if already in queue
        if queue.contains(where: { $0.articleID == articleID }) {
            print("[QueueCoordinator] Article already in queue: \(article.title ?? "Unknown")")
            return
        }

        let item = QueueItem(
            id: UUID(),
            type: .article,
            title: article.title ?? "Untitled",
            source: article.feed?.name ?? "Unknown",
            addedAt: Date(),
            expiresAt: nil,  // Articles never expire
            articleID: articleID,
            summaryState: article.summary != nil ? .ready : .pending,
            cachedAudioURL: nil,
            episodeID: nil,
            streamURL: nil,
            lastPosition: 0,
            isListened: false
        )

        insertItem(item, playNow: playNow, playNext: playNext)
        persistState()

        print("[QueueCoordinator] Added article to queue: \(article.title ?? "Unknown")")
    }

    /// Add a Live News episode to the queue
    func addEpisode(
        _ episode: RSSEpisode,
        playNow: Bool = false,
        playNext: Bool = false
    ) {
        let episodeID = ensureStableEpisodeID(episode)

        // Check if already in queue
        if queue.contains(where: { $0.episodeID == episodeID }) {
            print("[QueueCoordinator] Episode already in queue: \(episode.title)")
            return
        }

        // Calculate expiration time
        let expirationHours = UserDefaultsManager.shared.liveNewsExpirationHours
        let expiresAt = Calendar.current.date(byAdding: .hour, value: expirationHours, to: Date())

        let item = QueueItem(
            id: UUID(),
            type: .liveNews,
            title: episode.title,
            source: episode.feed?.displayName ?? "Unknown Feed",
            addedAt: Date(),
            expiresAt: expiresAt,
            articleID: nil,
            summaryState: .ready,  // Episodes already have audio
            cachedAudioURL: nil,
            episodeID: episodeID,
            streamURL: URL(string: episode.audioUrl),
            lastPosition: 0,
            isListened: false
        )

        insertItem(item, playNow: playNow, playNext: playNext)
        persistState()

        print("[QueueCoordinator] Added episode to queue: \(episode.title) (expires: \(expiresAt?.formatted() ?? "never"))")
    }

    /// Helper to insert item based on play mode
    private func insertItem(_ item: QueueItem, playNow: Bool, playNext: Bool) {
        if playNow {
            // Insert at current position and update index
            let insertIndex = max(0, currentIndex)
            queue.insert(item, at: insertIndex)
            currentIndex = insertIndex
            currentPosition = item.lastPosition
        } else if playNext {
            // Insert after current item
            let insertIndex = currentIndex >= 0 ? currentIndex + 1 : 0
            queue.insert(item, at: insertIndex)
        } else {
            // FIFO: Add to bottom of queue
            queue.append(item)
        }
    }

    // MARK: - Remove from Queue

    func removeItem(at index: Int) {
        guard index >= 0 && index < queue.count else { return }

        queue.remove(at: index)

        // Adjust current index if needed
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            // Current item was removed
            if queue.isEmpty {
                currentIndex = -1
                currentPosition = 0
            } else if currentIndex >= queue.count {
                currentIndex = queue.count - 1
            }

            if currentIndex >= 0 && currentIndex < queue.count {
                currentPosition = queue[currentIndex].lastPosition
            }
        }

        // Final safety clamp
        if !queue.isEmpty {
            currentIndex = max(-1, min(currentIndex, queue.count - 1))
        } else {
            currentIndex = -1
        }

        persistState()
        print("[QueueCoordinator] Removed item at index \(index)")
    }

    func removeItem(id: UUID) {
        if let index = queue.firstIndex(where: { $0.id == id }) {
            removeItem(at: index)
        }
    }

    func clearQueue() {
        queue.removeAll()
        currentIndex = -1
        currentPosition = 0
        persistState()
        print("[QueueCoordinator] Queue cleared")
    }

    // MARK: - Reorder Queue

    func moveItems(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)

        // Update current index if it was affected
        if let first = source.first {
            if first == currentIndex {
                // Moving the current item
                currentIndex = destination > first ? destination - 1 : destination
            } else if first < currentIndex && destination > currentIndex {
                // Moving item from before to after current
                currentIndex -= 1
            } else if first > currentIndex && destination <= currentIndex {
                // Moving item from after to before/at current
                currentIndex += 1
            }
        }

        persistState()
        print("[QueueCoordinator] Queue reordered")
    }

    // MARK: - Navigation

    func setCurrentIndex(_ index: Int) {
        guard index >= -1 && index < queue.count else { return }
        currentIndex = index
        if index >= 0 && index < queue.count {
            currentPosition = queue[index].lastPosition
        } else {
            currentPosition = 0
        }
        persistState()
    }

    func updateCurrentPosition(_ position: TimeInterval) {
        currentPosition = position

        // Update the item's lastPosition
        if currentIndex >= 0 && currentIndex < queue.count {
            queue[currentIndex].lastPosition = position
        }

        // Debounced persistence - only persist if enough time has passed
        // This prevents excessive writes during playback
        schedulePositionPersist()
    }

    /// Schedule a debounced position persist
    private func schedulePositionPersist() {
        // Cancel existing timer
        positionPersistTimer?.invalidate()

        // Schedule new timer
        positionPersistTimer = Timer.scheduledTimer(withTimeInterval: positionPersistInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.persistState()
            }
        }
    }

    /// Force save state immediately (call on app background/termination)
    func saveStateNow() {
        positionPersistTimer?.invalidate()
        positionPersistTimer = nil
        persistState()
        print("[QueueCoordinator] State saved immediately (lifecycle event)")
    }

    func markCurrentAsListened() {
        guard currentIndex >= 0 && currentIndex < queue.count else { return }
        queue[currentIndex].isListened = true
        persistState()
    }

    // MARK: - Summary State Updates

    func updateSummaryState(for itemID: UUID, state: SummaryState) {
        if let index = queue.firstIndex(where: { $0.id == itemID }) {
            queue[index].summaryState = state
            persistState()
        }
    }

    func updateCachedAudioURL(for itemID: UUID, url: URL?) {
        if let index = queue.firstIndex(where: { $0.id == itemID }) {
            queue[index].cachedAudioURL = url
            if url != nil {
                queue[index].summaryState = .ready
            }
            persistState()
        }
    }

    // MARK: - Error Tracking (Phase 2)

    /// Mark an item as failed with an error message, incrementing retry count
    func markItemFailed(for itemID: UUID, error: String) {
        if let index = queue.firstIndex(where: { $0.id == itemID }) {
            queue[index].summaryState = .failed
            queue[index].errorMessage = error
            queue[index].retryCount += 1
            persistState()
            print("[QueueCoordinator] Item failed (attempt \(queue[index].retryCount)): \(queue[index].title) - \(error)")
        }
    }

    /// Clear error state and reset to pending for retry
    func resetItemForRetry(for itemID: UUID) {
        if let index = queue.firstIndex(where: { $0.id == itemID }) {
            queue[index].summaryState = .pending
            queue[index].errorMessage = nil
            // Note: retryCount is preserved to track total attempts
            persistState()
            print("[QueueCoordinator] Item reset for retry: \(queue[index].title) (attempt \(queue[index].retryCount + 1))")
        }
    }

    /// Get items that can be retried (failed but under max attempts)
    var retryableItems: [QueueItem] {
        queue.filter { $0.canRetry }
    }

    /// Get items that have permanently failed (exhausted retries)
    var permanentlyFailedItems: [QueueItem] {
        queue.filter { $0.summaryState == .failed && $0.retryCount >= 3 }
    }

    // MARK: - Expiration Management

    private func startExpirationTimer() {
        // Check every 5 minutes
        expirationTimer?.invalidate()
        expirationTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanExpiredItems()
            }
        }
    }

    private func cleanExpiredItems() {
        let expiredCount = queue.filter { $0.isExpired }.count
        guard expiredCount > 0 else { return }

        // Don't remove the currently playing item even if expired
        let currentItemID = currentItem?.id

        queue = queue.filter { item in
            if item.isExpired && item.id != currentItemID {
                print("[QueueCoordinator] Removing expired item: \(item.title)")
                return false
            }
            return true
        }

        // Recalculate current index
        if let currentID = currentItemID,
           let newIndex = queue.firstIndex(where: { $0.id == currentID }) {
            currentIndex = newIndex
        }

        persistState()
        print("[QueueCoordinator] Cleaned \(expiredCount) expired items")
    }

    /// Prevent expiration for a specific item (swipe to keep)
    func preventExpiration(for itemID: UUID) {
        if let index = queue.firstIndex(where: { $0.id == itemID }) {
            // Create a new item without expiration
            var item = queue[index]
            queue[index] = QueueItem(
                id: item.id,
                type: item.type,
                title: item.title,
                source: item.source,
                addedAt: item.addedAt,
                expiresAt: nil,  // Remove expiration
                articleID: item.articleID,
                summaryState: item.summaryState,
                cachedAudioURL: item.cachedAudioURL,
                episodeID: item.episodeID,
                streamURL: item.streamURL,
                lastPosition: item.lastPosition,
                isListened: item.isListened
            )
            persistState()
            print("[QueueCoordinator] Prevented expiration for: \(item.title)")
        }
    }

    // MARK: - Persistence

    private func persistState() {
        let state = PersistedQueueState(
            items: queue,
            currentIndex: currentIndex,
            currentPosition: currentPosition,
            savedAt: Date()
        )

        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: persistenceKey)
            print("[QueueCoordinator] State persisted: \(queue.count) items, index \(currentIndex)")
        } catch {
            print("[QueueCoordinator] Failed to persist state: \(error)")
        }
    }

    private func loadPersistedState() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else {
            print("[QueueCoordinator] No persisted state found")
            return
        }

        do {
            let state = try JSONDecoder().decode(PersistedQueueState.self, from: data)

            // Filter out any expired items on load
            queue = state.items.filter { !$0.isExpired }

            // Restore index if valid
            if state.currentIndex >= 0 && state.currentIndex < queue.count {
                currentIndex = state.currentIndex
                currentPosition = state.currentPosition

                // Ensure the current item's lastPosition matches the saved position
                queue[currentIndex].lastPosition = state.currentPosition
            } else {
                currentIndex = queue.isEmpty ? -1 : 0
                currentPosition = 0
            }

            print("[QueueCoordinator] Restored state: \(queue.count) items, index \(currentIndex), position \(currentPosition)")
        } catch {
            print("[QueueCoordinator] Failed to load persisted state: \(error)")
        }
    }

    // MARK: - Query Methods

    func isInQueue(articleID: UUID) -> Bool {
        queue.contains { $0.articleID == articleID }
    }

    func isInQueue(episodeID: String) -> Bool {
        queue.contains { $0.episodeID == episodeID }
    }

    func queuePosition(for articleID: UUID) -> Int? {
        queue.firstIndex { $0.articleID == articleID }
    }

    func queuePosition(for episodeID: String) -> Int? {
        queue.firstIndex { $0.episodeID == episodeID }
    }

    func item(at index: Int) -> QueueItem? {
        guard index >= 0 && index < queue.count else { return nil }
        return queue[index]
    }

    // MARK: - Filter Support

    func filteredQueue(filter: QueueFilter) -> [QueueItem] {
        switch filter {
        case .all:
            return queue
        case .articles:
            return queue.filter { $0.isArticle }
        case .liveNews:
            return queue.filter { $0.isLiveNews }
        }
    }

    // MARK: - Cleanup

    deinit {
        expirationTimer?.invalidate()
        positionPersistTimer?.invalidate()
    }
}

// MARK: - UserDefaultsManager Extension

extension UserDefaultsManager {
    /// Live News expiration time in hours (default: 48)
    var liveNewsExpirationHours: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: "liveNewsExpirationHours")
            return value > 0 ? value : 48  // Default to 48 hours
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "liveNewsExpirationHours")
        }
    }
}
