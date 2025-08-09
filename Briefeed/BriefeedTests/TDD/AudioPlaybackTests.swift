import XCTest
@testable import Briefeed

// MARK: - TDD: Audio Playback Tests
// Written BEFORE implementation - these define our requirements

final class AudioPlaybackTests: XCTestCase {
    
    // MARK: - Basic Playback Tests
    
    func testPlayAudioFromURL() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        
        // When
        service.play(url: testURL)
        
        // Then
        XCTAssertEqual(service.currentURL, testURL, "Should set current URL")
        XCTAssertTrue(service.isPlaying, "Should be playing")
        XCTAssertFalse(service.isPaused, "Should not be paused")
        XCTAssertEqual(service.playbackState, .playing, "State should be playing")
    }
    
    func testPlayLocalAudioFile() {
        // Given
        let service = AudioStreamingService.shared
        let localURL = URL(fileURLWithPath: "/path/to/local/audio.mp3")
        
        // When
        service.play(url: localURL)
        
        // Then
        XCTAssertEqual(service.currentURL, localURL)
        XCTAssertTrue(service.isPlaying)
        XCTAssertEqual(service.playbackState, .playing)
    }
    
    func testPausePlayback() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        service.play(url: testURL)
        
        // When
        service.pause()
        
        // Then
        XCTAssertFalse(service.isPlaying, "Should not be playing")
        XCTAssertTrue(service.isPaused, "Should be paused")
        XCTAssertEqual(service.playbackState, .paused, "State should be paused")
        XCTAssertEqual(service.currentURL, testURL, "URL should remain set")
    }
    
    func testResumePlayback() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        service.play(url: testURL)
        service.pause()
        
        // When
        service.resume()
        
        // Then
        XCTAssertTrue(service.isPlaying, "Should be playing")
        XCTAssertFalse(service.isPaused, "Should not be paused")
        XCTAssertEqual(service.playbackState, .playing, "State should be playing")
    }
    
    func testStopPlayback() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        service.play(url: testURL)
        
        // When
        service.stop()
        
        // Then
        XCTAssertFalse(service.isPlaying, "Should not be playing")
        XCTAssertFalse(service.isPaused, "Should not be paused")
        XCTAssertEqual(service.playbackState, .stopped, "State should be stopped")
        XCTAssertNil(service.currentURL, "URL should be cleared")
        XCTAssertEqual(service.currentTime, 0, "Time should reset to 0")
    }
    
    // MARK: - Progress Tracking Tests
    
    func testGetCurrentPlaybackTime() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        
        // When
        service.play(url: testURL)
        // Simulate some playback time
        service.seek(to: 30.0)
        
        // Then
        XCTAssertEqual(service.currentTime, 30.0, accuracy: 0.1)
    }
    
    func testGetTotalDuration() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        
        // When
        service.play(url: testURL)
        // Duration should be available after loading
        
        // Then
        XCTAssertGreaterThan(service.duration, 0, "Should have duration")
    }
    
    func testSeekToPosition() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        service.play(url: testURL)
        
        // When
        service.seek(to: 45.5)
        
        // Then
        XCTAssertEqual(service.currentTime, 45.5, accuracy: 0.5)
    }
    
    func testSeekBeyondDuration() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        service.play(url: testURL)
        let duration = 120.0 // assume 2 minute audio
        
        // When - seek beyond duration
        service.seek(to: 200.0)
        
        // Then - should clamp to duration
        XCTAssertLessThanOrEqual(service.currentTime, duration)
    }
    
    // MARK: - Skip Controls Tests
    
    func testSkipForward() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        service.play(url: testURL)
        service.seek(to: 30.0)
        
        // When
        service.skipForward(seconds: 15)
        
        // Then
        XCTAssertEqual(service.currentTime, 45.0, accuracy: 0.5)
    }
    
    func testSkipBackward() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        service.play(url: testURL)
        service.seek(to: 30.0)
        
        // When
        service.skipBackward(seconds: 10)
        
        // Then
        XCTAssertEqual(service.currentTime, 20.0, accuracy: 0.5)
    }
    
    func testSkipBackwardFromStart() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        service.play(url: testURL)
        service.seek(to: 5.0)
        
        // When - skip back more than current position
        service.skipBackward(seconds: 10)
        
        // Then - should clamp to 0
        XCTAssertEqual(service.currentTime, 0, accuracy: 0.1)
    }
    
    // MARK: - Error Handling Tests
    
    func testPlayInvalidURL() {
        // Given
        let service = AudioStreamingService.shared
        let invalidURL = URL(string: "https://invalid.url/notfound.mp3")!
        
        // When
        service.play(url: invalidURL)
        
        // Then
        XCTAssertEqual(service.playbackState, .failed)
        XCTAssertNotNil(service.lastError)
        XCTAssertFalse(service.isPlaying)
    }
    
    func testPlaybackInterruption() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        service.play(url: testURL)
        
        // When - simulate interruption (phone call)
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began]
        )
        
        // Then
        XCTAssertTrue(service.isPaused || !service.isPlaying)
        XCTAssertEqual(service.playbackState, .interrupted)
    }
}