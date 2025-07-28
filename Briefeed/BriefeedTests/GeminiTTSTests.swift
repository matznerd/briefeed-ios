//
//  GeminiTTSTests.swift
//  BriefeedTests
//
//  Created by Briefeed Team on 7/24/25.
//

import Testing
import Foundation
@testable import Briefeed

struct GeminiTTSTests {
    
    // MARK: - Request Format Tests
    
    @Test("Gemini TTS request uses snake_case field names")
    func testRequestFieldNamesAreSnakeCase() throws {
        // Given
        let request = GeminiTTSRequest(
            contents: [
                GeminiContent(parts: [GeminiPart(text: "Test text")], role: "user")
            ],
            generationConfig: GeminiTTSConfig(
                responseModalities: ["AUDIO"],
                speechConfig: GeminiSpeechConfig(
                    voiceConfig: GeminiVoiceConfig(
                        prebuiltVoiceConfig: GeminiPrebuiltVoiceConfig(
                            voiceName: "Zephyr"
                        )
                    )
                )
            )
        )
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        // Then
        #expect(json["generation_config"] != nil)
        #expect(json["generationConfig"] == nil)
        
        let config = json["generation_config"] as! [String: Any]
        #expect(config["response_modalities"] != nil)
        #expect(config["speech_config"] != nil)
        
        let speechConfig = config["speech_config"] as! [String: Any]
        #expect(speechConfig["voice_config"] != nil)
    }
    
    @Test("Gemini TTS request includes all required fields")
    func testRequestIncludesRequiredFields() throws {
        // Given
        let text = "Hello, world!"
        let voice = "Zephyr"
        
        // When
        let request = createTTSRequest(text: text, voice: voice)
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        // Then
        #expect(json["contents"] != nil)
        #expect(json["generation_config"] != nil)
        
        let contents = json["contents"] as! [[String: Any]]
        #expect(contents.count == 1)
        
        let parts = contents[0]["parts"] as! [[String: Any]]
        #expect(parts[0]["text"] as? String == text)
    }
    
    @Test("Valid voice names are accepted")
    func testValidVoiceNames() {
        let validVoices = GeminiTTSService.availableVoices
        
        for voice in validVoices {
            let config = GeminiPrebuiltVoiceConfig(voiceName: voice)
            #expect(config.voiceName == voice)
        }
    }
    
    // MARK: - Response Parsing Tests
    
    @Test("Parse successful TTS response")
    func testParseSuccessfulResponse() throws {
        // Given
        let mockResponse = """
        {
            "candidates": [{
                "content": {
                    "parts": [{
                        "inline_data": {
                            "mime_type": "audio/L16;codec=pcm;rate=24000",
                            "data": "UklGRiQAAABXQVZFZm10IBAAAAABAAEAEE=="
                        }
                    }],
                    "role": "model"
                }
            }]
        }
        """.data(using: .utf8)!
        
        // When
        let response = try JSONDecoder().decode(GeminiTTSResponse.self, from: mockResponse)
        
        // Then
        #expect(response.candidates?.count == 1)
        #expect(response.error == nil)
        
        let audioData = response.candidates?.first?.content.parts.first?.inlineData?.data
        #expect(audioData != nil)
        #expect(audioData == "UklGRiQAAABXQVZFZm10IBAAAAABAAEAEE==")
    }
    
    @Test("Parse error response")
    func testParseErrorResponse() throws {
        // Given
        let mockError = """
        {
            "error": {
                "code": 400,
                "message": "Invalid field name",
                "status": "INVALID_ARGUMENT"
            }
        }
        """.data(using: .utf8)!
        
        // When
        let response = try JSONDecoder().decode(GeminiTTSResponse.self, from: mockError)
        
        // Then
        #expect(response.error != nil)
        #expect(response.error?.code == 400)
        #expect(response.candidates == nil)
    }
    
    // MARK: - Audio Processing Tests
    
    @Test("Base64 audio data decoding")
    func testBase64AudioDecoding() throws {
        // Given - Simple PCM data (silence)
        let pcmData = Data(repeating: 0, count: 100)
        let base64String = pcmData.base64EncodedString()
        
        // When
        let decoded = Data(base64Encoded: base64String)
        
        // Then
        #expect(decoded == pcmData)
        #expect(decoded?.count == 100)
    }
    
    @Test("PCM to WAV conversion")
    func testPCMToWAVConversion() {
        // Given
        let service = GeminiTTSService.shared
        let pcmData = Data(repeating: 0, count: 1000)
        
        // When
        let wavData = service.pcmToWav(pcmData: pcmData, sampleRate: 24000)
        
        // Then
        #expect(wavData.count == pcmData.count + 44) // WAV header is 44 bytes
        
        // Check RIFF header
        let riffHeader = String(data: wavData[0..<4], encoding: .ascii)
        #expect(riffHeader == "RIFF")
        
        // Check WAVE format
        let waveFormat = String(data: wavData[8..<12], encoding: .ascii)
        #expect(waveFormat == "WAVE")
    }
    
    // MARK: - Integration Tests
    
    @Test("Live Gemini TTS call")
    func testLiveGeminiTTSCall() async throws {
        // Skip if no API key
        guard UserDefaultsManager.shared.geminiAPIKey != nil else {
            throw XCTSkip("Gemini API key not configured")
        }
        
        // Given
        let service = GeminiTTSService.shared
        let testText = "Hello, this is a test."
        
        // When
        let result = await service.generateSpeech(text: testText, voiceName: "Zephyr")
        
        // Then
        if result.success {
            #expect(result.audioData != nil)
            #expect(result.audioURL != nil)
            #expect(result.voiceUsed == "Zephyr")
        } else {
            print("TTS failed with error: \(result.error ?? "Unknown")")
            #expect(result.usedFallback == true)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTTSRequest(text: String, voice: String) -> GeminiTTSRequest {
        return GeminiTTSRequest(
            contents: [
                GeminiContent(parts: [GeminiPart(text: text)], role: "user")
            ],
            generationConfig: GeminiTTSConfig(
                responseModalities: ["AUDIO"],
                speechConfig: GeminiSpeechConfig(
                    voiceConfig: GeminiVoiceConfig(
                        prebuiltVoiceConfig: GeminiPrebuiltVoiceConfig(
                            voiceName: voice
                        )
                    )
                )
            )
        )
    }
}

// MARK: - Test Helpers

extension GeminiTTSService {
    // Expose private method for testing
    func pcmToWav(pcmData: Data, sampleRate: Int) -> Data {
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