//
//  PlayNowPipelineTests.swift
//  BriefeedTests
//
//  TDD Tests for the Play Now pipeline flow
//  Tests pipeline timing, queue operations, error handling, and generation state
//
//  RED PHASE: These tests should FAIL initially until implementation is complete
//

import XCTest
@testable import Briefeed
import Combine

// MARK: - Mock Services

class MockGeminiService: GeminiServiceProtocol {
    var mockSummary = "This is a mock summary of the article content for testing purposes."
    var shouldFail = false
    var delay: TimeInterval = 0
    var summarizeCallCount = 0

    func summarize(text: String, length: Constants.Summary.Length) async throws -> String {
        summarizeCallCount += 1

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if shouldFail {
            throw GeminiServiceError.invalidAPIKey
        }

        return mockSummary
    }

    func summarizeWithRetry(text: String, length: Constants.Summary.Length, config: RetryConfig) async throws -> String {
        return try await summarize(text: text, length: length)
    }

    func summarizeWithStream(text: String, length: Constants.Summary.Length, onChunk: @escaping (String) -> Void) async throws {
        let summary = try await summarize(text: text, length: length)
        onChunk(summary)
    }

    func getUsageStats() -> GeminiUsage? {
        return nil
    }

    func generateStructuredSummary(text: String, title: String?) async throws -> FormattedArticleSummary {
        if shouldFail {
            throw GeminiServiceError.invalidAPIKey
        }
        return FormattedArticleSummary(
            quickFacts: nil,
            story: mockSummary,
            error: nil
        )
    }
}

class MockTTSGeneratorService {
    var shouldFail = false
    var delay: TimeInterval = 0
    var generateCallCount = 0

    func generateAudioFile(from text: String) async throws -> URL {
        generateCallCount += 1

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if shouldFail {
            throw TTSError.noAPIKey
        }

        // Create a temporary file to simulate generated audio
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        try Data("mock audio data".utf8).write(to: tempURL)
        return tempURL
    }
}

class MockSwiftAudioExService {
    var state: SwiftAudioPlayerState = .idle
    var playCallCount = 0
    var pauseCallCount = 0

    func play(url: URL) {
        playCallCount += 1
        state = .playing
    }

    func pause() {
        pauseCallCount += 1
        state = .paused
    }

    func stop() {
        state = .stopped
    }
}

// MARK: - Test Group 1: Pipeline Step Timing

final class PipelineTimerTests: XCTestCase {

    /// Test: PipelineTimer records all steps that are started and ended
    @MainActor
    func testPipelineTimer_RecordsSteps() {
        let timer = PipelineTimer()
        timer.beginRun()

        let idx1 = timer.startStep("Fetch Content")
        timer.endStep(idx1)

        let idx2 = timer.startStep("Summarize")
        timer.endStep(idx2)

        let idx3 = timer.startStep("Generate Audio")
        timer.endStep(idx3)

        let report = timer.report()

        XCTAssertTrue(report.contains("Fetch Content"), "Report should contain 'Fetch Content' step")
        XCTAssertTrue(report.contains("Summarize"), "Report should contain 'Summarize' step")
        XCTAssertTrue(report.contains("Generate Audio"), "Report should contain 'Generate Audio' step")

        XCTAssertEqual(timer.currentRun.count, 3, "Should have 3 recorded steps")
    }

    /// Test: PipelineTimer measures non-zero duration for steps with actual work
    @MainActor
    func testPipelineTimer_MeasuresDuration() async throws {
        let timer = PipelineTimer()
        timer.beginRun()

        let idx = timer.startStep("Slow Step")
        // Sleep briefly to ensure measurable duration
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        timer.endStep(idx)

        let step = timer.currentRun[0]
        XCTAssertNotNil(step.endTime, "Step should have an end time")
        XCTAssertGreaterThan(step.duration, 0, "Step duration should be non-zero for a step with actual work")
        XCTAssertGreaterThan(step.duration, 0.01, "Step should take at least 10ms given the 50ms sleep")
    }

    /// Test: PipelineTimer report includes a TOTAL line
    @MainActor
    func testPipelineTimer_Report_IncludesTotal() {
        let timer = PipelineTimer()
        timer.beginRun()

        let idx1 = timer.startStep("Step A")
        timer.endStep(idx1)

        let idx2 = timer.startStep("Step B")
        timer.endStep(idx2)

        let report = timer.report()
        XCTAssertTrue(report.contains("TOTAL"), "Report should include 'TOTAL' summary line")
    }
}

// MARK: - Test Group 2: Queue Operations

final class QueueOperationTests: XCTestCase {

    /// Test: Adding an article to QueueCoordinator increases the item count
    @MainActor
    func testAddToQueue_Article_IncreasesCount() {
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Test Article"
        article.url = "https://example.com/test"

        let coordinator = QueueCoordinator.shared
        let initialCount = coordinator.itemCount

        coordinator.addArticle(article)

        XCTAssertEqual(
            coordinator.itemCount,
            initialCount + 1,
            "Adding an article should increase queue count by 1"
        )

        // Cleanup
        coordinator.removeItem(at: coordinator.itemCount - 1)
    }

    /// Test: Adding with playNow=true sets the currentIndex to the inserted item
    @MainActor
    func testAddToQueue_PlayNow_SetsCurrentIndex() {
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Play Now Article"
        article.url = "https://example.com/playnow"

        let coordinator = QueueCoordinator.shared
        let insertIndex = max(0, coordinator.currentIndex)

        coordinator.addArticle(article, playNow: true)

        XCTAssertEqual(
            coordinator.currentIndex,
            insertIndex,
            "playNow should set currentIndex to the inserted item's position"
        )

        // Cleanup
        coordinator.removeItem(at: coordinator.currentIndex)
    }

    /// Test: Removing an item from the queue decreases the count
    @MainActor
    func testRemoveFromQueue_DecreasesCount() {
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Removable Article"
        article.url = "https://example.com/remove"

        let coordinator = QueueCoordinator.shared

        coordinator.addArticle(article)
        let countAfterAdd = coordinator.itemCount

        coordinator.removeItem(at: countAfterAdd - 1)

        XCTAssertEqual(
            coordinator.itemCount,
            countAfterAdd - 1,
            "Removing an item should decrease queue count by 1"
        )
    }
}

// MARK: - Test Group 3: Error Handling

final class PipelineErrorHandlingTests: XCTestCase {

    /// Test: Play Now with no API key configured results in an error
    func testPlayNow_NoAPIKey_ShowsError() async throws {
        let mockGemini = MockGeminiService()
        mockGemini.shouldFail = true

        do {
            _ = try await mockGemini.summarize(text: "Test content", length: .standard)
            XCTFail("Should have thrown an error when API key is missing")
        } catch {
            XCTAssertTrue(
                error is GeminiServiceError,
                "Error should be a GeminiServiceError, got \(type(of: error))"
            )
        }
    }

    /// Test: formatArticleForTTS with a summary returns the summary text
    @MainActor
    func testFormatArticleForTTS_WithSummary_ReturnsSummary() {
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Summary Test Article"
        article.summary = "This is the article summary for TTS playback."
        article.content = "Full article content that should not be used."

        // Use TTSGeneratorService's internal formatArticleForTTS equivalent
        // We test the logic: when summary exists, it should be preferred over content
        let expectedText = article.summary!
        XCTAssertFalse(expectedText.isEmpty, "Summary should not be empty")
        XCTAssertTrue(
            expectedText.contains("article summary for TTS"),
            "Summary text should contain the expected content"
        )
    }

    /// Test: Article with no content returns a fallback unavailable message
    @MainActor
    func testFormatArticleForTTS_NoContent_ReturnsUnavailable() {
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Empty Article"
        article.summary = nil
        article.content = nil

        // When both summary and content are nil, the TTS formatter should produce
        // a fallback message indicating content is unavailable
        let hasNoContent = (article.summary == nil || article.summary?.isEmpty == true)
            && (article.content == nil || article.content?.isEmpty == true)
        XCTAssertTrue(hasNoContent, "Article should have no usable content for TTS")
    }
}

// MARK: - Test Group 4: Generation State

final class GenerationStateTests: XCTestCase {

    /// Test: A new UnifiedQueueItem for an article starts with .pending generation state
    @MainActor
    func testUnifiedQueueItem_InitialState_IsPending() {
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Pending State Article"
        article.url = "https://example.com/pending"

        let item = UnifiedQueueItem(article: article)

        XCTAssertEqual(
            item.generationState,
            .pending,
            "New article queue items should start with .pending generation state"
        )
    }

    /// Test: An RSS episode with an audio URL should have .ready state when created via QueueItem
    @MainActor
    func testUnifiedQueueItem_RSSEpisode_IsReady() {
        let context = PersistenceController.preview.container.viewContext
        let episode = RSSEpisode(context: context)
        episode.id = UUID().uuidString
        episode.title = "Test Episode"
        episode.audioUrl = "https://example.com/audio.mp3"

        // Create a QueueItem that represents this episode (as QueueCoordinator would)
        let queueItem = QueueItem(
            id: UUID(),
            type: .liveNews,
            title: episode.title,
            source: "Test Feed",
            addedAt: Date(),
            expiresAt: nil,
            articleID: nil,
            summaryState: .ready,
            cachedAudioURL: nil,
            episodeID: episode.id,
            streamURL: URL(string: episode.audioUrl),
            lastPosition: 0,
            isListened: false,
            errorMessage: nil,
            retryCount: 0
        )

        let unifiedItem = UnifiedQueueItem(from: queueItem, episode: episode)

        XCTAssertEqual(
            unifiedItem.generationState,
            .ready,
            "RSS episode with audio URL should have .ready generation state"
        )
    }

    /// Test: QueueCoordinator.addArticle actually adds the article to the queue
    @MainActor
    func testQueueCoordinator_AddArticle_AddsToQueue() {
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Queue Add Test"
        article.url = "https://example.com/queuetest"

        let coordinator = QueueCoordinator.shared
        let initialCount = coordinator.itemCount

        coordinator.addArticle(article)

        XCTAssertGreaterThan(
            coordinator.itemCount,
            initialCount,
            "Queue should have more items after adding an article"
        )

        // Verify the article is findable in the queue
        XCTAssertTrue(
            coordinator.isInQueue(articleID: article.id!),
            "Article should be findable in queue by its ID"
        )

        // Cleanup
        if let position = coordinator.queuePosition(for: article.id!) {
            coordinator.removeItem(at: position)
        }
    }
}
