//
//  TTSGeneratorService.swift
//  Briefeed
//
//  Main TTS orchestrator - coordinates Gemini API and AVSpeech fallback
//

import Foundation
import AVFoundation
import CoreData

/// Errors that can occur during TTS generation
enum TTSError: Error, Equatable {
    case emptyText
    case generationFailed
    case fileWriteFailed
    case noAPIKey
    case networkError(String)
    
    var localizedDescription: String {
        switch self {
        case .emptyText:
            return "Cannot generate speech from empty text"
        case .generationFailed:
            return "Failed to generate speech"
        case .fileWriteFailed:
            return "Failed to write audio file"
        case .noAPIKey:
            return "No API key configured"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

/// Main service for generating TTS audio files
final class TTSGeneratorService {
    
    // MARK: - Properties
    
    /// Shared instance
    static let shared = TTSGeneratorService()
    
    /// Cache manager
    private let cacheManager = AudioCacheManager.shared
    
    /// Gemini TTS service
    private let geminiService = GeminiTTSService.shared
    
    /// Concurrent queue for generation tasks
    private let generationQueue = DispatchQueue(label: "com.briefeed.tts.generation", attributes: .concurrent)
    
    /// Maximum concurrent generations
    private let maxConcurrentGenerations = 3
    
    /// Active generation tasks
    private var activeGenerations = Set<String>()
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // MARK: - Public Methods
    
    /// Generate audio file from text with caching
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: Optional voice preference (defaults to user setting)
    ///   - context: Core Data context for tracking (optional)
    ///   - article: Associated article for tracking (optional)
    /// - Returns: URL to the generated audio file
    func generateAudioFile(
        from text: String,
        voice: String? = nil,
        trackingIn context: NSManagedObjectContext? = nil,
        for article: Article? = nil
    ) async throws -> URL {
        
        // Validate input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TTSError.emptyText
        }
        
        // Check cache first
        let selectedVoice = voice ?? UserDefaultsManager.shared.selectedVoice
        if let cachedURL = cacheManager.getCachedAudioURL(for: text, voice: selectedVoice) {
            print("[TTSGenerator] Cache hit for text hash")
            return cachedURL
        }
        
        // Check if already generating
        let cacheKey = cacheManager.cacheKey(for: text, voice: selectedVoice)
        
        lock.lock()
        if activeGenerations.contains(cacheKey) {
            lock.unlock()
            // Wait for existing generation
            return try await waitForGeneration(key: cacheKey, text: text, voice: selectedVoice)
        }
        activeGenerations.insert(cacheKey)
        lock.unlock()
        
        defer {
            lock.lock()
            activeGenerations.remove(cacheKey)
            lock.unlock()
        }
        
        // Try Gemini TTS first
        do {
            let audioURL = try await generateWithGemini(text: text, voice: selectedVoice)
            
            // Track in Core Data if context provided
            if let context = context {
                await trackInCoreData(
                    audioURL: audioURL,
                    text: text,
                    voice: selectedVoice,
                    article: article,
                    context: context
                )
            }
            
            return audioURL
        } catch {
            print("[TTSGenerator] Gemini TTS failed: \(error), falling back to AVSpeech")
            
            // Fallback to AVSpeech
            let audioURL = try await generateWithAVSpeech(text: text)
            
            // Track fallback in Core Data
            if let context = context {
                await trackInCoreData(
                    audioURL: audioURL,
                    text: text,
                    voice: "AVSpeech",
                    article: article,
                    context: context
                )
            }
            
            return audioURL
        }
    }
    
    /// Pre-generate audio for queue items
    /// - Parameters:
    ///   - queue: Array of queue items (Articles or RSSEpisodes)
    ///   - currentIndex: Index of currently playing item
    ///   - context: Core Data context for tracking
    /// - Returns: URLs of pre-generated audio files
    func preGenerateForQueue(
        queue: [Any],
        currentIndex: Int,
        context: NSManagedObjectContext
    ) async throws -> [URL] {
        
        // Determine items to pre-generate (current + next 2)
        let indicesToGenerate = [
            currentIndex,
            currentIndex + 1,
            currentIndex + 2
        ].filter { $0 >= 0 && $0 < queue.count }
        
        // Generate concurrently with priority
        return await withTaskGroup(of: URL?.self) { group in
            for (offset, index) in indicesToGenerate.enumerated() {
                let priority = cacheManager.preGenerationPriority(for: offset)
                
                group.addTask(priority: priority) {
                    do {
                        let item = queue[index]
                        
                        if let article = item as? Article {
                            let text = self.formatArticleForTTS(article)
                            return try await self.generateAudioFile(
                                from: text,
                                trackingIn: context,
                                for: article
                            )
                        } else if let episode = item as? RSSEpisode {
                            // RSS episodes have their own audio URLs, no TTS needed
                            return URL(string: episode.audioUrl ?? "")
                        }
                        
                        return nil
                    } catch {
                        print("[TTSGenerator] Pre-generation failed for index \(index): \(error)")
                        return nil
                    }
                }
            }
            
            var results: [URL] = []
            for await url in group {
                if let url = url {
                    results.append(url)
                }
            }
            return results
        }
    }
    
    // MARK: - Private Methods
    
    /// Generate using Gemini TTS API
    private func generateWithGemini(text: String, voice: String) async throws -> URL {
        // Check API key
        guard UserDefaultsManager.shared.geminiAPIKey != nil else {
            throw TTSError.noAPIKey
        }
        
        // Call Gemini service
        let result = await geminiService.generateSpeech(
            text: text,
            voiceName: voice,
            useRandomVoice: false
        )
        
        if result.success {
            if let audioURL = result.audioURL {
                return audioURL
            } else if let audioData = result.audioData {
                // Save to cache
                return try cacheManager.saveAudioToCache(audioData, for: text, voice: voice)
            }
        }
        
        throw TTSError.generationFailed
    }
    
    /// Generate using AVSpeechSynthesizer as fallback
    private func generateWithAVSpeech(text: String) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    // Create synthesizer and delegate handler
                    let synthesizer = AVSpeechSynthesizer()
                    let utterance = AVSpeechUtterance(string: text)
                    
                    // Configure voice for best quality
                    if let voice = AVSpeechSynthesisVoice(language: "en-US") {
                        utterance.voice = voice
                    }
                    utterance.rate = 0.5 // Default rate
                    utterance.pitchMultiplier = 1.0
                    utterance.volume = 1.0
                    
                    // Create output file URL
                    let outputURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("caf")
                    
                    // Write to file using write method
                    var writeError: Error?
                    synthesizer.write(utterance) { buffer in
                        guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
                        
                        do {
                            // Create audio file for writing
                            let audioFile = try AVAudioFile(
                                forWriting: outputURL,
                                settings: pcmBuffer.format.settings,
                                commonFormat: .pcmFormatFloat32,
                                interleaved: false
                            )
                            
                            // Write buffer to file
                            try audioFile.write(from: pcmBuffer)
                        } catch {
                            writeError = error
                        }
                    }
                    
                    if let error = writeError {
                        throw error
                    }
                    
                    // Read the file data and save to cache
                    let audioData = try Data(contentsOf: outputURL)
                    let cachedURL = try self.cacheManager.saveAudioToCache(
                        audioData,
                        for: text,
                        voice: "AVSpeech"
                    )
                    
                    // Clean up temp file
                    try? FileManager.default.removeItem(at: outputURL)
                    
                    continuation.resume(returning: cachedURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Generate placeholder audio (temporary - replace with real AVSpeech recording)
    private func generatePlaceholderAudio(for text: String) throws -> Data {
        // This is a placeholder that generates silent audio
        // In production, you'd capture actual AVSpeech output
        
        let sampleRate = 44100.0
        let duration = Double(text.count) * 0.05 // Rough estimate
        let samples = Int(sampleRate * duration)
        
        var audioData = Data()
        
        // WAV header
        audioData.append("RIFF".data(using: .ascii)!)
        audioData.append(UInt32(36 + samples * 2).littleEndianData)
        audioData.append("WAVE".data(using: .ascii)!)
        audioData.append("fmt ".data(using: .ascii)!)
        audioData.append(UInt32(16).littleEndianData)
        audioData.append(UInt16(1).littleEndianData) // PCM
        audioData.append(UInt16(1).littleEndianData) // Mono
        audioData.append(UInt32(sampleRate).littleEndianData)
        audioData.append(UInt32(sampleRate * 2).littleEndianData) // Byte rate
        audioData.append(UInt16(2).littleEndianData) // Block align
        audioData.append(UInt16(16).littleEndianData) // Bits per sample
        audioData.append("data".data(using: .ascii)!)
        audioData.append(UInt32(samples * 2).littleEndianData)
        
        // Silent audio data
        for _ in 0..<samples {
            audioData.append(UInt16(0).littleEndianData)
        }
        
        return audioData
    }
    
    /// Wait for an existing generation to complete
    private func waitForGeneration(key: String, text: String, voice: String) async throws -> URL {
        // Poll for completion (max 30 seconds)
        let maxAttempts = 60
        
        for _ in 0..<maxAttempts {
            // Check if file now exists in cache
            if let cachedURL = cacheManager.getCachedAudioURL(for: text, voice: voice) {
                return cachedURL
            }
            
            // Check if still generating
            lock.lock()
            let stillGenerating = activeGenerations.contains(key)
            lock.unlock()
            
            if !stillGenerating {
                // Generation completed, check cache again
                if let cachedURL = cacheManager.getCachedAudioURL(for: text, voice: voice) {
                    return cachedURL
                }
                // Check one more time with a small delay (file system lag)
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                if let cachedURL = cacheManager.getCachedAudioURL(for: text, voice: voice) {
                    return cachedURL
                }
                // Generation failed
                throw TTSError.generationFailed
            }
            
            // Wait 500ms before next check
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        
        throw TTSError.generationFailed
    }
    
    /// Format article for TTS
    private func formatArticleForTTS(_ article: Article) -> String {
        var text = ""
        
        // Add title
        if let title = article.title {
            text += "\(title). "
        }
        
        // Prefer summary over content
        if let summary = article.summary, !summary.isEmpty {
            text += summary
        } else if let content = article.content {
            // Clean HTML from content
            let cleanContent = content.stripHTML
                .replacingOccurrences(of: "\n\n", with: ". ")
                .replacingOccurrences(of: "\n", with: " ")
            
            // Limit length for TTS
            if cleanContent.count > 5000 {
                text += String(cleanContent.prefix(5000)) + "... Content truncated."
            } else {
                text += cleanContent
            }
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Track audio generation in Core Data
    private func trackInCoreData(
        audioURL: URL,
        text: String,
        voice: String,
        article: Article?,
        context: NSManagedObjectContext
    ) async {
        await context.perform {
            // This will be implemented when CachedAudio entity is added
            print("[TTSGenerator] Would track in Core Data: \(audioURL.lastPathComponent)")
        }
    }
}

// MARK: - Testing Support

#if DEBUG
extension TTSGeneratorService {
    /// Reset for testing
    func resetForTesting() {
        lock.lock()
        activeGenerations.removeAll()
        lock.unlock()
    }
}
#endif