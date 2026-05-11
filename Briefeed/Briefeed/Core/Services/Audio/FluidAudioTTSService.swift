//
//  FluidAudioTTSService.swift
//  Briefeed
//
//  On-device TTS using FluidAudio's Kokoro TTS engine
//  Non-autoregressive: generates all audio frames in a single CoreML prediction per chunk
//  Parallel chunk processing via TaskGroup for fast synthesis
//

import Foundation
import AVFoundation

#if canImport(FluidAudioTTS)
import FluidAudioTTS
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
    // American English Female
    case af_alloy, af_aoede, af_bella, af_heart, af_jessica
    case af_kore, af_nicole, af_nova, af_river, af_sarah, af_sky
    // American English Male
    case am_adam, am_echo, am_eric, am_fenrir, am_liam
    case am_michael, am_onyx, am_puck, am_santa

    var displayName: String {
        // "af_heart" -> "Heart", "am_adam" -> "Adam"
        let name = rawValue.dropFirst(3) // drop "af_" or "am_" prefix
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    var genderLabel: String {
        rawValue.hasPrefix("af_") ? "Female" : "Male"
    }

    static var defaultVoice: FluidAudioVoice { .af_heart }
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

    #if canImport(FluidAudioTTS)
    private var kokoroTts: KokoroTtsManager?
    private var initializationTask: Task<Void, Never>?
    #endif

    var isModelReady: Bool { modelState == .ready }

    private init() {
        migrateFromPocketTTSIfNeeded()
        checkExistingModels()
    }

    /// One-time migration: PocketTTS models ≠ Kokoro models.
    /// Reset the download flag so users see "Download Models" for Kokoro.
    private func migrateFromPocketTTSIfNeeded() {
        let migrationKey = "kokoroTTSMigrationComplete"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        UserDefaultsManager.shared.fluidAudioModelsDownloaded = false
        UserDefaults.standard.set(true, forKey: migrationKey)
        print("[KokoroTTS] Migration: Reset model download state (PocketTTS -> Kokoro)")
    }

    /// Check if models are already downloaded (called at app launch)
    func checkExistingModels() {
        if UserDefaultsManager.shared.fluidAudioModelsDownloaded {
            #if canImport(FluidAudioTTS)
            // Models were previously downloaded — re-initialize in background
            modelState = .compiling
            let voice = UserDefaultsManager.shared.fluidAudioVoice
            initializationTask = Task {
                do {
                    let manager = KokoroTtsManager(defaultVoice: voice)
                    try await manager.initialize(preloadVoices: [voice])
                    self.kokoroTts = manager
                    self.modelState = .ready
                    print("[KokoroTTS] Re-initialized from previously downloaded models (voice: \(voice))")
                } catch {
                    self.modelState = .failed("\(error)")
                    UserDefaultsManager.shared.fluidAudioModelsDownloaded = false
                    print("[KokoroTTS] Re-initialization failed: \(error)")
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

        #if canImport(FluidAudioTTS)
        guard let task = initializationTask else {
            return false
        }

        print("[KokoroTTS] Awaiting model initialization (timeout: \(timeout)s)...")

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
            print("[KokoroTTS] Model ready after wait")
        } else {
            print("[KokoroTTS] Timeout waiting for model initialization")
        }
        return isModelReady
        #else
        return false
        #endif
    }

    /// Download models and initialize the TTS engine
    func downloadAndInitialize(voice: String = FluidAudioVoice.defaultVoice.rawValue) async throws {
        #if canImport(FluidAudioTTS)
        modelState = .downloading(progress: 0.0)

        do {
            let manager = KokoroTtsManager(defaultVoice: voice)

            // Initialize downloads models from HuggingFace and compiles CoreML
            print("[KokoroTTS] Starting model download and initialization (voice: \(voice))...")
            modelState = .downloading(progress: 0.3)
            try await manager.initialize(preloadVoices: [voice])
            modelState = .compiling
            print("[KokoroTTS] Models downloaded, compiling CoreML...")

            self.kokoroTts = manager
            modelState = .ready
            UserDefaultsManager.shared.fluidAudioModelsDownloaded = true

            print("[KokoroTTS] Models downloaded and initialized successfully")
        } catch {
            let errorMsg = "\(error)"
            modelState = .failed(errorMsg)
            UserDefaultsManager.shared.fluidAudioModelsDownloaded = false
            print("[KokoroTTS] Initialization failed: \(errorMsg)")
            throw FluidAudioError.initializationFailed(errorMsg)
        }
        #else
        throw FluidAudioError.fluidAudioNotAvailable
        #endif
    }

    /// Synthesize text to WAV audio data
    func synthesize(text: String, voice: String? = nil, voiceSpeed: Float = 1.0) async throws -> Data {
        #if canImport(FluidAudioTTS)
        guard let manager = kokoroTts, isModelReady else {
            throw FluidAudioError.modelsNotDownloaded
        }

        do {
            print("[KokoroTTS] Starting synthesis: \(text.count) chars, voice=\(voice ?? "default"), speed=\(voiceSpeed)")
            let audioData = try await manager.synthesize(text: text, voice: voice, voiceSpeed: voiceSpeed)
            print("[KokoroTTS] Synthesized \(text.count) chars -> \(audioData.count) bytes WAV")
            return audioData
        } catch {
            print("[KokoroTTS] Synthesis failed: \(error)")
            throw FluidAudioError.synthesisFailed("\(error)")
        }
        #else
        throw FluidAudioError.fluidAudioNotAvailable
        #endif
    }

    /// Synthesize text and save to a file, returns the file URL
    func synthesizeToFile(text: String, voice: String? = nil, voiceSpeed: Float = 1.0) async throws -> URL {
        // Incorporate voice + speed into the cache key so different speeds aren't conflated
        let cacheVoice = "\(voice ?? FluidAudioVoice.defaultVoice.rawValue)-\(String(format: "%.1f", voiceSpeed))"

        // Check cache first
        if let cachedURL = cacheManager.getCachedAudioURL(for: text, voice: cacheVoice) {
            print("[KokoroTTS] Cache hit for text")
            return cachedURL
        }

        let audioData = try await synthesize(text: text, voice: voice, voiceSpeed: voiceSpeed)

        // Save to cache
        let key = cacheManager.cacheKey(for: text, voice: cacheVoice)
        let fileURL = cacheManager.cacheDirectory
            .appendingPathComponent(key)
            .appendingPathExtension("wav")

        try audioData.write(to: fileURL)
        print("[KokoroTTS] Saved audio to: \(fileURL.lastPathComponent)")

        return fileURL
    }
}
