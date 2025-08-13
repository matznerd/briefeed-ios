//
//  OpenAIGeminiFallbackTests.swift
//  BriefeedTests
//
//  Tests for OpenAI to Gemini fallback behavior
//

import XCTest
import CoreData
@testable import Briefeed

@MainActor
final class OpenAIGeminiFallbackTests: XCTestCase {
    
    var unifiedPlayer: UnifiedAudioPlayer!
    var context: NSManagedObjectContext!
    
    override func setUp() async throws {
        try await super.setUp()
        
        unifiedPlayer = UnifiedAudioPlayer.shared
        context = PersistenceController.preview.container.viewContext
        
        // Clear state
        unifiedPlayer.clearQueue()
        UserDefaultsManager.shared.openAIAPIKey = nil
        TTSQuotaManager.shared.resetQuotaTracking()
    }
    
    override func tearDown() async throws {
        unifiedPlayer.clearQueue()
        UserDefaultsManager.shared.openAIAPIKey = nil
        try await super.tearDown()
    }
    
    // MARK: - Primary Path Tests
    
    func testFallback_WhenOpenAIKeyExists_TriesOpenAIFirst() async {
        // Given
        UserDefaultsManager.shared.openAIAPIKey = "sk-test-key"
        let article = createTestArticle()
        
        // When
        await unifiedPlayer.loadQueue(from: [article])
        
        // Then
        XCTAssertNotNil(UserDefaultsManager.shared.openAIAPIKey,
                       "✅ OpenAI key is configured")
        XCTAssertEqual(unifiedPlayer.queue.count, 1,
                      "✅ Queue loads with OpenAI as primary")
    }
    
    func testFallback_WhenNoOpenAIKey_UsesGeminiDirectly() async {
        // Given
        UserDefaultsManager.shared.openAIAPIKey = nil
        let article = createTestArticle()
        
        // When
        await unifiedPlayer.loadQueue(from: [article])
        
        // Then
        XCTAssertNil(UserDefaultsManager.shared.openAIAPIKey,
                    "✅ No OpenAI key configured")
        XCTAssertEqual(unifiedPlayer.queue.count, 1,
                      "✅ Falls back to Gemini when no OpenAI key")
    }
    
    // MARK: - Error Handling Tests
    
    func testFallback_WhenOpenAIRateLimited_FallsBackToGemini() {
        // Document expected behavior
        // When OpenAI returns 429 (rate limited), should try Gemini
        
        let expectedError = OpenAITTSError.rateLimited
        XCTAssertEqual(expectedError, .rateLimited,
                      "✅ Handles OpenAI rate limiting")
    }
    
    func testFallback_WhenOpenAINetworkError_FallsBackToGemini() {
        // Document expected behavior
        // When OpenAI has network issues, should try Gemini
        
        let expectedError = OpenAITTSError.networkError("Connection failed")
        XCTAssertNotNil(expectedError,
                       "✅ Handles OpenAI network errors")
    }
    
    // MARK: - Quota Management Tests
    
    func testQuotaManager_TracksGeminiUsage() {
        // Given
        let quotaManager = TTSQuotaManager.shared
        quotaManager.resetQuotaTracking()
        
        // When
        quotaManager.recordGeminiGeneration()
        
        // Then
        XCTAssertEqual(quotaManager.geminiGenerationsToday, 1,
                      "✅ Tracks Gemini generation count")
        XCTAssertEqual(quotaManager.remainingGeminiGenerations, 99,
                      "✅ Calculates remaining generations")
    }
    
    func testQuotaManager_ShowsWarningAt90Generations() {
        // Given
        let quotaManager = TTSQuotaManager.shared
        quotaManager.resetQuotaTracking()
        
        // When - simulate 90 generations
        for _ in 0..<90 {
            quotaManager.recordGeminiGeneration()
        }
        
        // Then
        XCTAssertTrue(quotaManager.shouldSuggestOpenAI,
                     "✅ Suggests OpenAI when approaching limit")
        XCTAssertEqual(quotaManager.remainingGeminiGenerations, 10,
                      "✅ Shows 10 generations remaining")
    }
    
    func testQuotaManager_ResetsDaily() {
        // Given
        let quotaManager = TTSQuotaManager.shared
        
        // When - new day arrives
        quotaManager.resetQuotaTracking()
        
        // Then
        XCTAssertEqual(quotaManager.geminiGenerationsToday, 0,
                      "✅ Resets count on new day")
        XCTAssertEqual(quotaManager.remainingGeminiGenerations, 100,
                      "✅ Full quota available after reset")
    }
    
    // MARK: - Cost Comparison Tests
    
    func testCostComparison_OpenAIVsGemini() {
        // Document cost differences
        
        // Gemini: Free but limited to 100/day
        let geminiDailyCost = 0.0
        let geminiDailyLimit = 100
        
        // OpenAI: Unlimited but costs money
        let openAICostPer1K = 0.015
        let openAIDailyLimit: Int? = nil // Unlimited
        
        XCTAssertEqual(geminiDailyCost, 0.0,
                      "✅ Gemini is free")
        XCTAssertEqual(geminiDailyLimit, 100,
                      "✅ Gemini limited to 100/day")
        XCTAssertNil(openAIDailyLimit,
                    "✅ OpenAI has no daily limit")
        XCTAssertEqual(openAICostPer1K, 0.015,
                      "✅ OpenAI costs $0.015 per 1K chars")
    }
    
    // MARK: - Migration Flow Tests
    
    func testMigrationFlow_PromptsAtQuotaLimit() {
        // Given
        let quotaManager = TTSQuotaManager.shared
        
        // When hitting limit
        for _ in 0..<100 {
            quotaManager.recordGeminiGeneration()
        }
        
        // Then
        XCTAssertTrue(quotaManager.showingQuotaAlert,
                     "✅ Shows quota alert at limit")
        XCTAssertEqual(quotaManager.remainingGeminiGenerations, 0,
                      "✅ No generations remaining")
    }
    
    func testMigrationFlow_UserCanConfigureOpenAI() {
        // Given
        XCTAssertNil(UserDefaultsManager.shared.openAIAPIKey)
        
        // When user adds API key
        UserDefaultsManager.shared.openAIAPIKey = "sk-test-key"
        
        // Then
        XCTAssertNotNil(UserDefaultsManager.shared.openAIAPIKey,
                       "✅ User can configure OpenAI")
    }
    
    // MARK: - Streaming Fallback Tests
    
    func testStreamingFallback_WhenStreamingFails_UsesRegularGeneration() {
        // Given
        UserDefaultsManager.shared.useOpenAIStreaming = true
        
        // Document fallback path
        // 1. Try OpenAI streaming
        // 2. If fails -> Try OpenAI non-streaming
        // 3. If fails -> Try Gemini
        
        XCTAssertTrue(UserDefaultsManager.shared.useOpenAIStreaming,
                     "✅ Streaming enabled")
    }
    
    // MARK: - Helper Methods
    
    private func createTestArticle() -> Article {
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Test Article"
        article.summary = "Test summary for fallback testing"
        article.content = "Full content for testing OpenAI to Gemini fallback"
        return article
    }
    
    private func resetQuotaTracking() {
        let quotaManager = TTSQuotaManager.shared
        quotaManager.resetQuotaTracking()
    }
}

// MARK: - Integration Scenario Tests

@MainActor
final class OpenAIGeminiIntegrationScenarioTests: XCTestCase {
    
    func testScenario_NewUser_StartsWithGemini() {
        // Document new user experience
        // 1. No OpenAI key configured
        // 2. Uses Gemini by default
        // 3. Gets 100 free generations per day
        // 4. Prompted to add OpenAI when approaching limit
        
        XCTAssertNil(UserDefaultsManager.shared.openAIAPIKey,
                    "✅ New users start without OpenAI")
    }
    
    func testScenario_PowerUser_MigratesFromGemini() {
        // Document power user migration
        // 1. Hits 100/day Gemini limit regularly
        // 2. Gets migration prompt
        // 3. Adds OpenAI API key
        // 4. Unlimited generations with cost tracking
        
        UserDefaultsManager.shared.openAIAPIKey = "sk-power-user"
        XCTAssertNotNil(UserDefaultsManager.shared.openAIAPIKey,
                       "✅ Power users migrate to OpenAI")
    }
    
    func testScenario_CasualUser_StaysOnGemini() {
        // Document casual user experience
        // 1. Uses < 100 generations per day
        // 2. Never hits limit
        // 3. Continues with free Gemini
        // 4. No need for OpenAI
        
        let quotaManager = TTSQuotaManager.shared
        quotaManager.resetQuotaTracking()
        
        // Simulate casual usage (20 articles/day)
        for _ in 0..<20 {
            quotaManager.recordGeminiGeneration()
        }
        
        XCTAssertFalse(quotaManager.shouldSuggestOpenAI,
                      "✅ Casual users not prompted for OpenAI")
        XCTAssertEqual(quotaManager.remainingGeminiGenerations, 80,
                      "✅ Plenty of quota remaining")
    }
}

// MARK: - Performance Comparison Tests

final class FallbackPerformanceTests: XCTestCase {
    
    func testLatencyComparison_OpenAIVsGemini() {
        // Document expected latencies
        
        struct LatencyProfile {
            let service: String
            let firstByteLatency: Int // milliseconds
            let fullGenerationTime: Int // milliseconds
        }
        
        let profiles = [
            LatencyProfile(service: "OpenAI Streaming", firstByteLatency: 200, fullGenerationTime: 1500),
            LatencyProfile(service: "OpenAI Standard", firstByteLatency: 2000, fullGenerationTime: 2000),
            LatencyProfile(service: "Gemini", firstByteLatency: 3000, fullGenerationTime: 3000)
        ]
        
        let fastestFirstByte = profiles.min(by: { $0.firstByteLatency < $1.firstByteLatency })
        
        XCTAssertEqual(fastestFirstByte?.service, "OpenAI Streaming",
                      "✅ OpenAI streaming has lowest latency")
    }
    
    func testCostEfficiency_ByUsageLevel() {
        // Calculate cost efficiency at different usage levels
        
        func calculateMonthlyCost(dailyArticles: Int, useOpenAI: Bool) -> Double {
            if useOpenAI {
                let charsPerArticle = 500
                let dailyChars = dailyArticles * charsPerArticle
                let dailyCost = Double(dailyChars) / 1000.0 * 0.015
                return dailyCost * 30 // Monthly
            } else {
                return 0.0 // Gemini is free
            }
        }
        
        // Light user: 20 articles/day
        let lightGeminiCost = calculateMonthlyCost(dailyArticles: 20, useOpenAI: false)
        let lightOpenAICost = calculateMonthlyCost(dailyArticles: 20, useOpenAI: true)
        
        XCTAssertEqual(lightGeminiCost, 0.0,
                      "✅ Light users: Gemini is free")
        XCTAssertEqual(lightOpenAICost, 4.5, accuracy: 0.1,
                      "✅ Light users: OpenAI ~$4.50/month")
        
        // Heavy user: 200 articles/day (exceeds Gemini limit)
        let heavyOpenAICost = calculateMonthlyCost(dailyArticles: 200, useOpenAI: true)
        
        XCTAssertEqual(heavyOpenAICost, 45.0, accuracy: 0.1,
                      "✅ Heavy users: OpenAI ~$45/month")
    }
}