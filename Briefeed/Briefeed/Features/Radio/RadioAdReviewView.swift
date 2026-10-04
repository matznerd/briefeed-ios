import SwiftUI

struct RadioAdReviewView: View {
    @ObservedObject var player: AudioPlayerViewModelV2
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let record = player.currentRadioAdRecord {
                    Section {
                        LabeledContent("Playing Audio", value: player.radioAdPlaybackIsExact ? "Exact version verified" : "Version unverified")
                        if record.timing.failedWindows > 0 {
                            LabeledContent("Unavailable Windows", value: String(record.timing.failedWindows))
                        }
                        if player.radioAdUndoAvailable {
                            Button("Undo Skip", systemImage: "arrow.uturn.backward", action: player.undoRadioAdSkip)
                        }
                    }
                    Section("Candidates") {
                        ForEach(record.spans) { span in
                            NavigationLink {
                                RadioAdSpanReviewView(player: player, record: record, span: span)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(span.kind.title)
                                    Text("\(PlayerPresentationFormat.elapsed(span.startSeconds)) - \(PlayerPresentationFormat.elapsed(span.endSeconds))")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(span.categoryReviewed && span.boundariesReviewed ? "Reviewed" : "Review pending")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if record.spans.isEmpty { Text("No candidates detected").foregroundStyle(.secondary) }
                    }
                } else {
                    Text("Ad review unavailable").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ad Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .accessibilityIdentifier("radio.adReview")
    }
}

private struct RadioAdSpanReviewView: View {
    @ObservedObject var player: AudioPlayerViewModelV2
    private let spanID: UUID
    @State private var record: RadioAdRecord
    @State private var kind: RadioAdKind
    @State private var start: TimeInterval
    @State private var end: TimeInterval
    @State private var boundariesReviewed: Bool
    @State private var saving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(player: AudioPlayerViewModelV2, record: RadioAdRecord, span: RadioAdSpan) {
        self.player = player
        spanID = span.id
        _record = State(initialValue: record)
        _kind = State(initialValue: span.kind)
        _start = State(initialValue: span.startSeconds)
        _end = State(initialValue: span.endSeconds)
        _boundariesReviewed = State(initialValue: span.boundariesReviewed)
    }

    var body: some View {
        Form {
            Section("Classification") {
                Picker("Category", selection: $kind) {
                    ForEach(RadioAdKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section("Original Audio Time") {
                Stepper("Start: \(start.formatted(.number.precision(.fractionLength(2)))) s",
                        value: boundaryBinding($start), in: 0...record.audioDurationSeconds, step: 0.25)
                Stepper("End: \(end.formatted(.number.precision(.fractionLength(2)))) s",
                        value: boundaryBinding($end), in: 0...record.audioDurationSeconds, step: 0.25)
                Button("Listen Before Start", systemImage: "play") { player.listenToRadioAd(at: max(0, start - 3)) }
                    .disabled(!hasExactAudio)
                Button("Listen At End", systemImage: "play") { player.listenToRadioAd(at: max(0, end - 3)) }
                    .disabled(!hasExactAudio)
                Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause" : "play",
                       action: player.togglePlayPause)
                    .disabled(!hasExactAudio)
                Toggle("Boundaries Confirmed", isOn: $boundariesReviewed).disabled(!hasExactAudio || !validBounds)
            }
            Section {
                Button("Save Review", systemImage: "checkmark") {
                    saving = true
                    Task { @MainActor in
                        defer { saving = false }
                        do {
                            try await player.reviewRadioAd(record: record, spanID: spanID, kind: kind,
                                                           start: start, end: end, boundariesReviewed: boundariesReviewed)
                            dismiss()
                        } catch {
                            errorMessage = error as? RadioAdStore.StoreError == .staleRevision
                                ? "Review changed; reload required" : "Review could not be saved"
                        }
                    }
                }
                .disabled(saving || !validBounds || player.currentRadioAdRecord?.key != record.key)
                Button("Skip Reviewed Ad", systemImage: "forward.end") { player.skipReviewedRadioAd(spanID: spanID) }
                    .disabled(!canSkip)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                    Button("Reload", systemImage: "arrow.clockwise", action: reload)
                }
            }
        }
        .navigationTitle("Review Candidate")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hasExactAudio: Bool { player.radioAdPlaybackIsExact && player.currentRadioAdRecord?.key == record.key }
    private var validBounds: Bool { start.isFinite && end.isFinite && start >= 0 && start < end && end <= record.audioDurationSeconds }
    private var canSkip: Bool {
        guard hasExactAudio, boundariesReviewed, let current = player.currentRadioAdRecord,
              let saved = current.spans.first(where: { $0.id == spanID }),
              saved.startSeconds == start, saved.endSeconds == end, saved.kind == kind else { return false }
        return RadioAdSkipPolicy.manualTarget(record: current, spanID: spanID,
                                              playingFingerprint: current.key.assetFingerprint, isOwnedAudio: true) != nil
    }

    private func boundaryBinding(_ value: Binding<TimeInterval>) -> Binding<TimeInterval> {
        Binding(get: { value.wrappedValue }, set: {
            value.wrappedValue = $0
            boundariesReviewed = false
        })
    }

    private func reload() {
        guard let current = player.currentRadioAdRecord, current.key == record.key,
              let span = current.spans.first(where: { $0.id == spanID }) else { return }
        record = current
        kind = span.kind
        start = span.startSeconds
        end = span.endSeconds
        boundariesReviewed = span.boundariesReviewed
        errorMessage = nil
    }
}
