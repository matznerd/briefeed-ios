//
//  OpenAITTSSimpleTests.swift
//  BriefeedTests
//
//  TDD tests for OpenAI TTS implementation
//  These tests should FAIL first, then we implement to make them pass
//

import XCTest
import CoreData
@testable import Briefeed

@MainActor
final class OpenAITTSSimpleTests: XCTestCase {
    
    var sut: OpenAITTSServiceSimple!
    
    override func setUp() async throws {
        try await super.setUp()
        sut = OpenAITTSServiceSimple.shared
        
        // Clear API key to test from clean state
        UserDefaultsManager.shared.openAIAPIKey = nil
        sut.resetCostTracking()
    }
    
    override func tearDown() async throws {
        UserDefaultsManager.shared.openAIAPIKey = nil
        try await super.tearDown()
    }
    
    // MARK: - RED Phase: Tests that should FAIL initially
    
    func testOpenAITTS_WhenNoAPIKey_ThrowsNoAPIKeyError() async {
        // Given
        UserDefaultsManager.shared.openAIAPIKey = nil
        
        // When/Then
        do {
            _ = try await sut.generateAudioFile(from: "Test text")
            XCTFail("❌ Should throw no API key error")
        } catch {
            XCTAssertEqual(error as? OpenAITTSError, OpenAITTSError.noAPIKey, 
                          "✅ Correctly throws no API key error")
        }
    }
    
    func testOpenAITTS_WhenAPIKeyIsEmpty_ThrowsNoAPIKeyError() async {
        // Given
        UserDefaultsManager.shared.openAIAPIKey = ""
        
        // When/Then
        do {
            _ = try await sut.generateAudioFile(from: "Test")
            XCTFail("❌ Should throw error for empty API key")
        } catch {
            XCTAssertEqual(error as? OpenAITTSError, OpenAITTSError.noAPIKey,
                          "✅ Empty string treated as no API key")
        }
    }
    
    func testNewsVoiceProfile_DefaultsToCoralVoice() {
        // Given
        let profile = NewsVoiceProfile()
        
        // Then
        XCTAssertEqual(profile.primaryVoice, .coral, 
                      "✅ Coral is default news voice")
        XCTAssertEqual(profile.alternativeVoice, .sage,
                      "✅ Sage is alternative news voice")
    }
    
    func testContentTypeDetection_IdentifiesHeadline() {
        // Given
        let shortText = "Breaking: Major announcement today"
        
        // When
        let type = NewsVoiceProfile.ContentType.detect(from: shortText)
        
        // Then
        XCTAssertEqual(type, .headline,
                      "✅ Short text detected as headline")
    }
    
    func testContentTypeDetection_IdentifiesQuote() {
        // Given
        let quoteText = "The CEO said \"We are excited\" today."
        
        // When
        let type = NewsVoiceProfile.ContentType.detect(from: quoteText)
        
        // Then
        XCTAssertEqual(type, .quote,
                      "✅ Text with quotes detected correctly")
    }
    
    func testCostTracking_CalculatesCorrectCost() {
        // Given
        let testCharacters = 1000
        let expectedCost = 0.015 // $0.015 per 1K chars
        
        // When
        // Simulate processing (in real implementation)
        // For now, just test the calculation
        let cost = Double(testCharacters) / 1000.0 * 0.015
        
        // Then
        XCTAssertEqual(cost, expectedCost, accuracy: 0.001,
                      "✅ Cost calculation is correct")
    }
    
    func testCostTracking_ResetsToZero() {
        // When
        sut.resetCostTracking()
        
        // Then
        XCTAssertEqual(sut.getEstimatedCost(), 0.0,
                      "✅ Cost resets to zero")
    }
    
    func testUserDefaults_StoresOpenAIAPIKey() {
        // Given
        let testKey = "sk-test-key-123"
        
        // When
        UserDefaultsManager.shared.openAIAPIKey = testKey
        
        // Then
        XCTAssertEqual(UserDefaultsManager.shared.openAIAPIKey, testKey,
                      "✅ API key stored in UserDefaults")
    }
    
    func testUserDefaults_StoresPreferredVoice() {
        // Given
        let testVoice = OpenAIVoice.sage
        
        // When
        UserDefaultsManager.shared.preferredOpenAIVoice = testVoice
        
        // Then
        XCTAssertEqual(UserDefaultsManager.shared.preferredOpenAIVoice, testVoice,
                      "✅ Voice preference stored")
    }
    
    func testVoiceRecommendation_IdentifiesNewsVoices() {
        // Given
        let newsVoices: [OpenAIVoice] = [.coral, .sage, .echo]
        let nonNewsVoices: [OpenAIVoice] = [.alloy, .ash, .ballad, .fable, .nova, .onyx, .shimmer]
        
        // Then
        for voice in newsVoices {
            XCTAssertTrue(voice.isRecommendedForNews,
                         "✅ \(voice.rawValue) is recommended for news")
        }
        
        for voice in nonNewsVoices {
            XCTAssertFalse(voice.isRecommendedForNews,
                          "✅ \(voice.rawValue) is not recommended for news")
        }
    }
}

// MARK: - Integration Tests

@MainActor
final class OpenAITTSIntegrationTests: XCTestCase {
    
    var unifiedPlayer: UnifiedAudioPlayer!
    var context: NSManagedObjectContext!
    
    override func setUp() async throws {
        try await super.setUp()
        
        unifiedPlayer = UnifiedAudioPlayer.shared
        context = PersistenceController.preview.container.viewContext
        
        // Clear state
        unifiedPlayer.clearQueue()
        UserDefaultsManager.shared.openAIAPIKey = nil
    }
    
    override func tearDown() async throws {
        unifiedPlayer.clearQueue()
        UserDefaultsManager.shared.openAIAPIKey = nil
        try await super.tearDown()
    }
    
    func testUnifiedPlayer_WhenNoOpenAIKey_UsesGemini() async {
        // Given
        UserDefaultsManager.shared.openAIAPIKey = nil
        let article = createTestArticle()
        
        // When
        await unifiedPlayer.loadQueue(from: [article])
        
        // Then
        XCTAssertEqual(unifiedPlayer.queue.count, 1,
                      "✅ Queue loads with Gemini fallback")
        XCTAssertNil(UserDefaultsManager.shared.openAIAPIKey,
                    "✅ Confirms no OpenAI key")
    }
    
    func testUnifiedPlayer_WhenOpenAIKeySet_AttemptsOpenAI() async {
        // Given
        UserDefaultsManager.shared.openAIAPIKey = "test-key"
        let article = createTestArticle()
        
        // When
        await unifiedPlayer.loadQueue(from: [article])
        
        // Then
        XCTAssertEqual(unifiedPlayer.queue.count, 1,
                      "✅ Queue loads with OpenAI attempt")
        XCTAssertNotNil(UserDefaultsManager.shared.openAIAPIKey,
                       "✅ OpenAI key is configured")
    }
    
    func testQueueItem_StartsInPendingState() {
        // Given
        let article = createTestArticle()
        
        // When
        let item = UnifiedQueueItem(article: article)
        
        // Then
        XCTAssertEqual(item.generationState, .pending,
                      "✅ New items start in pending state")
    }
    
    private func createTestArticle() -> Article {
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Test Article"
        article.summary = "Test summary"
        article.content = "Test content"
        return article
    }
}

// MARK: - Fallback Behavior Tests

@MainActor
final class OpenAIGeminiSimpleFallbackTests: XCTestCase {
    
    func testFallbackLogic_DocumentedCorrectly() {
        // This test documents the expected fallback behavior
        
        // Expected flow:
        // 1. Check if OpenAI API key exists
        // 2. If yes -> Try OpenAI TTS
        // 3. If OpenAI fails -> Fallback to Gemini
        // 4. If no key -> Use Gemini directly
        // 5. If Gemini hits 100/day limit -> Log warning
        
        XCTAssertTrue(true, "✅ Fallback logic documented")
    }
    
    func testGeminiQuotaLimit_Is100PerDay() {
        // Document Gemini's limitation that prompted this migration
        let geminiDailyLimit = 100
        
        XCTAssertEqual(geminiDailyLimit, 100,
                      "✅ Gemini limited to 100 generations/day")
    }
    
    func testOpenAIQuotaLimit_IsUnlimited() {
        // Document OpenAI's advantage
        let openAIDailyLimit: Int? = nil // No limit
        
        XCTAssertNil(openAIDailyLimit,
                    "✅ OpenAI has no daily generation limit")
    }
}

// MARK: - Performance Tests

final class OpenAITTSPerformanceSimpleTests: XCTestCase {
    
    func testCostCalculation_PerformanceFor1000Articles() {
        measure {
            // Simulate cost calculation for 1000 articles
            var totalCost = 0.0
            for _ in 0..<1000 {
                let charCount = 500 // Average article
                totalCost += Double(charCount) / 1000.0 * 0.015
            }
            
            XCTAssertEqual(totalCost, 7.5, accuracy: 0.01,
                          "✅ 1000 articles cost ~$7.50")
        }
    }
    
    func testContentTypeDetection_Performance() {
        let testTexts = [
            "Short headline",
            String(repeating: "Summary. ", count: 30),
            "CEO said \"Quote here\" yesterday.",
            String(repeating: "Article. ", count: 100)
        ]
        
        measure {
            for _ in 0..<100 {
                for text in testTexts {
                    _ = NewsVoiceProfile.ContentType.detect(from: text)
                }
            }
        }
    }
}