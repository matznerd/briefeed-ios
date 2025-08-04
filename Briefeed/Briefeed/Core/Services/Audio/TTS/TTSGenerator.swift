//
//  TTSGenerator.swift
//  Briefeed
//
//  Created by Briefeed Team on 1/8/25.
//

import Foundation
import AVFoundation

// MARK: - TTS Result
struct TTSGenerationResult {
    let audioURL: URL
    let duration: TimeInterval
    let voiceUsed: String?
    let generationMethod: GenerationMethod
    
    enum GenerationMethod {
        case gemini
        case device
        case cached
    }
}

// MARK: - TTS Generator
final class TTSGenerator: NSObject {
    static let shared = TTSGenerator()
    
    // Dependencies
    private let cacheManager = AudioCacheManager.shared
    private let geminiTTS = GeminiTTSService.shared
    
    // Device TTS
    private let synthesizer = AVSpeechSynthesizer()
    private var currentDeviceTTSCompletion: ((Result<URL, Error>) -> Void)?
    
    // Queue for sequential TTS generation
    private let generationQueue = DispatchQueue(label: "com.briefeed.tts.generation", attributes: .concurrent)
    private let generationSemaphore = DispatchSemaphore(value: 1) // Allow one generation at a time
    
    private override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    // MARK: - Public Methods
    
    /// Generate TTS audio for article content
    func generateAudio(for article: Article) async -> Result<TTSGenerationResult, Error> {
        // Create cache key
        let content = article.summary ?? article.content ?? ""
        let cacheKey = cacheManager.cacheKey(for: article.id ?? UUID(), content: content)
        
        // Check cache first
        if let cachedURL = cacheManager.getCachedAudioURL(for: cacheKey) {
            if let duration = getAudioDuration(url: cachedURL) {
                return .success(TTSGenerationResult(
                    audioURL: cachedURL,
                    duration: duration,
                    voiceUsed: nil,
                    generationMethod: .cached
                ))
            }
        }
        
        // Format text for speech
        let textToSpeak = formatStoryForSpeech(article)
        
        // Try Gemini TTS first
        let geminiResult = await generateWithGemini(text: textToSpeak)
        
        switch geminiResult {
        case .success(let tempURL):
            // Move to cache
            do {
                let cachedURL = try cacheManager.moveToCache(from: tempURL, key: cacheKey)
                let duration = getAudioDuration(url: cachedURL) ?? 0
                
                return .success(TTSGenerationResult(
                    audioURL: cachedURL,
                    duration: duration,
                    voiceUsed: "Gemini Voice",  // Voice tracking not available in current API
                    generationMethod: .gemini
                ))
            } catch {
                print("❌ Failed to cache Gemini audio: \(error)")
                return .failure(error)
            }
            
        case .failure(let error):
            print("⚠️ Gemini TTS failed, falling back to device TTS: \(error)")
            
            // Fall back to device TTS
            let deviceResult = await generateWithDevice(text: textToSpeak)
            
            switch deviceResult {
            case .success(let tempURL):
                // Move to cache
                do {
                    let cachedURL = try cacheManager.moveToCache(from: tempURL, key: cacheKey)
                    let duration = getAudioDuration(url: cachedURL) ?? 0
                    
                    return .success(TTSGenerationResult(
                        audioURL: cachedURL,
                        duration: duration,
                        voiceUsed: "Device",
                        generationMethod: .device
                    ))
                } catch {
                    print("❌ Failed to cache device audio: \(error)")
                    return .failure(error)
                }
                
            case .failure(let error):
                return .failure(error)
            }
        }
    }
    
    /// Pre-generate audio for upcoming items in queue
    func pregenerate(articles: [Article]) {
        generationQueue.async {
            for article in articles {
                // Check if already cached
                let content = article.summary ?? article.content ?? ""
                let cacheKey = self.cacheManager.cacheKey(for: article.id ?? UUID(), content: content)
                
                if self.cacheManager.getCachedAudioURL(for: cacheKey) == nil {
                    // Generate in background
                    Task {
                        let _ = await self.generateAudio(for: article)
                    }
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func generateWithGemini(text: String) async -> Result<URL, Error> {
        await withCheckedContinuation { continuation in
            generationQueue.async {
                self.generationSemaphore.wait()
                
                Task {
                    let result = await self.geminiTTS.generateSpeech(
                        text: text,
                        voiceName: nil,
                        useRandomVoice: true
                    )
                    
                    self.generationSemaphore.signal()
                    
                    if result.success, let audioURL = result.audioURL {
                        continuation.resume(returning: .success(audioURL))
                    } else {
                        let error = NSError(
                            domain: "TTSGenerator",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: result.error ?? "Unknown Gemini TTS error"]
                        )
                        continuation.resume(returning: .failure(error))
                    }
                }
            }
        }
    }
    
    private func generateWithDevice(text: String) async -> Result<URL, Error> {
        await withCheckedContinuation { continuation in
            generationQueue.async {
                self.generationSemaphore.wait()
                
                DispatchQueue.main.async {
                    // Create temp file URL
                    let tempURL = self.cacheManager.getTemporaryFileURL()
                    
                    // Configure audio session for recording
                    do {
                        let session = AVAudioSession.sharedInstance()
                        try session.setCategory(.playAndRecord, options: [.defaultToSpeaker])
                        try session.setActive(true)
                    } catch {
                        self.generationSemaphore.signal()
                        continuation.resume(returning: .failure(error))
                        return
                    }
                    
                    // Create utterance
                    let utterance = AVSpeechUtterance(string: text)
                    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                    utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                    
                    // Store completion handler
                    self.currentDeviceTTSCompletion = { result in
                        self.generationSemaphore.signal()
                        continuation.resume(returning: result)
                    }
                    
                    // Synthesize to file
                    self.synthesizer.write(utterance) { buffer in
                        self.writeBufferToFile(buffer: buffer, url: tempURL)
                    }
                }
            }
        }
    }
    
    private func writeBufferToFile(buffer: AVAudioBuffer, url: URL) {
        guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
        
        let audioFile: AVAudioFile
        do {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: pcmBuffer.format.sampleRate,
                AVNumberOfChannelsKey: pcmBuffer.format.channelCount
            ]
            
            audioFile = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            
            try audioFile.write(from: pcmBuffer)
        } catch {
            print("❌ Failed to write audio buffer to file: \(error)")
            currentDeviceTTSCompletion?(.failure(error))
            currentDeviceTTSCompletion = nil
        }
    }
    
    private func formatStoryForSpeech(_ article: Article) -> String {
        // Use the same formatting as GeminiTTSService
        var parts: [String] = []
        
        // Add title
        if let title = article.title {
            parts.append(title)
            parts.append("") // Add pause
        }
        
        // Add author/source
        if let author = article.author {
            parts.append("By \(author)")
            parts.append("") // Add pause
        } else if let feedTitle = article.feed?.name {
            parts.append("From \(feedTitle)")
            parts.append("") // Add pause
        }
        
        // Add main content
        if let summary = article.summary, !summary.isEmpty {
            parts.append(summary)
        } else if let content = article.content, !content.isEmpty {
            parts.append(content)
        } else {
            parts.append("No content available for this article.")
        }
        
        return parts.joined(separator: "\n\n")
    }
    
    private func getAudioDuration(url: URL) -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        
        if duration.isValid && !duration.isIndefinite {
            return CMTimeGetSeconds(duration)
        } else {
            // For local files, try to load duration synchronously
            do {
                let audioFile = try AVAudioFile(forReading: url)
                let frameCount = audioFile.length
                let sampleRate = audioFile.fileFormat.sampleRate
                return Double(frameCount) / sampleRate
            } catch {
                print("⚠️ Failed to get audio duration: \(error)")
                return nil
            }
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension TTSGenerator: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Successfully generated audio
        if let completion = currentDeviceTTSCompletion {
            let tempURL = cacheManager.getTemporaryFileURL()
            completion(.success(tempURL))
            currentDeviceTTSCompletion = nil
        }
        
        // Reset audio session
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Generation was cancelled
        if let completion = currentDeviceTTSCompletion {
            let error = NSError(
                domain: "TTSGenerator",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Device TTS was cancelled"]
            )
            completion(.failure(error))
            currentDeviceTTSCompletion = nil
        }
    }
}