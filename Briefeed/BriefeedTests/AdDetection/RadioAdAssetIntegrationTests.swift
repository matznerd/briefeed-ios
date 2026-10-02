import CryptoKit
import Foundation
import Testing
@testable import Briefeed

@Suite("Radio ad owned audio")
struct RadioAdAssetIntegrationTests {
    @Test func anHourCanBeDownloadedOnceThenPlayedFromTheAnalyzedFile() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = AdAssetDownloader(root: root)
        let service = try RadioTranscriptAssetService(rootDirectory: root, downloader: downloader, durationLoader: { _ in 3600 })
        await #expect(throws: RadioTranscriptAssetService.AssetError.automaticDurationLimit) {
            try await service.acquire(request(purpose: .automaticLookahead))
        }
        #expect(await downloader.callCount == 0)
        let asset = try await service.acquire(request(purpose: .automaticAdLookahead))
        let bytes = try Data(contentsOf: asset.localFileURL)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #expect(asset.assetFingerprint == hash)
        #expect(asset.localFileURL.isFileURL)
        #expect(await service.preparedPlaybackURL(for: asset.episodeKey) == nil)
        try await service.markTranscriptReady(asset)
        #expect(await service.preparedPlaybackURL(for: asset.episodeKey) == asset.localFileURL)
        let repeated = try await service.acquire(request(purpose: .automaticAdLookahead))
        #expect(repeated.localFileURL == asset.localFileURL)
        #expect(repeated.assetFingerprint == hash)
        #expect(await downloader.callCount == 1)
    }

    @Test func unknownOrMisreportedDurationFailsOpenWithoutCachingOversizeAudio() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = AdAssetDownloader(root: root)
        let service = try RadioTranscriptAssetService(rootDirectory: root, downloader: downloader, durationLoader: { _ in 6000 })
        await #expect(throws: RadioTranscriptAssetService.AssetError.automaticDurationLimit) {
            try await service.acquire(request(purpose: .automaticAdLookahead, duration: nil))
        }
        #expect(await downloader.callCount == 0)
        await #expect(throws: RadioTranscriptAssetService.AssetError.automaticDurationLimit) {
            try await service.acquire(request(purpose: .automaticAdLookahead))
        }
        #expect(try await service.cachedAsset(for: request(purpose: .automaticAdLookahead).episodeKey) == nil)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("staged-1").path) == false)
    }

    @Test func oversizedDownloadIsRemovedBeforeItCanBecomePlayable() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = AdAssetDownloader(root: root, oversized: true)
        let service = try RadioTranscriptAssetService(rootDirectory: root, downloader: downloader, durationLoader: { _ in 3600 })
        await #expect(throws: RadioTranscriptAssetService.AssetError.automaticByteLimit) {
            try await service.acquire(request(purpose: .automaticAdLookahead))
        }
        #expect(try await service.cachedAsset(for: request(purpose: .automaticAdLookahead).episodeKey) == nil)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("staged-1").path) == false)
    }

    @Test func aPlaylistDisguisedAsMP3IsNotAnOwnedAudioRendition() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = AdAssetDownloader(root: root, manifest: true)
        let service = try RadioTranscriptAssetService(rootDirectory: root, downloader: downloader,
                                                      durationLoader: { _ in 3600 })
        await #expect(throws: RadioTranscriptAssetService.AssetError.unsupportedStreamingManifest) {
            try await service.acquire(request(purpose: .automaticAdLookahead))
        }
        #expect(try await service.cachedAsset(for: request(purpose: .automaticAdLookahead).episodeKey) == nil)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("staged-1").path) == false)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("briefeed-ad-asset-\(UUID())")
    }
    private func request(purpose: RadioTranscriptAudioPurpose, duration: TimeInterval? = 3600) -> RadioTranscriptAudioRequest {
        .init(episodeKey: .init(feedID: "synthetic", episodeID: "one"),
              remoteURL: URL(string: "https://example.invalid/audio.mp3")!, expectedDurationSeconds: duration, purpose: purpose)
    }
}

private actor AdAssetDownloader: RadioTranscriptDownloading {
    let root: URL
    let oversized: Bool
    let manifest: Bool
    private(set) var callCount = 0
    init(root: URL, oversized: Bool = false, manifest: Bool = false) {
        self.root = root
        self.oversized = oversized
        self.manifest = manifest
    }
    func download(_ request: RadioTranscriptAudioRequest) async throws -> RadioTranscriptDownloadResult {
        callCount += 1
        let staged = root.appendingPathComponent("staged-\(callCount)")
        let content = manifest ? "#EXTM3U\n#EXTINF:3600\nhttps://example.invalid/mutable-segment.aac" : "Synthetic rendition \(callCount)"
        try Data(content.utf8).write(to: staged)
        if oversized {
            let handle = try FileHandle(forWritingTo: staged)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(RadioAdResourcePolicy.maximumDownloadBytes + 1))
        }
        return .init(stagedFileURL: staged, finalURL: request.remoteURL, etag: nil,
                     lastModified: nil, responseContentLength: nil, request: request)
    }
}
