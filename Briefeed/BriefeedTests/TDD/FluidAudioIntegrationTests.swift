//
//  FluidAudioIntegrationTests.swift
//  BriefeedTests
//
//  TDD Tests for FluidAudio integration with the Briefeed pipeline
//  Tests full pipeline, GenerationPhase display, and model state equatable
//
//  RED PHASE: These tests should FAIL initially until implementation is complete
//

import XCTest
@testable import Briefeed

final class FluidAudioIntegrationTests: XCTestCase {

    /// Test: Full synthesis pipeline mock - init, synthesize, get file URL
    @MainActor
    func testFullPipeline_InitAndSynthesize_ProducesFile() async throws {
        let service = MockFluidAudioTTSService()

        // Initialize
        try await service.downloadAndInitialize()
        XCTAssertTrue(service.isModelReady)

        // Synthesize to file
        let fileURL = try await service.synthesizeToFile(text: "Breaking news today.")

        // Verify file exists and has content
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let data = try Data(contentsOf: fileURL)
        XCTAssertGreaterThan(data.count, 44, "File should have WAV data beyond header")

        // Cleanup
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Test: GenerationPhase display messages are correct for on-device
    @MainActor
    func testGenerationPhase_OnDeviceMessages() {
        let phase = GenerationPhase.generatingAudio(provider: "On-Device")
        XCTAssertTrue(phase.displayMessage.contains("On-Device"))
        XCTAssertTrue(phase.shortMessage.contains("On-Device"))
        XCTAssertTrue(phase.isActive)
    }

    /// Test: FluidAudioModelState equatable works correctly
    func testModelState_Equatable() {
        XCTAssertEqual(FluidAudioModelState.notDownloaded, FluidAudioModelState.notDownloaded)
        XCTAssertEqual(FluidAudioModelState.ready, FluidAudioModelState.ready)
        XCTAssertEqual(FluidAudioModelState.compiling, FluidAudioModelState.compiling)
        XCTAssertEqual(FluidAudioModelState.downloading(progress: 0.5), FluidAudioModelState.downloading(progress: 0.5))
        XCTAssertNotEqual(FluidAudioModelState.downloading(progress: 0.5), FluidAudioModelState.downloading(progress: 0.8))
        XCTAssertEqual(FluidAudioModelState.failed("error"), FluidAudioModelState.failed("error"))
        XCTAssertNotEqual(FluidAudioModelState.ready, FluidAudioModelState.notDownloaded)
    }
}
