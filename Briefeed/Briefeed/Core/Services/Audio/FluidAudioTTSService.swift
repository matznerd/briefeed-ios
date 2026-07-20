//
//  FluidAudioTTSService.swift
//  Briefeed
//
//  On-device TTS using FluidAudio's PocketTTS engine
//  PocketTTS runs locally through CoreML and can stream frames, while this
//  service keeps Briefeed's existing file-based playback contract.
//

import Foundation
import AVFoundation

#if canImport(FluidAudio)
import FluidAudio
#endif

// MARK: - Model State

enum FluidAudioModelState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case compiling
    case ready
    case failed(String)

    static func == (lhs: FluidAudioModelState, rhs: FluidAudioModelState) -> Bool {
        switch (lhs, rhs) {
        case (.notDownloaded, .notDownloaded), (.compiling, .compiling), (.ready, .ready):
            return true
        case (.downloading(let a), .downloading(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Voice Options

enum FluidAudioVoice: String, CaseIterable {
    // PocketTTS English shipped voices
    case alba, anna, azelma, bill_boerst, caro_davy
    case charles, cosette, eponine, eve, fantine
    case george, jane, javert, jean, marius
    case mary, michael, paul, peter_yearsley, stuart_bell
    case vera

    var displayName: String {
        rawValue
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    var genderLabel: String {
        switch self {
        case .alba, .anna, .azelma, .caro_davy, .cosette, .eponine,
             .eve, .fantine, .jane, .mary, .vera:
            return "Female"
        case .bill_boerst, .charles, .george, .javert, .jean, .marius,
             .michael, .paul, .peter_yearsley, .stuart_bell:
            return "Male"
        }
    }

    static var defaultVoice: FluidAudioVoice { .alba }
    static let femaleVoices = allCases.filter { $0.genderLabel == "Female" }
    static let maleVoices = allCases.filter { $0.genderLabel == "Male" }
}

// MARK: - Errors

enum FluidAudioError: LocalizedError {
    case modelsNotDownloaded
    case initializationFailed(String)
    case synthesisFailed(String)
    case fluidAudioNotAvailable

    var errorDescription: String? {
        switch self {
        case .modelsNotDownloaded:
            return "On-device TTS models not downloaded"
        case .initializationFailed(let msg):
            return "TTS initialization failed: \(msg)"
        case .synthesisFailed(let msg):
            return "TTS synthesis failed: \(msg)"
        case .fluidAudioNotAvailable:
            return "FluidAudio TTS not available on this device"
        }
    }
}

// MARK: - FluidAudio TTS Service

@MainActor
final class FluidAudioTTSService: ObservableObject {
    static let shared = FluidAudioTTSService()

    @Published private(set) var modelState: FluidAudioModelState = .notDownloaded
    private let cacheManager = AudioCacheManager.shared

    #if canImport(FluidAudio)
    private var pocketTts: PocketTtsManager?
    private var initializationTask: Task<Void, Never>?
    #endif

    var isModelReady: Bool { modelState == .ready }

    private init() {
        guard !AppRuntime.shouldSkipAutomaticStartupWork else { return }
        migrateFromLegacyTTSIfNeeded()
        checkExistingModels()
    }

    /// One-time migration: older builds used Kokoro voices/models.
    /// Reset model readiness so the next on-device run downloads PocketTTS.
    private func migrateFromLegacyTTSIfNeeded() {
        let migrationKey = "pocketTTSMigrationCompleteV1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        UserDefaultsManager.shared.fluidAudioModelsDownloaded = false
        if FluidAudioVoice(rawValue: UserDefaultsManager.shared.fluidAudioVoice) == nil {
            UserDefaultsManager.shared.fluidAudioVoice = FluidAudioVoice.defaultVoice.rawValue
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
        print("[PocketTTS] Migration: Reset model download state for PocketTTS")
    }

    /// Check if models are already downloaded (called at app launch)
    func checkExistingModels() {
        if UserDefaultsManager.shared.fluidAudioModelsDownloaded {
            #if canImport(FluidAudio)
            // Models were previously downloaded — re-initialize in background
            modelState = .compiling
            let voice = UserDefaultsManager.shared.fluidAudioVoice
            initializationTask = Task {
                do {
                    let manager = PocketTtsManager(
                        defaultVoice: Self.validatedVoice(voice),
                        language: .english,
                        precision: .int8
                    )
                    try await manager.initialize()
                    self.pocketTts = manager
                    self.modelState = .ready
                    print("[PocketTTS] Re-initialized from previously downloaded models (voice: \(voice))")
                } catch {
                    self.modelState = .failed("\(error)")
                    UserDefaultsManager.shared.fluidAudioModelsDownloaded = false
                    print("[PocketTTS] Re-initialization failed: \(error)")
                }
                self.initializationTask = nil
            }
            #else
            modelState = .notDownloaded
            #endif
        }
    }

    /// Wait for model initialization if currently compiling (with timeout).
    /// Returns true if model is ready, false otherwise.
    func awaitReadyIfCompiling(timeout: TimeInterval = 5.0) async -> Bool {
        guard modelState == .compiling else {
            return isModelReady
        }

        #if canImport(FluidAudio)
        guard let task = initializationTask else {
            return false
        }

        print("[PocketTTS] Awaiting model initialization (timeout: \(timeout)s)...")

        let ready = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await task.value
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        if ready {
            print("[PocketTTS] Model ready after wait")
        } else {
            print("[PocketTTS] Timeout waiting for model initialization")
        }
        return isModelReady
        #else
        return false
        #endif
    }

    /// Ensure PocketTTS is ready for a user-initiated Play Now flow.
    /// This may download/compile models on first use.
    func ensureReadyForPlayback(voice: String = FluidAudioVoice.defaultVoice.rawValue) async -> Bool {
        if isModelReady {
            return true
        }
        if modelState == .compiling {
            return await awaitReadyIfCompiling(timeout: 90)
        }

        do {
            try await downloadAndInitialize(voice: voice)
            return isModelReady
        } catch {
            print("[PocketTTS] Automatic initialization failed: \(error)")
            return false
        }
    }

    /// Download models and initialize the TTS engine
    func downloadAndInitialize(voice: String = FluidAudioVoice.defaultVoice.rawValue) async throws {
        #if canImport(FluidAudio)
        modelState = .downloading(progress: 0.1)

        do {
            let selectedVoice = Self.validatedVoice(voice)
            let manager = PocketTtsManager(
                defaultVoice: selectedVoice,
                language: .english,
                precision: .int8
            )

            // Initialize downloads models from HuggingFace and compiles CoreML
            print("[PocketTTS] Starting model download and initialization (voice: \(selectedVoice))...")
            modelState = .downloading(progress: 0.3)
            try await manager.initialize()
            modelState = .compiling
            print("[PocketTTS] Models downloaded, compiling CoreML...")

            self.pocketTts = manager
            modelState = .ready
            UserDefaultsManager.shared.fluidAudioModelsDownloaded = true
            UserDefaultsManager.shared.fluidAudioVoice = selectedVoice

            print("[PocketTTS] Models downloaded and initialized successfully")
        } catch {
            let errorMsg = "\(error)"
            modelState = .failed(errorMsg)
            UserDefaultsManager.shared.fluidAudioModelsDownloaded = false
            print("[PocketTTS] Initialization failed: \(errorMsg)")
            throw FluidAudioError.initializationFailed(errorMsg)
        }
        #else
        throw FluidAudioError.fluidAudioNotAvailable
        #endif
    }

    /// Synthesize text to WAV audio data
    func synthesize(text: String, voice: String? = nil, voiceSpeed: Float = 1.0) async throws -> Data {
        #if canImport(FluidAudio)
        guard let manager = pocketTts, isModelReady else {
            throw FluidAudioError.modelsNotDownloaded
        }

        do {
            let selectedVoice = Self.validatedVoice(voice)
            print("[PocketTTS] Starting synthesis: \(text.count) chars, voice=\(selectedVoice), playbackSpeed=\(voiceSpeed)")
            let audioData = try await manager.synthesize(text: text, voice: selectedVoice)
            guard audioData.count > 1_024 else {
                throw FluidAudioError.synthesisFailed("PocketTTS returned an empty audio buffer")
            }
            print("[PocketTTS] Synthesized \(text.count) chars -> \(audioData.count) bytes WAV")
            return audioData
        } catch {
            print("[PocketTTS] Synthesis failed: \(error)")
            throw FluidAudioError.synthesisFailed("\(error)")
        }
        #else
        throw FluidAudioError.fluidAudioNotAvailable
        #endif
    }

    /// Synthesize text and save to a file, returns the file URL
    func synthesizeToFile(text: String, voice: String? = nil, voiceSpeed: Float = 1.0) async throws -> URL {
        let cacheVoice = "pocket-\(Self.validatedVoice(voice))"

        // Check cache first
        if let cachedURL = cacheManager.getCachedAudioURL(for: text, voice: cacheVoice) {
            print("[PocketTTS] Cache hit for text")
            return cachedURL
        }

        let audioData = try await synthesize(text: text, voice: voice, voiceSpeed: voiceSpeed)

        // Save to cache
        let key = cacheManager.cacheKey(for: text, voice: cacheVoice)
        let fileURL = cacheManager.cacheDirectory
            .appendingPathComponent(key)
            .appendingPathExtension("wav")

        try audioData.write(to: fileURL)
        print("[PocketTTS] Saved audio to: \(fileURL.lastPathComponent)")

        return fileURL
    }

    private static func validatedVoice(_ voice: String?) -> String {
        guard let voice, FluidAudioVoice(rawValue: voice) != nil else {
            return FluidAudioVoice.defaultVoice.rawValue
        }
        return voice
    }
}
