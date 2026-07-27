import SwiftUI

enum RadioTranscriptPrepareAllAction: Equatable {
    case none
    case prepare
    case stop
}

struct RadioTranscriptCompactContent: Equatable {
    let title: String
    let detail: String?
    let progress: Double?
    let canRetry: Bool
    let fixedHeight: Double
    let transcript: TimedTranscript?
    let visibleLines: [TimedTranscriptLine]
    let activeLineID: Int?
    let activeUnitIndexes: Set<Int>

    var isReady: Bool { transcript != nil }
}

struct RadioTranscriptPrepareAllContent: Equatable {
    let title: String
    let detail: String
    let action: RadioTranscriptPrepareAllAction
    let progress: Double?
    let isEnabled: Bool
}

enum RadioTranscriptUIPresentation {
    static let compactHeight = 116.0
    static let compactAccessibilityHeight = 148.0
    static let readingLineMaximumCharacters = 38
    static let readingLineMaximumWords = 4

    static func compactContent(
        presentation: RadioTranscriptPresentation,
        mediaTime: TimeInterval,
        accessibilityTextSize: Bool,
        playbackSyncState: RadioTranscriptPlaybackSyncState = .synchronized,
        playbackRate: Double = 1,
        allowsPartialText: Bool = true
    ) -> RadioTranscriptCompactContent {
        guard let transcript = presentation.transcript else {
            return statusContent(
                state: presentation.state,
                accessibilityTextSize: accessibilityTextSize
            )
        }
        if !presentation.isComplete, !allowsPartialText {
            return statusContent(
                state: presentation.state,
                accessibilityTextSize: accessibilityTextSize
            )
        }
        guard playbackSyncState == .synchronized else {
            let status = playbackSyncStatus(playbackSyncState)
            return RadioTranscriptCompactContent(
                title: status.title,
                detail: status.detail,
                progress: nil,
                canRetry: false,
                fixedHeight:
                    height(accessibilityTextSize: accessibilityTextSize),
                transcript: nil,
                visibleLines: [],
                activeLineID: nil,
                activeUnitIndexes: []
            )
        }
        let projection = TimedTranscriptProjection(
            transcript: transcript,
            maxCharactersPerLine: 42,
            maxWordsPerLine: 4
        )
        return compactContent(
            transcript: transcript,
            projection: projection,
            mediaTime: mediaTime,
            accessibilityTextSize: accessibilityTextSize,
            playbackRate: playbackRate
        )
    }

    static func playbackSyncStatus(
        _ state: RadioTranscriptPlaybackSyncState
    ) -> (title: String, detail: String) {
        switch state {
        case .waiting:
            (
                "Syncing transcript",
                "Catching up to the current audio"
            )
        case .audioVersionMismatch:
            (
                "Transcript doesn't match this audio",
                "This stream included different audio, so text stays hidden."
            )
        case .synchronized:
            ("Live transcript", "")
        }
    }

    static func compactContent(
        transcript: TimedTranscript,
        projection: TimedTranscriptProjection,
        mediaTime: TimeInterval,
        accessibilityTextSize: Bool,
        playbackRate: Double = 1
    ) -> RadioTranscriptCompactContent {
        let boundedMediaTime = mediaTime.isFinite
            ? max(mediaTime, 0)
            : 0
        let activeLineIndex = projection.activeLineIndex(
            at: boundedMediaTime
        )
        let visibleLines = visibleLines(
            projection: projection,
            activeLineIndex: activeLineIndex,
            maximumCount: accessibilityTextSize ? 2 : 3
        )
        let activeUnitIndexes = highlightedUnitIndexes(
            projection: projection,
            mediaTime: boundedMediaTime,
            playbackRate: playbackRate
        )
        return RadioTranscriptCompactContent(
            title: "Live transcript",
            detail: nil,
            progress: nil,
            canRetry: false,
            fixedHeight: height(accessibilityTextSize: accessibilityTextSize),
            transcript: transcript,
            visibleLines: visibleLines,
            activeLineID: activeLineIndex.map { projection.lines[$0].id },
            activeUnitIndexes: activeUnitIndexes
        )
    }

    static func highlightedUnitIndexes(
        projection: TimedTranscriptProjection,
        mediaTime: TimeInterval,
        playbackRate: Double
    ) -> Set<Int> {
        let boundedMediaTime = mediaTime.isFinite
            ? max(mediaTime, 0)
            : 0
        guard TimedTranscriptSamplingPolicy.usesRangeHighlight(
            playbackRate: playbackRate
        ) else {
            return projection.activeUnitIndex(at: boundedMediaTime)
                .map { [$0] } ?? []
        }
        let sourceWindow =
            TimedTranscriptSamplingPolicy.highlightedSourceWindow(
                playbackRate: playbackRate
            )
        return Set(
            projection.unitIndexes(
                intersecting: max(
                    boundedMediaTime - sourceWindow,
                    0
                )...boundedMediaTime
            )
        )
    }

    static func prepareAll(
        batch: RadioTranscriptBatchPresentation,
        eligibleCount: Int,
        isAvailable: Bool
    ) -> RadioTranscriptPrepareAllContent {
        guard isAvailable else {
            return RadioTranscriptPrepareAllContent(
                title: "Prepare all unavailable",
                detail: "Requires iOS 26 and on-device speech",
                action: .none,
                progress: nil,
                isEnabled: false
            )
        }

        switch batch.state {
        case .idle:
            guard eligibleCount > 0 else {
                return RadioTranscriptPrepareAllContent(
                    title: "Nothing to prepare",
                    detail: "Your visible episodes are ready or listened",
                    action: .none,
                    progress: nil,
                    isEnabled: false
                )
            }
            return RadioTranscriptPrepareAllContent(
                title: "Prepare all",
                detail: episodeDetail(count: eligibleCount),
                action: .prepare,
                progress: nil,
                isEnabled: true
            )

        case .preparing:
            let total = max(batch.totalCount, 0)
            let completed = min(max(batch.completedCount, 0), total)
            let progress = total > 0 ? Double(completed) / Double(total) : nil
            return RadioTranscriptPrepareAllContent(
                title: "Preparing \(completed) of \(total)",
                detail: continuationDetail(batch.backgroundContinuation),
                action: .stop,
                progress: progress,
                isEnabled: true
            )

        case .completed:
            return RadioTranscriptPrepareAllContent(
                title: "All transcripts ready",
                detail: "Prepared on this iPhone",
                action: .none,
                progress: 1,
                isEnabled: false
            )

        case .stopped:
            let remaining = max(
                batch.totalCount - batch.completedCount,
                0
            )
            guard remaining > 0 else {
                return RadioTranscriptPrepareAllContent(
                    title: "All transcripts ready",
                    detail: "Prepared on this iPhone",
                    action: .none,
                    progress: 1,
                    isEnabled: false
                )
            }
            return RadioTranscriptPrepareAllContent(
                title: "Resume preparation",
                detail: "\(remaining) remaining · On-device",
                action: .prepare,
                progress: nil,
                isEnabled: true
            )
        }
    }

    static func eligibleCandidates(
        from rows: [RadioPlaylistItem],
        at now: Date = Date()
    ) -> [RadioEpisodeCandidate] {
        var seen = Set<RadioEpisodeKey>()
        return rows.compactMap { row in
            guard !row.candidate.isCompleted,
                  row.status != .listened,
                  RadioEpisodeFreshnessPolicy.isFresh(
                      row.candidate,
                      at: now
                  ),
                  seen.insert(row.candidate.key).inserted else {
                return nil
            }
            return row.candidate
        }
    }

    static func expandedProjection(
        transcript: TimedTranscript
    ) -> TimedTranscriptProjection {
        TimedTranscriptProjection(
            transcript: transcript,
            maxCharactersPerLine: readingLineMaximumCharacters,
            maxWordsPerLine: readingLineMaximumWords
        )
    }

    private static func statusContent(
        state: RadioTranscriptPreparationState,
        accessibilityTextSize: Bool
    ) -> RadioTranscriptCompactContent {
        let title: String
        let detail: String?
        let progress: Double?
        let canRetry: Bool

        switch state {
        case .unavailableOS:
            title = "Live transcript requires iOS 26"
            detail = nil
            progress = nil
            canRetry = false
        case .unsupportedDevice:
            title = "Live transcript is not available on this iPhone"
            detail = nil
            progress = nil
            canRetry = false
        case .unsupportedLocale(let identifier):
            let language = Locale.autoupdatingCurrent
                .localizedString(forIdentifier: identifier) ?? identifier
            title = "\(language) is not supported for this episode"
            detail = nil
            progress = nil
            canRetry = false
        case .assetRequired:
            title = "Preparing on-device speech model"
            detail = "Audio keeps playing"
            progress = nil
            canRetry = false
        case .queued:
            title = "Transcript queued"
            detail = "Audio starts while text is prepared"
            progress = nil
            canRetry = false
        case .downloading(let value):
            title = "Preparing transcript"
            detail = value.map {
                "\(Int((min(max($0, 0), 1) * 100).rounded()))%"
            }
            progress = value
            canRetry = false
        case .transcribing:
            title = "Transcribing on this iPhone"
            detail = "Audio keeps playing"
            progress = nil
            canRetry = false
        case .partial(let partial):
            title = "Catching up to the current audio"
            let elapsed = PlayerPresentationFormat.elapsed(
                partial.finalizedThroughSeconds
            )
            detail = "\(elapsed) transcribed"
            progress = partial.finalizedThroughSeconds /
                max(partial.transcript.audioDurationSeconds, 1)
            canRetry = false
        case .deferred:
            title = "Transcript will continue when Briefeed is active"
            detail = nil
            progress = nil
            canRetry = false
        case .failed(let message, let retry):
            title = message
            detail = retry ? "Retry without interrupting audio" : nil
            progress = nil
            canRetry = retry
        case .ready:
            preconditionFailure("Ready transcripts use text projection")
        }

        return RadioTranscriptCompactContent(
            title: title,
            detail: detail,
            progress: progress,
            canRetry: canRetry,
            fixedHeight: height(accessibilityTextSize: accessibilityTextSize),
            transcript: nil,
            visibleLines: [],
            activeLineID: nil,
            activeUnitIndexes: []
        )
    }

    private static func visibleLines(
        projection: TimedTranscriptProjection,
        activeLineIndex: Int?,
        maximumCount: Int
    ) -> [TimedTranscriptLine] {
        guard !projection.lines.isEmpty, maximumCount > 0 else { return [] }
        guard let activeLineIndex else {
            return Array(projection.lines.prefix(maximumCount))
        }

        let before = maximumCount == 3 ? 1 : 0
        var lower = max(activeLineIndex - before, 0)
        var upper = min(lower + maximumCount, projection.lines.count)
        lower = max(upper - maximumCount, 0)
        upper = min(lower + maximumCount, projection.lines.count)
        return Array(projection.lines[lower..<upper])
    }

    private static func height(accessibilityTextSize: Bool) -> Double {
        accessibilityTextSize
            ? compactAccessibilityHeight
            : compactHeight
    }

    private static func episodeDetail(count: Int) -> String {
        "\(count) \(count == 1 ? "episode" : "episodes") · On-device"
    }

    private static func continuationDetail(
        _ continuation: RadioTranscriptBackgroundContinuation
    ) -> String {
        switch continuation {
        case .accepted:
            "Can continue in background"
        case .none, .unavailableOS, .rejected:
            "Continues while Briefeed stays open"
        }
    }
}

struct RadioTranscriptViewer: View {
    let presentation: RadioTranscriptPresentation
    let currentTime: TimeInterval
    let playbackRate: Double
    let playbackSyncState: RadioTranscriptPlaybackSyncState
    let onOpen: () -> Void
    let onRetry: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var cachedProjection: CachedProjection?
    @State private var displaysPartialText = false
    @State private var displayedPartialEpisodeKey: RadioEpisodeKey?

    private struct CachedProjection {
        let identity: String
        let transcript: TimedTranscript
        let projection: TimedTranscriptProjection
    }

    private struct CoverageIdentity: Equatable {
        let episodeKey: RadioEpisodeKey?
        let finalizedThroughSeconds: TimeInterval?
        let mediaTime: TimeInterval
    }

    var body: some View {
        let content = compactContent
        Group {
            if content.isReady {
                Button(action: onOpen) {
                    transcriptContent(content)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open live transcript")
            } else {
                statusContent(content)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: content.fixedHeight,
            alignment: .leading
        )
        .padding(.horizontal, 16)
        .background(Color(uiColor: .secondarySystemBackground))
        .accessibilityIdentifier(AccessibilityID.Radio.transcriptBand)
        .task(id: projectionIdentity) {
            rebuildProjection()
        }
        .onChange(of: coverageIdentity, initial: true) {
            updatePartialVisibility()
        }
    }

    private var transcriptIdentity: String? {
        guard let transcript = presentation.transcript else { return nil }
        return [
            presentation.episodeKey?.feedID ?? "",
            presentation.episodeKey?.episodeID ?? "",
            transcript.assetFingerprint,
            transcript.engineIdentifier,
            transcript.engineVersion,
            transcript.localeIdentifier,
            String(transcript.units.count),
            String(transcript.units.last?.endSeconds ?? 0)
        ].joined(separator: "|")
    }

    private var projectionIdentity: String? {
        guard let transcriptIdentity else { return nil }
        return [
            transcriptIdentity,
            String(describing: dynamicTypeSize),
            horizontalSizeClass == .compact ? "compact" : "regular"
        ].joined(separator: "|")
    }

    private var compactContent: RadioTranscriptCompactContent {
        guard playbackSyncState == .synchronized,
              presentation.isComplete || allowsPartialText else {
            return RadioTranscriptUIPresentation.compactContent(
                presentation: presentation,
                mediaTime: currentTime,
                accessibilityTextSize:
                    dynamicTypeSize.isAccessibilitySize,
                playbackSyncState: playbackSyncState,
                playbackRate: playbackRate,
                allowsPartialText: allowsPartialText
            )
        }
        if let cachedProjection,
           cachedProjection.identity == projectionIdentity {
            return RadioTranscriptUIPresentation.compactContent(
                transcript: cachedProjection.transcript,
                projection: cachedProjection.projection,
                mediaTime: currentTime,
                accessibilityTextSize: dynamicTypeSize.isAccessibilitySize,
                playbackRate: playbackRate
            )
        }
        return RadioTranscriptUIPresentation.compactContent(
            presentation: presentation,
            mediaTime: currentTime,
            accessibilityTextSize: dynamicTypeSize.isAccessibilitySize,
            playbackSyncState: playbackSyncState,
            playbackRate: playbackRate,
            allowsPartialText: allowsPartialText
        )
    }

    private var allowsPartialText: Bool {
        if presentation.isComplete { return true }
        guard let coverage = presentation.finalizedThroughSeconds else {
            return false
        }
        return TimedTranscriptCoveragePolicy.shouldDisplay(
            finalizedThroughSeconds: coverage,
            mediaTime: currentTime,
            wasDisplaying:
                displaysPartialText &&
                displayedPartialEpisodeKey == presentation.episodeKey
        )
    }

    private var coverageIdentity: CoverageIdentity {
        CoverageIdentity(
            episodeKey: presentation.episodeKey,
            finalizedThroughSeconds:
                presentation.finalizedThroughSeconds,
            mediaTime: currentTime
        )
    }

    private func updatePartialVisibility() {
        guard !presentation.isComplete,
              let coverage = presentation.finalizedThroughSeconds else {
            displaysPartialText = false
            displayedPartialEpisodeKey = nil
            return
        }
        let sameEpisode =
            displayedPartialEpisodeKey == presentation.episodeKey
        let nextVisibility =
            TimedTranscriptCoveragePolicy.shouldDisplay(
                finalizedThroughSeconds: coverage,
                mediaTime: currentTime,
                wasDisplaying: displaysPartialText && sameEpisode
            )
        if displaysPartialText != nextVisibility {
            displaysPartialText = nextVisibility
        }
        if displayedPartialEpisodeKey != presentation.episodeKey {
            displayedPartialEpisodeKey = presentation.episodeKey
        }
    }

    private func rebuildProjection() {
        guard let transcript = presentation.transcript,
              let projectionIdentity else {
            cachedProjection = nil
            return
        }
        cachedProjection = CachedProjection(
            identity: projectionIdentity,
            transcript: transcript,
            projection: TimedTranscriptProjection(
                transcript: transcript,
                maxCharactersPerLine:
                    dynamicTypeSize.isAccessibilitySize
                        ? 28
                        : (horizontalSizeClass == .compact ? 38 : 48),
                maxWordsPerLine: 4
            )
        )
    }

    private func transcriptContent(
        _ content: RadioTranscriptCompactContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label("Live transcript", systemImage: "captions.bubble.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(content.visibleLines) { line in
                    transcriptLine(
                        line,
                        transcript: content.transcript,
                        activeLineID: content.activeLineID,
                        activeUnitIndexes: content.activeUnitIndexes
                    )
                    .font(
                        line.id == content.activeLineID
                            ? .body.weight(.medium)
                            : .subheadline
                    )
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .foregroundStyle(
                        line.id == content.activeLineID
                            ? .primary
                            : .secondary
                    )
                    .accessibilityHidden(true)
                    .accessibilityIdentifier(
                        line.id == content.activeLineID
                            ? AccessibilityID.Radio.transcriptActiveLine
                            : ""
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)

            #if DEBUG
            if !dynamicTypeSize.isAccessibilitySize,
               let wordsPerMinute = debugWordsPerMinute {
                HStack {
                    Spacer()
                    Text("~\(wordsPerMinute) WPM")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(height: 12)
            }
            #endif
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open live transcript")
        .accessibilityValue(
            content.visibleLines.first(where: {
                $0.id == content.activeLineID
            })?.text ?? ""
        )
    }

    #if DEBUG
    private var debugWordsPerMinute: Int? {
        guard playbackSyncState == .synchronized,
              let transcript = presentation.transcript else {
            return nil
        }
        return TimedTranscriptPace.estimatedEffectiveWordsPerMinute(
            transcript: transcript,
            mediaTime: currentTime,
            playbackRate: playbackRate
        )
    }
    #endif

    private func statusContent(
        _ content: RadioTranscriptCompactContent
    ) -> some View {
        HStack(spacing: 12) {
            if let progress = content.progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(.circular)
            } else {
                Image(systemName: statusSymbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(content.title)
                    .font(.headline)
                    .lineLimit(2)
                if let detail = content.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if content.canRetry {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry transcript")
                .accessibilityIdentifier(AccessibilityID.Radio.transcriptRetry)
            }
        }
        .accessibilityIdentifier(AccessibilityID.Radio.transcriptState)
        .accessibilityElement(children: .contain)
    }

    private var statusSymbol: String {
        if playbackSyncState == .audioVersionMismatch {
            return "exclamationmark.triangle"
        }
        return switch presentation.state {
        case .failed:
            "exclamationmark.triangle"
        case .unavailableOS, .unsupportedDevice, .unsupportedLocale:
            "captions.bubble"
        case .deferred:
            "pause.circle"
        case .assetRequired, .queued, .downloading, .transcribing, .partial,
             .ready:
            "waveform.badge.magnifyingglass"
        }
    }
}

struct RadioExpandedTranscriptView: View {
    let presentation: RadioTranscriptPresentation
    let currentTime: TimeInterval
    let playbackSyncState: RadioTranscriptPlaybackSyncState
    let playbackRate: Double
    let isPlaying: Bool
    let canPlayNext: Bool
    let onSeek: (TimeInterval) -> Void
    let onBackTen: () -> Void
    let onPlayPause: () -> Void
    let onForwardTen: () -> Void
    let onNext: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var followsPlayback = true
    @State private var projection: TimedTranscriptProjection?
    @State private var projectionIdentity: String?
    @State private var displaysPartialText = false
    @State private var displayedPartialEpisodeKey: RadioEpisodeKey?

    private struct CoverageIdentity: Equatable {
        let episodeKey: RadioEpisodeKey?
        let finalizedThroughSeconds: TimeInterval?
        let mediaTime: TimeInterval
    }

    var body: some View {
        NavigationStack {
            Group {
                if playbackSyncState == .synchronized,
                   let transcript = presentation.transcript,
                   let projection,
                   allowsPartialText {
                    transcriptScroll(
                        transcript: transcript,
                        projection: projection
                    )
                } else if presentation.transcript != nil {
                    let status = expandedStatus
                    ContentUnavailableView(
                        status.title,
                        systemImage: "captions.bubble",
                        description: Text(status.detail)
                    )
                } else {
                    ContentUnavailableView(
                        "Transcript is not ready",
                        systemImage: "captions.bubble",
                        description: Text(
                            "Audio can keep playing while text is prepared."
                        )
                    )
                }
            }
            .navigationTitle("Live Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                expandedTransport
            }
            .task(id: transcriptIdentity) {
                rebuildProjection()
            }
            .onChange(of: coverageIdentity, initial: true) {
                updatePartialVisibility()
            }
        }
        .accessibilityIdentifier(AccessibilityID.Radio.transcriptExpanded)
    }

    private var expandedStatus: (title: String, detail: String) {
        if playbackSyncState != .synchronized {
            return RadioTranscriptUIPresentation
                .playbackSyncStatus(playbackSyncState)
        }
        return (
            "Catching up to the current audio",
            "More finalized text will appear as it is prepared."
        )
    }

    private var allowsPartialText: Bool {
        if presentation.isComplete { return true }
        guard let coverage = presentation.finalizedThroughSeconds else {
            return false
        }
        return TimedTranscriptCoveragePolicy.shouldDisplay(
            finalizedThroughSeconds: coverage,
            mediaTime: currentTime,
            wasDisplaying:
                displaysPartialText &&
                displayedPartialEpisodeKey == presentation.episodeKey
        )
    }

    private var coverageIdentity: CoverageIdentity {
        CoverageIdentity(
            episodeKey: presentation.episodeKey,
            finalizedThroughSeconds:
                presentation.finalizedThroughSeconds,
            mediaTime: currentTime
        )
    }

    private func updatePartialVisibility() {
        guard !presentation.isComplete,
              let coverage = presentation.finalizedThroughSeconds else {
            displaysPartialText = false
            displayedPartialEpisodeKey = nil
            return
        }
        let sameEpisode =
            displayedPartialEpisodeKey == presentation.episodeKey
        let nextVisibility =
            TimedTranscriptCoveragePolicy.shouldDisplay(
                finalizedThroughSeconds: coverage,
                mediaTime: currentTime,
                wasDisplaying: displaysPartialText && sameEpisode
            )
        if displaysPartialText != nextVisibility {
            displaysPartialText = nextVisibility
        }
        if displayedPartialEpisodeKey != presentation.episodeKey {
            displayedPartialEpisodeKey = presentation.episodeKey
        }
    }

    private var transcriptIdentity: String? {
        guard let transcript = presentation.transcript else { return nil }
        return [
            presentation.episodeKey?.feedID ?? "",
            presentation.episodeKey?.episodeID ?? "",
            transcript.assetFingerprint,
            transcript.engineVersion,
            transcript.localeIdentifier,
            String(transcript.units.count),
            String(transcript.units.last?.endSeconds ?? 0)
        ].joined(separator: "|")
    }

    private var activeLineID: Int? {
        projection?.activeLine(at: currentTime)?.id
    }

    private func rebuildProjection() {
        guard let transcript = presentation.transcript,
              let transcriptIdentity else {
            projection = nil
            projectionIdentity = nil
            return
        }
        guard projectionIdentity != transcriptIdentity else { return }
        projection = RadioTranscriptUIPresentation.expandedProjection(
            transcript: transcript
        )
        projectionIdentity = transcriptIdentity
        followsPlayback = true
    }

    private func transcriptScroll(
        transcript: TimedTranscript,
        projection: TimedTranscriptProjection
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(projection.lines) { line in
                        Button {
                            onSeek(line.startSeconds)
                            followsPlayback = true
                        } label: {
                            transcriptLine(
                                line,
                                transcript: transcript,
                                activeLineID: activeLineID,
                                activeUnitIndexes:
                                    RadioTranscriptUIPresentation
                                    .highlightedUnitIndexes(
                                        projection: projection,
                                        mediaTime: currentTime,
                                        playbackRate: playbackRate
                                    )
                            )
                            .font(
                                line.id == activeLineID
                                    ? .body.weight(.medium)
                                    : .subheadline
                            )
                            .foregroundStyle(
                                line.id == activeLineID
                                    ? .primary
                                    : .secondary
                            )
                            .frame(
                                maxWidth: 300,
                                alignment: .leading
                            )
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 44,
                                alignment: .center
                            )
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(line.id)
                        .accessibilityLabel(line.text)
                        .accessibilityHint(
                            "Seek to \(PlayerPresentationFormat.elapsed(line.startSeconds))"
                        )
                    }
                }
                .padding(.vertical, 80)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { _ in followsPlayback = false }
            )
            .overlay(alignment: .bottomTrailing) {
                if !followsPlayback {
                    Button {
                        followsPlayback = true
                        scrollToActive(proxy: proxy)
                    } label: {
                        Label("Resume Live", systemImage: "location.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.briefeedRed)
                    .padding()
                    .accessibilityIdentifier(
                        AccessibilityID.Radio.transcriptResumeLive
                    )
                }
            }
            .onChange(of: activeLineID) {
                guard followsPlayback else { return }
                scrollToActive(proxy: proxy)
            }
            .onAppear {
                scrollToActive(proxy: proxy)
            }
        }
    }

    private func scrollToActive(proxy: ScrollViewProxy) {
        guard let activeLineID else { return }
        if reduceMotion {
            proxy.scrollTo(activeLineID, anchor: .center)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(activeLineID, anchor: .center)
            }
        }
    }

    private var expandedTransport: some View {
        HStack(spacing: 12) {
            transportButton(
                symbol: "gobackward.10",
                label: "Back 10 seconds",
                action: onBackTen
            )
            transportButton(
                symbol: isPlaying ? "pause.fill" : "play.fill",
                label: isPlaying ? "Pause" : "Play",
                prominent: true,
                action: onPlayPause
            )
            transportButton(
                symbol: "goforward.10",
                label: "Forward 10 seconds",
                action: onForwardTen
            )
            transportButton(
                symbol: "forward.end.fill",
                label: "Next",
                disabled: !canPlayNext,
                action: onNext
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private func transportButton(
        symbol: String,
        label: String,
        prominent: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .frame(width: 48, height: 48)
                .background {
                    if prominent {
                        Circle().fill(Color.briefeedRed)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

struct RadioTranscriptPlaylistHeader: View {
    let content: RadioTranscriptPrepareAllContent
    let onPrepare: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Your radio brief")
                .font(.headline)
                .foregroundStyle(.secondary)
                .textCase(nil)
                .accessibilityIdentifier(AccessibilityID.Radio.playlist)
            Spacer(minLength: 8)
            action
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var action: some View {
        switch content.action {
        case .prepare:
            Button(action: onPrepare) {
                Label(content.title, systemImage: "waveform.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.briefeedRed)
            .disabled(!content.isEnabled)
            .accessibilityHint(content.detail)
            .accessibilityIdentifier(
                AccessibilityID.Radio.transcriptPrepareAll
            )

        case .stop:
            Button(action: onStop) {
                HStack(spacing: 6) {
                    if let progress = content.progress {
                        ProgressView(value: min(max(progress, 0), 1))
                            .frame(width: 28)
                            .tint(.briefeedRed)
                            .accessibilityIdentifier(
                                AccessibilityID.Radio
                                    .transcriptPrepareProgress
                            )
                    }
                    Image(systemName: "stop.circle.fill")
                    Text(content.title)
                        .lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.briefeedRed)
            .accessibilityLabel("Stop transcript preparation")
            .accessibilityValue(content.detail)
            .accessibilityIdentifier(
                AccessibilityID.Radio.transcriptPrepareAll
            )

        case .none:
            Label(content.title, systemImage: "checkmark.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minHeight: 44)
                .accessibilityIdentifier(
                    AccessibilityID.Radio.transcriptPrepareAll
                )
        }
    }
}

private func transcriptLine(
    _ line: TimedTranscriptLine,
    transcript: TimedTranscript?,
    activeLineID: Int?,
    activeUnitIndexes: Set<Int>
) -> Text {
    guard let transcript else { return Text(line.text) }
    var result = Text("")
    for (offset, unitIndex) in line.unitIndexes.enumerated() {
        guard transcript.units.indices.contains(unitIndex) else { continue }
        let unit = transcript.units[unitIndex]
        let prefix = offset == 0 ? "" : " "
        var segment = Text(prefix + unit.text)
        if activeUnitIndexes.contains(unitIndex) {
            segment = segment
                .fontWeight(.semibold)
                .foregroundColor(Color(uiColor: .systemRed))
        } else if line.id == activeLineID {
            segment = segment.fontWeight(.medium)
        }
        result = result + segment
    }
    return result
}
