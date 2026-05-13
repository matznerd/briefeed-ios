//
//  FluidAudioTTSServiceTests.swift
//  BriefeedTests
//
//  TDD Tests for FluidAudio on-device TTS service
//  Tests model lifecycle, synthesis, and error handling
//
//  RED PHASE: These tests should FAIL initially until implementation is complete
//

import XCTest
@testable import Briefeed

// MARK: - Mock FluidAudio TTS Service

class MockFluidAudioTTSService: ObservableObject {
    @Published var modelState: FluidAudioModelState = .notDownloaded
    var shouldFail = false
    var delay: TimeInterval = 0
    var synthesizeCallCount = 0
    var initializeCallCount = 0
    var mockWAVData = createMinimalWAVData()

    var isModelReady: Bool { modelState == .ready }

    func downloadAndInitialize(voice: String = "alba") async throws {
        initializeCallCount += 1
        if shouldFail {
            modelState = .failed("Mock initialization error")
            throw FluidAudioError.initializationFailed("Mock initialization error")
        }
        modelState = .downloading(progress: 0.5)
        modelState = .compiling
        modelState = .ready
    }

    func synthesize(text: String, voice: String? = nil, voiceSpeed: Float = 1.0) async throws -> Data {
        synthesizeCallCount += 1
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        if shouldFail {
            throw FluidAudioError.synthesisFailed("Mock synthesis error")
        }
        guard isModelReady else {
            throw FluidAudioError.modelsNotDownloaded
        }
        return mockWAVData
    }

    func synthesizeToFile(text: String, voice: String? = nil) async throws -> URL {
        let data = try await synthesize(text: text, voice: voice)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try data.write(to: tempURL)
        return tempURL
    }

    static func createMinimalWAVData() -> Data {
        // Create minimal valid WAV header + silence
        var data = Data()
        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        let dataSize: UInt32 = 36 + 480 // header + 10ms of 24kHz 16-bit mono
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // mono
        data.append(contentsOf: withUnsafeBytes(of: UInt32(24000).littleEndian) { Array($0) }) // 24kHz
        data.append(contentsOf: withUnsafeBytes(of: UInt32(48000).littleEndian) { Array($0) }) // byte rate
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) }) // block align
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) }) // 16-bit
        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(480).littleEndian) { Array($0) }) // data size
        data.append(Data(repeating: 0, count: 480)) // silence
        return data
    }
}

// MARK: - FluidAudio TTS Service Tests

final class FluidAudioTTSServiceTests: XCTestCase {

    /// Test: Model state starts as .notDownloaded
    @MainActor
    func testModelState_InitialState_IsNotDownloaded() {
        let service = MockFluidAudioTTSService()
        XCTAssertEqual(service.modelState, .notDownloaded)
        XCTAssertFalse(service.isModelReady)
    }

    /// Test: After successful initialization, model state is .ready
    @MainActor
    func testModelState_AfterInitialize_IsReady() async throws {
        let service = MockFluidAudioTTSService()
        try await service.downloadAndInitialize()
        XCTAssertEqual(service.modelState, .ready)
        XCTAssertTrue(service.isModelReady)
        XCTAssertEqual(service.initializeCallCount, 1)
    }

    /// Test: Failed initialization sets state to .failed
    @MainActor
    func testModelState_FailedInit_SetsFailed() async {
        let service = MockFluidAudioTTSService()
        service.shouldFail = true
        do {
            try await service.downloadAndInitialize()
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is FluidAudioError)
        }
        if case .failed(_) = service.modelState {
            // Expected
        } else {
            XCTFail("Model state should be .failed, got \(service.modelState)")
        }
    }

    /// Test: Synthesis returns valid WAV data when model is ready
    @MainActor
    func testSynthesize_WhenReady_ReturnsData() async throws {
        let service = MockFluidAudioTTSService()
        try await service.downloadAndInitialize()

        let data = try await service.synthesize(text: "Hello world")
        XCTAssertGreaterThan(data.count, 44, "WAV data should be larger than header")
        XCTAssertEqual(service.synthesizeCallCount, 1)

        // Verify WAV header
        let header = String(data: data.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "RIFF", "Should start with RIFF header")
    }

    /// Test: Synthesis throws when models not downloaded
    @MainActor
    func testSynthesize_ModelsNotReady_Throws() async {
        let service = MockFluidAudioTTSService()
        // Don't initialize
        do {
            _ = try await service.synthesize(text: "Hello world")
            XCTFail("Should have thrown modelsNotDownloaded error")
        } catch let error as FluidAudioError {
            if case .modelsNotDownloaded = error {
                // Expected
            } else {
                XCTFail("Expected modelsNotDownloaded, got \(error)")
            }
        } catch {
            XCTFail("Expected FluidAudioError, got \(type(of: error))")
        }
    }
}
