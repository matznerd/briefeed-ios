//
//  GeminiTTSService.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import Foundation
import AVFoundation

// MARK: - Gemini TTS Types
struct GeminiTTSRequest: Codable {
    let contents: [GeminiContent]
    let config: GeminiTTSConfig
}

struct GeminiTTSConfig: Codable {
    let responseModalities: [String]
    let speechConfig: GeminiSpeechConfig
}

struct GeminiSpeechConfig: Codable {
    let voiceConfig: GeminiVoiceConfig
}

struct GeminiVoiceConfig: Codable {
    let prebuiltVoiceConfig: GeminiPrebuiltVoiceConfig
}

struct GeminiPrebuiltVoiceConfig: Codable {
    let voiceName: String
}

struct GeminiTTSResponse: Codable {
    let candidates: [GeminiTTSCandidate]?
    let error: GeminiError?
}

struct GeminiTTSCandidate: Codable {
    let content: GeminiTTSContent
}

struct GeminiTTSContent: Codable {
    let parts: [GeminiTTSPart]
}

struct GeminiTTSPart: Codable {
    let inlineData: GeminiInlineData?
    let text: String?
}

struct GeminiInlineData: Codable {
    let mimeType: String
    let data: String // Base64 encoded audio data
}

// MARK: - TTS Result
struct TTSResult {
    let success: Bool
    let audioData: Data?
    let audioURL: URL?
    let error: String?
    let usedFallback: Bool
    let voiceUsed: String?
}

// MARK: - Gemini TTS Service
@MainActor
class GeminiTTSService: ObservableObject {
    // MARK: - Singleton
    static let shared = GeminiTTSService()
    
    // MARK: - Properties
    private let modelName = "models/gemini-2.5-flash-preview-tts"
    private let defaultVoice = "Autonoe"
    
    // Available Gemini voices
    static let availableVoices = [
        "Autonoe", "Zephyr", "Puck", "Charon", "Kore", "Fenrir",
        "Leda", "Orus", "Aoede", "Callirhoe", "Enceladus", "Iapetus",
        "Umbriel", "Algieba", "Despina", "Erinome", "Algenib", "Rasalgethi",
        "Laomedeia", "Achernar", "Alnilam", "Schedar", "Gacrux", "Pulcherrima",
        "Achird", "Zubenelgenubi", "Vindemiatrix", "Sadachbia", "Sadaltager", "Sulafar"
    ]
    
    // Cache for API key
    private var apiKey: String? {
        // Use the same API key as GeminiService
        return UserDefaultsManager.shared.geminiAPIKey
    }
    
    private var lastUsedVoiceIndex = 0
    
    // MARK: - Public Methods
    
    /// Generate speech from text using Gemini TTS
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voiceName: Optional voice name. If nil, will select a random voice
    ///   - useRandomVoice: If true, will use a different voice each time
    /// - Returns: TTSResult with audio data or error
    func generateSpeech(text: String, voiceName: String? = nil, useRandomVoice: Bool = true) async -> TTSResult {
        print("[GeminiTTS] Generating speech for text of length: \(text.count)")
        
        // Select voice
        let selectedVoice: String
        if let providedVoice = voiceName, Self.availableVoices.contains(providedVoice) {
            selectedVoice = providedVoice
        } else if useRandomVoice {
            // Select next voice in sequence for variety
            selectedVoice = selectNextVoice()
        } else {
            selectedVoice = UserDefaultsManager.shared.selectedVoice
        }
        
        print("[GeminiTTS] Using voice: \(selectedVoice)")
        
        // Try Gemini TTS first
        if let apiKey = apiKey {
            let geminiResult = await generateWithGemini(text: text, voiceName: selectedVoice, apiKey: apiKey)
            if geminiResult.success {
                return geminiResult
            }
            print("[GeminiTTS] Gemini TTS failed: \(geminiResult.error ?? "Unknown error")")
        } else {
            print("[GeminiTTS] No API key available")
        }
        
        // Fallback to device TTS
        print("[GeminiTTS] Falling back to device TTS")
        return await generateWithDeviceTTS(text: text)
    }
    
    /// Format story for speech
    func formatStoryForSpeech(_ article: Article) -> String {
        var speechText = ""
        
        // Title
        if let title = article.title {
            speechText += "\(title). "
        }
        
        // Summary takes precedence
        if let summary = article.summary, !summary.isEmpty {
            // Clean up the summary text
            let cleanSummary = summary
                .replacingOccurrences(of: "**", with: "") // Remove markdown bold
                .replacingOccurrences(of: "*", with: "") // Remove markdown italic
                .replacingOccurrences(of: "#", with: "") // Remove markdown headers
                .replacingOccurrences(of: "\n\n", with: ". ") // Replace double newlines
                .replacingOccurrences(of: "\n", with: " ") // Replace single newlines
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            speechText += cleanSummary
        } else if let content = article.content {
            // Fall back to content if no summary
            let cleanContent = content.stripHTML
                .replacingOccurrences(of: "\n\n", with: ". ")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Limit content length for TTS
            let maxLength = 5000
            if cleanContent.count > maxLength {
                let truncated = String(cleanContent.prefix(maxLength))
                speechText += truncated + "... Content truncated for speech."
            } else {
                speechText += cleanContent
            }
        }
        
        // Add source attribution
        if let author = article.author {
            speechText += " By \(author)."
        }
        
        if let subreddit = article.subreddit {
            speechText += " From r/\(subreddit)."
        }
        
        return speechText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Private Methods
    
    private func selectNextVoice() -> String {
        // Ensure index is valid
        if lastUsedVoiceIndex >= Self.availableVoices.count {
            lastUsedVoiceIndex = 0
        }
        
        // Use a sequential selection to ensure variety
        let voice = Self.availableVoices[lastUsedVoiceIndex]
        lastUsedVoiceIndex = (lastUsedVoiceIndex + 1) % Self.availableVoices.count
        return voice
    }
    
    private func generateWithGemini(text: String, voiceName: String, apiKey: String) async -> TTSResult {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/\(modelName):generateContent?key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            return TTSResult(success: false, audioData: nil, audioURL: nil, error: "Invalid URL", usedFallback: false, voiceUsed: nil)
        }
        
        // Create request body
        let request = GeminiTTSRequest(
            contents: [
                GeminiContent(parts: [GeminiPart(text: text)], role: "user")
            ],
            config: GeminiTTSConfig(
                responseModalities: ["AUDIO"],
                speechConfig: GeminiSpeechConfig(
                    voiceConfig: GeminiVoiceConfig(
                        prebuiltVoiceConfig: GeminiPrebuiltVoiceConfig(
                            voiceName: voiceName
                        )
                    )
                )
            )
        )
        
        do {
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONEncoder().encode(request)
            urlRequest.timeoutInterval = 60 // Longer timeout for audio generation
            
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return TTSResult(success: false, audioData: nil, audioURL: nil, error: "Invalid response", usedFallback: false, voiceUsed: nil)
            }
            
            if httpResponse.statusCode != 200 {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                return TTSResult(success: false, audioData: nil, audioURL: nil, error: "HTTP \(httpResponse.statusCode): \(errorMessage)", usedFallback: false, voiceUsed: nil)
            }
            
            let ttsResponse = try JSONDecoder().decode(GeminiTTSResponse.self, from: data)
            
            if let error = ttsResponse.error {
                return TTSResult(success: false, audioData: nil, audioURL: nil, error: error.message, usedFallback: false, voiceUsed: nil)
            }
            
            guard let audioData = ttsResponse.candidates?.first?.content.parts.first?.inlineData?.data else {
                return TTSResult(success: false, audioData: nil, audioURL: nil, error: "No audio data in response", usedFallback: false, voiceUsed: nil)
            }
            
            // Decode base64 audio data
            guard let decodedData = Data(base64Encoded: audioData) else {
                return TTSResult(success: false, audioData: nil, audioURL: nil, error: "Failed to decode audio data", usedFallback: false, voiceUsed: nil)
            }
            
            // Convert PCM to WAV
            let wavData = pcmToWav(pcmData: decodedData, sampleRate: 24000)
            
            // Save to temporary file
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
            try wavData.write(to: tempURL)
            
            return TTSResult(success: true, audioData: wavData, audioURL: tempURL, error: nil, usedFallback: false, voiceUsed: voiceName)
            
        } catch {
            return TTSResult(success: false, audioData: nil, audioURL: nil, error: error.localizedDescription, usedFallback: false, voiceUsed: nil)
        }
    }
    
    private func generateWithDeviceTTS(text: String) async -> TTSResult {
        return await withCheckedContinuation { continuation in
            // Use AVSpeechSynthesizer as fallback
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = UserDefaultsManager.shared.playbackSpeed
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            
            // For now, return a fallback result indicating device TTS should be used
            // In a real implementation, you might record the speech or use a different approach
            continuation.resume(returning: TTSResult(
                success: true,
                audioData: nil,
                audioURL: nil,
                error: nil,
                usedFallback: true,
                voiceUsed: "Device TTS"
            ))
        }
    }
    
    private func pcmToWav(pcmData: Data, sampleRate: Int) -> Data {
        var wavData = Data()
        
        // WAV header
        let headerSize = 44
        let dataSize = pcmData.count
        let fileSize = headerSize + dataSize - 8
        
        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(UInt32(fileSize).littleEndianData)
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt subchunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(UInt32(16).littleEndianData) // Subchunk size
        wavData.append(UInt16(1).littleEndianData) // Audio format (1 = PCM)
        wavData.append(UInt16(1).littleEndianData) // Number of channels (1 = mono)
        wavData.append(UInt32(sampleRate).littleEndianData) // Sample rate
        wavData.append(UInt32(sampleRate * 2).littleEndianData) // Byte rate
        wavData.append(UInt16(2).littleEndianData) // Block align
        wavData.append(UInt16(16).littleEndianData) // Bits per sample
        
        // data subchunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(UInt32(dataSize).littleEndianData)
        wavData.append(pcmData)
        
        return wavData
    }
}

// MARK: - Helper Extensions
extension UInt16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}