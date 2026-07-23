import Foundation
import Testing
@testable import Briefeed

@Suite("Radio transcript store")
struct RadioTranscriptStoreTests {
    @Test func transcriptIsReadableOnlyAfterArtifactAndIndexCommit() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try RadioTranscriptStore(rootDirectory: root)
        let key = makeCacheKey(episodeID: "hour")
        let record = makeRecord(key: key, relativePath: "artifacts/hour.json")
        let transcript = try makeTranscript(key: key)

        try await store.save(transcript: transcript, record: record)

        #expect(try await store.record(for: key) == record)
        #expect(try await store.loadTranscript(for: key) == transcript)
    }

    @Test func corruptTranscriptDeletesOnlyItsOwnRecord() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try RadioTranscriptStore(rootDirectory: root)
        let firstKey = makeCacheKey(episodeID: "first")
        let secondKey = makeCacheKey(episodeID: "second")
        let first = makeRecord(key: firstKey, relativePath: "artifacts/first.json")
        let second = makeRecord(key: secondKey, relativePath: "artifacts/second.json")
        try await store.save(transcript: makeTranscript(key: firstKey), record: first)
        try await store.save(transcript: makeTranscript(key: secondKey), record: second)
        try Data("not-json".utf8).write(
            to: root.appendingPathComponent(first.transcriptRelativePath),
            options: .atomic
        )

        #expect(try await store.loadTranscript(for: firstKey) == nil)
        #expect(try await store.record(for: firstKey) == nil)
        #expect(try await store.loadTranscript(for: secondKey) != nil)
        #expect(try await store.record(for: secondKey) == second)
    }

    @Test func reconcileRecoversAValidArtifactWhenIndexWriteWasLost() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeCacheKey(episodeID: "orphan")
        let record = makeRecord(key: key, relativePath: "artifacts/orphan.json")
        let writer = try RadioTranscriptStore(rootDirectory: root)
        try await writer.save(transcript: makeTranscript(key: key), record: record)
        try FileManager.default.removeItem(at: root.appendingPathComponent("index-v1.json"))

        let restored = try RadioTranscriptStore(rootDirectory: root)
        try await restored.reconcile()

        #expect(try await restored.record(for: key) == record)
        #expect(try await restored.loadTranscript(for: key) != nil)
    }

    @Test func interruptedAudioReadyBatchEntrySurvivesRelaunch() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeCacheKey(episodeID: "batch")
        let manifest = RadioTranscriptBatchManifest(
            schemaVersion: RadioTranscriptBatchManifest.currentSchemaVersion,
            id: UUID(),
            createdAt: .distantPast,
            updatedAt: .now,
            entries: [
                .init(
                    episodeKey: key.episodeKey,
                    order: 0,
                    state: .audioReady(assetFingerprint: key.assetFingerprint)
                )
            ]
        )
        let writer = try RadioTranscriptStore(rootDirectory: root)
        try await writer.saveBatch(manifest)

        let restored = try RadioTranscriptStore(rootDirectory: root)

        #expect(try await restored.loadBatch() == manifest)
    }

    @Test func saveRejectsARecordWhoseIdentityDoesNotMatchTheTranscript() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try RadioTranscriptStore(rootDirectory: root)
        let transcriptKey = makeCacheKey(episodeID: "episode")
        var mismatchedKey = makeCacheKey(episodeID: "episode")
        mismatchedKey = RadioTranscriptCacheKey(
            episodeKey: mismatchedKey.episodeKey,
            assetFingerprint: "different",
            engineIdentifier: mismatchedKey.engineIdentifier,
            engineVersion: mismatchedKey.engineVersion,
            localeIdentifier: mismatchedKey.localeIdentifier
        )

        await #expect(throws: RadioTranscriptStore.StoreError.self) {
            try await store.save(
                transcript: makeTranscript(key: transcriptKey),
                record: makeRecord(key: mismatchedKey, relativePath: "artifacts/bad.json")
            )
        }
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RadioTranscriptStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeCacheKey(episodeID: String) -> RadioTranscriptCacheKey {
        RadioTranscriptCacheKey(
            episodeKey: .init(feedID: "feed", episodeID: episodeID),
            assetFingerprint: "sha256-\(episodeID)",
            engineIdentifier: "apple-speech-analyzer",
            engineVersion: "iOS-26",
            localeIdentifier: "en-US"
        )
    }

    private func makeRecord(
        key: RadioTranscriptCacheKey,
        relativePath: String
    ) -> RadioTranscriptRecord {
        RadioTranscriptRecord(
            schemaVersion: RadioTranscriptRecord.currentSchemaVersion,
            key: key,
            sourceURLHash: "source-hash",
            audioDurationSeconds: 2,
            transcriptRelativePath: relativePath,
            preparedAt: .distantPast,
            lastAccessedAt: .distantPast
        )
    }

    private func makeTranscript(key: RadioTranscriptCacheKey) throws -> TimedTranscript {
        try TimedTranscript(
            assetFingerprint: key.assetFingerprint,
            engineIdentifier: key.engineIdentifier,
            engineVersion: key.engineVersion,
            localeIdentifier: key.localeIdentifier,
            recognizedText: "Good morning",
            audioDurationSeconds: 2,
            processingDurationSeconds: 0.2,
            units: [
                .init(
                    text: "Good",
                    startSeconds: 0,
                    endSeconds: 0.5,
                    confidence: 0.9,
                    granularity: .word
                ),
                .init(
                    text: "morning",
                    startSeconds: 0.5,
                    endSeconds: 1,
                    confidence: 0.9,
                    granularity: .word
                )
            ]
        )
    }
}
