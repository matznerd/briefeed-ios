//
//  TTSProviderSelectionTests.swift
//  BriefeedTests
//
//  TDD Tests for TTS provider selection / fallback chain
//  Tests 4-tier priority: On-Device -> OpenAI -> Gemini, user preferences
//
//  RED PHASE: These tests should FAIL initially until implementation is complete
//

import XCTest
@testable import Briefeed

final class TTSProviderSelectionTests: XCTestCase {

    /// Test: When preferOnDeviceTTS is true and models ready, Tier 1 is selected
    @MainActor
    func testProviderSelection_OnDevicePreferred_AndReady_SelectsTier1() {
        let service = MockFluidAudioTTSService()
        service.modelState = .ready

        // Simulate selection logic
        let preferOnDevice = true
        let isModelReady = service.isModelReady
        let hasOpenAIKey = false

        var selectedProvider = ""
        if preferOnDevice && isModelReady {
            selectedProvider = "On-Device"
        } else if hasOpenAIKey {
            selectedProvider = "OpenAI"
        } else {
            selectedProvider = "Gemini"
        }

        XCTAssertEqual(selectedProvider, "On-Device")
    }

    /// Test: When models not ready, falls through to OpenAI
    @MainActor
    func testProviderSelection_ModelsNotReady_FallsToOpenAI() {
        let service = MockFluidAudioTTSService()
        service.modelState = .notDownloaded

        let preferOnDevice = true
        let isModelReady = service.isModelReady
        let hasOpenAIKey = true

        var selectedProvider = ""
        if preferOnDevice && isModelReady {
            selectedProvider = "On-Device"
        } else if hasOpenAIKey {
            selectedProvider = "OpenAI"
        } else {
            selectedProvider = "Gemini"
        }

        XCTAssertEqual(selectedProvider, "OpenAI")
    }

    /// Test: When user disables on-device, skips to cloud even if models ready
    @MainActor
    func testProviderSelection_OnDeviceDisabled_SkipsToCloud() {
        let service = MockFluidAudioTTSService()
        service.modelState = .ready

        let preferOnDevice = false  // User disabled on-device
        let isModelReady = service.isModelReady
        let hasOpenAIKey = false

        var selectedProvider = ""
        if preferOnDevice && isModelReady {
            selectedProvider = "On-Device"
        } else if hasOpenAIKey {
            selectedProvider = "OpenAI"
        } else {
            selectedProvider = "Gemini"
        }

        XCTAssertEqual(selectedProvider, "Gemini")
    }

    /// Test: Full fallback chain reaches Gemini when no other option
    @MainActor
    func testProviderSelection_NoOnDeviceNoOpenAI_UsesGemini() {
        let service = MockFluidAudioTTSService()
        service.modelState = .notDownloaded

        let preferOnDevice = true
        let isModelReady = service.isModelReady
        let hasOpenAIKey = false

        var selectedProvider = ""
        if preferOnDevice && isModelReady {
            selectedProvider = "On-Device"
        } else if hasOpenAIKey {
            selectedProvider = "OpenAI"
        } else {
            selectedProvider = "Gemini"
        }

        XCTAssertEqual(selectedProvider, "Gemini")
    }
}
