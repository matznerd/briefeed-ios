//
//  TTSFileGenerationTests.swift
//  BriefeedTests
//
//  TDD Tests for TTS File Generation with Gemini API
//  Written BEFORE implementation - these tests should fail initially
//

import XCTest
import AVFoundation
import CoreData
@testable import Briefeed

class TTSFileGenerationTests: XCTestCase {
    
    var ttsService: TTSGeneratorService!
    var geminiTTSService: GeminiTTSService!
    var cacheManager: AudioCacheManager!
    var testContext: NSManagedObjectContext!
    
    override func setUp() {
        super.setUp()
        
        // Initialize services
        ttsService = TTSGeneratorService()
        geminiTTSService = GeminiTTSService()
        cacheManager = AudioCacheManager()
        testContext = PersistenceController.preview.container.viewContext
    }
    
    override func tearDown() {
        // Clean up test cache
        try? cacheManager.clearCache()
        
        ttsService = nil
        geminiTTSService = nil
        cacheManager = nil
        super.tearDown()
    }
    
    // MARK: - Test 1: Cache Directory Creation
    
    func testCacheDirectoryIsCreated() throws {
        // Given: A cache manager
        let cacheURL = cacheManager.cacheDirectory
        
        // Then: Cache directory should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path),
                     "Cache directory should be created at: \(cacheURL.path)")
        
        // And: It should be in the correct location
        let expectedPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("tts_audio", isDirectory: true)
        XCTAssertEqual(cacheURL, expectedPath)
    }
    
    // MARK: - Test 2: Generate Audio File from Text
    
    func testGenerateAudioFileFromText() async throws {
        // Given: Sample text
        let text = "This is a test article about SwiftAudioEx integration."
        
        // When: Generating audio file
        let audioURL = try await ttsService.generateAudioFile(from: text)
        
        // Then: File should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path),
                     "Audio file should exist at: \(audioURL.path)")
        
        // And: File should be valid audio
        let asset = AVAsset(url: audioURL)
        XCTAssertTrue(asset.isPlayable, "Generated file should be playable")
        XCTAssertGreaterThan(asset.duration.seconds, 0, "Audio should have duration")
        
        // And: File should be MP3 format
        XCTAssertEqual(audioURL.pathExtension, "mp3", "File should be MP3 format")
    }
    
    // MARK: - Test 3: Cache Hit for Same Text
    
    func testCacheHitForSameText() async throws {
        // Given: Text to generate
        let text = "This text should be cached after first generation."
        
        // When: Generating first time
        let startTime1 = Date()
        let audioURL1 = try await ttsService.generateAudioFile(from: text)
        let duration1 = Date().timeIntervalSince(startTime1)
        
        // And: Generating second time (should hit cache)
        let startTime2 = Date()
        let audioURL2 = try await ttsService.generateAudioFile(from: text)
        let duration2 = Date().timeIntervalSince(startTime2)
        
        // Then: URLs should be the same
        XCTAssertEqual(audioURL1, audioURL2, "Should return same cached file")
        
        // And: Second generation should be much faster (cache hit)
        XCTAssertLessThan(duration2, duration1 * 0.1,
                         "Cache hit should be at least 10x faster than generation")
    }
    
    // MARK: - Test 4: Gemini TTS with Voice Selection
    
    func testGeminiTTSWithVoiceSelection() async throws {
        // Given: Text and voice preference
        let text = "Testing Gemini TTS with specific voice."
        let voice = "F" // Female voice
        
        // When: Generating with Gemini TTS
        let audioData = try await geminiTTSService.generateSpeech(
            from: text,
            voice: voice
        )
        
        // Then: Data should not be empty
        XCTAssertFalse(audioData.isEmpty, "Audio data should not be empty")
        
        // And: Should be valid audio data
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        try audioData.write(to: tempURL)
        
        let asset = AVAsset(url: tempURL)
        XCTAssertTrue(asset.isPlayable, "Gemini TTS should produce playable audio")
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    // MARK: - Test 5: Fallback to AVSpeechSynthesizer
    
    func testFallbackToAVSpeechWhenGeminiFails() async throws {
        // Given: A TTS service with simulated Gemini failure
        let text = "This should fallback to AVSpeechSynthesizer"
        
        // When: Gemini fails (simulate by using nil API key)
        let originalKey = UserDefaults.standard.string(forKey: "geminiAPIKey")
        UserDefaults.standard.set(nil, forKey: "geminiAPIKey")
        
        let audioURL = try await ttsService.generateAudioFile(from: text)
        
        // Restore key
        if let originalKey = originalKey {
            UserDefaults.standard.set(originalKey, forKey: "geminiAPIKey")
        }
        
        // Then: Should still generate audio (via fallback)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path),
                     "Should generate audio via AVSpeech fallback")
        
        // And: Audio should be valid
        let asset = AVAsset(url: audioURL)
        XCTAssertTrue(asset.isPlayable, "Fallback audio should be playable")
    }
    
    // MARK: - Test 6: Cache Size Management
    
    func testCacheSizeManagement() async throws {
        // Given: Multiple texts to generate
        let texts = [
            "First article about Swift programming.",
            "Second article about iOS development.",
            "Third article about SwiftUI animations.",
            "Fourth article about Core Data.",
            "Fifth article about networking."
        ]
        
        // When: Generating multiple audio files
        for text in texts {
            _ = try await ttsService.generateAudioFile(from: text)
        }
        
        // Then: Cache size should be tracked
        let cacheSize = cacheManager.currentCacheSize
        XCTAssertGreaterThan(cacheSize, 0, "Cache should have size after generation")
        
        // And: Should not exceed limit (500MB)
        let maxSize: Int64 = 500 * 1024 * 1024 // 500MB
        XCTAssertLessThanOrEqual(cacheSize, maxSize, "Cache should not exceed 500MB")
    }
    
    // MARK: - Test 7: Auto-cleanup After 5 Days
    
    func testAutoCleanupAfterFiveDays() async throws {
        // Given: An old cached file
        let text = "Old article that should be cleaned up"
        let audioURL = try await ttsService.generateAudioFile(from: text)
        
        // When: Setting file modification date to 6 days ago
        let sixDaysAgo = Date().addingTimeInterval(-6 * 24 * 60 * 60)
        try FileManager.default.setAttributes(
            [.modificationDate: sixDaysAgo],
            ofItemAtPath: audioURL.path
        )
        
        // And: Running cleanup
        try cacheManager.cleanupOldFiles(olderThan: 5)
        
        // Then: File should be removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path),
                      "Files older than 5 days should be removed")
    }
    
    // MARK: - Test 8: Core Data Tracking
    
    func testCoreDataTracking() async throws {
        // Given: Text to generate
        let text = "Article to track in Core Data"
        let article = createTestArticle(content: text)
        
        // When: Generating audio
        let audioURL = try await ttsService.generateAudioFile(
            from: text,
            trackingIn: testContext,
            for: article
        )
        
        // Then: Should be tracked in Core Data
        let fetchRequest: NSFetchRequest<CachedAudio> = CachedAudio.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "articleID == %@", article.id! as CVarArg)
        
        let results = try testContext.fetch(fetchRequest)
        XCTAssertEqual(results.count, 1, "Should track cached audio in Core Data")
        
        let cachedAudio = results.first!
        XCTAssertEqual(cachedAudio.filePath, audioURL.path)
        XCTAssertEqual(cachedAudio.textHash, text.hash)
        XCTAssertNotNil(cachedAudio.generatedAt)
    }
    
    // MARK: - Test 9: Avoid Regeneration with Core Data
    
    func testAvoidRegenerationWithCoreData() async throws {
        // Given: Article with previously generated audio
        let text = "This audio was already generated"
        let article = createTestArticle(content: text)
        
        // First generation
        let audioURL1 = try await ttsService.generateAudioFile(
            from: text,
            trackingIn: testContext,
            for: article
        )
        
        // When: Requesting same article again
        var apiCallCount = 0
        geminiTTSService.onAPICall = { apiCallCount += 1 }
        
        let audioURL2 = try await ttsService.generateAudioFile(
            from: text,
            trackingIn: testContext,
            for: article
        )
        
        // Then: Should return cached file without API call
        XCTAssertEqual(audioURL1, audioURL2, "Should return same cached file")
        XCTAssertEqual(apiCallCount, 0, "Should not make API call for cached audio")
    }
    
    // MARK: - Test 10: Pre-generation for Queue
    
    func testPreGenerationForQueue() async throws {
        // Given: Queue with 5 items
        let queue = [
            createTestArticle(content: "Currently playing article"),
            createTestArticle(content: "Next article in queue"),
            createTestArticle(content: "Second next article"),
            createTestArticle(content: "Third article - should not pre-generate"),
            createTestArticle(content: "Fourth article - should not pre-generate")
        ]
        
        // When: Pre-generating for queue (current + next 2)
        let preGenerated = try await ttsService.preGenerateForQueue(
            queue: queue,
            currentIndex: 0,
            context: testContext
        )
        
        // Then: Should pre-generate exactly 3 items
        XCTAssertEqual(preGenerated.count, 3,
                      "Should pre-generate current + next 2 items")
        
        // And: Files should exist
        for url in preGenerated {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }
    
    // MARK: - Test 11: Performance Metrics
    
    func testTTSGenerationTimeMetrics() async throws {
        // Given: Text samples of different lengths
        let shortText = "Short text."
        let mediumText = String(repeating: "Medium length text. ", count: 50)
        let longText = String(repeating: "Long text content. ", count: 200)
        
        // When: Generating and measuring time
        let metrics = TTSPerformanceMetrics()
        
        let shortTime = try await metrics.measure {
            _ = try await ttsService.generateAudioFile(from: shortText)
        }
        
        let mediumTime = try await metrics.measure {
            _ = try await ttsService.generateAudioFile(from: mediumText)
        }
        
        let longTime = try await metrics.measure {
            _ = try await ttsService.generateAudioFile(from: longText)
        }
        
        // Then: Generation time should scale with text length
        XCTAssertLessThan(shortTime, mediumTime,
                         "Short text should generate faster than medium")
        XCTAssertLessThan(mediumTime, longTime,
                         "Medium text should generate faster than long")
        
        // And: All should complete within reasonable time (10 seconds)
        XCTAssertLessThan(longTime, 10.0,
                         "Even long text should generate within 10 seconds")
    }
    
    // MARK: - Test 12: Empty Text Handling
    
    func testEmptyTextHandling() async throws {
        // Given: Empty text
        let emptyText = ""
        
        // When/Then: Should throw error
        do {
            _ = try await ttsService.generateAudioFile(from: emptyText)
            XCTFail("Should throw error for empty text")
        } catch {
            XCTAssertEqual(error as? TTSError, TTSError.emptyText,
                          "Should throw emptyText error")
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestArticle(content: String) -> Article {
        let article = Article(context: testContext)
        article.id = UUID()
        article.title = "Test Article"
        article.content = content
        article.createdAt = Date()
        return article
    }
}

// MARK: - Supporting Types (These need to be implemented)

enum TTSError: Error, Equatable {
    case emptyText
    case generationFailed
    case fileWriteFailed
}

class AudioCacheManager {
    let cacheDirectory: URL
    
    init() {
        let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachePath.appendingPathComponent("tts_audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    var currentCacheSize: Int64 {
        // To be implemented
        return 0
    }
    
    func clearCache() throws {
        // To be implemented
    }
    
    func cleanupOldFiles(olderThan days: Int) throws {
        // To be implemented
    }
}

// Core Data entity (needs to be added to data model)
class CachedAudio: NSManagedObject {
    @NSManaged var articleID: UUID
    @NSManaged var filePath: String
    @NSManaged var textHash: Int
    @NSManaged var generatedAt: Date
}

struct TTSPerformanceMetrics {
    func measure<T>(block: () async throws -> T) async throws -> TimeInterval {
        let start = Date()
        _ = try await block()
        return Date().timeIntervalSince(start)
    }
}

// Extension to make tests work
extension TTSGeneratorService {
    func generateAudioFile(from text: String,
                          trackingIn context: NSManagedObjectContext? = nil,
                          for article: Article? = nil) async throws -> URL {
        // To be implemented
        throw TTSError.generationFailed
    }
    
    func preGenerateForQueue(queue: [Article],
                           currentIndex: Int,
                           context: NSManagedObjectContext) async throws -> [URL] {
        // To be implemented
        return []
    }
}

extension GeminiTTSService {
    var onAPICall: (() -> Void)?
}