//
//  BriefeedAudioService.swift
//  Briefeed
//
//  Created by Briefeed Team on 1/8/25.
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import CoreData
import SwiftAudioEx
import UIKit


// MARK: - Briefeed Audio Service
final class BriefeedAudioService: ObservableObject {
    // Singleton
    static let shared = BriefeedAudioService()
    
    // Audio player - lazy to defer initialization
    private lazy var audioPlayer = QueuedAudioPlayer()
    
    // Dependencies - lazy to defer initialization
    private lazy var ttsGenerator = TTSGenerator.shared
    private lazy var cacheManager = AudioCacheManager.shared
    private lazy var historyManager = PlaybackHistoryManager.shared
    private lazy var sleepTimer = SleepTimerManager.shared
    
    // Published properties
    @Published private(set) var currentItem: BriefeedAudioItem?
    @Published private(set) var currentPlaybackItem: CurrentPlaybackItem?
    @Published private(set) var playbackContext: PlaybackContext = .direct
    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false {
        willSet {
            if isPlaying != newValue {
                perfLog.logPublisher("BriefeedAudioService.isPlaying", value: "\(isPlaying) -> \(newValue)")
            }
            print("🔄 BriefeedAudioService: isPlaying willSet - old: \(isPlaying), new: \(newValue)")
            if Thread.isMainThread && isPlaying != newValue {
                perfLog.checkMainThread("BriefeedAudioService.isPlaying change")
                print("⚠️ WARNING: isPlaying being changed on main thread during potential view update")
                print("📍 Stack trace: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))")
            }
        }
    }
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var playbackRate: Float = 1.0
    @Published var volume: Float = 1.0 {
        didSet {
            audioPlayer.volume = volume
        }
    }
    
    // Queue management
    @Published private(set) var queue: [BriefeedAudioItem] = []
    @Published private(set) var queueIndex = -1
    
    // Error handling
    @Published private(set) var lastError: Error?
    
    // MARK: - Compatibility Properties (for UI that expects old AudioService)
    @Published var currentArticle: Article?
    
    // State publishers for UI compatibility
    let state = CurrentValueSubject<AudioPlayerState, Never>(.idle)
    let progress = CurrentValueSubject<Float, Never>(0.0)
    
    // Private properties
    private var cancellables = Set<AnyCancellable>()
    private let queuePersistenceKey = "BriefeedAudioQueue"
    private var maintenanceTimerCancellable: AnyCancellable?
    
    private var isConfigured = false
    private let configurationQueue = DispatchQueue(label: "com.briefeed.audioservice.config")
    
    private init() {
        perfLog.logService("BriefeedAudioService", method: "init", detail: "Started")
        // Heavy initialization deferred until first actual use
        perfLog.logService("BriefeedAudioService", method: "init", detail: "Completed")
    }
    
    private func configureIfNeeded() {
        configurationQueue.async { [weak self] in
            guard let self = self, !self.isConfigured else {
                perfLog.log("BriefeedAudioService already configured", category: .audio)
                return
            }
            self.isConfigured = true
            
            perfLog.logService("BriefeedAudioService", method: "configureIfNeeded", detail: "Starting configuration")
            Task {
                await self.performConfiguration()
            }
        }
    }
    
    @MainActor
    private func performConfiguration() async {
        perfLog.startOperation("BriefeedAudioService.performConfiguration")
        
        perfLog.startOperation("BriefeedAudioService.setupAudioSession")
        setupAudioSession()
        perfLog.endOperation("BriefeedAudioService.setupAudioSession")
        
        perfLog.startOperation("BriefeedAudioService.setupAudioPlayer")
        setupAudioPlayer()
        perfLog.endOperation("BriefeedAudioService.setupAudioPlayer")
        
        perfLog.startOperation("BriefeedAudioService.setupSleepTimer")
        setupSleepTimer()
        perfLog.endOperation("BriefeedAudioService.setupSleepTimer")
        
        perfLog.startOperation("BriefeedAudioService.restoreQueueAsync")
        await restoreQueueAsync()
        perfLog.endOperation("BriefeedAudioService.restoreQueueAsync")
        
        perfLog.startOperation("BriefeedAudioService.setupPeriodicMaintenance")
        setupPeriodicMaintenance()
        perfLog.endOperation("BriefeedAudioService.setupPeriodicMaintenance")
        
        perfLog.endOperation("BriefeedAudioService.performConfiguration")
    }
    
    // MARK: - Setup
    
    private func setupAudioSession() {
        perfLog.logService("BriefeedAudioService", method: "setupAudioSession", detail: "Starting")
        // Configure AVAudioSession
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            // Fixed configuration - removed incompatible .mixWithOthers with .spokenAudio
            try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay])
            try audioSession.setActive(true, options: [])
            print("✅ Audio session configured for BriefeedAudioService")
        } catch {
            print("❌ Failed to configure audio session: \(error)")
            print("📱 Error code: \((error as NSError).code)")
            print("📱 Error domain: \((error as NSError).domain)")
            // Error -50 typically means invalid parameter. Try without setActive
            if (error as NSError).code == -50 {
                do {
                    try audioSession.setCategory(.playback, mode: .default, options: [])
                    print("✅ Audio session configured with basic options")
                } catch {
                    print("❌ Failed to configure audio session with basic options: \(error)")
                }
            }
        }
    }
    
    private func setupSleepTimer() {
        sleepTimer.onTimerExpired = { [weak self] in
            Task { @MainActor in
                self?.handleSleepTimerExpired()
            }
        }
        
        sleepTimer.onEndOfTrackExpired = { [weak self] in
            Task { @MainActor in
                self?.handleSleepTimerExpired()
            }
        }
    }
    
    private func setupPeriodicMaintenance() {
        // Run cache maintenance every hour
        Timer.publish(every: 3600, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                self.cacheManager.performCacheMaintenance()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Playback Control
    
    /// Play an article (generates TTS if needed)
    func playArticle(_ article: Article, context: PlaybackContext = .direct) async {
        perfLog.startOperation("BriefeedAudioService.playArticle")
        print("📢 BriefeedAudioService: playArticle called")
        print("  Article: \(article.title ?? "Unknown")")
        print("  Context: \(context)")
        perfLog.logService("BriefeedAudioService", method: "playArticle", detail: "Article: \(article.title ?? "Unknown")")
        
        // Ensure service is configured
        configureIfNeeded()
        
        await MainActor.run {
            isLoading = true
            playbackContext = context
            lastError = nil
            
            // Update current article for UI compatibility
            currentArticle = article
            
            // Update current playback item immediately for UI
            currentPlaybackItem = CurrentPlaybackItem(from: article)
        }
        
        // Generate or get cached audio
        let result = await ttsGenerator.generateAudio(for: article)
        
        switch result {
        case .success(let ttsResult):
            // Create audio item
            let audioContent = ArticleAudioContent(article: article)
            let audioItem = BriefeedAudioItem(
                content: audioContent,
                audioURL: ttsResult.audioURL,
                isTemporary: false
            )
            
            // Play the item
            await playAudioItem(audioItem)
            
            // Update processing status
            await ProcessingStatusService.shared.completeProcessing()
            
        case .failure(let error):
            print("❌ Failed to generate audio: \(error)")
            await MainActor.run {
                lastError = error
                isLoading = false
            }
            await ProcessingStatusService.shared.updateError(error.localizedDescription)
        }
        
        perfLog.endOperation("BriefeedAudioService.playArticle")
    }
    
    /// Play an RSS episode
    func playRSSEpisode(_ episode: RSSEpisode, context: PlaybackContext = .direct) async {
        perfLog.startOperation("BriefeedAudioService.playRSSEpisode")
        print("📻 BriefeedAudioService: playRSSEpisode called")
        print("  Episode: \(episode.title)")
        print("  Context: \(context)")
        perfLog.logService("BriefeedAudioService", method: "playRSSEpisode", detail: "Episode: \(episode.title)")
        guard let audioURL = URL(string: episode.audioUrl) else {
            print("❌ Invalid audio URL for RSS episode")
            return
        }
        
        await MainActor.run {
            isLoading = true
            playbackContext = context
            lastError = nil
            
            // Update current playback item
            currentPlaybackItem = CurrentPlaybackItem(from: episode)
        }
        
        // Create audio item
        let audioContent = RSSEpisodeAudioContent(episode: episode)
        let audioItem = BriefeedAudioItem(
            content: audioContent,
            audioURL: audioURL,
            isTemporary: false
        )
        
        // Play the item
        await playAudioItem(audioItem)
        perfLog.endOperation("BriefeedAudioService.playRSSEpisode")
    }
    
    /// Play a specific audio item
    private func playAudioItem(_ item: BriefeedAudioItem) async {
        perfLog.startOperation("BriefeedAudioService.playAudioItem")
        await MainActor.run {
            currentItem = item
        }
        
        // Load and play the item
        audioPlayer.load(item: item, playWhenReady: true)
        
        // Add to history
        historyManager.addToHistory(item, position: 0, duration: item.content.duration ?? 0)
        
        // Pregenerate next items if in queue
        pregenerateUpcomingItems()
        perfLog.endOperation("BriefeedAudioService.playAudioItem")
    }
    
    /// Toggle play/pause
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    /// Play
    func play() {
        perfLog.logService("BriefeedAudioService", method: "play", detail: "Current: \(currentItem?.content.title ?? "None")")
        print("🎵 BriefeedAudioService: play() called")
        print("  Current item: \(currentItem?.content.title ?? "None")")
        print("  Queue size: \(queue.count)")
        audioPlayer.play()
    }
    
    /// Pause
    func pause() {
        perfLog.logService("BriefeedAudioService", method: "pause")
        print("⏸️ BriefeedAudioService: pause() called")
        audioPlayer.pause()
        
        // Update history
        if let item = currentItem {
            historyManager.addToHistory(item, position: currentTime, duration: duration)
        }
    }
    
    /// Stop
    func stop() {
        audioPlayer.stop()
        
        // Update history
        if let item = currentItem {
            historyManager.addToHistory(item, position: currentTime, duration: duration)
        }
        
        Task { @MainActor in
            currentItem = nil
            currentPlaybackItem = nil
        }
    }
    
    /// Skip forward
    func skipForward() {
        let interval: TimeInterval = currentItem?.content.contentType == .article ? 15 : 30
        print("⏩ BriefeedAudioService: skipForward(\(interval)s) called")
        seek(to: currentTime + interval)
    }
    
    /// Skip backward
    func skipBackward() {
        let interval: TimeInterval = currentItem?.content.contentType == .article ? 15 : 30
        print("⏪ BriefeedAudioService: skipBackward(\(interval)s) called")
        seek(to: max(0, currentTime - interval))
    }
    
    /// Seek to position
    func seek(to position: TimeInterval) {
        audioPlayer.seek(to: position)
    }
    
    /// Set playback rate
    func setPlaybackRate(_ rate: Float) {
        playbackRate = max(0.5, min(2.0, rate))
        UserDefaultsManager.shared.playbackSpeed = playbackRate
        audioPlayer.rate = playbackRate
    }
    
    // MARK: - Convenience Methods (UI Compatibility)
    
    /// Play article immediately, clearing queue
    func playNow(_ article: Article) async {
        clearQueue()
        await playArticle(article)
    }
    
    /// Insert article after current playing item
    func playAfterCurrent(_ article: Article) async {
        let insertIndex = max(0, queueIndex + 1)
        
        // Create audio item
        let audioContent = ArticleAudioContent(article: article)
        let audioItem = BriefeedAudioItem(content: audioContent)
        
        // Insert into queue
        Task { @MainActor in
            queue.insert(audioItem, at: insertIndex)
        }
        saveQueue()
        
        // Start generating TTS in background
        Task {
            let result = await ttsGenerator.generateAudio(for: article)
            if case .success(let ttsResult) = result {
                audioItem.setAudioURL(ttsResult.audioURL)
            }
        }
    }
    
    /// Alias for setPlaybackRate (UI compatibility)
    func setSpeechRate(_ rate: Float) {
        setPlaybackRate(rate)
    }
    
    /// Play RSS episode with URL support
    func playRSSEpisode(url: URL, title: String, episode: RSSEpisode?) async {
        print("📻 BriefeedAudioService: playRSSEpisode(url:) called")
        print("  URL: \(url)")
        print("  Title: \(title)")
        if let episode = episode {
            await playRSSEpisode(episode)
        } else {
            // Direct URL playback without episode data
            await MainActor.run {
                isLoading = true
                playbackContext = .direct
                lastError = nil
            }
            
            // Create temporary minimal RSS content
            let tempContent = MinimalRSSContent(
                id: UUID(),
                title: title,
                author: "Live News",
                dateAdded: Date(),
                episodeURL: url,
                feedTitle: "Live News"
            )
            
            let tempItem = BriefeedAudioItem(
                content: tempContent,
                audioURL: url,
                isTemporary: true
            )
            
            // Update current playback item from the temp item
            await MainActor.run {
                currentPlaybackItem = CurrentPlaybackItem(from: tempItem)
            }
            
            await playAudioItem(tempItem)
        }
    }
    
    /// Check if currently playing RSS content
    var isPlayingRSS: Bool {
        currentItem?.content.contentType == .rssEpisode && isPlaying
    }
    
    // MARK: - Queue Management
    
    /// Add article to queue
    func addToQueue(_ article: Article) async {
        let audioContent = ArticleAudioContent(article: article)
        let audioItem = BriefeedAudioItem(content: audioContent)
        
        Task { @MainActor in
            queue.append(audioItem)
        }
        saveQueue()
        
        // Start generating TTS in background
        Task {
            let result = await ttsGenerator.generateAudio(for: article)
            if case .success(let ttsResult) = result {
                audioItem.setAudioURL(ttsResult.audioURL)
            }
        }
    }
    
    /// Add RSS episode to queue
    func addToQueue(_ episode: RSSEpisode) {
        guard let audioURL = URL(string: episode.audioUrl) else { return }
        
        let audioContent = RSSEpisodeAudioContent(episode: episode)
        let audioItem = BriefeedAudioItem(
            content: audioContent,
            audioURL: audioURL,
            isTemporary: false
        )
        
        Task { @MainActor in
            queue.append(audioItem)
        }
        saveQueue()
    }
    
    /// Play next in queue
    func playNext() async {
        // Check for sleep timer end of track
        if sleepTimer.shouldStopAtEndOfTrack() {
            sleepTimer.notifyTrackEnded()
            return
        }
        
        guard queueIndex + 1 < queue.count else { return }
        
        await MainActor.run {
            queueIndex += 1
        }
        let nextItem = queue[queueIndex]
        
        // Ensure audio is ready
        if nextItem.audioURL == nil && nextItem.content.contentType == .article {
            // Generate TTS if needed
            if let article = await fetchArticle(id: nextItem.content.id) {
                await playArticle(article, context: playbackContext)
                return
            }
        }
        
        await playAudioItem(nextItem)
    }
    
    /// Play previous in queue
    func playPrevious() async {
        guard queueIndex > 0 else { return }
        
        await MainActor.run {
            queueIndex -= 1
        }
        let previousItem = queue[queueIndex]
        
        await playAudioItem(previousItem)
    }
    
    /// Remove from queue
    func removeFromQueue(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        
        Task { @MainActor in
            queue.remove(at: index)
            
            // Adjust current index if needed
            if index < queueIndex {
                queueIndex -= 1
            } else if index == queueIndex {
                // Will handle below
            }
        }
        
        if index == queueIndex {
            // Current item was removed, stop playback
            stop()
        }
        
        saveQueue()
    }
    
    /// Clear queue
    func clearQueue() {
        Task { @MainActor in
            queue.removeAll()
            queueIndex = -1
        }
        saveQueue()
        stop()
    }
    
    // MARK: - History
    
    /// Resume from history
    func resumeFromHistory(_ historyItem: PlaybackHistoryItem) async {
        switch historyItem.contentType {
        case .article:
            if let articleID = historyItem.articleID,
               let article = await fetchArticle(id: articleID) {
                await playArticle(article)
                seek(to: historyItem.lastPlaybackPosition)
            }
            
        case .rssEpisode:
            if let episodeURL = historyItem.episodeURL,
               let episode = await fetchRSSEpisode(audioURL: episodeURL) {
                await playRSSEpisode(episode)
                seek(to: historyItem.lastPlaybackPosition)
            }
        }
    }
    
    // MARK: - Sleep Timer
    
    func startSleepTimer(option: SleepTimerOption) {
        sleepTimer.startTimer(option: option)
    }
    
    func stopSleepTimer() {
        sleepTimer.stopTimer()
    }
    
    private func handleSleepTimerExpired() {
        pause()
        
        // Show notification
        let content = UNMutableNotificationContent()
        content.title = "Sleep Timer"
        content.body = "Playback has been paused"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Private Helpers
    
    private func pregenerateUpcomingItems() {
        // Get next few items in queue
        let startIndex = max(0, queueIndex + 1)
        let endIndex = min(queue.count, startIndex + 3)
        
        guard startIndex < endIndex else { return }
        
        let upcomingItems = Array(queue[startIndex..<endIndex])
        
        // Collect article IDs that need TTS generation
        let articleIDsToGenerate = upcomingItems.compactMap { item -> UUID? in
            guard item.content.contentType == .article,
                  item.audioURL == nil else { return nil }
            return item.content.id
        }
        
        if !articleIDsToGenerate.isEmpty {
            Task {
                // Fetch articles from Core Data
                let articles = await fetchArticles(ids: articleIDsToGenerate)
                if !articles.isEmpty {
                    ttsGenerator.pregenerate(articles: articles)
                }
            }
        }
    }
    
    private func fetchArticles(ids: [UUID]) async -> [Article] {
        return await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            let request: NSFetchRequest<Article> = Article.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", ids)
            
            do {
                return try context.fetch(request)
            } catch {
                print("❌ Failed to fetch articles: \(error)")
                return []
            }
        }
    }
    
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
                print("❌ Failed to fetch article: \(error)")
                return nil
            }
        }
    }
    
    private func fetchRSSEpisode(audioURL: String) async -> RSSEpisode? {
        return await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            let request: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
            request.predicate = NSPredicate(format: "audioUrl == %@", audioURL)
            request.fetchLimit = 1
            
            do {
                let episodes = try context.fetch(request)
                return episodes.first
            } catch {
                print("❌ Failed to fetch RSS episode: \(error)")
                return nil
            }
        }
    }
    
    // MARK: - Queue Persistence
    
    private func saveQueue() {
        // Create simplified queue items for persistence
        let queueData = queue.map { item -> [String: Any] in
            var data: [String: Any] = [
                "contentType": item.content.contentType == .article ? "article" : "rssEpisode",
                "id": item.content.id.uuidString,
                "title": item.content.title,
                "dateAdded": item.content.dateAdded
            ]
            
            if let author = item.content.author {
                data["author"] = author
            }
            
            if item.content.contentType == .article {
                // Save article-specific data
                if let articleURL = item.content.articleURL?.absoluteString {
                    data["articleURL"] = articleURL
                }
            } else {
                // Save RSS episode-specific data
                if let episodeURL = item.content.episodeURL?.absoluteString {
                    data["episodeURL"] = episodeURL
                }
                if let feedTitle = item.content.feedTitle {
                    data["feedTitle"] = feedTitle
                }
            }
            
            // Save audio URL if already generated
            if let audioURL = item.audioURL?.absoluteString {
                data["audioURL"] = audioURL
            }
            
            return data
        }
        
        UserDefaults.standard.set(queueData, forKey: queuePersistenceKey)
        UserDefaults.standard.set(queueIndex, forKey: "\(queuePersistenceKey)_index")
    }
    
    private func restoreQueueAsync() async {
        perfLog.logService("BriefeedAudioService", method: "restoreQueueAsync", detail: "Starting")
        guard let queueData = UserDefaults.standard.array(forKey: queuePersistenceKey) as? [[String: Any]] else {
            perfLog.log("No saved queue data found", category: .audio)
            return
        }
        
        perfLog.log("Restoring \(queueData.count) items from saved queue", category: .audio)
        
        queue = queueData.compactMap { data -> BriefeedAudioItem? in
            guard let contentTypeString = data["contentType"] as? String,
                  let idString = data["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let title = data["title"] as? String,
                  let dateAdded = data["dateAdded"] as? Date else {
                return nil
            }
            
            let audioURLString = data["audioURL"] as? String
            let audioURL = audioURLString != nil ? URL(string: audioURLString!) : nil
            
            if contentTypeString == "article" {
                // Restore article - we'll need to fetch full data later
                // For now, create a minimal content object
                let content = MinimalArticleContent(
                    id: id,
                    title: title,
                    author: data["author"] as? String,
                    dateAdded: dateAdded,
                    articleURL: (data["articleURL"] as? String).flatMap { URL(string: $0) }
                )
                
                return BriefeedAudioItem(content: content, audioURL: audioURL)
            } else {
                // Restore RSS episode
                let content = MinimalRSSContent(
                    id: id,
                    title: title,
                    author: data["author"] as? String,
                    dateAdded: dateAdded,
                    episodeURL: (data["episodeURL"] as? String).flatMap { URL(string: $0) },
                    feedTitle: data["feedTitle"] as? String
                )
                
                return BriefeedAudioItem(content: content, audioURL: audioURL)
            }
        }
        
        queueIndex = UserDefaults.standard.integer(forKey: "\(queuePersistenceKey)_index")
        
        // Validate queue index
        if queue.isEmpty {
            queueIndex = -1
        } else if queueIndex >= queue.count {
            queueIndex = queue.count - 1
        }
        
        // Load the queue into the audio player
        if !queue.isEmpty {
            // Clear any existing queue first
            audioPlayer.removeUpcomingItems()
            
            // Add all items to the queue
            for item in queue {
                audioPlayer.add(item: item)
            }
            
            // Jump to the saved queue index
            if queueIndex >= 0 && queueIndex < queue.count {
                try? audioPlayer.jumpToItem(atIndex: queueIndex)
            }
        }
        
        perfLog.logService("BriefeedAudioService", method: "restoreQueueAsync", detail: "Restored \(queue.count) items")
    }
}

// MARK: - SwiftAudioEx Integration
extension BriefeedAudioService {
    private func setupAudioPlayer() {
        perfLog.logService("BriefeedAudioService", method: "setupAudioPlayer", detail: "Configuring SwiftAudioEx player")
        // Configure audio player
        audioPlayer.bufferDuration = 2.0
        audioPlayer.automaticallyWaitsToMinimizeStalling = true
        audioPlayer.automaticallyUpdateNowPlayingInfo = true
        audioPlayer.volume = volume
        
        // Configure remote commands
        audioPlayer.remoteCommands = [
            .play, .pause, 
            .skipForward(preferredIntervals: [15]),
            .skipBackward(preferredIntervals: [15]),
            .changePlaybackPosition,
            .next, .previous
        ]
        
        // Defer event listeners to avoid immediate triggering
        Task { @MainActor in
            // Subscribe to events
            audioPlayer.event.stateChange.addListener(self) { [weak self] state in
                self?.handleStateChange(state)
            }
            
            audioPlayer.event.secondElapse.addListener(self) { [weak self] seconds in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.currentTime = seconds
                    // Update progress publisher
                    if self.duration > 0 {
                        let progressValue = Float(seconds / self.duration)
                        self.progress.send(progressValue)
                    }
                }
            }
            
            audioPlayer.event.updateDuration.addListener(self) { [weak self] duration in
                Task { @MainActor in
                    self?.duration = duration
                }
            }
            
            audioPlayer.event.currentItem.addListener(self) { [weak self] itemData in
                // itemData is a tuple (item, index, lastItem, lastIndex, lastPosition)
                self?.handleCurrentItemChanged(itemData.item as? BriefeedAudioItem)
            }
            
            audioPlayer.event.playbackEnd.addListener(self) { [weak self] reason in
                self?.handlePlaybackEnd(reason)
            }
            
            // Set up remote command center
            setupRemoteCommands()
            
            // Setup Now Playing info
            setupNowPlayingInfo()
            
            // Handle interruptions
            setupInterruptionHandling()
        }
    }
    
    private func handleStateChange(_ state: AVPlayerWrapperState) {
        perfLog.logService("BriefeedAudioService", method: "handleStateChange", detail: "State: \(state)")
        // AVPlayerWrapperState from SwiftAudioEx
        Task { @MainActor in
            switch state {
            case .loading:
                self.isLoading = true
                self.isPlaying = false
                self.state.send(.loading)
            case .playing:
                self.isLoading = false
                self.isPlaying = true
                self.state.send(.playing)
            case .paused:
                self.isLoading = false
                self.isPlaying = false
                self.state.send(.paused)
            case .idle, .ready:
                self.isLoading = false
                self.isPlaying = false
                self.state.send(.idle)
            case .buffering:
                self.isLoading = true
                self.isPlaying = false
                self.state.send(.loading)
            case .stopped:
                self.isLoading = false
                self.isPlaying = false
                self.state.send(.idle)
            case .ended:
                self.isLoading = false
                self.isPlaying = false
                self.state.send(.idle)
            case .failed:
                self.isLoading = false
                self.isPlaying = false
                // SwiftAudioEx doesn't provide error details in state
                self.state.send(.idle)
            @unknown default:
                break
            }
        }
    }
    
    private func handlePlaybackEnd(_ reason: PlaybackEndedReason) {
        // Update history
        if let item = currentItem {
            historyManager.addToHistory(item, position: currentTime, duration: duration)
        }
        
        // Handle sleep timer
        if sleepTimer.shouldStopAtEndOfTrack() {
            sleepTimer.notifyTrackEnded()
            return
        }
        
        // Auto-play next if enabled
        if UserDefaultsManager.shared.autoPlayNext {
            Task {
                await playNext()
            }
        }
    }
    
    private func handleCurrentItemChanged(_ item: AudioItem?) {
        // Update current item info
        if let item = item as? BriefeedAudioItem {
            Task { @MainActor in
                currentItem = item
                currentPlaybackItem = CurrentPlaybackItem(from: item)
            }
            
            // Update Now Playing info
            setupNowPlayingInfo()
        }
    }
    
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        
        // Play/Pause
        center.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        // Skip controls
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward()
            return .success
        }
        
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward()
            return .success
        }
        
        // Next/Previous
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { await self?.playNext() }
            return .success
        }
        
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { await self?.playPrevious() }
            return .success
        }
        
        // Position change
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
        
        // Skip intervals
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
    }
    
    private func setupNowPlayingInfo() {
        // Update Now Playing info when item changes
        guard let item = currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = item.content.title
        info[MPMediaItemPropertyArtist] = item.content.author ?? "Briefeed"
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0
        
        // Add album/feed name
        if let feedTitle = item.content.feedTitle {
            info[MPMediaItemPropertyAlbumTitle] = feedTitle
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            // Interruption began (e.g., phone call)
            pause()
            
        case .ended:
            // Interruption ended
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    play()
                }
            }
            
        @unknown default:
            break
        }
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones were unplugged, or other audio device was removed
            pause()
            
        case .newDeviceAvailable:
            // Headphones were plugged in
            // Optionally resume playback
            break
            
        case .categoryChange, .override, .wakeFromSleep, .noSuitableRouteForCategory,
             .routeConfigurationChange, .unknown:
            // Handle other known cases
            break
            
        @unknown default:
            break
        }
    }
}