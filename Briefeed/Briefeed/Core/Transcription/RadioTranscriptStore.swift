import CryptoKit
import Foundation

actor RadioTranscriptStore {
    enum StoreError: Error, Equatable {
        case unsupportedRecordSchema(Int)
        case unsupportedBatchSchema(Int)
        case invalidTranscriptIdentity
        case invalidRelativePath
        case duplicateBatchEpisode
    }

    private struct IndexFile: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        var records: [RadioTranscriptRecord]
    }

    private struct Artifact: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let record: RadioTranscriptRecord
        let transcript: TimedTranscript
    }

    private struct CheckpointArtifact: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let key: RadioTranscriptCacheKey
        let progress: TimedTranscriptProgress
    }

    private let rootDirectory: URL
    private let artifactsDirectory: URL
    private let checkpointsDirectory: URL
    private let indexURL: URL
    private let batchURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cachedIndex: IndexFile?

    init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        let resolvedRoot = try rootDirectory ?? Self.defaultRootDirectory(fileManager: fileManager)
        self.rootDirectory = resolvedRoot
        artifactsDirectory = resolvedRoot.appendingPathComponent("artifacts", isDirectory: true)
        checkpointsDirectory = resolvedRoot.appendingPathComponent(
            "checkpoints",
            isDirectory: true
        )
        indexURL = resolvedRoot.appendingPathComponent("index-v1.json")
        batchURL = resolvedRoot.appendingPathComponent("batch-v1.json")
        encoder = JSONEncoder()
        decoder = JSONDecoder()

        try fileManager.createDirectory(
            at: artifactsDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: checkpointsDirectory,
            withIntermediateDirectories: true
        )
        Self.excludeFromBackup(resolvedRoot)
    }

    func record(for key: RadioTranscriptCacheKey) throws -> RadioTranscriptRecord? {
        try loadIndex().records.first { $0.key == key }
    }

    func records(
        for episodeKey: RadioEpisodeKey
    ) throws -> [RadioTranscriptRecord] {
        try loadIndex().records.filter { $0.key.episodeKey == episodeKey }
    }

    func save(
        transcript: TimedTranscript,
        record: RadioTranscriptRecord
    ) throws {
        try validate(record: record, transcript: transcript)
        let artifactURL = try url(forRelativePath: record.transcriptRelativePath)
        try fileManager.createDirectory(
            at: artifactURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let artifact = Artifact(
            schemaVersion: Artifact.currentSchemaVersion,
            record: record,
            transcript: transcript
        )
        try encoder.encode(artifact).write(to: artifactURL, options: .atomic)
        Self.excludeFromBackup(artifactURL)

        let committed = try decoder.decode(
            Artifact.self,
            from: Data(contentsOf: artifactURL)
        )
        try validate(artifact: committed, expectedKey: record.key)

        var index = try loadIndex()
        index.records.removeAll { $0.key == record.key }
        index.records.append(record)
        try write(index: index)
    }

    func loadTranscript(for key: RadioTranscriptCacheKey) throws -> TimedTranscript? {
        guard let record = try record(for: key) else { return nil }
        let artifactURL: URL
        do {
            artifactURL = try url(forRelativePath: record.transcriptRelativePath)
            let artifact = try decoder.decode(
                Artifact.self,
                from: Data(contentsOf: artifactURL)
            )
            try validate(artifact: artifact, expectedKey: key)
            return artifact.transcript
        } catch {
            try removeRecord(key: key, relativePath: record.transcriptRelativePath)
            return nil
        }
    }

    func removeTranscript(for key: RadioTranscriptCacheKey) throws {
        guard let record = try record(for: key) else { return }
        try removeRecord(
            key: key,
            relativePath: record.transcriptRelativePath
        )
    }

    func saveCheckpoint(
        _ progress: TimedTranscriptProgress,
        for key: RadioTranscriptCacheKey
    ) throws {
        try validateCheckpoint(progress, for: key)
        let url = checkpointURL(for: key)
        let artifact = CheckpointArtifact(
            schemaVersion: CheckpointArtifact.currentSchemaVersion,
            key: key,
            progress: progress
        )
        try encoder.encode(artifact).write(to: url, options: .atomic)
        Self.excludeFromBackup(url)
    }

    func loadCheckpoint(
        for key: RadioTranscriptCacheKey
    ) throws -> TimedTranscriptProgress? {
        let url = checkpointURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let artifact = try decoder.decode(
                CheckpointArtifact.self,
                from: Data(contentsOf: url)
            )
            guard artifact.schemaVersion ==
                    CheckpointArtifact.currentSchemaVersion,
                  artifact.key == key else {
                throw StoreError.invalidTranscriptIdentity
            }
            try validateCheckpoint(artifact.progress, for: key)
            return artifact.progress
        } catch {
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    func removeCheckpoint(for key: RadioTranscriptCacheKey) throws {
        let url = checkpointURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func saveBatch(_ manifest: RadioTranscriptBatchManifest) throws {
        guard manifest.schemaVersion == RadioTranscriptBatchManifest.currentSchemaVersion else {
            throw StoreError.unsupportedBatchSchema(manifest.schemaVersion)
        }
        guard Set(manifest.entries.map(\.episodeKey)).count == manifest.entries.count else {
            throw StoreError.duplicateBatchEpisode
        }
        try encoder.encode(manifest).write(to: batchURL, options: .atomic)
        Self.excludeFromBackup(batchURL)
    }

    func loadBatch() throws -> RadioTranscriptBatchManifest? {
        guard fileManager.fileExists(atPath: batchURL.path) else { return nil }
        do {
            let manifest = try decoder.decode(
                RadioTranscriptBatchManifest.self,
                from: Data(contentsOf: batchURL)
            )
            guard manifest.schemaVersion == RadioTranscriptBatchManifest.currentSchemaVersion else {
                throw StoreError.unsupportedBatchSchema(manifest.schemaVersion)
            }
            guard Set(manifest.entries.map(\.episodeKey)).count == manifest.entries.count else {
                throw StoreError.duplicateBatchEpisode
            }
            return manifest
        } catch {
            try? fileManager.removeItem(at: batchURL)
            return nil
        }
    }

    @discardableResult
    func updateBatchEntry(
        for episodeKey: RadioEpisodeKey,
        state: RadioTranscriptBatchEntryState,
        updatedAt: Date = Date()
    ) throws -> RadioTranscriptBatchManifest? {
        guard var manifest = try loadBatch(),
              let index = manifest.entries.firstIndex(where: {
                  $0.episodeKey == episodeKey
              }) else {
            return nil
        }
        manifest.entries[index].state = state
        manifest.updatedAt = updatedAt
        try saveBatch(manifest)
        return manifest
    }

    func removeBatch() throws {
        guard fileManager.fileExists(atPath: batchURL.path) else { return }
        try fileManager.removeItem(at: batchURL)
    }

    func reconcile() throws {
        var validRecords: [RadioTranscriptCacheKey: RadioTranscriptRecord] = [:]
        let files = try fileManager.contentsOfDirectory(
            at: artifactsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for fileURL in files where fileURL.pathExtension == "json" {
            do {
                let artifact = try decoder.decode(
                    Artifact.self,
                    from: Data(contentsOf: fileURL)
                )
                try validate(artifact: artifact, expectedKey: artifact.record.key)
                let expectedURL = try url(forRelativePath: artifact.record.transcriptRelativePath)
                guard expectedURL.standardizedFileURL == fileURL.standardizedFileURL else {
                    throw StoreError.invalidRelativePath
                }
                validRecords[artifact.record.key] = artifact.record
            } catch {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        let index = IndexFile(
            schemaVersion: IndexFile.currentSchemaVersion,
            records: validRecords.values.sorted {
                if $0.preparedAt != $1.preparedAt {
                    return $0.preparedAt < $1.preparedAt
                }
                if $0.key.episodeKey.feedID != $1.key.episodeKey.feedID {
                    return $0.key.episodeKey.feedID < $1.key.episodeKey.feedID
                }
                return $0.key.episodeKey.episodeID < $1.key.episodeKey.episodeID
            }
        )
        try write(index: index)

        guard var batch = try loadBatch() else { return }
        var changed = false
        for index in batch.entries.indices {
            guard case .transcriptReady(let key) = batch.entries[index].state else {
                continue
            }
            if validRecords[key] == nil {
                batch.entries[index].state = .pending
                changed = true
            }
        }
        if changed {
            batch.updatedAt = Date()
            try saveBatch(batch)
        }
    }

    private func loadIndex() throws -> IndexFile {
        if let cachedIndex { return cachedIndex }
        guard fileManager.fileExists(atPath: indexURL.path) else {
            let empty = IndexFile(
                schemaVersion: IndexFile.currentSchemaVersion,
                records: []
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
                throw StoreError.unsupportedRecordSchema(index.schemaVersion)
            }
            cachedIndex = index
            return index
        } catch {
            try? fileManager.removeItem(at: indexURL)
            let empty = IndexFile(
                schemaVersion: IndexFile.currentSchemaVersion,
                records: []
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

    private func removeRecord(
        key: RadioTranscriptCacheKey,
        relativePath: String
    ) throws {
        if let artifactURL = try? url(forRelativePath: relativePath) {
            try? fileManager.removeItem(at: artifactURL)
        }
        var index = try loadIndex()
        index.records.removeAll { $0.key == key }
        try write(index: index)
    }

    private func validate(
        artifact: Artifact,
        expectedKey: RadioTranscriptCacheKey
    ) throws {
        guard artifact.schemaVersion == Artifact.currentSchemaVersion else {
            throw StoreError.unsupportedRecordSchema(artifact.schemaVersion)
        }
        guard artifact.record.key == expectedKey else {
            throw StoreError.invalidTranscriptIdentity
        }
        try validate(record: artifact.record, transcript: artifact.transcript)
    }

    private func validateCheckpoint(
        _ progress: TimedTranscriptProgress,
        for key: RadioTranscriptCacheKey
    ) throws {
        let transcript = progress.transcript
        guard key.assetFingerprint == transcript.assetFingerprint,
              key.engineIdentifier == transcript.engineIdentifier,
              key.engineVersion == transcript.engineVersion,
              key.localeIdentifier == transcript.localeIdentifier,
              progress.finalizedThroughSeconds >=
                (transcript.units.last?.endSeconds ?? 0),
              progress.finalizedThroughSeconds <=
                transcript.audioDurationSeconds else {
            throw StoreError.invalidTranscriptIdentity
        }
    }

    private func checkpointURL(
        for key: RadioTranscriptCacheKey
    ) -> URL {
        let identity = [
            key.episodeKey.feedID,
            key.episodeKey.episodeID,
            key.assetFingerprint,
            key.engineIdentifier,
            key.engineVersion,
            key.localeIdentifier
        ].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return checkpointsDirectory
            .appendingPathComponent(digest)
            .appendingPathExtension("json")
    }

    private func validate(
        record: RadioTranscriptRecord,
        transcript: TimedTranscript
    ) throws {
        guard record.schemaVersion == RadioTranscriptRecord.currentSchemaVersion else {
            throw StoreError.unsupportedRecordSchema(record.schemaVersion)
        }
        guard record.key.assetFingerprint == transcript.assetFingerprint,
              record.key.engineIdentifier == transcript.engineIdentifier,
              record.key.engineVersion == transcript.engineVersion,
              record.key.localeIdentifier == transcript.localeIdentifier,
              record.audioDurationSeconds == transcript.audioDurationSeconds else {
            throw StoreError.invalidTranscriptIdentity
        }
        _ = try url(forRelativePath: record.transcriptRelativePath)
    }

    private func url(forRelativePath relativePath: String) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            throw StoreError.invalidRelativePath
        }
        let candidate = rootDirectory
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        let rootPath = rootDirectory.standardizedFileURL.path
        guard candidate.path.hasPrefix(rootPath + "/") else {
            throw StoreError.invalidRelativePath
        }
        return candidate
    }

    private static func defaultRootDirectory(fileManager: FileManager) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appendingPathComponent("Briefeed", isDirectory: true)
            .appendingPathComponent("RadioTranscripts", isDirectory: true)
    }

    private static func excludeFromBackup(_ url: URL) {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(values)
    }
}
