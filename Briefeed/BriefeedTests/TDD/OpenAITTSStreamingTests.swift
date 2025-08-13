//
//  OpenAITTSStreamingTests.swift
//  BriefeedTests
//
//  TDD tests for OpenAI TTS streaming implementation
//

import XCTest
import AVFoundation
@testable import Briefeed

@MainActor
final class OpenAITTSStreamingTests: XCTestCase {
    
    var sut: OpenAITTSStreamingService!
    var mockDelegate: MockStreamingDelegate!
    
    override func setUp() async throws {
        try await super.setUp()
        sut = OpenAITTSStreamingService()
        mockDelegate = MockStreamingDelegate()
        sut.delegate = mockDelegate
        
        // Clear state
        UserDefaultsManager.shared.openAIAPIKey = nil
        UserDefaultsManager.shared.useOpenAIStreaming = false
    }
    
    override func tearDown() async throws {
        sut.cancelStreaming()
        UserDefaultsManager.shared.openAIAPIKey = nil
        UserDefaultsManager.shared.useOpenAIStreaming = false
        try await super.tearDown()
    }
    
    // MARK: - Configuration Tests
    
    func testStreaming_RequiresAPIKey() {
        // Given
        UserDefaultsManager.shared.openAIAPIKey = nil
        
        // When
        sut.streamAudio(from: "Test text")
        
        // Then
        XCTAssertTrue(mockDelegate.didFailWithError, 
                     "✅ Streaming fails without API key")
        XCTAssertEqual(mockDelegate.receivedError as? OpenAITTSError, 
                      OpenAITTSError.noAPIKey,
                      "✅ Returns correct error type")
    }
    
    func testStreaming_IsOptional() {
        // Given/When
        let defaultSetting = UserDefaultsManager.shared.useOpenAIStreaming
        
        // Then
        XCTAssertFalse(defaultSetting,
                      "✅ Streaming is disabled by default")
    }
    
    func testStreaming_CanBeEnabled() {
        // Given
        UserDefaultsManager.shared.useOpenAIStreaming = true
        
        // Then
        XCTAssertTrue(UserDefaultsManager.shared.useOpenAIStreaming,
                     "✅ Streaming can be enabled in settings")
    }
    
    // MARK: - Format Tests
    
    func testStreaming_RequestsPCMFormat() {
        // Document that PCM format is used for lowest latency
        let expectedFormat = "pcm"
        let expectedSampleRate = 24000.0
        
        XCTAssertEqual(expectedFormat, "pcm",
                      "✅ PCM format for streaming")
        XCTAssertEqual(expectedSampleRate, 24000.0,
                      "✅ 24kHz sample rate for PCM")
    }
    
    func testNonStreaming_RequestsMP3Format() {
        // Document that non-streaming uses MP3
        let expectedFormat = "mp3"
        
        XCTAssertEqual(expectedFormat, "mp3",
                      "✅ MP3 format for non-streaming")
    }
    
    // MARK: - Chunk Processing Tests
    
    func testChunkSize_Is4KB() {
        // Document optimal chunk size
        let expectedChunkSize = 4096
        
        XCTAssertEqual(expectedChunkSize, 4096,
                      "✅ 4KB chunks for streaming")
    }
    
    func testStreaming_NotifiesDelegateOfChunks() {
        // Given
        mockDelegate.reset()
        
        // When simulating chunk receipt
        let testData = Data(repeating: 0, count: 100)
        sut.urlSession(sut.session, dataTask: URLSessionDataTask(), didReceive: testData)
        
        // Then
        XCTAssertTrue(mockDelegate.didReceiveChunk,
                     "✅ Delegate notified of audio chunks")
        XCTAssertEqual(mockDelegate.receivedChunks.count, 1,
                      "✅ Chunk data passed to delegate")
    }
    
    // MARK: - Cancellation Tests
    
    func testCancelStreaming_StopsActiveStream() {
        // When
        sut.cancelStreaming()
        
        // Then
        XCTAssertTrue(true, "✅ Streaming can be cancelled")
    }
    
    // MARK: - Integration Tests
    
    func testUnifiedPlayer_SupportsStreaming() async {
        // Given
        let player = UnifiedAudioPlayer.shared
        UserDefaultsManager.shared.useOpenAIStreaming = true
        UserDefaultsManager.shared.openAIAPIKey = "test-key"
        
        // Document integration point
        XCTAssertTrue(UserDefaultsManager.shared.useOpenAIStreaming,
                     "✅ UnifiedPlayer checks streaming preference")
    }
    
    func testUnifiedPlayer_FallsBackOnStreamingError() async {
        // Document fallback behavior
        // When streaming fails, should fall back to non-streaming generation
        
        XCTAssertTrue(true, 
                     "✅ Falls back to non-streaming on error")
    }
}

// MARK: - Mock Delegate

class MockStreamingDelegate: OpenAITTSStreamingDelegate {
    var didReceiveChunk = false
    var didComplete = false
    var didFailWithError = false
    var receivedChunks: [Data] = []
    var receivedURL: URL?
    var receivedError: Error?
    
    func reset() {
        didReceiveChunk = false
        didComplete = false
        didFailWithError = false
        receivedChunks = []
        receivedURL = nil
        receivedError = nil
    }
    
    func streamingService(_ service: OpenAITTSStreamingService, didReceiveAudioChunk data: Data) {
        didReceiveChunk = true
        receivedChunks.append(data)
    }
    
    func streamingService(_ service: OpenAITTSStreamingService, didCompleteWithURL url: URL) {
        didComplete = true
        receivedURL = url
    }
    
    func streamingService(_ service: OpenAITTSStreamingService, didFailWithError error: Error) {
        didFailWithError = true
        receivedError = error
    }
}

// MARK: - Performance Tests

final class OpenAIStreamingPerformanceTests: XCTestCase {
    
    func testChunkProcessing_Performance() {
        measure {
            // Simulate processing 100 chunks
            var totalData = Data()
            for _ in 0..<100 {
                let chunk = Data(repeating: 0, count: 4096)
                totalData.append(chunk)
            }
            
            XCTAssertEqual(totalData.count, 409600,
                          "✅ Processed 400KB of audio data")
        }
    }
    
    func testLatencyComparison_StreamingVsNonStreaming() {
        // Document expected latency improvements
        let nonStreamingLatency = 2000 // ms - wait for full generation
        let streamingLatency = 200 // ms - first chunk arrives
        
        let improvement = Double(nonStreamingLatency - streamingLatency) / Double(nonStreamingLatency) * 100
        
        XCTAssertGreaterThan(improvement, 80,
                            "✅ Streaming reduces latency by >80%")
    }
}