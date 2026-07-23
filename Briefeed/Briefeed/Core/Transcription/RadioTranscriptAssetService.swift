import AVFoundation
import CryptoKit
import Foundation

enum RadioTranscriptAudioPurpose: String, Codable, Equatable, Sendable {
    case current
    case automaticLookahead
    case explicitBatch
}

struct RadioTranscriptAudioRequest: Codable, Equatable, Sendable {
    let episodeKey: RadioEpisodeKey
    let remoteURL: URL
    let expectedDurationSeconds: TimeInterval?
    let purpose: RadioTranscriptAudioPurpose
}

struct RadioTranscriptDownloadResult: Sendable {
    let stagedFileURL: URL
    let finalURL: URL
    let etag: String?
    let lastModified: String?
    let responseContentLength: Int64?
    let request: RadioTranscriptAudioRequest?

    init(
        stagedFileURL: URL,
        finalURL: URL,
        etag: String?,
        lastModified: String?,
        responseContentLength: Int64?,
        request: RadioTranscriptAudioRequest? = nil
    ) {
        self.stagedFileURL = stagedFileURL
        self.finalURL = finalURL
        self.etag = etag
        self.lastModified = lastModified
        self.responseContentLength = responseContentLength
        self.request = request
    }
}

protocol RadioTranscriptDownloading: Sendable {
    func download(
        _ request: RadioTranscriptAudioRequest
    ) async throws -> RadioTranscriptDownloadResult
}

struct RadioTranscriptAudioAsset: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let episodeKey: RadioEpisodeKey
    let originalURL: URL
    let finalURL: URL
    let etag: String?
    let lastModified: String?
    let responseContentLength: Int64?
    let audioDurationSeconds: TimeInterval
    let assetFingerprint: String
    let localFileURL: URL
    let completedAt: Date
    var lastAccessedAt: Date
    var isTranscriptReady: Bool
}

enum RadioTranscriptAssetPinReason: Hashable, Sendable {
    case automaticWorkingSet
    case batch(UUID)
    case activePlayback
}

protocol RadioTranscriptAssetProviding: Sendable {
    func acquire(
        _ request: RadioTranscriptAudioRequest
    ) async throws -> RadioTranscriptAudioAsset
    func cachedAsset(for episodeKey: RadioEpisodeKey) async throws -> RadioTranscriptAudioAsset?
    func preparedPlaybackURL(for episodeKey: RadioEpisodeKey) async -> URL?
    func markTranscriptReady(_ asset: RadioTranscriptAudioAsset) async throws
}

actor RadioTranscriptAssetService: RadioTranscriptAssetProviding {
    enum AssetError: Error, Equatable {
        case automaticDurationLimit
        case invalidAudioDuration
        case missingDownloadedFile
        case storagePressure
        case unsupportedIndexSchema(Int)
    }

    typealias DurationLoader = @Sendable (URL) async throws -> TimeInterval

    private struct IndexFile: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        var assets: [RadioTranscriptAudioAsset]
    }

    private let rootDirectory: URL
    private let audioDirectory: URL
    private let indexURL: URL
    private let fileManager: FileManager
    private let downloader: any RadioTranscriptDownloading
    private let cacheLimitBytes: Int64
    private let durationLoader: DurationLoader
    private let permits = RadioTranscriptDownloadPermitPool(limit: 2)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cachedIndex: IndexFile?
    private var pins: [RadioEpisodeKey: Set<RadioTranscriptAssetPinReason>] = [:]
    private var inFlight: [
        RadioEpisodeKey: Task<RadioTranscriptAudioAsset, Error>
    ] = [:]

    init(
        rootDirectory: URL,
        downloader: any RadioTranscriptDownloading,
        cacheLimitBytes: Int64 = 500 * 1_024 * 1_024,
        fileManager: FileManager = .default,
        durationLoader: DurationLoader? = nil
    ) throws {
        self.rootDirectory = rootDirectory
        audioDirectory = rootDirectory.appendingPathComponent("audio", isDirectory: true)
        indexURL = rootDirectory.appendingPathComponent("asset-index-v1.json")
        self.downloader = downloader
        self.cacheLimitBytes = cacheLimitBytes
        self.fileManager = fileManager
        self.durationLoader = durationLoader ?? { url in
            try await RadioTranscriptAssetService.loadAudioDuration(at: url)
        }
        try fileManager.createDirectory(
            at: audioDirectory,
            withIntermediateDirectories: true
        )
        Self.excludeFromBackup(rootDirectory)
    }

    static func makeProduction(
        fileManager: FileManager = .default
    ) throws -> RadioTranscriptAssetService {
        let caches = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = caches
            .appendingPathComponent("Briefeed", isDirectory: true)
            .appendingPathComponent("RadioTranscriptAudio", isDirectory: true)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        let downloader = try RadioTranscriptBackgroundDownloader(
            stagingDirectory: staging
        )
        let service = try RadioTranscriptAssetService(
            rootDirectory: root,
            downloader: downloader,
            fileManager: fileManager
        )
        downloader.setOrphanCompletionHandler { result in
            Task {
                try? await service.ingestCompletedBackgroundDownload(result)
            }
        }
        return service
    }

    func acquire(
        _ request: RadioTranscriptAudioRequest
    ) async throws -> RadioTranscriptAudioAsset {
        if request.purpose == .automaticLookahead,
           let duration = request.expectedDurationSeconds,
           duration > 45 * 60 {
            throw AssetError.automaticDurationLimit
        }
        if let cached = try cachedAsset(for: request.episodeKey) {
            return cached
        }
        if let inFlight = inFlight[request.episodeKey] {
            return try await inFlight.value
        }

        let task = Task {
            try await self.performAcquire(request)
        }
        inFlight[request.episodeKey] = task
        do {
            let asset = try await task.value
            inFlight[request.episodeKey] = nil
            return asset
        } catch {
            inFlight[request.episodeKey] = nil
            throw error
        }
    }

    func cachedAsset(
        for episodeKey: RadioEpisodeKey
    ) throws -> RadioTranscriptAudioAsset? {
        var index = try loadIndex()
        let candidates = index.assets
            .filter { $0.episodeKey == episodeKey }
            .sorted { $0.completedAt > $1.completedAt }
        guard var asset = candidates.first else { return nil }
        guard fileManager.fileExists(atPath: asset.localFileURL.path) else {
            index.assets.removeAll { $0.localFileURL == asset.localFileURL }
            try write(index: index)
            return nil
        }
        asset.lastAccessedAt = Date()
        if let assetIndex = index.assets.firstIndex(where: {
            $0.episodeKey == asset.episodeKey &&
            $0.assetFingerprint == asset.assetFingerprint
        }) {
            index.assets[assetIndex] = asset
            try write(index: index)
        }
        return asset
    }

    func preparedPlaybackURL(for episodeKey: RadioEpisodeKey) -> URL? {
        guard let asset = try? cachedAsset(for: episodeKey),
              asset.isTranscriptReady else {
            return nil
        }
        return asset.localFileURL
    }

    func pin(
        _ episodeKey: RadioEpisodeKey,
        reason: RadioTranscriptAssetPinReason
    ) {
        pins[episodeKey, default: []].insert(reason)
    }

    func unpin(
        _ episodeKey: RadioEpisodeKey,
        reason: RadioTranscriptAssetPinReason
    ) {
        pins[episodeKey]?.remove(reason)
        if pins[episodeKey]?.isEmpty == true {
            pins[episodeKey] = nil
        }
    }

    func markTranscriptReady(_ asset: RadioTranscriptAudioAsset) throws {
        var index = try loadIndex()
        guard let assetIndex = index.assets.firstIndex(where: {
            $0.episodeKey == asset.episodeKey &&
            $0.assetFingerprint == asset.assetFingerprint
        }) else {
            return
        }
        index.assets[assetIndex].isTranscriptReady = true
        try write(index: index)
    }

    func trimIfNeeded() throws {
        var index = try loadIndex()
        try evictToFit(additionalBytes: 0, index: &index, excluding: nil)
        try write(index: index)
    }

    func handleEventsForBackgroundURLSession(
        completionHandler: @escaping @Sendable () -> Void
    ) {
        (downloader as? RadioTranscriptBackgroundDownloader)?
            .setBackgroundEventsCompletionHandler(completionHandler)
    }

    func ingestCompletedBackgroundDownload(
        _ result: RadioTranscriptDownloadResult
    ) async throws {
        guard let request = result.request else {
            try? fileManager.removeItem(at: result.stagedFileURL)
            return
        }
        if try cachedAsset(for: request.episodeKey) != nil {
            try? fileManager.removeItem(at: result.stagedFileURL)
            return
        }
        _ = try await commit(result: result, request: request)
    }

    private func performAcquire(
        _ request: RadioTranscriptAudioRequest
    ) async throws -> RadioTranscriptAudioAsset {
        await permits.acquire()
        let result: RadioTranscriptDownloadResult
        do {
            result = try await downloader.download(request)
            await permits.release()
        } catch {
            await permits.release()
            throw error
        }

        return try await commit(result: result, request: request)
    }

    private func commit(
        result: RadioTranscriptDownloadResult,
        request: RadioTranscriptAudioRequest
    ) async throws -> RadioTranscriptAudioAsset {
        guard fileManager.fileExists(atPath: result.stagedFileURL.path) else {
            throw AssetError.missingDownloadedFile
        }
        var fileToRemoveOnFailure: URL? = result.stagedFileURL
        defer {
            if let fileToRemoveOnFailure {
                try? fileManager.removeItem(at: fileToRemoveOnFailure)
            }
        }

        let byteCount = try fileSize(at: result.stagedFileURL)
        var index = try loadIndex()
        try evictToFit(
            additionalBytes: byteCount,
            index: &index,
            excluding: request.episodeKey
        )

        let fingerprint = try fingerprint(of: result.stagedFileURL)
        let duration = try await durationLoader(result.stagedFileURL)
        guard duration.isFinite, duration > 0 else {
            throw AssetError.invalidAudioDuration
        }

        let pathExtension = request.remoteURL.pathExtension.isEmpty
            ? "audio"
            : request.remoteURL.pathExtension
        let destination = audioDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)
        try fileManager.moveItem(at: result.stagedFileURL, to: destination)
        fileToRemoveOnFailure = destination
        Self.excludeFromBackup(destination)

        let now = Date()
        let asset = RadioTranscriptAudioAsset(
            schemaVersion: RadioTranscriptAudioAsset.currentSchemaVersion,
            episodeKey: request.episodeKey,
            originalURL: request.remoteURL,
            finalURL: result.finalURL,
            etag: result.etag,
            lastModified: result.lastModified,
            responseContentLength: result.responseContentLength ?? byteCount,
            audioDurationSeconds: duration,
            assetFingerprint: fingerprint,
            localFileURL: destination,
            completedAt: now,
            lastAccessedAt: now,
            isTranscriptReady: false
        )
        index.assets.append(asset)
        try write(index: index)
        fileToRemoveOnFailure = nil
        return asset
    }

    private func evictToFit(
        additionalBytes: Int64,
        index: inout IndexFile,
        excluding episodeKey: RadioEpisodeKey?
    ) throws {
        var total = try index.assets.reduce(into: Int64(0)) { result, asset in
            if fileManager.fileExists(atPath: asset.localFileURL.path) {
                result += try fileSize(at: asset.localFileURL)
            }
        }
        guard additionalBytes <= cacheLimitBytes else {
            throw AssetError.storagePressure
        }

        let candidates = index.assets
            .filter {
                $0.isTranscriptReady &&
                pins[$0.episodeKey]?.isEmpty != false &&
                $0.episodeKey != episodeKey
            }
            .sorted { $0.lastAccessedAt < $1.lastAccessedAt }

        for candidate in candidates where total + additionalBytes > cacheLimitBytes {
            let size = (try? fileSize(at: candidate.localFileURL)) ?? 0
            try? fileManager.removeItem(at: candidate.localFileURL)
            index.assets.removeAll {
                $0.episodeKey == candidate.episodeKey &&
                $0.assetFingerprint == candidate.assetFingerprint
            }
            total = max(total - size, 0)
        }

        guard total + additionalBytes <= cacheLimitBytes else {
            throw AssetError.storagePressure
        }
    }

    private func loadIndex() throws -> IndexFile {
        if let cachedIndex { return cachedIndex }
        guard fileManager.fileExists(atPath: indexURL.path) else {
            let empty = IndexFile(
                schemaVersion: IndexFile.currentSchemaVersion,
                assets: []
            )
            cachedIndex = empty
            return empty
        }
        do {
            let index = try decoder.decode(
                IndexFile.self,
                from: Data(contentsOf: indexURL)
            )
            guard index.schemaVersion == IndexFile.currentSchemaVersion else {
                throw AssetError.unsupportedIndexSchema(index.schemaVersion)
            }
            cachedIndex = index
            return index
        } catch let error as AssetError {
            throw error
        } catch {
            try? fileManager.removeItem(at: indexURL)
            let empty = IndexFile(
                schemaVersion: IndexFile.currentSchemaVersion,
                assets: []
            )
            cachedIndex = empty
            return empty
        }
    }

    private func write(index: IndexFile) throws {
        try encoder.encode(index).write(to: indexURL, options: .atomic)
        Self.excludeFromBackup(indexURL)
        cachedIndex = index
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func fingerprint(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_024 * 1_024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func loadAudioDuration(at url: URL) async throws -> TimeInterval {
        let duration = try await AVURLAsset(url: url).load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw AssetError.invalidAudioDuration
        }
        return seconds
    }

    private static func excludeFromBackup(_ url: URL) {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(values)
    }
}

private actor RadioTranscriptDownloadPermitPool {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        available = max(limit, 1)
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

final class RadioTranscriptBackgroundDownloader:
    NSObject,
    RadioTranscriptDownloading,
    URLSessionDownloadDelegate,
    @unchecked Sendable
{
    enum DownloadError: Error {
        case invalidTaskMetadata
        case invalidHTTPStatus(Int)
        case missingTemporaryFile
    }

    static let sessionIdentifier = "Matznerd.Briefeed.radio-transcript-audio"

    private let stagingDirectory: URL
    private let lock = NSLock()
    private var continuations: [
        Int: CheckedContinuation<RadioTranscriptDownloadResult, Error>
    ] = [:]
    private var tasksByEpisode: [RadioEpisodeKey: URLSessionDownloadTask] = [:]
    private var finishedResults: [Int: RadioTranscriptDownloadResult] = [:]
    private var backgroundEventsCompletionHandler: (@Sendable () -> Void)?
    private var orphanCompletionHandler: (
        @Sendable (RadioTranscriptDownloadResult) -> Void
    )?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.sessionIdentifier
        )
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
    }()

    init(
        stagingDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        self.stagingDirectory = stagingDirectory
        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )
        super.init()
    }

    func download(
        _ request: RadioTranscriptAudioRequest
    ) async throws -> RadioTranscriptDownloadResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var urlRequest = URLRequest(url: request.remoteURL)
                urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
                let task = session.downloadTask(with: urlRequest)
                if let metadata = try? JSONEncoder().encode(request) {
                    task.taskDescription = metadata.base64EncodedString()
                }
                lock.withLock {
                    continuations[task.taskIdentifier] = continuation
                    tasksByEpisode[request.episodeKey] = task
                }
                task.resume()
            }
        } onCancel: {
            self.lock.withLock {
                self.tasksByEpisode[request.episodeKey]?.cancel()
            }
        }
    }

    func setBackgroundEventsCompletionHandler(
        _ completionHandler: @escaping @Sendable () -> Void
    ) {
        lock.withLock {
            backgroundEventsCompletionHandler = completionHandler
        }
    }

    func setOrphanCompletionHandler(
        _ completionHandler: @escaping @Sendable (RadioTranscriptDownloadResult) -> Void
    ) {
        lock.withLock {
            orphanCompletionHandler = completionHandler
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let request = request(from: downloadTask) else { return }
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            finish(
                task: downloadTask,
                result: .failure(
                    DownloadError.invalidHTTPStatus(response.statusCode)
                )
            )
            return
        }
        let destination = stagingDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(
                request.remoteURL.pathExtension.isEmpty
                    ? "audio"
                    : request.remoteURL.pathExtension
            )
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            let response = downloadTask.response as? HTTPURLResponse
            let result = RadioTranscriptDownloadResult(
                stagedFileURL: destination,
                finalURL: response?.url ?? request.remoteURL,
                etag: response?.value(forHTTPHeaderField: "ETag"),
                lastModified: response?.value(forHTTPHeaderField: "Last-Modified"),
                responseContentLength: response.map(\.expectedContentLength),
                request: request
            )
            lock.withLock {
                finishedResults[downloadTask.taskIdentifier] = result
            }
        } catch {
            finish(task: downloadTask, result: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let downloadTask = task as? URLSessionDownloadTask else { return }
        if let error {
            finish(task: downloadTask, result: .failure(error))
            return
        }
        let result = lock.withLock {
            finishedResults.removeValue(forKey: task.taskIdentifier)
        }
        finish(
            task: downloadTask,
            result: result.map(Result.success) ?? .failure(DownloadError.missingTemporaryFile)
        )
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = lock.withLock {
            let completion = backgroundEventsCompletionHandler
            backgroundEventsCompletionHandler = nil
            return completion
        }
        DispatchQueue.main.async {
            completion?()
        }
    }

    private func finish(
        task: URLSessionDownloadTask,
        result: Result<RadioTranscriptDownloadResult, Error>
    ) {
        let request = request(from: task)
        let completion = lock.withLock {
            finishedResults[task.taskIdentifier] = nil
            if let request {
                tasksByEpisode[request.episodeKey] = nil
            }
            return (
                continuations.removeValue(forKey: task.taskIdentifier),
                orphanCompletionHandler
            )
        }
        if let continuation = completion.0 {
            continuation.resume(with: result)
        } else if case .success(let download) = result {
            completion.1?(download)
        }
    }

    private func request(
        from task: URLSessionTask
    ) -> RadioTranscriptAudioRequest? {
        guard let description = task.taskDescription,
              let data = Data(base64Encoded: description) else {
            return nil
        }
        return try? JSONDecoder().decode(
            RadioTranscriptAudioRequest.self,
            from: data
        )
    }
}
