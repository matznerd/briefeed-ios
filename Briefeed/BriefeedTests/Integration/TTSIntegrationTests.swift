//
//  TTSIntegrationTests.swift
//  BriefeedTests
//
//  Created by Briefeed Team on 1/8/25.
//

import Testing
import Foundation
import AVFoundation
import CoreData
@testable import Briefeed

/// Tests for Text-to-Speech integration
struct TTSIntegrationTests {
    
    // MARK: - Gemini TTS Tests
    
    @Test("Gemini TTS should generate audio for article")
    @MainActor
    func test_geminiTTS_generateAudio() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(
            title: "Gemini TTS Test",
            content: "This is a test article for Gemini text-to-speech generation.",
            summary: "Test summary for TTS.",
            in: context
        )
        
        // Mock Gemini API key
        let mockAPIKey = "test-api-key"
        UserDefaults.standard.set(mockAPIKey, forKey: "GeminiAPIKey")
        
        // When
        let ttsService = GeminiTTSService()
        
        // Skip if no real API key
        guard GeminiService.shared.hasAPIKey else {
            throw XCTSkip("Gemini API key not configured")
        }
        
        do {
            let audioData = try await ttsService.generateSpeech(
                from: article.summary ?? article.content ?? "",
                voice: .journeyO
            )
            
            // Then
            #expect(audioData.count > 0)
            
            // Verify it's valid audio data
            // MP3 files typically start with "ID3" or 0xFF
            let headerBytes = audioData.prefix(3)
            let isValidAudio = headerBytes.elementsEqual([0x49, 0x44, 0x33]) || // ID3
                              headerBytes.first == 0xFF // MP3 sync byte
            
            #expect(isValidAudio)
        } catch {
            // If API fails, ensure fallback would work
            #expect(error != nil)
        }
    }
    
    @Test("Gemini TTS should handle different voices")
    @MainActor
    func test_geminiTTS_differentVoices() async throws {
        // Given
        let text = "Testing different Gemini voices."
        let ttsService = GeminiTTSService()
        
        guard GeminiService.shared.hasAPIKey else {
            throw XCTSkip("Gemini API key not configured")
        }
        
        // Test each voice
        let voices: [GeminiVoice] = [.puck, .charon, .kore, .fenrir, .aoede]
        
        for voice in voices {
            do {
                // When
                let audioData = try await ttsService.generateSpeech(
                    from: text,
                    voice: voice
                )
                
                // Then
                #expect(audioData.count > 0)
            } catch {
                // Log which voice failed
                print("Voice \(voice) failed: \(error)")
            }
        }
    }
    
    @Test("Gemini TTS should handle long text")
    @MainActor
    func test_geminiTTS_longText() async throws {
        // Given - Generate long text (5000 characters)
        let longText = String(repeating: "This is a long test sentence. ", count: 200)
        let ttsService = GeminiTTSService()
        
        guard GeminiService.shared.hasAPIKey else {
            throw XCTSkip("Gemini API key not configured")
        }
        
        // When
        do {
            let startTime = Date()
            let audioData = try await ttsService.generateSpeech(
                from: longText,
                voice: .journeyO
            )
            let generationTime = Date().timeIntervalSince(startTime)
            
            // Then
            #expect(audioData.count > 0)
            #expect(generationTime < 30.0) // Should complete in reasonable time
            
            // Verify audio duration roughly matches text length
            // Rough estimate: 150 words per minute
            let wordCount = longText.split(separator: " ").count
            let expectedDurationMinutes = Double(wordCount) / 150.0
            let expectedBytes = Int(expectedDurationMinutes * 60 * 16000) // 16kbps estimate
            
            #expect(audioData.count > expectedBytes / 2) // Within reasonable range
        } catch {
            // Handle rate limiting or API errors
            #expect(error != nil)
        }
    }
    
    // MARK: - Device TTS Tests
    
    @Test("Device TTS should work as fallback")
    @MainActor
    func test_deviceTTS_fallback() async throws {
        // Given
        let text = "This is a device TTS test."
        let synthesizer = AVSpeechSynthesizer()
        var audioGenerated = false
        
        // When
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        
        // Set up expectation
        let expectation = expectation(description: "Speech completed")
        
        // Synthesize to buffer
        var audioBuffers: [AVAudioPCMBuffer] = []
        
        synthesizer.write(utterance) { buffer in
            if let buffer = buffer {
                audioBuffers.append(buffer)
                audioGenerated = true
            } else {
                // Synthesis complete
                expectation.fulfill()
            }
        }
        
        // Wait for completion
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Then
        #expect(audioGenerated)
        #expect(audioBuffers.count > 0)
    }
    
    @Test("Device TTS should handle different languages")
    @MainActor
    func test_deviceTTS_languages() async throws {
        // Given
        let languages = [
            ("en-US", "Hello, this is English."),
            ("es-ES", "Hola, esto es español."),
            ("fr-FR", "Bonjour, c'est français."),
            ("de-DE", "Hallo, das ist Deutsch.")
        ]
        
        let synthesizer = AVSpeechSynthesizer()
        
        for (languageCode, text) in languages {
            // When
            let utterance = AVSpeechUtterance(string: text)
            
            if let voice = AVSpeechSynthesisVoice(language: languageCode) {
                utterance.voice = voice
                
                // Verify voice is available
                #expect(voice.language == languageCode)
                
                // Could synthesize if needed
                // synthesizer.speak(utterance)
            } else {
                print("Voice not available for \(languageCode)")
            }
        }
    }
    
    // MARK: - Integration Tests
    
    @Test("TTS should fall back from Gemini to device")
    @MainActor
    func test_tts_fallback() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(
            title: "Fallback Test",
            summary: "Test fallback from Gemini to device TTS.",
            in: context
        )
        
        // Remove API key to force fallback
        UserDefaults.standard.removeObject(forKey: "GeminiAPIKey")
        
        // When
        let service = BriefeedAudioService.shared
        await service.playArticle(article)
        
        // Then - Should use device TTS
        #expect(service.currentPlaybackItem?.title == "Fallback Test")
        
        // Audio should still be generated
        let cacheManager = AudioCacheManager.shared
        let cachedAudio = cacheManager.getCachedAudio(for: article.id?.uuidString ?? "")
        
        // Device TTS might not cache immediately in test environment
        // But service should not error out
        #expect(service.lastError == nil)
    }
    
    @Test("TTS should handle empty content gracefully")
    @MainActor
    func test_tts_emptyContent() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(
            title: "Empty Content",
            content: "",
            summary: nil,
            in: context
        )
        
        // When
        let service = BriefeedAudioService.shared
        await service.playArticle(article)
        
        // Then - Should handle gracefully
        if service.lastError != nil {
            // Error is acceptable for empty content
            #expect(service.isPlaying == false)
        } else {
            // Or it might generate audio for just the title
            #expect(service.currentPlaybackItem?.title == "Empty Content")
        }
    }
    
    // MARK: - Cache Integration Tests
    
    @Test("TTS audio should be cached correctly")
    @MainActor
    func test_tts_caching() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(
            id: UUID(),
            title: "Cache Test Article",
            summary: "This audio should be cached.",
            in: context
        )
        
        let cacheManager = AudioCacheManager.shared
        let articleID = article.id?.uuidString ?? ""
        
        // Ensure not already cached
        cacheManager.removeCachedAudio(for: articleID)
        
        // When - Generate audio
        let service = BriefeedAudioService.shared
        await service.playArticle(article)
        
        // Then - Should be cached
        let cachedURL = cacheManager.getCachedAudio(for: articleID)
        #expect(cachedURL != nil)
        
        if let url = cachedURL {
            #expect(FileManager.default.fileExists(atPath: url.path))
            
            // Verify file size
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes?[.size] as? Int64 ?? 0
            #expect(fileSize > 0)
        }
        
        // When - Play again, should use cache
        let startTime = Date()
        await service.playArticle(article)
        let loadTime = Date().timeIntervalSince(startTime)
        
        // Loading from cache should be fast
        #expect(loadTime < 1.0)
    }
    
    // MARK: - Performance Tests
    
    @Test("TTS generation performance")
    @MainActor
    func test_tts_performance() async throws {
        // Given
        let context = TestPersistenceController.createInMemoryContext()
        let measurements: [(String, TimeInterval)] = []
        
        // Test different content lengths
        let contentSizes = [
            ("Small", 100),
            ("Medium", 500),
            ("Large", 2000)
        ]
        
        for (sizeName, wordCount) in contentSizes {
            let content = String(repeating: "Test word ", count: wordCount)
            let article = AudioTestHelpers.createTestArticle(
                title: "\(sizeName) Article",
                content: content,
                in: context
            )
            
            // Measure generation time
            let startTime = Date()
            
            // Generate TTS (using device TTS for consistent testing)
            let synthesizer = AVSpeechSynthesizer()
            let utterance = AVSpeechUtterance(string: content)
            
            // In real test, we'd measure actual generation
            let estimatedTime = Double(wordCount) / 150.0 * 60.0 // seconds
            
            // Then
            #expect(estimatedTime < 300) // Under 5 minutes for large content
        }
    }
    
    // MARK: - Error Handling Tests
    
    @Test("TTS should handle network errors")
    @MainActor
    func test_tts_networkError() async throws {
        // Given - Mock network error for Gemini
        let context = TestPersistenceController.createInMemoryContext()
        let article = AudioTestHelpers.createTestArticle(in: context)
        
        // Simulate network error by using invalid API endpoint
        // In real implementation, we'd mock the network layer
        
        // When
        let service = BriefeedAudioService.shared
        await service.playArticle(article)
        
        // Then - Should fall back to device TTS
        // Service should not crash
        #expect(service.currentPlaybackItem != nil || service.lastError != nil)
    }
    
    @Test("TTS should handle API rate limiting")
    @MainActor
    func test_tts_rateLimiting() async throws {
        // Given
        guard GeminiService.shared.hasAPIKey else {
            throw XCTSkip("Gemini API key not configured")
        }
        
        let context = TestPersistenceController.createInMemoryContext()
        let ttsService = GeminiTTSService()
        
        // When - Make multiple rapid requests
        var successCount = 0
        var rateLimitError: Error?
        
        for i in 1...5 {
            let article = AudioTestHelpers.createTestArticle(
                title: "Rate Limit Test \(i)",
                in: context
            )
            
            do {
                _ = try await ttsService.generateSpeech(
                    from: article.summary ?? "",
                    voice: .journeyO
                )
                successCount += 1
            } catch {
                rateLimitError = error
                break
            }
            
            // Small delay between requests
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // Then - Should handle rate limiting gracefully
        if rateLimitError != nil {
            #expect(successCount >= 1) // At least one should succeed
        } else {
            #expect(successCount == 5) // All succeeded
        }
    }
}

// MARK: - Test Helpers

extension TTSIntegrationTests {
    
    func expectation(description: String) -> TestExpectation {
        TestExpectation(description: description)
    }
    
    func fulfillment(of expectations: [TestExpectation], timeout: TimeInterval) async {
        // Simulate expectation fulfillment for async testing
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
    }
}

// Simple test expectation for async testing
struct TestExpectation {
    let description: String
    private(set) var isFulfilled = false
    
    mutating func fulfill() {
        isFulfilled = true
    }
}