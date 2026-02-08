//
//  FluidAudioTTSService.swift
//  Briefeed
//
//  On-device TTS using FluidAudio's Pocket TTS engine
//  Provides ~1-3s latency vs ~26s for cloud-based Gemini TTS
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
    case alba, azelma, cosette, javert
    var displayName: String { rawValue.capitalized }
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
    private var pocketTts: PocketTtsManager?
    private var initializationTask: Task<Void, Never>?
    #endif

    var isModelReady: Bool { modelState == .ready }

    private init() {
        checkExistingModels()
    }

    /// Check if models are already downloaded (called at app launch)
    func checkExistingModels() {
        if UserDefaultsManager.shared.fluidAudioModelsDownloaded {
            #if canImport(FluidAudioTTS)
            // Models were previously downloaded — re-initialize in background
            modelState = .compiling
            initializationTask = Task {
                do {
                    let manager = PocketTtsManager()
                    try await manager.initialize()
                    self.pocketTts = manager
                    self.modelState = .ready
                    print("[FluidAudioTTS] Re-initialized from previously downloaded models")
                } catch {
                    self.modelState = .failed(error.localizedDescription)
                    print("[FluidAudioTTS] Re-initialization failed: \(error)")
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

        print("[FluidAudioTTS] Awaiting model initialization (timeout: \(timeout)s)...")

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
            print("[FluidAudioTTS] Model ready after wait")
        } else {
            print("[FluidAudioTTS] Timeout waiting for model initialization")
        }
        return isModelReady
        #else
        return false
        #endif
    }

    /// Download models and initialize the TTS engine
    func downloadAndInitialize(voice: String = "alba") async throws {
        #if canImport(FluidAudioTTS)
        modelState = .downloading(progress: 0.0)

        do {
            let manager = PocketTtsManager()

            // Initialize downloads models from HuggingFace and compiles CoreML
            modelState = .downloading(progress: 0.5)
            try await manager.initialize()
            modelState = .compiling

            self.pocketTts = manager
            modelState = .ready
            UserDefaultsManager.shared.fluidAudioModelsDownloaded = true

            print("[FluidAudioTTS] Models downloaded and initialized successfully")
        } catch {
            let errorMsg = error.localizedDescription
            modelState = .failed(errorMsg)
            print("[FluidAudioTTS] Initialization failed: \(errorMsg)")
            throw FluidAudioError.initializationFailed(errorMsg)
        }
        #else
        throw FluidAudioError.fluidAudioNotAvailable
        #endif
    }

    /// Synthesize text to WAV audio data
    func synthesize(text: String, voice: String? = nil, temperature: Float = 0.5) async throws -> Data {
        #if canImport(FluidAudioTTS)
        guard let manager = pocketTts, isModelReady else {
            throw FluidAudioError.modelsNotDownloaded
        }

        do {
            let audioData = try await manager.synthesize(text: text, voice: voice, temperature: temperature)
            print("[FluidAudioTTS] Synthesized \(text.count) chars -> \(audioData.count) bytes WAV")
            return audioData
        } catch {
            throw FluidAudioError.synthesisFailed(error.localizedDescription)
        }
        #else
        throw FluidAudioError.fluidAudioNotAvailable
        #endif
    }

    /// Synthesize text and save to a file, returns the file URL
    func synthesizeToFile(text: String, voice: String? = nil) async throws -> URL {
        // Check cache first
        if let cachedURL = cacheManager.getCachedAudioURL(for: text, voice: voice ?? "pocket-tts") {
            print("[FluidAudioTTS] Cache hit for text")
            return cachedURL
        }

        let audioData = try await synthesize(text: text, voice: voice)

        // Save to cache
        let key = cacheManager.cacheKey(for: text, voice: voice ?? "pocket-tts")
        let fileURL = cacheManager.cacheDirectory
            .appendingPathComponent(key)
            .appendingPathExtension("wav")

        try audioData.write(to: fileURL)
        print("[FluidAudioTTS] Saved audio to: \(fileURL.lastPathComponent)")

        return fileURL
    }
}
