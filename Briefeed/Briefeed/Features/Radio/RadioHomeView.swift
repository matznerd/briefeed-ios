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

struct RadioPlaylistItem: Identifiable, Equatable {
    var id: RadioEpisodeKey { candidate.key }
    let candidate: RadioEpisodeCandidate
    let entry: RadioQueueEntry?
    let isCurrent: Bool
    let status: RadioPlaylistStatus
}

enum RadioHomePresentation {
    static func playlistItems(
        candidates: [RadioEpisodeCandidate],
        entries: [RadioQueueEntry],
        currentKey: RadioEpisodeKey?
    ) -> [RadioPlaylistItem] {
        let candidatesByKey = Dictionary(uniqueKeysWithValues: candidates.map { ($0.key, $0) })
        let queuedItems = entries.compactMap { entry in
            candidatesByKey[entry.key].map {
                makePlaylistItem(candidate: $0, entry: entry, currentKey: currentKey)
            }
        }
        let queuedKeys = Set(queuedItems.map(\.candidate.key))
        let latestBySource = Dictionary(grouping: candidates, by: { $0.key.feedID })
            .values
            .compactMap { episodes in
                episodes.sorted {
                    if $0.publicationDate != $1.publicationDate {
                        return $0.publicationDate > $1.publicationDate
                    }
                    return $0.key.episodeID < $1.key.episodeID
                }.first
            }
            .sorted {
                if $0.sourcePriority != $1.sourcePriority {
                    return $0.sourcePriority < $1.sourcePriority
                }
                if $0.key.feedID != $1.key.feedID {
                    return $0.key.feedID < $1.key.feedID
                }
                if $0.publicationDate != $1.publicationDate {
                    return $0.publicationDate > $1.publicationDate
                }
                return $0.key.episodeID < $1.key.episodeID
            }

        let supplementalLatest: [RadioPlaylistItem] = latestBySource.compactMap { candidate in
            guard !queuedKeys.contains(candidate.key) else { return nil }
            return makePlaylistItem(candidate: candidate, entry: nil, currentKey: currentKey)
        }

        return queuedItems + supplementalLatest
    }

    private static func makePlaylistItem(
        candidate: RadioEpisodeCandidate,
        entry: RadioQueueEntry?,
        currentKey: RadioEpisodeKey?
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
        } else if entry != nil {
            status = .upNext
        } else {
            status = .latest
        }
        return RadioPlaylistItem(
            candidate: candidate,
            entry: entry,
            isCurrent: candidate.key == currentKey,
            status: status
        )
    }

    static func showsDegradedBanner(
        state: RadioSessionState,
        activeMode: ActivePlaybackMode,
        hasCurrentEpisode: Bool,
        sourceFailureCount: Int
    ) -> Bool {
        guard activeMode == .radio, hasCurrentEpisode, sourceFailureCount > 0 else { return false }
        switch state {
        case .readyPaused, .loading, .playing, .pausedByUser:
            return true
        case .idle, .restoring, .refreshing, .waitingForNetwork, .noSources, .exhausted, .failed:
            return false
        }
    }

    static func currentControlLabel(
        activeMode: ActivePlaybackMode,
        isPlaying: Bool
    ) -> String {
        activeMode == .radio && isPlaying ? "Pause Radio" : "Play Radio"
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
    @EnvironmentObject private var audioPlayerViewModel: AudioPlayerViewModelV2
    @State private var showingAddSource = false
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \RSSEpisode.pubDate, ascending: false)],
        predicate: NSPredicate(format: "feed.isEnabled == YES"),
        animation: .default
    ) private var enabledEpisodes: FetchedResults<RSSEpisode>

    var body: some View {
        NavigationStack {
            List {
                if showsDegradedBanner {
                    Section {
                        sourceFailureBanner
                    }
                    .listRowSeparator(.hidden)
                }

                if !playlistItems.isEmpty {
                    Section("Your radio brief") {
                        ForEach(playlistItems) { item in
                            playlistRow(item)
                        }
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
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if AppRuntime.radioFixtureScenario != nil {
                RadioFixtureDiagnosticsAccessibilityView()
            }
        }
        #endif
    }

    private var isRadioActivelyPlaying: Bool {
        audioPlayerViewModel.activeMode == .radio && audioPlayerViewModel.isPlaying
    }

    private var playlistItems: [RadioPlaylistItem] {
        RadioHomePresentation.playlistItems(
            candidates: enabledEpisodes.compactMap { RadioEpisodeCandidate(episode: $0) },
            entries: audioPlayerViewModel.radioEntries,
            currentKey: audioPlayerViewModel.currentRadioEpisode?.key
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

    private var showsDegradedBanner: Bool {
        RadioHomePresentation.showsDegradedBanner(
            state: audioPlayerViewModel.radioState,
            activeMode: audioPlayerViewModel.activeMode,
            hasCurrentEpisode: audioPlayerViewModel.currentRadioEpisode != nil,
            sourceFailureCount: audioPlayerViewModel.sourceFailures.count
        )
    }

    private func playlistRow(_ item: RadioPlaylistItem) -> some View {
        Button {
            Task { await audioPlayerViewModel.playRadioEpisode(item.candidate.key) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: playlistIcon(for: item))
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(playlistTint(for: item))
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.candidate.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .accessibilityIdentifier(AccessibilityID.Radio.episodeTitle(item.candidate.key))

                    HStack(spacing: 5) {
                        Text(item.candidate.sourceName)
                        Text("•")
                            .accessibilityHidden(true)
                        Text(item.candidate.publicationDate, style: .relative)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    Text(playlistStatusText(for: item))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(playlistTint(for: item))
                        .accessibilityIdentifier(AccessibilityID.Radio.episodeState(item.candidate.key))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if item.isCurrent {
                    Image(systemName: isRadioActivelyPlaying ? "waveform" : "pause.circle")
                        .foregroundStyle(Color.briefeedRed)
                        .accessibilityLabel(isRadioActivelyPlaying ? "Playing" : "Current episode")
                        .accessibilityIdentifier(AccessibilityID.Radio.currentTitle)
                } else if item.status != .listened && item.status != .latest {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.status == .listened || item.status == .failed || item.status == .latest)
        .accessibilityIdentifier(AccessibilityID.Radio.episode(item.candidate.key))
    }

    private func playlistIcon(for item: RadioPlaylistItem) -> String {
        switch item.status {
        case .listened: "checkmark.circle.fill"
        case .inProgress: "circle.lefthalf.filled"
        case .failed: "exclamationmark.circle.fill"
        case .upNext, .latest: item.isCurrent ? "dot.radiowaves.left.and.right" : "radio"
        }
    }

    private func playlistTint(for item: RadioPlaylistItem) -> Color {
        switch item.status {
        case .listened: .green
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
            "Not in current brief"
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

    private var sourceFailureBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Some sources could not refresh")
                    .font(.subheadline.weight(.semibold))
                Text("Radio will keep playing available episodes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityIdentifier(AccessibilityID.Radio.sourceFailures)
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
