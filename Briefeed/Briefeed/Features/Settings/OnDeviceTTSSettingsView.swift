//
//  OnDeviceTTSSettingsView.swift
//  Briefeed
//
//  Settings for on-device TTS using FluidAudio Kokoro TTS
//

import SwiftUI
import AVFoundation

struct OnDeviceTTSSettingsView: View {
    @StateObject private var fluidAudioService = FluidAudioTTSService.shared
    @ObservedObject private var userDefaults = UserDefaultsManager.shared

    @State private var testText = "Breaking news today: Scientists have discovered a new species of deep-sea fish near the Mariana Trench. The creature, nicknamed the phantom anglerfish, was found at a depth of over 8,000 meters."
    @State private var testState: TestState = .idle
    @State private var testDuration: TimeInterval?
    @State private var audioPlayer: AVAudioPlayer?

    private enum TestState {
        case idle, synthesizing, playing, error(String)
    }

    var body: some View {
        Form {
            // MARK: - Model Status Section
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    modelStatusBadge
                }

                switch fluidAudioService.modelState {
                case .notDownloaded:
                    Button(action: {
                        Task {
                            try? await fluidAudioService.downloadAndInitialize(
                                voice: userDefaults.fluidAudioVoice
                            )
                        }
                    }) {
                        Label("Download Models", systemImage: "arrow.down.circle")
                    }
                    .accessibilityIdentifier(AccessibilityID.Settings.downloadOnDeviceModels)

                    Text("~601 MB download. Models run entirely on-device after download.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: progress) {
                            Text("Downloading models...")
                                .font(.caption)
                        }
                        Text("\(Int(progress * 100))% complete")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                case .compiling:
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Compiling models for your device...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                case .ready:
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Models ready — on-device TTS active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                case .failed(let message):
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Download failed")
                                .font(.subheadline)
                        }
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Retry Download") {
                            Task {
                                try? await fluidAudioService.downloadAndInitialize(
                                    voice: userDefaults.fluidAudioVoice
                                )
                            }
                        }
                        .font(.caption)
                    }
                }
            } header: {
                Label("Model Status", systemImage: "cpu")
            }

            // MARK: - Voice Settings Section (only if models ready)
            if fluidAudioService.isModelReady {
                Section {
                    Picker("Voice", selection: $userDefaults.fluidAudioVoice) {
                        Section("Female") {
                            ForEach(FluidAudioVoice.femaleVoices, id: \.self) { voice in
                                Text(voice.displayName).tag(voice.rawValue)
                            }
                        }
                        Section("Male") {
                            ForEach(FluidAudioVoice.maleVoices, id: \.self) { voice in
                                Text(voice.displayName).tag(voice.rawValue)
                            }
                        }
                    }

                    Toggle("Prefer On-Device TTS", isOn: $userDefaults.preferOnDeviceTTS)
                        .accessibilityIdentifier(AccessibilityID.Settings.preferOnDeviceTTS)
                } header: {
                    Label("Voice Settings", systemImage: "person.wave.2")
                } footer: {
                    Text("When enabled, on-device Kokoro TTS is used as the primary engine. Cloud TTS is used as fallback.")
                }
            }

            // MARK: - Test TTS Section (only if models ready)
            if fluidAudioService.isModelReady {
                Section {
                    TextEditor(text: $testText)
                        .frame(minHeight: 80)
                        .font(.subheadline)

                    Button(action: runTest) {
                        HStack {
                            switch testState {
                            case .idle:
                                Label("Play Test", systemImage: "play.circle")
                            case .synthesizing:
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Synthesizing...")
                            case .playing:
                                Label("Playing...", systemImage: "speaker.wave.2")
                            case .error:
                                Label("Retry", systemImage: "arrow.clockwise")
                            }

                            if let duration = testDuration {
                                Spacer()
                                Text(String(format: "%.1fs", duration))
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .disabled(testText.isEmpty || isBusy)

                    if case .error(let msg) = testState {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Slider(value: Binding(
                        get: { Double(userDefaults.fluidAudioVoiceSpeed) },
                        set: { userDefaults.fluidAudioVoiceSpeed = Float($0) }
                    ), in: 0.5...2.0, step: 0.1) {
                        Text("Voice Speed")
                    }
                    HStack {
                        Text("Voice Speed")
                        Spacer()
                        Text(String(format: "%.1fx", userDefaults.fluidAudioVoiceSpeed))
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                } header: {
                    Label("Test", systemImage: "waveform")
                } footer: {
                    Text("0.5x = slow, 1.0x = normal, 2.0x = fast.")
                }
            }

            // MARK: - Comparison Section
            Section {
                TTSComparisonRow(
                    label: "On-Device (Kokoro TTS)",
                    latency: "~2-5s",
                    cost: "Free",
                    network: "Offline",
                    highlight: true
                )
                TTSComparisonRow(
                    label: "OpenAI TTS",
                    latency: "~200ms",
                    cost: "$0.015/1K chars",
                    network: "Required"
                )
                TTSComparisonRow(
                    label: "Gemini TTS",
                    latency: "~26s",
                    cost: "Free (100/day)",
                    network: "Required"
                )
            } header: {
                Label("Provider Comparison", systemImage: "chart.bar")
            }
        }
        .navigationTitle("On-Device TTS")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isBusy: Bool {
        if case .synthesizing = testState { return true }
        if case .playing = testState { return true }
        return false
    }

    private func runTest() {
        testState = .synthesizing
        testDuration = nil
        audioPlayer?.stop()
        audioPlayer = nil

        Task {
            let start = CFAbsoluteTimeGetCurrent()
            do {
                let audioData = try await fluidAudioService.synthesize(
                    text: testText,
                    voice: userDefaults.fluidAudioVoice,
                    voiceSpeed: userDefaults.fluidAudioVoiceSpeed
                )
                testDuration = CFAbsoluteTimeGetCurrent() - start
                print("[TTS Test] Synthesized \(testText.count) chars in \(String(format: "%.2f", testDuration!))s -> \(audioData.count) bytes")

                let player = try AVAudioPlayer(data: audioData)
                self.audioPlayer = player
                testState = .playing
                player.play()

                // Reset to idle after playback finishes
                let duration = player.duration
                Task {
                    try? await Task.sleep(for: .seconds(duration + 0.5))
                    if case .playing = testState {
                        testState = .idle
                    }
                }
            } catch {
                testDuration = CFAbsoluteTimeGetCurrent() - start
                testState = .error(error.localizedDescription)
                print("[TTS Test] Failed: \(error)")
            }
        }
    }

    @ViewBuilder
    private var modelStatusBadge: some View {
        switch fluidAudioService.modelState {
        case .notDownloaded:
            Text("Not Downloaded")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2))
                .clipShape(Capsule())
        case .downloading:
            Text("Downloading")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())
        case .compiling:
            Text("Compiling")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2))
                .clipShape(Capsule())
        case .ready:
            Text("Ready")
                .font(.caption)
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .clipShape(Capsule())
        case .failed:
            Text("Failed")
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.2))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Comparison Row

private struct TTSComparisonRow: View {
    let label: String
    let latency: String
    let cost: String
    let network: String
    var highlight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .fontWeight(highlight ? .semibold : .regular)

            HStack(spacing: 16) {
                Label(latency, systemImage: "clock")
                Label(cost, systemImage: "dollarsign.circle")
                Label(network, systemImage: "wifi")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        OnDeviceTTSSettingsView()
    }
}
