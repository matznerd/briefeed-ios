import Foundation
import SwiftUI

enum PlayerSeekAdjustment {
    case increment
    case decrement
}

enum PlayerSeekGeometry {
    static let hitLaneHeight: CGFloat = 44
    static let adjustmentStep: TimeInterval = 10

    static func clampedPosition(_ position: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard position.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(max(position, 0), duration)
    }

    static func progress(position: TimeInterval, duration: TimeInterval) -> CGFloat {
        guard duration.isFinite, duration > 0 else { return 0 }
        return CGFloat(clampedPosition(position, duration: duration) / duration)
    }

    static func position(atX xPosition: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard xPosition.isFinite, width.isFinite, width > 0, duration.isFinite, duration > 0 else { return 0 }
        let fraction = min(max(xPosition / width, 0), 1)
        return TimeInterval(fraction) * duration
    }

    static func adjustedPosition(
        from position: TimeInterval,
        direction: PlayerSeekAdjustment,
        duration: TimeInterval
    ) -> TimeInterval {
        let delta = direction == .increment ? adjustmentStep : -adjustmentStep
        return clampedPosition(position + delta, duration: duration)
    }
}

enum PlayerTransportControl: Equatable {
    case previous
    case backTen
    case playPause
    case forwardTen
    case next
}

enum PlayerPresentationPolicy {
    static let speedOptions = PlaybackSpeedPolicy.supported

    static func transportControls(for mode: ActivePlaybackMode) -> [PlayerTransportControl] {
        if mode == .radio {
            return [.backTen, .playPause, .forwardTen, .next]
        }
        return [.previous, .backTen, .playPause, .forwardTen, .next]
    }

    static func showsPrevious(for mode: ActivePlaybackMode) -> Bool {
        transportControls(for: mode).contains(.previous)
    }
}

enum PlayerSurfaceKind: Equatable {
    case playable
    case caughtUp
    case unavailable
}

enum PlayerPrimaryAction: Equatable {
    case playPause
    case refresh
}

struct PlayerSurfacePresentation: Equatable {
    let kind: PlayerSurfaceKind
    let mode: ActivePlaybackMode
    let title: String
    let source: String
    let position: TimeInterval
    let duration: TimeInterval
    let showsPrevious: Bool
    let showsSleep: Bool
    let showsQueue: Bool
    let allowsPlay: Bool
    let allowsSeek: Bool
    let allowsExpand: Bool
    let primaryAction: PlayerPrimaryAction
}

enum RadioSleepMenuOption: Equatable, Identifiable {
    case off
    case endOfEpisode
    case minutes(Int)
    case custom

    static let customBounds = 1...180
    static let defaultCustomMinutes = 20
    static let all: [Self] = [
        .off,
        .endOfEpisode,
        .minutes(10),
        .minutes(20),
        .minutes(30),
        .minutes(45),
        .minutes(60),
        .custom
    ]

    var id: String {
        switch self {
        case .off: "off"
        case .endOfEpisode: "endOfEpisode"
        case .minutes(let value): "minutes-\(value)"
        case .custom: "custom"
        }
    }

    var title: String {
        switch self {
        case .off: "Off"
        case .endOfEpisode: "End of Episode"
        case .minutes(let value): "\(value) min"
        case .custom: "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .off: "moon.zzz"
        case .endOfEpisode: "moon.stars"
        case .minutes: "timer"
        case .custom: "slider.horizontal.3"
        }
    }

    static func clampedCustomMinutes(_ minutes: Int) -> Int {
        min(max(minutes, customBounds.lowerBound), customBounds.upperBound)
    }

    func timer(now: Date, customMinutes: Int = defaultCustomMinutes) -> RadioSleepTimer {
        switch self {
        case .off:
            return .off
        case .endOfEpisode:
            return .endOfEpisode
        case .minutes(let minutes):
            return .deadline(now.addingTimeInterval(TimeInterval(minutes * 60)))
        case .custom:
            let minutes = Self.clampedCustomMinutes(customMinutes)
            return .deadline(now.addingTimeInterval(TimeInterval(minutes * 60)))
        }
    }
}

enum PlayerPresentationFormat {
    static func elapsed(_ seconds: TimeInterval) -> String {
        clock(finiteNonnegative(seconds))
    }

    static func remaining(position: TimeInterval, duration: TimeInterval) -> String {
        "-\(clock(max(0, finiteNonnegative(duration) - finiteNonnegative(position))))"
    }

    static func scrubberAccessibilityValue(position: TimeInterval, duration: TimeInterval) -> String {
        let position = finiteNonnegative(position)
        let duration = finiteNonnegative(duration)
        let elapsed = components(position)
        let remaining = components(max(0, duration - position))
        return "\(spoken(elapsed)) elapsed, \(spoken(remaining)) remaining"
    }

    static func speed(_ speed: Float) -> String {
        if speed.rounded() == speed {
            return "\(Int(speed))x"
        }
        return "\(speed.formatted(.number.precision(.fractionLength(1...2))))x"
    }

    static func sleepTimer(_ timer: RadioSleepTimer, now: Date) -> String {
        switch timer {
        case .off:
            return "Off"
        case .endOfEpisode:
            return "End of Episode"
        case .deadline(let deadline):
            let interval = deadline.timeIntervalSince(now)
            let minutes = interval.isFinite ? max(0, Int(ceil(interval / 60))) : 0
            return "\(minutes) min"
        }
    }

    static func compactSleepTimer(_ timer: RadioSleepTimer, now: Date) -> String {
        switch timer {
        case .endOfEpisode: "End"
        default: sleepTimer(timer, now: now)
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(finiteNonnegative(seconds).rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainder = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }

    private static func components(_ seconds: TimeInterval) -> (minutes: Int, seconds: Int) {
        let totalSeconds = Int(finiteNonnegative(seconds).rounded(.down))
        return (totalSeconds / 60, totalSeconds % 60)
    }

    private static func spoken(_ value: (minutes: Int, seconds: Int)) -> String {
        "\(value.minutes) \(value.minutes == 1 ? "minute" : "minutes"), \(value.seconds) \(value.seconds == 1 ? "second" : "seconds")"
    }

    private static func finiteNonnegative(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? max(0, value) : 0
    }
}

struct MiniAudioPlayerV4: View {
    @EnvironmentObject private var viewModel: AudioPlayerViewModelV2
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var showTranscript = false
    @State private var showExpandedPlayer = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.playerPresentation.kind == .caughtUp {
                caughtUpContent
            } else if viewModel.playerPresentation.kind == .unavailable {
                unavailableContent
            } else {
                playableContent
            }
        }
        .background(playerBackground)
        .overlay(playerBoundary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.MiniPlayer.container)
        .sheet(isPresented: $showTranscript) {
            TranscriptReaderView()
                .environmentObject(viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showExpandedPlayer) {
            ExpandedAudioPlayerV2()
                .environmentObject(viewModel)
        }
    }

    @ViewBuilder
    private var playableContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .trailing, spacing: 4) {
                metadata
                transportCluster
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
        } else {
            HStack(spacing: 8) {
                metadata
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(0)
                transportCluster
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
        }

        PlayerScrubber(
            position: viewModel.playerPresentation.position,
            duration: viewModel.playerPresentation.duration,
            identifier: AccessibilityID.MiniPlayer.scrubber,
            onSeek: viewModel.seek(to:)
        )
        .padding(.horizontal, 10)
    }

    private var caughtUpContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.briefeedRed)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.playerPresentation.title)
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier(AccessibilityID.MiniPlayer.title)
                Text(viewModel.playerPresentation.source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.MiniPlayer.source)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await viewModel.refreshRadio() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 74, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.briefeedRed)
            .accessibilityIdentifier(AccessibilityID.MiniPlayer.refresh)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var unavailableContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "radio")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.playerPresentation.title)
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier(AccessibilityID.MiniPlayer.title)
                Text(viewModel.playerPresentation.source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.MiniPlayer.source)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var metadata: some View {
        HStack(spacing: 8) {
            Button {
                showExpandedPlayer = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.briefeedRed.opacity(0.14))
                    if viewModel.isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: itemIcon)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.briefeedRed)
                    }
                }
                .frame(width: 36, height: 36)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open player")
            .accessibilityIdentifier(AccessibilityID.MiniPlayer.expand)

            VStack(alignment: .leading, spacing: 1) {
                Button {
                    if viewModel.currentItemType == .article {
                        showTranscript = true
                    } else {
                        showExpandedPlayer = true
                    }
                } label: {
                    Text(viewModel.playerPresentation.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.MiniPlayer.title)

                Text(metadataSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier(AccessibilityID.MiniPlayer.source)

                HStack(spacing: 2) {
                    PlayerSpeedMenu(viewModel: viewModel, compact: true)
                    if viewModel.playerPresentation.showsSleep {
                        RadioSleepMenu(viewModel: viewModel, compact: true)
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var transportCluster: some View {
        HStack(spacing: 2) {
            ForEach(Array(PlayerPresentationPolicy.transportControls(for: viewModel.playerPresentation.mode).enumerated()), id: \.offset) { _, control in
                transportButton(control)
            }
        }
    }

    @ViewBuilder
    private func transportButton(_ control: PlayerTransportControl) -> some View {
        switch control {
        case .previous:
            Button {
                Task { await viewModel.playPrevious() }
            } label: {
                Image(systemName: "backward.end.fill")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canPlayPrevious)
            .accessibilityLabel("Previous")
            .accessibilityIdentifier(AccessibilityID.MiniPlayer.previous)

        case .backTen:
            playerIconButton(
                systemName: "gobackward.10",
                label: "Back 10 seconds",
                identifier: AccessibilityID.MiniPlayer.rewind,
                action: viewModel.seekBackward
            )

        case .playPause:
            Button {
                viewModel.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.briefeedRed)
                        .frame(width: 44, height: 44)
                    if viewModel.isLoading || viewModel.isGenerating {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                    } else {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: viewModel.isPlaying ? 0 : 1)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.playerPresentation.allowsPlay)
            .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier(AccessibilityID.MiniPlayer.playPause)

        case .forwardTen:
            playerIconButton(
                systemName: "goforward.10",
                label: "Forward 10 seconds",
                identifier: AccessibilityID.MiniPlayer.forward,
                action: viewModel.seekForward
            )

        case .next:
            Button {
                Task { await viewModel.playNext() }
            } label: {
                Image(systemName: "forward.end.fill")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canPlayNext)
            .accessibilityLabel("Next")
            .accessibilityIdentifier(AccessibilityID.MiniPlayer.next)
        }
    }

    private func playerIconButton(
        systemName: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(.title3, design: .rounded, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var metadataSubtitle: String {
        if viewModel.isGenerating {
            return viewModel.generationPhase.shortMessage
        }
        return viewModel.playerPresentation.source
    }

    private var itemIcon: String {
        switch viewModel.currentItemType {
        case .article: "doc.text.fill"
        case .rssEpisode: "dot.radiowaves.left.and.right"
        case .none: "play.fill"
        }
    }

    private var playerBackground: some ShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            : AnyShapeStyle(.regularMaterial)
    }

    private var playerBoundary: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(
                Color.primary.opacity(colorSchemeContrast == .increased ? 0.4 : 0.12),
                lineWidth: colorSchemeContrast == .increased ? 1.5 : 0.5
            )
    }
}

struct PlayerScrubber: View {
    let position: TimeInterval
    let duration: TimeInterval
    let identifier: String
    let onSeek: (TimeInterval) -> Void

    @State private var draggedPosition: TimeInterval?

    private var displayedPosition: TimeInterval {
        draggedPosition ?? PlayerSeekGeometry.clampedPosition(position, duration: duration)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(PlayerPresentationFormat.elapsed(displayedPosition))
                .accessibilityHidden(true)

            GeometryReader { geometry in
                let progress = PlayerSeekGeometry.progress(position: displayedPosition, duration: duration)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.22))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color.briefeedRed)
                        .frame(width: max(0, geometry.size.width * progress), height: 3)
                    Circle()
                        .fill(Color.briefeedRed)
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, min(geometry.size.width - 10, geometry.size.width * progress - 5)))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            draggedPosition = PlayerSeekGeometry.position(
                                atX: value.location.x,
                                width: geometry.size.width,
                                duration: duration
                            )
                        }
                        .onEnded { value in
                            let finalPosition = PlayerSeekGeometry.position(
                                atX: value.location.x,
                                width: geometry.size.width,
                                duration: duration
                            )
                            draggedPosition = nil
                            onSeek(finalPosition)
                        }
                )
            }

            Text(PlayerPresentationFormat.remaining(position: displayedPosition, duration: duration))
                .accessibilityHidden(true)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(height: PlayerSeekGeometry.hitLaneHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(PlayerPresentationFormat.scrubberAccessibilityValue(position: displayedPosition, duration: duration))
        .accessibilityHint("Swipe up or down to move by 10 seconds")
        .accessibilityAdjustableAction { direction in
            let adjustment: PlayerSeekAdjustment = direction == .increment ? .increment : .decrement
            onSeek(PlayerSeekGeometry.adjustedPosition(from: displayedPosition, direction: adjustment, duration: duration))
        }
        .accessibilityIdentifier(identifier)
    }
}

struct PlayerSpeedMenu: View {
    @ObservedObject var viewModel: AudioPlayerViewModelV2
    var compact = false

    var body: some View {
        Menu {
            ForEach(PlayerPresentationPolicy.speedOptions, id: \.self) { speed in
                Button {
                    viewModel.setSpeed(speed)
                } label: {
                    if speed == viewModel.playbackSpeed {
                        Label(PlayerPresentationFormat.speed(speed), systemImage: "checkmark")
                    } else {
                        Text(PlayerPresentationFormat.speed(speed))
                    }
                }
            }
        } label: {
            Label(PlayerPresentationFormat.speed(viewModel.playbackSpeed), systemImage: "speedometer")
                .font(compact ? .caption2.weight(.semibold) : .subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Playback speed")
        .accessibilityValue(PlayerPresentationFormat.speed(viewModel.playbackSpeed))
        .accessibilityIdentifier(AccessibilityID.MiniPlayer.speed)
    }
}

struct RadioSleepMenu: View {
    @ObservedObject var viewModel: AudioPlayerViewModelV2
    var compact = false

    @State private var now = Date()
    @State private var customMinutes = RadioSleepMenuOption.defaultCustomMinutes
    @State private var showingCustomSheet = false

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Menu {
            ForEach(RadioSleepMenuOption.all) { option in
                Button {
                    select(option)
                } label: {
                    Label(option.title, systemImage: option.systemImage)
                }
            }
        } label: {
            Label(
                compact
                    ? PlayerPresentationFormat.compactSleepTimer(viewModel.sleepTimer, now: now)
                    : PlayerPresentationFormat.sleepTimer(viewModel.sleepTimer, now: now),
                systemImage: "moon.fill"
            )
            .font(compact ? .caption2.weight(.semibold) : .subheadline.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sleep timer")
        .accessibilityValue(PlayerPresentationFormat.sleepTimer(viewModel.sleepTimer, now: now))
        .accessibilityIdentifier(AccessibilityID.MiniPlayer.sleep)
        .onReceive(clock) { now = $0 }
        .sheet(isPresented: $showingCustomSheet) {
            CustomSleepTimerSheet(
                minutes: $customMinutes,
                onCancel: { showingCustomSheet = false },
                onSet: {
                    viewModel.setCustomSleepTimer(minutes: customMinutes)
                    showingCustomSheet = false
                }
            )
            .presentationDetents([.medium])
        }
    }

    private func select(_ option: RadioSleepMenuOption) {
        if option == .custom {
            customMinutes = RadioSleepMenuOption.defaultCustomMinutes
            showingCustomSheet = true
        } else {
            viewModel.setSleepTimer(option.timer(now: Date()))
        }
    }
}

private struct CustomSleepTimerSheet: View {
    @Binding var minutes: Int
    let onCancel: () -> Void
    let onSet: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $minutes, in: RadioSleepMenuOption.customBounds) {
                    Text("\(minutes) minutes")
                        .font(.body.monospacedDigit())
                }
                .accessibilityLabel("Sleep timer minutes")
                .accessibilityValue("\(minutes) minutes")
                .accessibilityIdentifier(AccessibilityID.SleepTimer.customMinutes)
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier(AccessibilityID.SleepTimer.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set", action: onSet)
                        .accessibilityIdentifier(AccessibilityID.SleepTimer.set)
                }
            }
        }
    }
}

#Preview {
    VStack {
        Spacer()
        MiniAudioPlayerV4()
            .environmentObject(AudioPlayerViewModelV2())
    }
}
