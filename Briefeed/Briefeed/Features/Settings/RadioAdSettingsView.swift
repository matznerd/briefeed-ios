import Combine
import SwiftUI

@MainActor
struct RadioAdSettingsView: View {
    @ObservedObject var preferences: UserDefaultsManager
    private let coordinator: (any RadioTranscriptCoordinating)?
    private let radioCoordinator: RadioSessionCoordinator
    @State private var states: [RadioEpisodeKey: RadioAdPreparationState] = [:]
    @State private var entries: [RadioQueueEntry] = []

    init(preferences: UserDefaultsManager, services: RadioServiceContainer? = nil) {
        let services = services ?? .shared
        self.preferences = preferences
        coordinator = services.transcriptCoordinator
        radioCoordinator = services.coordinator
    }

    var body: some View {
        Form {
            Section {
                Toggle("Prepare Next Stories", isOn: $preferences.radioPrepareAdsAhead)
                    .disabled(coordinator?.isPreparationAvailable != true || !AppleRadioAdClassifier().isAvailable)
                    .accessibilityIdentifier(AccessibilityID.Settings.prepareAdsAhead)
                Toggle("Skip Ads Automatically", isOn: $preferences.radioSkipAds)
                    .disabled(!RadioAdSkipPolicy.isReleaseQualified)
                    .accessibilityIdentifier(AccessibilityID.Settings.skipAds)
                LabeledContent("Automatic Skipping", value: RadioAdSkipPolicy.isReleaseQualified ? "Available" : "Validation pending")
            }
            Section("On-Device Processing") {
                LabeledContent("Speech", value: coordinator?.isPreparationAvailable == true ? "Available" : "Unavailable")
                LabeledContent("Apple Language Model", value: AppleRadioAdClassifier().isAvailable ? "Available" : "Unavailable")
                LabeledContent("Hour-Long Estimate", value: hourEstimate)
                    .accessibilityHint("Based on successful processing measured on this device. Download time is additional.")
            }
            if !orderedStates.isEmpty {
                Section("Preparation Queue") {
                    ForEach(orderedStates, id: \.key) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(radioCoordinator.candidate(for: item.key)?.displayTitle() ?? "Story")
                                .lineLimit(2)
                            Text(status(item.value)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Ad Skip")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(coordinator?.adPreparationPublisher ?? Just([:]).eraseToAnyPublisher()) { states = $0 }
        .onReceive(radioCoordinator.entriesPublisher) { entries = $0 }
    }

    private var orderedStates: [(key: RadioEpisodeKey, value: RadioAdPreparationState)] {
        entries.compactMap { entry in states[entry.key].map { (entry.key, $0) } }
    }

    private var hourEstimate: String {
        let record = states.values.compactMap(\.record).max { $0.preparedAt < $1.preparedAt }
        guard let seconds = record?.timing.estimatedProcessingSeconds(for: 3600) else { return "Not measured yet" }
        let minutes = ceil(seconds / 60).formatted(.number.precision(.fractionLength(0)))
        return "About \(minutes) min"
    }

    private func status(_ state: RadioAdPreparationState) -> String {
        switch state {
        case .queued: "Preparing audio and transcript"
        case .analyzing(let completed, let total): "Analyzing \(completed) of \(total) windows"
        case .ready(let record):
            record.timing.failedWindows > 0
                ? "\(record.spans.count) candidates; \(record.timing.failedWindows) windows unavailable"
                : "\(record.spans.count) candidates ready for review"
        case .unavailable(let message): message
        case .deferred: "Waiting for Briefeed to be active"
        }
    }
}
