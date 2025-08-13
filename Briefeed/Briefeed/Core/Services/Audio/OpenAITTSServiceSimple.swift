//
//  OpenAITTSServiceSimple.swift
//  Briefeed
//
//  Simplified OpenAI TTS implementation without external SDK dependency
//  Uses direct API calls for better control and testability
//

import Foundation
import AVFoundation
import Combine

// MARK: - OpenAI TTS Models & Voices

enum OpenAITTSModel: String {
    case gpt4oMiniTTS = "gpt-4o-mini-tts"  // Best for news narration
    case tts1 = "tts-1"                     // Lower latency
    case tts1HD = "tts-1-hd"                // Higher quality
}

enum OpenAIVoice: String, CaseIterable {
    case alloy = "alloy"
    case ash = "ash"
    case ballad = "ballad"
    case coral = "coral"       // Recommended for news
    case echo = "echo"
    case fable = "fable"
    case nova = "nova"
    case onyx = "onyx"
    case sage = "sage"         // Alternative for news
    case shimmer = "shimmer"
    
    var isRecommendedForNews: Bool {
        self == .coral || self == .sage || self == .echo
    }
}

enum OpenAIAudioFormat: String {
    case mp3 = "mp3"
    case opus = "opus"
    case aac = "aac"
    case flac = "flac"
    case wav = "wav"
    case pcm = "pcm"
}

// MARK: - Error Types

enum OpenAITTSError: LocalizedError, Equatable {
    case noAPIKey
    case invalidResponse
    case networkError(String)
    case rateLimited
    case audioProcessingFailed
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenAI API key not configured"
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .networkError(let message):
            return "Network error: \(message)"
        case .rateLimited:
            return "OpenAI API rate limit exceeded"
        case .audioProcessingFailed:
            return "Failed to process audio data"
        }
    }
}

// MARK: - News Voice Profile

struct NewsVoiceProfile {
    let model: OpenAITTSModel = .tts1  // Use standard model for now
    let primaryVoice: OpenAIVoice = .coral
    let alternativeVoice: OpenAIVoice = .sage
    
    func instructions(for contentType: ContentType) -> String {
        switch contentType {
        case .headline:
            return "Speak like a news anchor introducing a major story."
        case .summary:
            return "Professional news broadcaster tone with clear enunciation."
        case .quote:
            return "Slightly slower pace for quoted material."
        case .article:
            return "Clear, professional news narration."
        }
    }
    
    enum ContentType {
        case headline
        case summary
        case quote
        case article
        
        static func detect(from text: String) -> ContentType {
            // Check for quotes first, regardless of length
            if text.contains("\"") && text.contains("said") {
                return .quote
            } else if text.count < 100 {
                return .headline
            } else if text.count < 500 {
                return .summary
            } else {
                return .article
            }
        }
    }
}

// MARK: - OpenAI TTS Service

@MainActor
final class OpenAITTSServiceSimple: NSObject {
    
    // MARK: - Singleton
    
    static let shared = OpenAITTSServiceSimple()
    
    // MARK: - Properties
    
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/audio/speech"
    private let newsProfile = NewsVoiceProfile()
    
    // Cost tracking
    private var totalCharactersProcessed: Int = 0
    private let costPer1KChars: Double = 0.015
    
    // MARK: - Initialization
    
    private override init() {
        self.apiKey = UserDefaultsManager.shared.openAIAPIKey ?? ""
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Generate audio file from text
    func generateAudioFile(
        from text: String,
        voice: OpenAIVoice = .coral,
        model: OpenAITTSModel = .tts1
    ) async throws -> URL {
        guard !apiKey.isEmpty else {
            throw OpenAITTSError.noAPIKey
        }
        
        print("[OpenAITTS] Generating audio for \(text.count) characters")
        
        // Create request
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Note: gpt-4o-mini-tts with instructions is not yet available
        // Use standard models for now
        let body: [String: Any] = [
            "model": model.rawValue,
            "input": text,
            "voice": voice.rawValue,
            "response_format": "mp3"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITTSError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw OpenAITTSError.rateLimited
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAITTSError.networkError(errorMessage)
        }
        
        // Save to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mp3")
        
        try data.write(to: tempURL)
        
        // Track usage
        totalCharactersProcessed += text.count
        
        return tempURL
    }
    
    /// Generate news-optimized audio
    func generateNewsAudio(
        _ text: String,
        useAlternativeVoice: Bool = false
    ) async throws -> URL {
        let voice = useAlternativeVoice ? newsProfile.alternativeVoice : newsProfile.primaryVoice
        return try await generateAudioFile(
            from: text,
            voice: voice,
            model: newsProfile.model
        )
    }
    
    /// Generate audio for article with streaming support (simplified)
    func generateAudioForArticle(
        title: String?,
        content: String,
        useStreaming: Bool = false
    ) async throws -> URL {
        var fullText = ""
        
        if let title = title {
            fullText += "\(title). "
        }
        
        fullText += content
        
        // For now, just use regular generation
        // Streaming would require URLSession delegate implementation
        return try await generateNewsAudio(fullText)
    }
    
    // MARK: - Cost Tracking
    
    func getEstimatedCost() -> Double {
        Double(totalCharactersProcessed) / 1000 * costPer1KChars
    }
    
    func resetCostTracking() {
        totalCharactersProcessed = 0
    }
}

// MARK: - UserDefaults Extension

extension UserDefaultsManager {
    private static let openAIAPIKeyKey = "openAIAPIKey"
    private static let preferredOpenAIVoiceKey = "preferredOpenAIVoice"
    private static let useOpenAIStreamingKey = "useOpenAIStreaming"
    
    var openAIAPIKey: String? {
        get { UserDefaults.standard.string(forKey: Self.openAIAPIKeyKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.openAIAPIKeyKey) }
    }
    
    var preferredOpenAIVoice: OpenAIVoice {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: Self.preferredOpenAIVoiceKey),
               let voice = OpenAIVoice(rawValue: rawValue) {
                return voice
            }
            return .coral
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.preferredOpenAIVoiceKey)
        }
    }
    
    var useOpenAIStreaming: Bool {
        get { UserDefaults.standard.bool(forKey: Self.useOpenAIStreamingKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.useOpenAIStreamingKey) }
    }
}