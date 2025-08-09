import XCTest
@testable import Briefeed

// MARK: - TDD: Audio State Transition Tests
// Define all valid state transitions and expected behaviors

final class AudioStateTransitionTests: XCTestCase {
    
    // MARK: - State Definitions
    
    func testInitialState() {
        // Given
        let service = AudioStreamingService.shared
        
        // Then
        XCTAssertEqual(service.playbackState, .idle)
        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.isPaused)
        XCTAssertFalse(service.isLoading)
        XCTAssertNil(service.currentURL)
    }
    
    // MARK: - Valid State Transitions
    
    func testIdleToLoading() {
        // Given
        let service = AudioStreamingService.shared
        XCTAssertEqual(service.playbackState, .idle)
        
        // When
        service.startLoading(url: URL(string: "https://example.com/audio.mp3")!)
        
        // Then
        XCTAssertEqual(service.playbackState, .loading)
        XCTAssertTrue(service.isLoading)
        XCTAssertFalse(service.isPlaying)
    }
    
    func testLoadingToPlaying() {
        // Given
        let service = AudioStreamingService.shared
        service.startLoading(url: URL(string: "https://example.com/audio.mp3")!)
        XCTAssertEqual(service.playbackState, .loading)
        
        // When
        service.transitionToPlaying()
        
        // Then
        XCTAssertEqual(service.playbackState, .playing)
        XCTAssertTrue(service.isPlaying)
        XCTAssertFalse(service.isLoading)
        XCTAssertFalse(service.isPaused)
    }
    
    func testPlayingToPaused() {
        // Given
        let service = AudioStreamingService.shared
        let url = URL(string: "https://example.com/audio.mp3")!
        service.play(url: url)
        XCTAssertEqual(service.playbackState, .playing)
        
        // When
        service.pause()
        
        // Then
        XCTAssertEqual(service.playbackState, .paused)
        XCTAssertFalse(service.isPlaying)
        XCTAssertTrue(service.isPaused)
        XCTAssertEqual(service.currentURL, url, "URL should be maintained")
    }
    
    func testPausedToPlaying() {
        // Given
        let service = AudioStreamingService.shared
        service.play(url: URL(string: "https://example.com/audio.mp3")!)
        service.pause()
        XCTAssertEqual(service.playbackState, .paused)
        
        // When
        service.resume()
        
        // Then
        XCTAssertEqual(service.playbackState, .playing)
        XCTAssertTrue(service.isPlaying)
        XCTAssertFalse(service.isPaused)
    }
    
    func testPlayingToStopped() {
        // Given
        let service = AudioStreamingService.shared
        service.play(url: URL(string: "https://example.com/audio.mp3")!)
        XCTAssertEqual(service.playbackState, .playing)
        
        // When
        service.stop()
        
        // Then
        XCTAssertEqual(service.playbackState, .stopped)
        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.isPaused)
        XCTAssertNil(service.currentURL)
    }
    
    func testStoppedToIdle() {
        // Given
        let service = AudioStreamingService.shared
        service.play(url: URL(string: "https://example.com/audio.mp3")!)
        service.stop()
        XCTAssertEqual(service.playbackState, .stopped)
        
        // When
        service.reset()
        
        // Then
        XCTAssertEqual(service.playbackState, .idle)
    }
    
    // MARK: - Error State Transitions
    
    func testLoadingToFailed() {
        // Given
        let service = AudioStreamingService.shared
        service.startLoading(url: URL(string: "https://invalid.url/notfound.mp3")!)
        XCTAssertEqual(service.playbackState, .loading)
        
        // When
        let error = AudioError.loadFailed(reason: "404 Not Found")
        service.transitionToFailed(error: error)
        
        // Then
        XCTAssertEqual(service.playbackState, .failed)
        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.isLoading)
        XCTAssertNotNil(service.lastError)
        XCTAssertEqual(service.lastError?.localizedDescription, error.localizedDescription)
    }
    
    func testFailedToIdle() {
        // Given
        let service = AudioStreamingService.shared
        service.transitionToFailed(error: AudioError.loadFailed(reason: "Test"))
        XCTAssertEqual(service.playbackState, .failed)
        
        // When
        service.reset()
        
        // Then
        XCTAssertEqual(service.playbackState, .idle)
        XCTAssertNil(service.lastError)
    }
    
    func testPlayingToFailed() {
        // Given
        let service = AudioStreamingService.shared
        service.play(url: URL(string: "https://example.com/audio.mp3")!)
        XCTAssertEqual(service.playbackState, .playing)
        
        // When - simulate network error
        service.transitionToFailed(error: AudioError.networkError)
        
        // Then
        XCTAssertEqual(service.playbackState, .failed)
        XCTAssertFalse(service.isPlaying)
        XCTAssertNotNil(service.lastError)
    }
    
    // MARK: - Interruption States
    
    func testPlayingToInterrupted() {
        // Given
        let service = AudioStreamingService.shared
        service.play(url: URL(string: "https://example.com/audio.mp3")!)
        XCTAssertEqual(service.playbackState, .playing)
        
        // When - phone call interruption
        service.handleInterruption(type: .began)
        
        // Then
        XCTAssertEqual(service.playbackState, .interrupted)
        XCTAssertFalse(service.isPlaying)
        XCTAssertTrue(service.wasPlayingBeforeInterruption)
    }
    
    func testInterruptedToPlaying() {
        // Given
        let service = AudioStreamingService.shared
        service.play(url: URL(string: "https://example.com/audio.mp3")!)
        service.handleInterruption(type: .began)
        XCTAssertEqual(service.playbackState, .interrupted)
        
        // When - interruption ends
        service.handleInterruption(type: .ended)
        
        // Then - should resume if was playing
        XCTAssertEqual(service.playbackState, .playing)
        XCTAssertTrue(service.isPlaying)
    }
    
    func testPausedToInterrupted() {
        // Given
        let service = AudioStreamingService.shared
        service.play(url: URL(string: "https://example.com/audio.mp3")!)
        service.pause()
        XCTAssertEqual(service.playbackState, .paused)
        
        // When
        service.handleInterruption(type: .began)
        
        // Then
        XCTAssertEqual(service.playbackState, .interrupted)
        XCTAssertFalse(service.wasPlayingBeforeInterruption)
    }
    
    func testInterruptedToPaused() {
        // Given - was paused before interruption
        let service = AudioStreamingService.shared
        service.play(url: URL(string: "https://example.com/audio.mp3")!)
        service.pause()
        service.handleInterruption(type: .began)
        XCTAssertFalse(service.wasPlayingBeforeInterruption)
        
        // When
        service.handleInterruption(type: .ended)
        
        // Then - should remain paused
        XCTAssertEqual(service.playbackState, .paused)
        XCTAssertFalse(service.isPlaying)
    }
    
    // MARK: - Buffering States
    
    func testPlayingToBuffering() {
        // Given
        let service = AudioStreamingService.shared
        service.play(url: URL(string: "https://example.com/audio.mp3")!)
        XCTAssertEqual(service.playbackState, .playing)
        
        // When - buffer runs out
        service.transitionToBuffering()
        
        // Then
        XCTAssertEqual(service.playbackState, .buffering)
        XCTAssertTrue(service.isBuffering)
        XCTAssertFalse(service.isPlaying)
    }
    
    func testBufferingToPlaying() {
        // Given
        let service = AudioStreamingService.shared
        service.play(url: URL(string: "https://example.com/audio.mp3")!)
        service.transitionToBuffering()
        XCTAssertEqual(service.playbackState, .buffering)
        
        // When - buffer fills
        service.transitionToPlaying()
        
        // Then
        XCTAssertEqual(service.playbackState, .playing)
        XCTAssertFalse(service.isBuffering)
        XCTAssertTrue(service.isPlaying)
    }
    
    // MARK: - Finished State
    
    func testPlayingToFinished() {
        // Given
        let service = AudioStreamingService.shared
        service.play(url: URL(string: "https://example.com/audio.mp3")!)
        XCTAssertEqual(service.playbackState, .playing)
        
        // When - audio reaches end
        service.transitionToFinished()
        
        // Then
        XCTAssertEqual(service.playbackState, .finished)
        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(service.currentTime, service.duration)
    }
    
    func testFinishedToIdle() {
        // Given
        let service = AudioStreamingService.shared
        service.play(url: URL(string: "https://example.com/audio.mp3")!)
        service.transitionToFinished()
        XCTAssertEqual(service.playbackState, .finished)
        
        // When
        service.reset()
        
        // Then
        XCTAssertEqual(service.playbackState, .idle)
        XCTAssertEqual(service.currentTime, 0)
    }
    
    // MARK: - Invalid State Transitions
    
    func testCannotPauseWhenNotPlaying() {
        // Given
        let service = AudioStreamingService.shared
        XCTAssertEqual(service.playbackState, .idle)
        
        // When
        service.pause()
        
        // Then - should not change state
        XCTAssertEqual(service.playbackState, .idle)
        XCTAssertFalse(service.isPaused)
    }
    
    func testCannotResumeWhenNotPaused() {
        // Given
        let service = AudioStreamingService.shared
        XCTAssertEqual(service.playbackState, .idle)
        
        // When
        service.resume()
        
        // Then - should not change state
        XCTAssertEqual(service.playbackState, .idle)
        XCTAssertFalse(service.isPlaying)
    }
    
    // MARK: - State Change Notifications
    
    func testStateChangeNotifications() {
        // Given
        let service = AudioStreamingService.shared
        let expectation = XCTestExpectation(description: "State change notification")
        var receivedStates: [AudioPlaybackState] = []
        
        let observer = NotificationCenter.default.addObserver(
            forName: .audioPlaybackStateChanged,
            object: service,
            queue: .main
        ) { notification in
            if let state = notification.userInfo?["state"] as? AudioPlaybackState {
                receivedStates.append(state)
                if receivedStates.count == 3 {
                    expectation.fulfill()
                }
            }
        }
        
        // When
        service.play(url: URL(string: "https://example.com/audio.mp3")!)
        service.pause()
        service.resume()
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedStates, [.playing, .paused, .playing])
        
        NotificationCenter.default.removeObserver(observer)
    }
}