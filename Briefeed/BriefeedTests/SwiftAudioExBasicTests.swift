//
//  SwiftAudioExBasicTests.swift
//  BriefeedTests
//
//  Basic tests to verify SwiftAudioEx classes compile and can be instantiated
//

import XCTest
@testable import Briefeed

class SwiftAudioExBasicTests: XCTestCase {
    
    func testCanCreateSwiftAudioExService() {
        // This should fail since we haven't implemented the actual functionality
        let service = SwiftAudioExService()
        XCTAssertNotNil(service)
        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(service.state, SwiftAudioPlayerState.idle)
    }
    
    func testCanCreateTTSGeneratorService() {
        let tts = TTSGeneratorService()
        XCTAssertNotNil(tts)
        XCTAssertEqual(tts.cacheSize, 0)
    }
    
    func testCanCreateUnifiedAudioPlayer() {
        let player = UnifiedAudioPlayer()
        XCTAssertNotNil(player)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.rate, 1.0)
    }
    
    func testTTSGenerateAudioFileShouldFail() async throws {
        // This should fail since we return empty Data() in the implementation
        let tts = TTSGeneratorService()
        
        do {
            let url = try await tts.generateAudioFile(from: "Test text")
            // If we get here, the test should fail because we expect it to fail
            XCTFail("Expected TTS generation to fail but it succeeded with URL: \(url)")
        } catch {
            // Expected to fail
            XCTAssertNotNil(error)
        }
    }
    
    func testPlayAudioShouldDoNothing() async throws {
        // Since SwiftAudioEx is not actually integrated, play should do nothing
        let service = SwiftAudioExService()
        let testURL = URL(string: "https://example.com/audio.mp3")!
        
        try await service.play(url: testURL)
        
        // These assertions show that without real implementation, state doesn't change properly
        XCTAssertTrue(service.isPlaying, "Service should report playing even though it's fake")
        XCTAssertEqual(service.state, SwiftAudioPlayerState.playing)
        XCTAssertEqual(service.duration, 0, "Duration should be 0 since no real audio loaded")
    }
}