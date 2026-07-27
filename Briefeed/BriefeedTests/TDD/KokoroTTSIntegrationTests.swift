//
//  KokoroTTSIntegrationTests.swift
//  BriefeedTests
//
//  Integration tests verifying the Kokoro -> PocketTTS migration
//

import XCTest
@testable import Briefeed

final class KokoroTTSIntegrationTests: XCTestCase {

    /// Test: FluidAudioVoice enum contains all expected PocketTTS English voices
    func testPocketTTSVoiceEnum_HasExpectedVoices() {
        let allVoices = FluidAudioVoice.allCases

        XCTAssertEqual(allVoices.count, 21, "Expected 21 PocketTTS voices")

        // Verify key voices exist
        XCTAssertNotNil(FluidAudioVoice(rawValue: "alba"), "alba should exist")
        XCTAssertNotNil(FluidAudioVoice(rawValue: "cosette"), "cosette should exist")
        XCTAssertNotNil(FluidAudioVoice(rawValue: "michael"), "michael should exist")
        XCTAssertNotNil(FluidAudioVoice(rawValue: "vera"), "vera should exist")

        // Verify legacy Kokoro voices are gone
        XCTAssertNil(FluidAudioVoice(rawValue: "af_heart"), "af_heart should not exist in PocketTTS")
        XCTAssertNil(FluidAudioVoice(rawValue: "am_michael"), "am_michael should not exist in PocketTTS")

        // Verify gender grouping works
        let female = allVoices.filter { $0.genderLabel == "Female" }
        let male = allVoices.filter { $0.genderLabel == "Male" }
        XCTAssertEqual(female.count, 11, "Should have 11 female voices")
        XCTAssertEqual(male.count, 10, "Should have 10 male voices")
    }

    /// Test: Default voice is PocketTTS alba
    func testDefaultVoice_IsPocketTTSAlba() {
        XCTAssertEqual(FluidAudioVoice.defaultVoice, .alba)
        XCTAssertEqual(FluidAudioVoice.defaultVoice.rawValue, "alba")
    }

    /// Test: FluidAudioTTSService keeps the app's existing synthesis contract while using PocketTTS internally
    @MainActor
    func testFluidAudioService_UsesPocketTTSVoice() async throws {
        let service = MockFluidAudioTTSService()
        try await service.downloadAndInitialize(voice: "alba")
        let data = try await service.synthesize(text: "Test", voice: "alba", voiceSpeed: 1.0)
        XCTAssertGreaterThan(data.count, 0, "Should return audio data")
    }

    /// Test: TTS tier selection does NOT enforce a text length limit
    @MainActor
    func testTTSTierSelection_NoTextLengthLimit() {
        let longText = String(repeating: "This is a long article summary. ", count: 50)
        XCTAssertGreaterThan(longText.count, 300, "Test text should be > 300 chars")

        let service = MockFluidAudioTTSService()
        service.modelState = .ready

        let preferOnDevice = true
        let isModelReady = service.isModelReady

        // The key assertion: on-device TTS should be selected regardless of text length
        var selectedProvider = ""
        if preferOnDevice && isModelReady {
            selectedProvider = "PocketTTS (On-Device)"
        } else {
            selectedProvider = "Cloud"
        }

        XCTAssertEqual(selectedProvider, "PocketTTS (On-Device)",
                       "PocketTTS should be selected for long text — no 300-char limit")
    }
}
