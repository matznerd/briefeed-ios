import CoreData
import SwiftUI

enum RadioFailureRecoveryAction: Equatable {
    case refreshSources
    case retryPlayback
}

enum RadioPlaylistStatus: Equatable {
    case upNext
    case latest
    case inProgress(fraction: Double)
    case listened
    case failed
}

enum RadioRowPrimaryAction: Equatable {
    case play
    case pause
    case resume
    case replay
    case retry

    var systemImage: String {
        switch self {
        case .play: "play.circle.fill"
        case .pause: "pause.circle.fill"
        case .resume: "play.circle.fill"
        case .replay: "arrow.counterclockwise.circle.fill"
        case .retry: "arrow.clockwise.circle.fill"
        }
    }

    var accessibilityVerb: String {
        switch self {
        case .play: "Play"
        case .pause: "Pause"
        case .resume: "Resume"
        case .replay: "Replay"
        case .retry: "Retry"
        }
    }
}

struct RadioPlaylistItem: Identifiable, Equatable {
    var id: RadioEpisodeKey { candidate.key }
    let candidate: RadioEpisodeCandidate
    let entry: RadioQueueEntry?
    let isCurrent: Bool
    let status: RadioPlaylistStatus
    let earlierEpisodeCount: Int
}

enum RadioHomePresentation {
    static func playlistItems(
        candidates: [RadioEpisodeCandidate],
        entries: [RadioQueueEntry],
        currentKey: RadioEpisodeKey?
    ) -> [RadioPlaylistItem] {
        let entriesByKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })
        let episodesBySource = Dictionary(grouping: candidates, by: { $0.key.feedID })
        return episodesBySource.values
            .compactMap { episodes -> RadioPlaylistItem? in
                let sorted = episodes.sorted(by: candidateRecencySort)
                guard let latest = sorted.first else { return nil }
                return makePlaylistItem(
                    candidate: latest,
                    entry: entriesByKey[latest.key],
                    currentKey: currentKey,
                    earlierEpisodeCount: max(sorted.count - 1, 0)
                )
            }
            .sorted {
                if $0.candidate.sourcePriority != $1.candidate.sourcePriority {
                    return $0.candidate.sourcePriority < $1.candidate.sourcePriority
                }
                if $0.candidate.key.feedID != $1.candidate.key.feedID {
                    return $0.candidate.key.feedID < $1.candidate.key.feedID
                }
                return candidateRecencySort($0.candidate, $1.candidate)
            }
    }

    static func displayTitle(
        for candidate: RadioEpisodeCandidate,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        candidate.displayTitle(timeZone: timeZone, locale: locale)
    }

    static func sourceIdentity(for candidate: RadioEpisodeCandidate) -> String {
        candidate.sourceIdentity
    }

    private static func candidateRecencySort(_ lhs: RadioEpisodeCandidate, _ rhs: RadioEpisodeCandidate) -> Bool {
        if lhs.publicationDate != rhs.publicationDate { return lhs.publicationDate > rhs.publicationDate }
        return lhs.key.episodeID < rhs.key.episodeID
    }

    private static func makePlaylistItem(
        candidate: RadioEpisodeCandidate,
        entry: RadioQueueEntry?,
        currentKey: RadioEpisodeKey?,
        earlierEpisodeCount: Int
    ) -> RadioPlaylistItem {
        let durableProgress = min(max(candidate.normalizedCoreDataProgress, 0), 1)
        let sessionProgress: Double = {
            guard let seconds = entry?.positionSeconds,
                  seconds.isFinite,
                  let duration = candidate.durationSeconds,
                  duration.isFinite,
                  duration > 0 else { return 0 }
            return min(max(seconds / duration, 0), 1)
        }()
        let progress = max(durableProgress, sessionProgress)
        let status: RadioPlaylistStatus
        if candidate.isCompleted || progress >= 1 {
            status = .listened
        } else if entry?.disposition == .failedThisSession {
            status = .failed
        } else if progress > 0 {
            status = .inProgress(fraction: progress)
        } else if entry?.disposition == .retired {
            status = .latest
        } else if entry != nil {
            status = .upNext
        } else {
            status = .latest
        }
        return RadioPlaylistItem(
            candidate: candidate,
            entry: entry,
            isCurrent: candidate.key == currentKey,
            status: status,
            earlierEpisodeCount: earlierEpisodeCount
        )
    }

    static func currentControlLabel(
        activeMode: ActivePlaybackMode,
        isPlaying: Bool
    ) -> String {
        activeMode == .radio && isPlaying ? "Pause Radio" : "Play Radio"
    }

    static func primaryAction(
        for item: RadioPlaylistItem,
        activeMode: ActivePlaybackMode,
        isPlaying: Bool
    ) -> RadioRowPrimaryAction {
        if item.isCurrent, activeMode == .radio, isPlaying { return .pause }
        switch item.status {
        case .listened: return .replay
        case .inProgress: return .resume
        case .failed: return .retry
        case .upNext, .latest: return .play
        }
    }

    static func failureRecovery(for failure: RadioFailure) -> RadioFailureRecoveryAction {
        switch failure {
        case .allSourcesUnavailable:
            .refreshSources
        case .playback, .persistence:
            .retryPlayback
        }
    }
}

struct RadioHomeView: View {
    private struct SourceRoute: Hashable, Identifiable {
        let feedID: String
        let sourceName: String

        var id: String { feedID }
    }

    @EnvironmentObject private var audioPlayerViewModel: AudioPlayerViewModelV2
    @State private var showingAddSource = false
    @State private var showingExpandedTranscript = false
    @State private var selectedSourceRoute: SourceRoute?
    private let onAppearRefresh: @MainActor () -> Void
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \RSSEpisode.pubDate, ascending: false)],
        predicate: NSPredicate(format: "feed.isEnabled == YES"),
        animation: .default
    ) private var enabledEpisodes: FetchedResults<RSSEpisode>

    init(onAppearRefresh: @escaping @MainActor () -> Void = {}) {
        self.onAppearRefresh = onAppearRefresh
    }

    var body: some View {
        NavigationStack {
            List {
                if audioPlayerViewModel.currentRadioEpisode != nil {
                    Section {
                        RadioTranscriptViewer(
                            presentation:
                                audioPlayerViewModel.radioTranscriptPresentation,
                            currentTime: audioPlayerViewModel.currentTime,
                            playbackSyncState:
                                audioPlayerViewModel
                                    .radioTranscriptPlaybackSyncState,
                            onOpen: {
                                showingExpandedTranscript = true
                            },
                            onRetry: {
                                audioPlayerViewModel
                                    .retryCurrentRadioTranscript()
                            }
                        )
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }

                if !playlistItems.isEmpty {
                    Section("Your radio brief") {
                        ForEach(playlistItems) { item in
                            playlistRow(item)
                        }

                        RadioTranscriptPrepareAllRow(
                            content: prepareAllContent,
                            onPrepare: {
                                updateVisibleTranscriptSnapshot()
                                audioPlayerViewModel
                                    .prepareAllRadioTranscripts()
                            },
                            onStop: {
                                audioPlayerViewModel
                                    .stopPreparingRadioTranscripts()
                            }
                        )
                    }
                    .accessibilityIdentifier(AccessibilityID.Radio.playlist)
                }

                if showsStateMessage {
                    Section {
                        radioStateView
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Radio")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedSourceRoute) { route in
                RadioSourceEpisodesView(
                    sourceName: route.sourceName,
                    episodes: sourceCandidates(for: route.feedID)
                )
            }
            .refreshable {
                await audioPlayerViewModel.refreshRadio()
            }
            .sheet(isPresented: $showingAddSource) {
                AddRSSFeedViewV2 {
                    await audioPlayerViewModel.radioSourceConfigurationDidChange(
                        enabledSourceCount: RSSAudioService.shared.enabledFeedCount
                    )
                }
            }
            .sheet(isPresented: $showingExpandedTranscript) {
                RadioExpandedTranscriptView(
                    presentation:
                        audioPlayerViewModel.radioTranscriptPresentation,
                    currentTime: audioPlayerViewModel.currentTime,
                    playbackSyncState:
                        audioPlayerViewModel
                            .radioTranscriptPlaybackSyncState,
                    isPlaying: audioPlayerViewModel.isPlaying,
                    canPlayNext: audioPlayerViewModel.canPlayNext,
                    onSeek: audioPlayerViewModel.seek(to:),
                    onBackTen: audioPlayerViewModel.seekBackward,
                    onPlayPause: audioPlayerViewModel.togglePlayPause,
                    onForwardTen: audioPlayerViewModel.seekForward,
                    onNext: {
                        Task { await audioPlayerViewModel.playNext() }
                    }
                )
                .presentationDetents([.large])
            }
        }
        .onAppear {
            onAppearRefresh()
            updateVisibleTranscriptSnapshot()
        }
        .onChange(of: visibleTranscriptKeys) {
            updateVisibleTranscriptSnapshot()
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if AppRuntime.radioFixtureScenario != nil {
                RadioFixtureDiagnosticsAccessibilityView()
            }
        }
        #endif
    }

    private var playlistItems: [RadioPlaylistItem] {
        RadioHomePresentation.playlistItems(
            candidates: enabledEpisodes.compactMap { RadioEpisodeCandidate(episode: $0) },
            entries: audioPlayerViewModel.radioEntries,
            currentKey: audioPlayerViewModel.currentRadioEpisode?.key
        )
    }

    private var visibleTranscriptCandidates: [RadioEpisodeCandidate] {
        RadioTranscriptUIPresentation.eligibleCandidates(
            from: playlistItems
        )
    }

    private var visibleTranscriptKeys: [RadioEpisodeKey] {
        visibleTranscriptCandidates.map(\.key)
    }

    private var prepareAllContent: RadioTranscriptPrepareAllContent {
        RadioTranscriptUIPresentation.prepareAll(
            batch:
                audioPlayerViewModel.radioTranscriptBatchPresentation,
            eligibleCount: visibleTranscriptCandidates.count,
            isAvailable: transcriptPreparationIsAvailable
        )
    }

    private var transcriptPreparationIsAvailable: Bool {
        audioPlayerViewModel.radioTranscriptPreparationIsAvailable
    }

    private func updateVisibleTranscriptSnapshot() {
        audioPlayerViewModel.updateVisibleRadioTranscriptCandidates(
            visibleTranscriptCandidates
        )
    }

    private var showsStateMessage: Bool {
        switch audioPlayerViewModel.radioState {
        case .idle:
            return playlistItems.isEmpty
        case .restoring, .refreshing, .waitingForNetwork, .noSources, .exhausted, .failed:
            return true
        case .readyPaused, .loading, .playing, .pausedByUser:
            return false
        }
    }

    private func playlistRow(_ item: RadioPlaylistItem) -> some View {
        let action = RadioHomePresentation.primaryAction(
            for: item,
            activeMode: audioPlayerViewModel.activeMode,
            isPlaying: audioPlayerViewModel.isPlaying
        )
        return HStack(spacing: 0) {
            Button {
                perform(action, for: item)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: action.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(action == .retry ? Color.orange : Color.briefeedRed)
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(RadioHomePresentation.displayTitle(for: item.candidate))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .accessibilityIdentifier(AccessibilityID.Radio.episodeTitle(item.candidate.key))

                        Text(sourceSummary(for: item))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(playlistStatusText(for: item))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(playlistTint(for: item))
                            .accessibilityIdentifier(AccessibilityID.Radio.episodeState(item.candidate.key))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(action.accessibilityVerb) \(RadioHomePresentation.displayTitle(for: item.candidate))")
            .accessibilityValue(playlistStatusText(for: item))
            .accessibilityIdentifier(AccessibilityID.Radio.episode(item.candidate.key))

            Button {
                selectedSourceRoute = SourceRoute(
                    feedID: item.candidate.key.feedID,
                    sourceName: item.candidate.sourceName
                )
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Episodes for \(RadioHomePresentation.sourceIdentity(for: item.candidate))")
            .accessibilityIdentifier(AccessibilityID.Radio.sourceEpisodes(item.candidate.key.feedID))
        }
        .padding(.vertical, 5)
    }

    private func perform(_ action: RadioRowPrimaryAction, for item: RadioPlaylistItem) {
        switch action {
        case .pause:
            audioPlayerViewModel.pause()
        case .retry:
            Task { await audioPlayerViewModel.retryRadio() }
        case .play, .resume, .replay:
            Task { await audioPlayerViewModel.playRadioEpisode(item.candidate.key) }
        }
    }

    private func sourceCandidates(for feedID: String) -> [RadioEpisodeCandidate] {
        enabledEpisodes
            .compactMap { RadioEpisodeCandidate(episode: $0) }
            .filter { $0.key.feedID == feedID }
            .sorted {
                if $0.publicationDate != $1.publicationDate { return $0.publicationDate > $1.publicationDate }
                return $0.key.episodeID < $1.key.episodeID
            }
    }

    private func sourceSummary(for item: RadioPlaylistItem) -> String {
        let archive = item.earlierEpisodeCount == 1
            ? "1 earlier episode"
            : "\(item.earlierEpisodeCount) earlier episodes"
        if item.candidate.sourceFrequency == .hourly {
            return item.earlierEpisodeCount > 0 ? "Latest bulletin · \(archive)" : "Latest bulletin"
        }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        let published = relative.localizedString(for: item.candidate.publicationDate, relativeTo: Date())
        return item.earlierEpisodeCount > 0
            ? "\(item.candidate.sourceName) · \(published) · \(archive)"
            : "\(item.candidate.sourceName) · \(published)"
    }

    private func playlistTint(for item: RadioPlaylistItem) -> Color {
        switch item.status {
        case .listened: .secondary
        case .failed: .orange
        case .upNext, .latest, .inProgress: item.isCurrent ? .briefeedRed : .secondary
        }
    }

    private func playlistStatusText(for item: RadioPlaylistItem) -> String {
        switch item.status {
        case .listened:
            "Listened"
        case .inProgress(let fraction):
            "\(Int((fraction * 100).rounded()))% listened"
        case .failed:
            "Unavailable this session"
        case .upNext:
            item.isCurrent ? "Ready" : "Up next"
        case .latest:
            "Latest update"
        }
    }

    @ViewBuilder
    private var radioStateView: some View {
        switch audioPlayerViewModel.radioState {
        case .idle:
            stateMessage(
                icon: "dot.radiowaves.left.and.right",
                title: "Your radio brief",
                detail: "Play the latest eligible episode from your enabled sources.",
                actionTitle: audioPlayerViewModel.radioEntries.isEmpty ? nil : "Play Radio",
                actionID: nil
            ) {
                await audioPlayerViewModel.playRadio()
            }

        case .restoring:
            progressState(title: "Restoring Radio")

        case .refreshing:
            progressState(title: "Refreshing Radio")

        case .readyPaused, .pausedByUser:
            stateMessage(
                icon: "play.circle",
                title: "Ready to play",
                detail: "Continue your radio brief where you left off.",
                actionTitle: "Play Radio",
                actionID: nil
            ) {
                await audioPlayerViewModel.playRadio()
            }

        case .loading:
            progressState(title: "Starting Radio")

        case .playing:
            stateMessage(
                icon: "waveform",
                title: "On Air",
                detail: "Your radio brief is playing.",
                actionTitle: nil,
                actionID: nil,
                action: nil
            )

        case .waitingForNetwork:
            stateMessage(
                icon: "wifi.slash",
                title: "Waiting for Network",
                detail: "Radio will continue when a connection is available.",
                actionTitle: "Try Again",
                actionID: AccessibilityID.Radio.retry
            ) {
                await audioPlayerViewModel.retryRadio()
            }

        case .noSources:
            stateMessage(
                icon: "plus.circle",
                title: "Choose your sources",
                detail: "Add a podcast or enable a source to start Radio.",
                actionTitle: "Add Source",
                actionID: AccessibilityID.Radio.addSource
            ) {
                showingAddSource = true
            }

        case .exhausted:
            stateMessage(
                icon: "checkmark.circle",
                title: "You're caught up",
                detail: "Refresh to check your sources for a new episode.",
                actionTitle: "Refresh",
                actionID: AccessibilityID.Radio.refresh
            ) {
                await audioPlayerViewModel.refreshRadio()
            }

        case .failed(let failure):
            let recovery = RadioHomePresentation.failureRecovery(for: failure)
            stateMessage(
                icon: "exclamationmark.triangle",
                title: "Radio needs attention",
                detail: failureMessage(failure),
                actionTitle: recovery == .refreshSources ? "Refresh" : "Retry",
                actionID: recovery == .refreshSources
                    ? AccessibilityID.Radio.refresh
                    : AccessibilityID.Radio.retry
            ) {
                switch recovery {
                case .refreshSources:
                    await audioPlayerViewModel.refreshRadio()
                case .retryPlayback:
                    await audioPlayerViewModel.retryRadio()
                }
            }
        }
    }

    private func progressState(title: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityIdentifier(AccessibilityID.Radio.state)
    }

    private func stateMessage(
        icon: String,
        title: String,
        detail: String,
        actionTitle: String?,
        actionID: String?,
        action: (() async -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let actionTitle, let action {
                Button(actionTitle) {
                    Task { await action() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.briefeedRed)
                .accessibilityIdentifier(actionID ?? "")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func stateMessage(
        icon: String,
        title: String,
        detail: String,
        actionTitle: String?,
        actionID: String?,
        action: @escaping () async -> Void
    ) -> some View {
        stateMessage(
            icon: icon,
            title: title,
            detail: detail,
            actionTitle: actionTitle,
            actionID: actionID,
            action: Optional(action)
        )
    }

    private func failureMessage(_ failure: RadioFailure) -> String {
        switch failure {
        case .allSourcesUnavailable:
            "None of your enabled sources responded."
        case .playback(let message):
            message
        case .persistence:
            "Your listening position could not be saved."
        }
    }
}

private struct RadioSourceEpisodesView: View {
    @EnvironmentObject private var audioPlayerViewModel: AudioPlayerViewModelV2

    let sourceName: String
    let episodes: [RadioEpisodeCandidate]

    var body: some View {
        List {
            Section {
                ForEach(episodes, id: \.key) { episode in
                    episodeRow(episode)
                }
            } footer: {
                Text("The newest update is used automatically. Earlier episodes play only when you choose them here.")
            }
        }
        .listStyle(.plain)
        .navigationTitle(sourceName)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(AccessibilityID.Radio.sourceArchive)
    }

    private func episodeRow(_ episode: RadioEpisodeCandidate) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await audioPlayerViewModel.playRadioEpisode(episode.key) }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(RadioHomePresentation.displayTitle(for: episode))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(episode.publicationDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(episodeStatus(episode))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(episodeTint(episode))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.Radio.archivePlay(episode.key))

            Menu {
                Button {
                    Task { await audioPlayerViewModel.playRadioEpisode(episode.key) }
                } label: {
                    Label("Play Now", systemImage: "play.fill")
                }

                Button {
                    _ = audioPlayerViewModel.queueRadioEpisode(episode.key)
                } label: {
                    Label("Play Later", systemImage: "text.badge.plus")
                }
                .disabled(isQueued(episode))
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Options for \(episode.title)")
            .accessibilityIdentifier(AccessibilityID.Radio.archiveOptions(episode.key))
        }
        .padding(.vertical, 4)
    }

    private func isQueued(_ episode: RadioEpisodeCandidate) -> Bool {
        audioPlayerViewModel.radioEntries.contains { $0.key == episode.key }
    }

    private func episodeStatus(_ episode: RadioEpisodeCandidate) -> String {
        if episode.isCompleted { return "Listened" }
        if audioPlayerViewModel.currentRadioEpisode?.key == episode.key {
            return audioPlayerViewModel.isPlaying ? "Playing" : "Current"
        }
        if let entry = audioPlayerViewModel.radioEntries.first(where: { $0.key == episode.key }) {
            if entry.isManuallyQueued { return "Queued for later" }
            if entry.disposition == .retired { return "Skipped for now" }
            if episode.durationSeconds.map({ $0 > 0 }) == true, entry.positionSeconds > 0 {
                let fraction = min(max(entry.positionSeconds / (episode.durationSeconds ?? 1), 0), 1)
                return "\(Int((fraction * 100).rounded()))% listened"
            }
            return "In your brief"
        }
        return episode.key == episodes.first?.key ? "Latest" : "Earlier episode"
    }

    private func episodeTint(_ episode: RadioEpisodeCandidate) -> Color {
        if episode.isCompleted { return .secondary }
        if audioPlayerViewModel.currentRadioEpisode?.key == episode.key { return .briefeedRed }
        return .secondary
    }
}

#if DEBUG
private struct RadioFixtureDiagnosticsAccessibilityView: View {
    @ObservedObject private var diagnostics = RadioFixtureDiagnostics.shared

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 1, height: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Radio fixture diagnostics")
            .accessibilityValue(diagnostics.accessibilityValue)
            .accessibilityIdentifier(AccessibilityID.Radio.fixtureDiagnostics)
    }
}
#endif

struct RadioSourceManagementView: View {
    @EnvironmentObject private var audioPlayerViewModel: AudioPlayerViewModelV2
    @Environment(\.managedObjectContext) private var context
    @State private var editMode = EditMode.inactive
    @State private var showingAddSource = false
    @State private var saveErrorMessage: String?

    @FetchRequest(
        entity: RSSFeed.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \RSSFeed.priority, ascending: true),
            NSSortDescriptor(keyPath: \RSSFeed.displayName, ascending: true)
        ]
    ) private var feeds: FetchedResults<RSSFeed>

    var body: some View {
        List {
            ForEach(feeds) { feed in
                sourceRow(feed)
            }
            .onMove(perform: moveSources)
            .onDelete(perform: deleteSources)

            Button {
                showingAddSource = true
            } label: {
                Label("Add Source", systemImage: "plus.circle")
            }
            .accessibilityIdentifier(AccessibilityID.Radio.addSource)
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Radio Sources")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(AccessibilityID.Radio.sourceList)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if feeds.count > 1 {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showingAddSource) {
            AddRSSFeedViewV2 {
                await audioPlayerViewModel.radioSourceConfigurationDidChange(
                    enabledSourceCount: RSSAudioService.shared.enabledFeedCount
                )
            }
        }
        .alert("Could Not Save Sources", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private func sourceRow(_ feed: RSSFeed) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                FeedDetailsContentViewV2(feed: feed)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(feed.displayName)
                        .lineLimit(1)
                    Text(feed.updateFrequencyEnum.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier(AccessibilityID.Radio.sourceDetail)

            if let failureMessage = audioPlayerViewModel.sourceFailures[feed.id] {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityElement()
                    .accessibilityLabel("\(feed.displayName) could not refresh: \(failureMessage)")
                    .accessibilityIdentifier(AccessibilityID.Radio.sourceFailure(feed.id))
            }

            Toggle("Enable \(feed.displayName)", isOn: Binding(
                get: { feed.isEnabled },
                set: { isEnabled in
                    feed.isEnabled = isEnabled
                    saveSources()
                }
            ))
            .labelsHidden()
            .accessibilityValue(feed.isEnabled ? "Enabled" : "Disabled")
        }
    }

    private func deleteSources(at offsets: IndexSet) {
        let deletedFeeds = offsets.compactMap { index in
            feeds.indices.contains(index) ? feeds[index] : nil
        }
        let deletedEnabledCount = deletedFeeds.lazy.filter(\.isEnabled).count
        let enabledSourceCount = max(0, feeds.lazy.filter(\.isEnabled).count - deletedEnabledCount)
        for feed in deletedFeeds {
            context.delete(feed)
        }
        saveSources(enabledSourceCount: enabledSourceCount)
    }

    private func moveSources(from offsets: IndexSet, to destination: Int) {
        var ordered = Array(feeds)
        ordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, feed) in ordered.enumerated() {
            feed.priority = Int16(index)
        }
        saveSources()
    }

    private func saveSources(enabledSourceCount: Int? = nil) {
        let reconciledEnabledCount = enabledSourceCount ?? feeds.lazy.filter {
            !$0.isDeleted && $0.isEnabled
        }.count
        do {
            try context.save()
            Task {
                await audioPlayerViewModel.radioSourceConfigurationDidChange(
                    enabledSourceCount: reconciledEnabledCount
                )
            }
        } catch {
            context.rollback()
            saveErrorMessage = error.localizedDescription
        }
    }
}
