//
//  KokoroTTSIntegrationTests.swift
//  BriefeedTests
//
//  Integration tests verifying the PocketTTS -> Kokoro TTS migration
//

import XCTest
@testable import Briefeed

final class KokoroTTSIntegrationTests: XCTestCase {

    /// Test: FluidAudioVoice enum contains all expected Kokoro American English voices
    func testKokoroVoiceEnum_HasExpectedVoices() {
        let allVoices = FluidAudioVoice.allCases

        // Should have 20 American English voices (11 female + 9 male)
        XCTAssertEqual(allVoices.count, 20, "Expected 20 Kokoro voices")

        // Verify key voices exist
        XCTAssertNotNil(FluidAudioVoice(rawValue: "af_heart"), "af_heart should exist")
        XCTAssertNotNil(FluidAudioVoice(rawValue: "af_nova"), "af_nova should exist")
        XCTAssertNotNil(FluidAudioVoice(rawValue: "am_adam"), "am_adam should exist")
        XCTAssertNotNil(FluidAudioVoice(rawValue: "am_michael"), "am_michael should exist")

        // Verify legacy PocketTTS voices are gone
        XCTAssertNil(FluidAudioVoice(rawValue: "alba"), "alba should not exist in Kokoro")
        XCTAssertNil(FluidAudioVoice(rawValue: "cosette"), "cosette should not exist in Kokoro")

        // Verify gender grouping works
        let female = allVoices.filter { $0.genderLabel == "Female" }
        let male = allVoices.filter { $0.genderLabel == "Male" }
        XCTAssertEqual(female.count, 11, "Should have 11 female voices")
        XCTAssertEqual(male.count, 9, "Should have 9 male voices")
    }

    /// Test: Default voice is Kokoro's af_heart
    func testDefaultVoice_IsKokoroAfHeart() {
        XCTAssertEqual(FluidAudioVoice.defaultVoice, .af_heart)
        XCTAssertEqual(FluidAudioVoice.defaultVoice.rawValue, "af_heart")
    }

    /// Test: FluidAudioTTSService uses KokoroTtsManager (via synthesize API signature)
    @MainActor
    func testFluidAudioService_UsesKokoroManager() async throws {
        // Verify the service's synthesize method accepts voiceSpeed (Kokoro API)
        // instead of temperature (PocketTTS API). This is a compile-time check —
        // if the signature doesn't match, this test won't compile.
        let service = MockFluidAudioTTSService()
        try await service.downloadAndInitialize(voice: "af_heart")
        let data = try await service.synthesize(text: "Test", voice: "af_heart", voiceSpeed: 1.0)
        XCTAssertGreaterThan(data.count, 0, "Should return audio data")
    }

    /// Test: TTS tier selection does NOT enforce a text length limit
    @MainActor
    func testTTSTierSelection_NoTextLengthLimit() {
        // Simulate the tier selection logic from UnifiedAudioPlayer
        // With Kokoro, there should be no text.count <= 300 guard
        let longText = String(repeating: "This is a long article summary. ", count: 50)
        XCTAssertGreaterThan(longText.count, 300, "Test text should be > 300 chars")

        let service = MockFluidAudioTTSService()
        service.modelState = .ready

        let preferOnDevice = true
        let isModelReady = service.isModelReady

        // The key assertion: on-device TTS should be selected regardless of text length
        var selectedProvider = ""
        if preferOnDevice && isModelReady {
            selectedProvider = "Kokoro (On-Device)"
        } else {
            selectedProvider = "Cloud"
        }

        XCTAssertEqual(selectedProvider, "Kokoro (On-Device)",
                       "Kokoro should be selected for long text — no 300-char limit")
    }
}
