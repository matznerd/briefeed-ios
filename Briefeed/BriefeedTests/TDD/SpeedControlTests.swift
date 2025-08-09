import XCTest
@testable import Briefeed

// MARK: - TDD: Speed Control Tests
// Critical requirement: Support playback speeds up to 4x

final class SpeedControlTests: XCTestCase {
    
    // MARK: - Speed Setting Tests
    
    func testDefaultPlaybackSpeed() {
        // Given
        let service = AudioStreamingService.shared
        
        // Then - default should be 1.0x
        XCTAssertEqual(service.playbackRate, 1.0)
    }
    
    func testSetPlaybackSpeedBeforePlaying() {
        // Given
        let service = AudioStreamingService.shared
        
        // When
        service.setRate(1.5)
        
        // Then
        XCTAssertEqual(service.playbackRate, 1.5)
        
        // And when we play
        let testURL = URL(string: "https://example.com/audio.mp3")!
        service.play(url: testURL)
        
        // Speed should be maintained
        XCTAssertEqual(service.playbackRate, 1.5)
    }
    
    func testSetPlaybackSpeedWhilePlaying() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        service.play(url: testURL)
        
        // When
        service.setRate(2.0)
        
        // Then
        XCTAssertEqual(service.playbackRate, 2.0)
        XCTAssertTrue(service.isPlaying, "Should continue playing")
    }
    
    func testAllStandardSpeeds() {
        // Given
        let service = AudioStreamingService.shared
        let standardSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        
        for speed in standardSpeeds {
            // When
            service.setRate(speed)
            
            // Then
            XCTAssertEqual(
                service.playbackRate,
                speed,
                accuracy: 0.01,
                "Should support \(speed)x speed"
            )
        }
    }
    
    func testHighSpeedPlayback() {
        // Given - CRITICAL: Must support up to 4x
        let service = AudioStreamingService.shared
        let highSpeeds: [Float] = [2.5, 3.0, 3.5, 4.0]
        
        for speed in highSpeeds {
            // When
            service.setRate(speed)
            
            // Then
            XCTAssertEqual(
                service.playbackRate,
                speed,
                accuracy: 0.01,
                "MUST support \(speed)x speed for power users"
            )
        }
    }
    
    func testVeryHighSpeedPlayback() {
        // Given - test beyond 4x
        let service = AudioStreamingService.shared
        
        // When
        service.setRate(5.0)
        
        // Then - should either support or clamp to max
        XCTAssertGreaterThanOrEqual(service.playbackRate, 4.0)
        XCTAssertLessThanOrEqual(service.playbackRate, 5.0)
    }
    
    func testSlowSpeedPlayback() {
        // Given
        let service = AudioStreamingService.shared
        let slowSpeeds: [Float] = [0.25, 0.5, 0.75]
        
        for speed in slowSpeeds {
            // When
            service.setRate(speed)
            
            // Then
            XCTAssertEqual(
                service.playbackRate,
                speed,
                accuracy: 0.01,
                "Should support \(speed)x slow speed"
            )
        }
    }
    
    // MARK: - Speed Persistence Tests
    
    func testSpeedPersistsAcrossPauseResume() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        service.play(url: testURL)
        service.setRate(2.5)
        
        // When
        service.pause()
        service.resume()
        
        // Then
        XCTAssertEqual(service.playbackRate, 2.5, "Speed should persist")
    }
    
    func testSpeedResetsOnStop() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        service.play(url: testURL)
        service.setRate(3.0)
        
        // When
        service.stop()
        
        // Then - depends on requirements
        // Option 1: Reset to default
        // XCTAssertEqual(service.playbackRate, 1.0)
        // Option 2: Remember last speed
        XCTAssertEqual(service.playbackRate, 3.0, "Should remember speed preference")
    }
    
    // MARK: - Speed with Different Content Tests
    
    func testSpeedWithTTSAudio() {
        // Given
        let service = AudioStreamingService.shared
        let ttsURL = URL(fileURLWithPath: "/tmp/tts-audio.mp3")
        
        // When
        service.play(url: ttsURL)
        service.setRate(3.5) // High speed for TTS
        
        // Then
        XCTAssertEqual(service.playbackRate, 3.5)
        XCTAssertTrue(service.maintainsPitch, "TTS should maintain pitch at high speed")
    }
    
    func testSpeedWithPodcastStreaming() {
        // Given
        let service = AudioStreamingService.shared
        let podcastURL = URL(string: "https://podcast.example.com/episode.mp3")!
        
        // When
        service.play(url: podcastURL)
        service.setRate(2.0) // Common podcast speed
        
        // Then
        XCTAssertEqual(service.playbackRate, 2.0)
    }
    
    // MARK: - Speed Change Performance Tests
    
    func testSpeedChangeIsInstant() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        service.play(url: testURL)
        
        // When
        let start = CFAbsoluteTimeGetCurrent()
        service.setRate(3.0)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        // Then
        XCTAssertLessThan(elapsed, 0.01, "Speed change should be instant")
        XCTAssertEqual(service.playbackRate, 3.0)
    }
    
    func testRapidSpeedChanges() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        service.play(url: testURL)
        
        // When - rapid speed changes
        let speeds: [Float] = [1.0, 2.0, 1.5, 3.0, 1.0, 4.0]
        for speed in speeds {
            service.setRate(speed)
            XCTAssertEqual(service.playbackRate, speed, accuracy: 0.01)
        }
        
        // Then - should handle all changes
        XCTAssertTrue(service.isPlaying, "Should still be playing")
    }
    
    // MARK: - Pitch Correction Tests
    
    func testPitchCorrectionEnabled() {
        // Given
        let service = AudioStreamingService.shared
        
        // Then
        XCTAssertTrue(service.maintainsPitch, "Pitch correction should be enabled by default")
    }
    
    func testPitchCorrectionAtHighSpeed() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = URL(string: "https://example.com/audio.mp3")!
        
        // When
        service.play(url: testURL)
        service.setRate(4.0)
        
        // Then
        XCTAssertTrue(service.maintainsPitch, "Should maintain natural pitch at 4x speed")
    }
    
    // MARK: - Speed Preferences Tests
    
    func testSaveSpeedPreference() {
        // Given
        let service = AudioStreamingService.shared
        
        // When
        service.setRate(2.5)
        service.saveSpeedPreference()
        
        // Then
        XCTAssertEqual(
            UserDefaults.standard.float(forKey: "PlaybackSpeed"),
            2.5,
            "Should save speed preference"
        )
    }
    
    func testLoadSpeedPreference() {
        // Given
        UserDefaults.standard.set(3.0, forKey: "PlaybackSpeed")
        
        // When
        let service = AudioStreamingService.shared
        service.loadSpeedPreference()
        
        // Then
        XCTAssertEqual(service.playbackRate, 3.0, "Should load saved speed")
    }
    
    func testSpeedPreferencePerContentType() {
        // Given
        let service = AudioStreamingService.shared
        
        // When - set different speeds for different content
        service.setRate(3.5, for: .tts)
        service.setRate(2.0, for: .podcast)
        service.setRate(1.0, for: .music)
        
        // Then
        XCTAssertEqual(service.getRate(for: .tts), 3.5)
        XCTAssertEqual(service.getRate(for: .podcast), 2.0)
        XCTAssertEqual(service.getRate(for: .music), 1.0)
    }
}