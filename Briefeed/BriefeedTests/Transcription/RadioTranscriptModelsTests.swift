import Foundation
import Testing
@testable import Briefeed

@Suite("Radio transcript models")
struct RadioTranscriptModelsTests {
    @Test func batchManifestRoundTripsEveryDurableStage() throws {
        let cacheKey = makeCacheKey()
        let states: [RadioTranscriptBatchEntryState] = [
            .pending,
            .audioReady(assetFingerprint: "sha256"),
            .transcriptReady(cacheKey: cacheKey),
            .failed(message: "Unsupported locale")
        ]

        for state in states {
            let entry = RadioTranscriptBatchEntry(
                episodeKey: cacheKey.episodeKey,
                order: 0,
                state: state
            )
            let decoded = try JSONDecoder().decode(
                RadioTranscriptBatchEntry.self,
                from: JSONEncoder().encode(entry)
            )
            #expect(decoded == entry)
        }
    }

    @Test func manifestReportsOnlyDurablyReadyEntriesAsCompleted() {
        let key = makeCacheKey()
        let manifest = RadioTranscriptBatchManifest(
            schemaVersion: RadioTranscriptBatchManifest.currentSchemaVersion,
            id: UUID(),
            createdAt: .distantPast,
            updatedAt: .now,
            entries: [
                .init(episodeKey: key.episodeKey, order: 0, state: .pending),
                .init(
                    episodeKey: .init(feedID: "bbc", episodeID: "latest"),
                    order: 1,
                    state: .audioReady(assetFingerprint: "audio")
                ),
                .init(
                    episodeKey: .init(feedID: "abc", episodeID: "latest"),
                    order: 2,
                    state: .transcriptReady(cacheKey: key)
                ),
                .init(
                    episodeKey: .init(feedID: "marketplace", episodeID: "latest"),
                    order: 3,
                    state: .failed(message: "Network unavailable")
                )
            ]
        )

        #expect(manifest.completedCount == 1)
        #expect(manifest.remainingCount == 3)
        #expect(manifest.failedCount == 1)
        #expect(manifest.terminalCount == 2)
        #expect(manifest.totalCount == 4)
    }

    @Test func preparationReadyStateRetainsTheValidatedTranscript() throws {
        let transcript = try makeTranscript()
        #expect(RadioTranscriptPreparationState.ready(transcript) == .ready(transcript))
    }

    private func makeCacheKey() -> RadioTranscriptCacheKey {
        RadioTranscriptCacheKey(
            episodeKey: .init(feedID: "npr", episodeID: "hour"),
            assetFingerprint: "sha256",
            engineIdentifier: "apple-speech-analyzer",
            engineVersion: "iOS-26",
            localeIdentifier: "en-US"
        )
    }

    private func makeTranscript() throws -> TimedTranscript {
        try TimedTranscript(
            assetFingerprint: "sha256",
            engineIdentifier: "apple-speech-analyzer",
            engineVersion: "iOS-26",
            localeIdentifier: "en-US",
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
