import CoreData
import SwiftUI

enum RadioHomePresentation {
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
}

struct RadioHomeView: View {
    @EnvironmentObject private var audioPlayerViewModel: AudioPlayerViewModelV2
    @State private var showingAddSource = false

    var body: some View {
        NavigationStack {
            List {
                if let episode = audioPlayerViewModel.currentRadioEpisode {
                    Section {
                        currentEpisodeView(episode)
                    }
                    .listRowSeparator(.hidden)
                }

                if showsDegradedBanner {
                    Section {
                        sourceFailureBanner
                    }
                    .listRowSeparator(.hidden)
                }

                Section {
                    radioStateView
                }
                .listRowSeparator(.hidden)

                Section("Sources") {
                    NavigationLink {
                        RadioSourceManagementView()
                    } label: {
                        Label("Feed Order and Enablement", systemImage: "list.number")
                    }
                    .accessibilityIdentifier(AccessibilityID.Radio.manageSources)

                    Button {
                        showingAddSource = true
                    } label: {
                        Label("Add Source", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier(AccessibilityID.Radio.addSource)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Radio")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await audioPlayerViewModel.refreshRadio()
            }
            .sheet(isPresented: $showingAddSource) {
                AddRSSFeedViewV2()
            }
        }
    }

    private var isRadioActivelyPlaying: Bool {
        audioPlayerViewModel.activeMode == .radio && audioPlayerViewModel.isPlaying
    }

    private var showsDegradedBanner: Bool {
        RadioHomePresentation.showsDegradedBanner(
            state: audioPlayerViewModel.radioState,
            activeMode: audioPlayerViewModel.activeMode,
            hasCurrentEpisode: audioPlayerViewModel.currentRadioEpisode != nil,
            sourceFailureCount: audioPlayerViewModel.sourceFailures.count
        )
    }

    private func currentEpisodeView(_ episode: RadioEpisodeCandidate) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityIdentifier(AccessibilityID.Radio.currentTitle)

                Text(episode.sourceName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(episode.publicationDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if isRadioActivelyPlaying {
                    audioPlayerViewModel.pause()
                } else {
                    Task { await audioPlayerViewModel.playRadio() }
                }
            } label: {
                Image(systemName: isRadioActivelyPlaying ? "pause.fill" : "play.fill")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.briefeedRed, in: Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(RadioHomePresentation.currentControlLabel(
                activeMode: audioPlayerViewModel.activeMode,
                isPlaying: audioPlayerViewModel.isPlaying
            ))
        }
        .padding(.vertical, 6)
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
            stateMessage(
                icon: "exclamationmark.triangle",
                title: "Radio needs attention",
                detail: failureMessage(failure),
                actionTitle: "Retry",
                actionID: AccessibilityID.Radio.retry
            ) {
                await audioPlayerViewModel.retryRadio()
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
        .accessibilityIdentifier(AccessibilityID.Radio.state)
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
            AddRSSFeedViewV2()
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
        Toggle(isOn: Binding(
            get: { feed.isEnabled },
            set: { isEnabled in
                feed.isEnabled = isEnabled
                saveSources()
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.displayName)
                    .lineLimit(1)
                Text(feed.updateFrequencyEnum.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(feed.displayName)
        .accessibilityValue(feed.isEnabled ? "Enabled" : "Disabled")
    }

    private func moveSources(from offsets: IndexSet, to destination: Int) {
        var ordered = Array(feeds)
        ordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, feed) in ordered.enumerated() {
            feed.priority = Int16(index)
        }
        saveSources()
    }

    private func saveSources() {
        do {
            try context.save()
            let enabledSourceCount = feeds.filter(\.isEnabled).count
            Task {
                await audioPlayerViewModel.radioSourceConfigurationDidChange(
                    enabledSourceCount: enabledSourceCount
                )
            }
        } catch {
            context.rollback()
            saveErrorMessage = error.localizedDescription
        }
    }
}
