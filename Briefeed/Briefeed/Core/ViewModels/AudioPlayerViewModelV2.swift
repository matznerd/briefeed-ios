//
//  AudioPlayerViewModelV2.swift
//  Briefeed
//
//  Updated ViewModel using UnifiedAudioPlayer with SwiftAudioEx
//  Uses the app-wide supported playback speeds
//

import Foundation
import SwiftUI
import Combine
import CoreData

@MainActor
final class AudioPlayerViewModelV2: ObservableObject {
    
    // MARK: - Published Properties (For UI Binding)
    
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isGenerating: Bool = false
    
    @Published private(set) var currentTitle: String?
    @Published private(set) var currentArtist: String?
    @Published private(set) var currentItemType: ItemType = .none
    
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var progress: Float = 0
    
    @Published var playbackSpeed: Float = 1.0 {
        didSet {
            applyPlaybackSpeed()
        }
    }
    
    @Published private(set) var queueItems: [UnifiedQueueItem] = []
    @Published private(set) var currentQueueIndex: Int = -1

    @Published private(set) var activeMode: ActivePlaybackMode = .none
    @Published private(set) var radioState: RadioSessionState = .idle
    @Published private(set) var radioEntries: [RadioQueueEntry] = []
    @Published private(set) var currentRadioEpisode: RadioEpisodeCandidate?
    @Published private(set) var sleepTimer: RadioSleepTimer = .off
    @Published private(set) var sourceFailures: [String: String] = [:]
    @Published private(set) var radioTranscriptPresentation =
        RadioTranscriptPresentation.idle
    @Published private(set) var radioTranscriptBatchPresentation =
        RadioTranscriptBatchPresentation.idle
    
    @Published private(set) var lastError: Error?
    @Published private(set) var generationPhase: GenerationPhase = .idle

    /// Display string for generation progress (derived from generationPhase)
    var generationProgress: String {
        generationPhase.displayMessage
    }
    
    let speedOptions = PlaybackSpeedPolicy.supported
    
    enum ItemType {
        case none
        case article
        case rssEpisode
    }
    
    // MARK: - Private Properties

    private let unifiedPlayer: UnifiedAudioPlayer
    private let radioCoordinator: RadioSessionCoordinating
    private let radioTranscriptCoordinator:
        (any RadioTranscriptCoordinating)?
    private let queueCoordinator = QueueCoordinator.shared
    private let rssService: RSSAudioService
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingPlaybackSpeed = false
    
    // MARK: - Initialization
    
    convenience init() {
        let services = RadioServiceContainer.shared
        self.init(
            unifiedPlayer: .shared,
            radioCoordinator: nil,
            rssService: .shared,
            radioTranscriptCoordinator: services.transcriptCoordinator
        )
    }

    init(
        unifiedPlayer: UnifiedAudioPlayer,
        radioCoordinator: RadioSessionCoordinating? = nil,
        rssService: RSSAudioService,
        radioTranscriptCoordinator:
            (any RadioTranscriptCoordinating)? = nil,
        playbackSpeedLoad: @escaping @MainActor () -> Float = {
            UserDefaultsManager.shared.playbackSpeed
        }
    ) {
        self.unifiedPlayer = unifiedPlayer
        self.radioCoordinator = radioCoordinator ?? unifiedPlayer.radioSessionCoordinator
        self.rssService = rssService
        self.radioTranscriptCoordinator = radioTranscriptCoordinator
        let restoredSpeed = PlaybackSpeedPolicy.normalize(playbackSpeedLoad())
        self.playbackSpeed = restoredSpeed
        unifiedPlayer.setRate(restoredSpeed)
        setupBindings()
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Bind to UnifiedAudioPlayer state
        unifiedPlayer.$isPlaying
            .assign(to: &$isPlaying)
        
        unifiedPlayer.$currentTime
            .removeDuplicates(by: Self.isSameDisplayedSecond)
            .assign(to: &$currentTime)
        
        unifiedPlayer.$duration
            .assign(to: &$duration)
        
        unifiedPlayer.$playbackRate
            .assign(to: &$playbackSpeed)

        unifiedPlayer.$queue
            .sink { [weak self] queue in
                self?.queueItems = queue
                self?.refreshNowPlaying()
            }
            .store(in: &cancellables)

        unifiedPlayer.$currentIndex
            .sink { [weak self] index in
                self?.currentQueueIndex = index
                self?.refreshNowPlaying()
            }
            .store(in: &cancellables)

        unifiedPlayer.$activeMode
            .sink { [weak self] mode in
                self?.activeMode = mode
                self?.refreshNowPlaying()
            }
            .store(in: &cancellables)

        radioCoordinator.statePublisher.assign(to: &$radioState)
        radioCoordinator.entriesPublisher
            .sink { [weak self] entries in
                self?.radioEntries = entries
                self?.updateTranscriptWorkingSet()
            }
            .store(in: &cancellables)
        radioCoordinator.currentEpisodePublisher
            .sink { [weak self] episode in
                self?.currentRadioEpisode = episode
                self?.refreshNowPlaying()
                self?.updateTranscriptWorkingSet()
            }
            .store(in: &cancellables)
        radioCoordinator.sleepTimerPublisher.assign(to: &$sleepTimer)
        radioCoordinator.sourceFailuresPublisher.assign(to: &$sourceFailures)
        radioTranscriptCoordinator?.presentationPublisher
            .assign(to: &$radioTranscriptPresentation)
        radioTranscriptCoordinator?.batchPresentationPublisher
            .assign(to: &$radioTranscriptBatchPresentation)
        
        unifiedPlayer.$isGenerating
            .assign(to: &$isGenerating)

        unifiedPlayer.$generationPhase
            .assign(to: &$generationPhase)

        Publishers.CombineLatest($currentTime, $duration)
            .map { currentTime, duration in
                guard currentTime.isFinite, duration.isFinite, duration > 0 else { return 0 }
                return Float(min(max(currentTime / duration, 0), 1))
            }
            .removeDuplicates()
            .assign(to: &$progress)
    }

    private static func isSameDisplayedSecond(_ previous: TimeInterval, _ next: TimeInterval) -> Bool {
        guard previous.isFinite, next.isFinite else { return previous == next }
        return Int(previous.rounded(.down)) == Int(next.rounded(.down))
    }

    private func refreshNowPlaying() {
        if effectivePlaybackMode == .radio, let episode = currentRadioEpisode {
            currentTitle = episode.displayTitle()
            currentArtist = episode.sourceName
            currentItemType = .rssEpisode
        } else {
            updateCurrentItemInfo(unifiedPlayer.currentItem)
        }
    }

    private func updateTranscriptWorkingSet() {
        guard let radioTranscriptCoordinator else { return }
        guard let currentRadioEpisode else {
            radioTranscriptCoordinator.updateCurrent(nil, next: [])
            return
        }
        let remaining = radioEntries.filter {
            $0.key != currentRadioEpisode.key
        }
        let orderedKeys =
            remaining.filter { $0.disposition == .pending }.map(\.key) +
            remaining.filter { $0.disposition == .deferred }.map(\.key)
        let next = orderedKeys.prefix(2).compactMap {
            radioCoordinator.candidate(for: $0)
        }
        radioTranscriptCoordinator.updateCurrent(
            currentRadioEpisode,
            next: next
        )
    }
    
    private func applyPlaybackSpeed() {
        guard !isApplyingPlaybackSpeed else { return }

        isApplyingPlaybackSpeed = true
        let normalized = PlaybackSpeedPolicy.normalize(playbackSpeed)
        if playbackSpeed != normalized {
            playbackSpeed = normalized
        }
        unifiedPlayer.setRate(normalized)
        isApplyingPlaybackSpeed = false
    }
    
    // MARK: - Computed Properties
    
    var canPlayPrevious: Bool {
        unifiedPlayer.canPlayPrevious
    }
    
    var canPlayNext: Bool {
        unifiedPlayer.canPlayNext
    }
    
    var formattedCurrentTime: String {
        unifiedPlayer.formattedCurrentTime
    }
    
    var formattedDuration: String {
        unifiedPlayer.formattedDuration
    }
    
    var formattedRemainingTime: String {
        unifiedPlayer.formattedRemainingTime
    }
    
    var progressPercentage: Double {
        unifiedPlayer.progressPercentage
    }

    var effectivePlaybackMode: ActivePlaybackMode {
        unifiedPlayer.effectivePlaybackMode
    }

    var playerPresentation: PlayerSurfacePresentation {
        if activeMode != .brief, radioState == .exhausted {
            return PlayerSurfacePresentation(
                kind: .caughtUp,
                mode: .radio,
                title: "You're caught up",
                source: "Check for new episodes",
                position: 0,
                duration: 0,
                showsPrevious: false,
                showsSleep: false,
                showsQueue: false,
                allowsPlay: false,
                allowsSeek: false,
                allowsExpand: false,
                primaryAction: .refresh
            )
        }

        let mode = effectivePlaybackMode
        let title: String
        let source: String
        if mode == .radio, let episode = currentRadioEpisode {
            title = episode.displayTitle()
            source = episode.sourceName
        } else {
            let queuedItem = unifiedPlayer.currentItem ?? (mode == .brief ? queueItems.first : nil)
            title = currentTitle ?? queuedItem?.title ?? "Not Playing"
            source = currentArtist
                ?? queuedItem?.article?.author
                ?? queuedItem?.episode?.feed?.displayName
                ?? (mode == .radio ? "Briefeed Radio" : "Briefeed")
        }
        let playable = mode != .none || currentTitle != nil
        return PlayerSurfacePresentation(
            kind: playable ? .playable : .unavailable,
            mode: mode,
            title: title,
            source: source,
            position: unifiedPlayer.presentationPosition,
            duration: unifiedPlayer.presentationDuration,
            showsPrevious: PlayerPresentationPolicy.showsPrevious(for: mode),
            showsSleep: mode == .radio,
            showsQueue: mode != .radio && !queueItems.isEmpty,
            allowsPlay: playable,
            allowsSeek: playable,
            allowsExpand: playable,
            primaryAction: .playPause
        )
    }
    
    // MARK: - Playback Control
    
    func togglePlayPause() {
        if isPlaying {
            unifiedPlayer.pause()
        } else {
            Task { await play() }
        }
    }
    
    func play() async {
        isLoading = true
        lastError = nil
        await Task.yield()
        defer { isLoading = false }
        await unifiedPlayer.beginEffectiveCurrent()
    }
    
    func pause() {
        unifiedPlayer.pause()
    }
    
    func stop() {
        unifiedPlayer.stop()
    }
    
    func skipForward(_ seconds: TimeInterval = 10) {
        unifiedPlayer.skipForward(seconds)
    }
    
    func skipBackward(_ seconds: TimeInterval = 10) {
        unifiedPlayer.skipBackward(seconds)
    }
    
    func seek(to progress: Float) {
        let time = TimeInterval(progress) * duration
        unifiedPlayer.seek(to: time)
    }
    
    // MARK: - Navigation Methods for Mini Player
    
    func playNext() async {
        guard canPlayNext else { return }
        isLoading = true

        // CRITICAL: Yield to allow SwiftUI to update UI before heavy work
        await Task.yield()

        defer { isLoading = false }
        await unifiedPlayer.playNext()
    }
    
    func playPrevious() async {
        // If we're more than 3 seconds into playback, restart current item
        if currentTime > 3 {
            unifiedPlayer.seek(to: 0)
            return
        }

        // Otherwise go to previous item if possible
        guard canPlayPrevious else {
            unifiedPlayer.seek(to: 0)
            return
        }

        isLoading = true

        // CRITICAL: Yield to allow SwiftUI to update UI before heavy work
        await Task.yield()

        defer { isLoading = false }
        await unifiedPlayer.playPrevious()
    }
    
    // MARK: - Seek Methods for Mini Player
    
    func seekForward() {
        // Seek forward 10 seconds
        skipForward(10)
    }
    
    func seekBackward() {
        // Seek backward 10 seconds
        skipBackward(10)
    }
    
    func seek(to time: TimeInterval) {
        unifiedPlayer.seek(to: time)
    }
    
    // MARK: - Speed Control
    
    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
    }
    
    func increaseSpeed() {
        if let currentIndex = speedOptions.firstIndex(where: { $0 >= playbackSpeed }),
           currentIndex < speedOptions.count - 1 {
            setSpeed(speedOptions[currentIndex + 1])
        }
    }
    
    func decreaseSpeed() {
        if let currentIndex = speedOptions.firstIndex(where: { $0 >= playbackSpeed }),
           currentIndex > 0 {
            setSpeed(speedOptions[currentIndex - 1])
        }
    }
    
    // MARK: - Play Specific Content
    
    func play(article: Article) async {
        isLoading = true
        lastError = nil

        // CRITICAL: Yield to allow SwiftUI to update UI before heavy work
        await Task.yield()

        // Check if article is already in the queue
        if let existingIndex = queueItems.firstIndex(where: { $0.article?.id == article.id }) {
            // Article already in queue, just play it at its current position
            await unifiedPlayer.play(at: existingIndex)
        } else {
            // Article not in queue: add to Brief queue and play immediately.
            await addToQueue(article, playNow: true)
        }
        
        isLoading = false
    }
    
    func play(episode: RSSEpisode) async {
        isLoading = true
        lastError = nil

        // CRITICAL: Yield to allow SwiftUI to update UI before heavy work
        await Task.yield()

        // Check if episode is already in the queue
        if let existingIndex = queueItems.firstIndex(where: { 
            $0.audioURL?.absoluteString == episode.audioUrl 
        }) {
            // Episode already in queue, just play it at its current position
            await unifiedPlayer.play(at: existingIndex)
        } else {
            // Episode not in queue: add to Brief queue and play immediately.
            await addToQueue(episode, playNow: true)
        }
        
        isLoading = false
    }
    
    func playQueue(articles: [Article]) async {
        isLoading = true
        lastError = nil

        // CRITICAL: Yield to allow SwiftUI to update UI before heavy work
        await Task.yield()

        // Replace queue and load fresh (clear stale items from previous sessions)
        await unifiedPlayer.loadQueue(from: articles, replace: true)

        // Start playing from beginning
        if !articles.isEmpty {
            await unifiedPlayer.play(at: 0)
        }
        
        isLoading = false
    }
    
    /// Sync articles to the queue without starting playback (used by Brief tab onAppear)
    func syncToQueue(articles: [Article]) async {
        await unifiedPlayer.loadQueue(from: articles)
    }

    func playQueue(episodes: [RSSEpisode]) async {
        isLoading = true
        lastError = nil

        // CRITICAL: Yield to allow SwiftUI to update UI before heavy work
        await Task.yield()

        // Load full queue
        await unifiedPlayer.loadQueue(from: episodes)
        
        // Start playing from beginning
        if !episodes.isEmpty {
            await unifiedPlayer.play(at: 0)
        }
        
        isLoading = false
    }
    
    func playMixedQueue(items: [Any]) async {
        isLoading = true
        lastError = nil

        // CRITICAL: Yield to allow SwiftUI to update UI before heavy work
        await Task.yield()

        // Load mixed queue
        await unifiedPlayer.loadMixedQueue(items: items)
        
        // Start playing from beginning
        if !items.isEmpty {
            await unifiedPlayer.play(at: 0)
        }
        
        isLoading = false
    }
    
    // MARK: - Queue Management
    
    func playItemAt(index: Int) async {
        await unifiedPlayer.play(at: index)
    }
    
    func addToQueue(_ article: Article, playNow: Bool = false, playNext: Bool = false) async {
        await unifiedPlayer.addToQueue(article, playNow: playNow, playNext: playNext)

        // If playNow, start playback immediately
        if playNow {
            await unifiedPlayer.play(at: unifiedPlayer.currentIndex >= 0 ? unifiedPlayer.currentIndex : 0)
        }
    }

    func addToQueue(_ episode: RSSEpisode, playNow: Bool = false, playNext: Bool = false) async {
        await unifiedPlayer.addToQueue(episode, playNow: playNow, playNext: playNext)

        // If playNow, start playback immediately
        if playNow {
            await unifiedPlayer.play(at: unifiedPlayer.currentIndex >= 0 ? unifiedPlayer.currentIndex : 0)
        }
    }

    func queueArticle(_ article: Article, playNow: Bool = false, playNext: Bool = false) async {
        await addToQueue(article, playNow: playNow, playNext: playNext)
    }

    func queueEpisode(_ episode: RSSEpisode, playNow: Bool = false, playNext: Bool = false) async {
        await addToQueue(episode, playNow: playNow, playNext: playNext)
    }
    
    func removeFromQueue(at index: Int) async {
        unifiedPlayer.removeFromQueue(at: index)
    }
    
    func clearQueue() async {
        unifiedPlayer.clearQueue()
    }
    
    func saveQueueState() async {
        // Save current queue to UserDefaults for persistence
        let queueData = queueItems.compactMap { item -> [String: Any]? in
            if let article = item.article {
                return [
                    "type": "article",
                    "id": article.id?.uuidString ?? "",
                    "title": article.title ?? ""
                ]
            } else if let episode = item.episode {
                return [
                    "type": "episode", 
                    "id": episode.id,
                    "title": episode.title
                ]
            }
            return nil
        }
        
        UserDefaults.standard.set(queueData, forKey: "audioQueueState")
        UserDefaults.standard.set(currentQueueIndex, forKey: "audioQueueIndex")
    }
    
    func playNextInQueue() {
        Task {
            await playNext()
        }
    }
    
    func playPreviousInQueue() {
        Task {
            await playPrevious()
        }
    }
    
    func reorderQueue(from source: IndexSet, to destination: Int) async {
        // Delegate to QueueCoordinator (source of truth)
        // Local queue (queueItems) syncs automatically via Combine subscription
        queueCoordinator.moveItems(from: source, to: destination)
    }
    
    // MARK: - Private Methods
    
    private func updateCurrentItemInfo(_ item: UnifiedQueueItem?) {
        guard let item = item else {
            currentTitle = nil
            currentArtist = nil
            currentItemType = .none
            return
        }
        
        currentTitle = item.title
        
        switch item.type {
        case .article:
            currentArtist = item.article?.author ?? "Unknown Author"
            currentItemType = .article
        case .rssEpisode:
            currentArtist = item.episode?.feed?.displayName ?? "Unknown Podcast"
            currentItemType = .rssEpisode
        }
    }
    
    // MARK: - Error Handling
    
    func handleError(_ error: Error) {
        lastError = error
        isLoading = false
        isGenerating = false
        
        // Log error
        print("[AudioPlayerViewModel] Error: \(error)")
    }
    
}

// MARK: - Radio Support

extension AudioPlayerViewModelV2 {
    func playRadio() async {
        isLoading = true
        lastError = nil
        await unifiedPlayer.playRadio()
        isLoading = false
    }

    func playRadioEpisode(_ key: RadioEpisodeKey) async {
        isLoading = true
        lastError = nil
        await unifiedPlayer.playRadioEpisode(key)
        isLoading = false
    }

    @discardableResult
    func queueRadioEpisode(_ key: RadioEpisodeKey) -> Bool {
        unifiedPlayer.queueRadioEpisode(key)
    }

    func retryRadio() async {
        isLoading = true
        await unifiedPlayer.retryRadio()
        isLoading = false
    }

    func refreshRadio() async {
        isLoading = true
        #if DEBUG
        if let definition = AppRuntime.radioFixtureDefinition {
            RadioFixtureDiagnostics.shared.recordRefreshInvocation()
            await unifiedPlayer.execute(
                definition.applyPostRestore(to: radioCoordinator)
            )
            isLoading = false
            return
        }
        #endif
        radioCoordinator.refreshStarted(enabledSourceCount: rssService.feeds.filter(\.isEnabled).count)
        let result = await rssService.refreshAllFeeds()
        await unifiedPlayer.execute(radioCoordinator.applyRefresh(result))
        isLoading = false
    }

    func radioSourceConfigurationDidChange(enabledSourceCount: Int) async {
        await unifiedPlayer.execute(
            radioCoordinator.sourceConfigurationDidChange(
                enabledSourceCount: enabledSourceCount
            )
        )
    }

    func setSleepTimer(_ timer: RadioSleepTimer) {
        unifiedPlayer.setRadioSleepTimer(timer)
    }

    func setCustomSleepTimer(minutes: Int, now: Date = Date()) {
        setSleepTimer(RadioSleepMenuOption.custom.timer(now: now, customMinutes: minutes))
    }

    func cancelSleepTimer() {
        unifiedPlayer.cancelRadioSleepTimer()
    }

    func updateVisibleRadioTranscriptCandidates(
        _ candidates: [RadioEpisodeCandidate]
    ) {
        radioTranscriptCoordinator?.updateVisibleSnapshot(candidates)
    }

    func prepareAllRadioTranscripts() {
        radioTranscriptCoordinator?.prepareAll()
    }

    func retryCurrentRadioTranscript() {
        radioTranscriptCoordinator?.retryCurrent()
    }

    func stopPreparingRadioTranscripts() {
        radioTranscriptCoordinator?.stopPrepareAll()
    }
}

// MARK: - Testing Support

#if DEBUG
extension AudioPlayerViewModelV2 {
    func loadTestQueue() async {
        // Create test items for debugging
        let testArticles = [
            "Test Article 1",
            "Test Article 2",
            "Test Article 3"
        ]
        
        // For now, just set up test items
        // This would need actual Article objects in a real implementation
        print("[AudioPlayerViewModelV2] Test queue loading not fully implemented")
    }
}
#endif
