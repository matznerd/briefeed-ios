import XCTest
@testable import Briefeed

// MARK: - TDD: TTS Audio Generation Tests
// Define expected behavior for text-to-speech audio generation

final class TTSAudioTests: XCTestCase {
    
    // MARK: - TTS Generation Tests
    
    func testGenerateTTSFromArticle() async {
        // Given
        let ttsService = TTSService.shared
        let article = MockArticle(
            title: "Test Article",
            content: "This is the article content that should be converted to speech.",
            author: "Test Author",
            url: "https://example.com/article"
        )
        
        // When
        let audioURL = try await ttsService.generateAudio(for: article)
        
        // Then
        XCTAssertNotNil(audioURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertTrue(audioURL.pathExtension == "mp3" || audioURL.pathExtension == "m4a")
    }
    
    func testGenerateTTSWithSummary() async {
        // Given
        let ttsService = TTSService.shared
        let article = MockArticle(
            title: "Long Article",
            content: String(repeating: "This is a very long article. ", count: 100),
            author: "Author"
        )
        
        // When - generate with summary
        let audioURL = try await ttsService.generateAudio(
            for: article,
            useSummary: true
        )
        
        // Then
        XCTAssertNotNil(audioURL)
        // Summary audio should be shorter than full content
        let audioAsset = AVURLAsset(url: audioURL)
        let duration = try await audioAsset.load(.duration)
        XCTAssertLessThan(duration.seconds, 60, "Summary should be shorter")
    }
    
    func testTTSCaching() async {
        // Given
        let ttsService = TTSService.shared
        let cacheManager = AudioCacheManager.shared
        let article = MockArticle(
            id: "cache-test-1",
            title: "Cached Article",
            content: "This content should be cached."
        )
        
        // When - generate first time
        let firstURL = try await ttsService.generateAudio(for: article)
        
        // Then - should be cached
        XCTAssertTrue(cacheManager.isCached(articleId: article.id))
        
        // When - request again
        let secondURL = try await ttsService.generateAudio(for: article)
        
        // Then - should return cached version
        XCTAssertEqual(firstURL, secondURL)
        XCTAssertTrue(cacheManager.wasServedFromCache)
    }
    
    func testTTSVoiceSelection() async {
        // Given
        let ttsService = TTSService.shared
        let article = MockArticle(
            title: "Voice Test",
            content: "Testing different voices."
        )
        
        // Test different voices
        let voices: [TTSVoice] = [.default, .enhanced, .premium]
        
        for voice in voices {
            // When
            ttsService.setVoice(voice)
            let audioURL = try await ttsService.generateAudio(for: article)
            
            // Then
            XCTAssertNotNil(audioURL)
            XCTAssertEqual(ttsService.currentVoice, voice)
        }
    }
    
    // MARK: - TTS with Gemini API Tests
    
    func testGeminiSummarization() async {
        // Given
        let geminiService = GeminiService.shared
        let article = MockArticle(
            title: "Article to Summarize",
            content: String(repeating: "Long content paragraph. ", count: 50)
        )
        
        // When
        let summary = try await geminiService.summarize(article)
        
        // Then
        XCTAssertNotNil(summary)
        XCTAssertLessThan(summary.text.count, article.content.count)
        XCTAssertGreaterThan(summary.text.count, 50, "Summary shouldn't be too short")
        XCTAssertEqual(summary.sourceArticleId, article.id)
    }
    
    func testGeminiTTSGeneration() async {
        // Given
        let geminiService = GeminiService.shared
        let text = "Hello, this is a test of Gemini text-to-speech."
        
        // When
        let audioData = try await geminiService.generateTTS(text: text)
        
        // Then
        XCTAssertNotNil(audioData)
        XCTAssertGreaterThan(audioData.count, 1000, "Audio data should have content")
        
        // Verify it's valid audio
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.mp3")
        try audioData.write(to: tempURL)
        let asset = AVURLAsset(url: tempURL)
        XCTAssertTrue(asset.isPlayable)
    }
    
    // MARK: - TTS Queue Processing Tests
    
    func testBatchTTSGeneration() async {
        // Given
        let ttsService = TTSService.shared
        let articles = (1...5).map { index in
            MockArticle(
                id: "batch-\(index)",
                title: "Article \(index)",
                content: "Content for article \(index)"
            )
        }
        
        // When - generate batch
        let audioURLs = try await ttsService.generateBatch(articles: articles)
        
        // Then
        XCTAssertEqual(audioURLs.count, 5)
        audioURLs.forEach { url in
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }
    
    func testBackgroundTTSGeneration() async {
        // Given
        let ttsService = TTSService.shared
        let article = MockArticle(
            title: "Background Article",
            content: "This should generate in background."
        )
        
        // When - start background generation
        let task = Task.detached(priority: .background) {
            try await ttsService.generateAudio(for: article)
        }
        
        // Then - should complete without blocking
        let audioURL = try await task.value
        XCTAssertNotNil(audioURL)
    }
    
    // MARK: - TTS Error Handling Tests
    
    func testTTSWithEmptyContent() async {
        // Given
        let ttsService = TTSService.shared
        let article = MockArticle(
            title: "Empty Article",
            content: "" // Empty content
        )
        
        // When/Then - should throw error
        do {
            _ = try await ttsService.generateAudio(for: article)
            XCTFail("Should throw error for empty content")
        } catch {
            XCTAssertEqual(error as? TTSError, TTSError.emptyContent)
        }
    }
    
    func testTTSWithInvalidCharacters() async {
        // Given
        let ttsService = TTSService.shared
        let article = MockArticle(
            title: "Invalid Characters",
            content: "Content with 🎉 emojis and special ♪♫ characters"
        )
        
        // When - should clean and generate
        let audioURL = try await ttsService.generateAudio(for: article)
        
        // Then
        XCTAssertNotNil(audioURL)
        // Should have cleaned the text
        XCTAssertTrue(ttsService.lastProcessedText.contains("Content with"))
        XCTAssertFalse(ttsService.lastProcessedText.contains("🎉"))
    }
    
    // MARK: - TTS Performance Tests
    
    func testTTSGenerationSpeed() async {
        // Given
        let ttsService = TTSService.shared
        let article = MockArticle(
            title: "Performance Test",
            content: String(repeating: "Test content. ", count: 20)
        )
        
        // When
        let start = CFAbsoluteTimeGetCurrent()
        let audioURL = try await ttsService.generateAudio(for: article)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        // Then - should generate reasonably fast
        XCTAssertNotNil(audioURL)
        XCTAssertLessThan(elapsed, 5.0, "TTS should generate within 5 seconds")
    }
    
    func testTTSMemoryUsage() async {
        // Given
        let ttsService = TTSService.shared
        let largeArticle = MockArticle(
            title: "Large Article",
            content: String(repeating: "Large content block. ", count: 1000)
        )
        
        // When
        let memoryBefore = getMemoryUsage()
        let audioURL = try await ttsService.generateAudio(for: largeArticle)
        let memoryAfter = getMemoryUsage()
        
        // Then
        XCTAssertNotNil(audioURL)
        let memoryIncrease = memoryAfter - memoryBefore
        XCTAssertLessThan(memoryIncrease, 50_000_000, "Should use less than 50MB")
    }
    
    // MARK: - Cache Management Tests
    
    func testCacheSize() {
        // Given
        let cacheManager = AudioCacheManager.shared
        
        // When
        let cacheSize = cacheManager.totalCacheSize()
        
        // Then
        XCTAssertGreaterThanOrEqual(cacheSize, 0)
        XCTAssertLessThan(cacheSize, 500_000_000, "Cache should be under 500MB")
    }
    
    func testClearOldCache() {
        // Given
        let cacheManager = AudioCacheManager.shared
        
        // When - clear items older than 7 days
        let clearedCount = cacheManager.clearCache(olderThan: 7 * 24 * 60 * 60)
        
        // Then
        XCTAssertGreaterThanOrEqual(clearedCount, 0)
    }
    
    func testCacheEviction() {
        // Given
        let cacheManager = AudioCacheManager.shared
        cacheManager.setMaxCacheSize(10_000_000) // 10MB limit
        
        // When - add items until over limit
        // Then - oldest items should be evicted
        let remainingItems = cacheManager.itemCount
        XCTAssertLessThanOrEqual(cacheManager.totalCacheSize(), 10_000_000)
    }
}

// MARK: - Helper Types

struct MockArticle {
    let id: String
    let title: String
    let content: String
    let author: String
    let url: String?
    
    init(
        id: String = UUID().uuidString,
        title: String,
        content: String,
        author: String = "Test Author",
        url: String? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.author = author
        self.url = url
    }
}

enum TTSVoice {
    case `default`
    case enhanced
    case premium
}

enum TTSError: Error, Equatable {
    case emptyContent
    case generationFailed
    case cacheFull
}

func getMemoryUsage() -> Int {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_,
                     task_flavor_t(MACH_TASK_BASIC_INFO),
                     $0,
                     &count)
        }
    }
    return result == KERN_SUCCESS ? Int(info.resident_size) : 0
}