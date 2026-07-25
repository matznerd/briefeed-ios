import CryptoKit
import Foundation
import Testing
@testable import Briefeed

@Suite("Radio transcript asset service")
struct RadioTranscriptAssetServiceTests {
    @Test func acquisitionFingerprintsAndIndexesExactDownloadedBytes() async throws {
        let harness = try AssetHarness()
        defer { harness.cleanup() }
        let request = harness.request(episodeID: "first")

        let asset = try await harness.service.acquire(request)

        let expected = SHA256.hash(data: Data("audio-first".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(asset.episodeKey == request.episodeKey)
        #expect(asset.assetFingerprint == expected)
        #expect(asset.originalURL == request.remoteURL)
        #expect(asset.finalURL == URL(string: "https://cdn.example.com/first.mp3"))
        #expect(asset.audioDurationSeconds == 30)
        #expect(FileManager.default.fileExists(atPath: asset.localFileURL.path))
        #expect(try Data(contentsOf: asset.localFileURL) == Data("audio-first".utf8))
    }

    @Test func aValidCacheHitNeverDownloadsAgain() async throws {
        let harness = try AssetHarness()
        defer { harness.cleanup() }
        let request = harness.request(episodeID: "cached")

        let first = try await harness.service.acquire(request)
        let second = try await harness.service.acquire(request)

        #expect(first.assetFingerprint == second.assetFingerprint)
        #expect(await harness.downloader.callCount == 1)
    }

    @Test func concurrentPlaybackAndTranscriptAcquisitionShareOneDownload() async throws {
        let harness = try AssetHarness(downloadDelay: .milliseconds(100))
        defer { harness.cleanup() }
        let request = harness.request(episodeID: "shared")

        async let playbackAsset = harness.service.acquire(request)
        async let transcriptAsset = harness.service.acquire(request)
        let assets = try await [playbackAsset, transcriptAsset]

        #expect(assets[0] == assets[1])
        #expect(await harness.downloader.callCount == 1)
    }

    @Test func automaticLookaheadRejectsLongEpisodesBeforeNetworkWork() async throws {
        let harness = try AssetHarness()
        defer { harness.cleanup() }
        let request = RadioTranscriptAudioRequest(
            episodeKey: .init(feedID: "feed", episodeID: "long"),
            remoteURL: URL(string: "https://example.com/long.mp3")!,
            expectedDurationSeconds: 46 * 60,
            purpose: .automaticLookahead
        )

        await #expect(throws: RadioTranscriptAssetService.AssetError.self) {
            try await harness.service.acquire(request)
        }
        #expect(await harness.downloader.callCount == 0)
    }

    @Test func pinnedPreparedInputIsNeverEvictedToAdmitAnotherAsset() async throws {
        let harness = try AssetHarness(cacheLimitBytes: 18)
        defer { harness.cleanup() }
        let firstRequest = harness.request(episodeID: "first")
        let secondRequest = harness.request(episodeID: "second")
        let first = try await harness.service.acquire(firstRequest)
        try await harness.service.markTranscriptReady(first)
        await harness.service.pin(first.episodeKey, reason: .automaticWorkingSet)

        await #expect(throws: RadioTranscriptAssetService.AssetError.self) {
            try await harness.service.acquire(secondRequest)
        }
        #expect(FileManager.default.fileExists(atPath: first.localFileURL.path))

        await harness.service.unpin(first.episodeKey, reason: .automaticWorkingSet)
        let second = try await harness.service.acquire(secondRequest)
        #expect(FileManager.default.fileExists(atPath: second.localFileURL.path))
        #expect(!FileManager.default.fileExists(atPath: first.localFileURL.path))
    }

    @Test func noMoreThanTwoDownloadsRunAtOnce() async throws {
        let harness = try AssetHarness(downloadDelay: .milliseconds(100))
        defer { harness.cleanup() }

        async let first = harness.service.acquire(harness.request(episodeID: "one"))
        async let second = harness.service.acquire(harness.request(episodeID: "two"))
        async let third = harness.service.acquire(harness.request(episodeID: "three"))
        _ = try await [first, second, third]

        #expect(await harness.downloader.maximumActiveCount == 2)
    }

    @Test func aRejectedDownloadDoesNotLeaveStagedAudioBehind() async throws {
        let harness = try AssetHarness(durationLoader: { _ in
            throw TestDurationError.unreadable
        })
        defer { harness.cleanup() }

        await #expect(throws: TestDurationError.self) {
            try await harness.service.acquire(
                harness.request(episodeID: "unreadable")
            )
        }

        let stagedFiles = try FileManager.default.contentsOfDirectory(
            at: harness.root.appendingPathComponent("staging"),
            includingPropertiesForKeys: nil
        )
        #expect(stagedFiles.isEmpty)
    }
}

private enum TestDurationError: Error {
    case unreadable
}

private final class AssetHarness: @unchecked Sendable {
    let root: URL
    let downloader: TestRadioTranscriptDownloader
    let service: RadioTranscriptAssetService

    init(
        cacheLimitBytes: Int64 = 10_000,
        downloadDelay: Duration = .zero,
        durationLoader: @escaping RadioTranscriptAssetService.DurationLoader = {
            _ in 30
        }
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RadioTranscriptAssetServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        downloader = TestRadioTranscriptDownloader(
            stagingDirectory: root.appendingPathComponent("staging"),
            delay: downloadDelay
        )
        service = try RadioTranscriptAssetService(
            rootDirectory: root.appendingPathComponent("cache"),
            downloader: downloader,
            cacheLimitBytes: cacheLimitBytes,
            durationLoader: durationLoader
        )
    }

    func request(episodeID: String) -> RadioTranscriptAudioRequest {
        RadioTranscriptAudioRequest(
            episodeKey: .init(feedID: "feed", episodeID: episodeID),
            remoteURL: URL(string: "https://example.com/\(episodeID).mp3")!,
            expectedDurationSeconds: 30,
            purpose: .current
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor TestRadioTranscriptDownloader: RadioTranscriptDownloading {
    private let stagingDirectory: URL
    private let delay: Duration
    private(set) var callCount = 0
    private(set) var maximumActiveCount = 0
    private var activeCount = 0

    init(stagingDirectory: URL, delay: Duration) {
        self.stagingDirectory = stagingDirectory
        self.delay = delay
    }

    func download(_ request: RadioTranscriptAudioRequest) async throws -> RadioTranscriptDownloadResult {
        callCount += 1
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        defer { activeCount -= 1 }
        if delay != .zero {
            try await Task.sleep(for: delay)
        }
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )
        let staged = stagingDirectory.appendingPathComponent("\(UUID().uuidString).mp3")
        let bytes = Data("audio-\(request.episodeKey.episodeID)".utf8)
        try bytes.write(to: staged, options: .atomic)
        return RadioTranscriptDownloadResult(
            stagedFileURL: staged,
            finalURL: URL(string: "https://cdn.example.com/\(request.episodeKey.episodeID).mp3")!,
            etag: "\"etag-\(request.episodeKey.episodeID)\"",
            lastModified: "Thu, 23 Jul 2026 08:00:00 GMT",
            responseContentLength: Int64(bytes.count)
        )
    }
}
