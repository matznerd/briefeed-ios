import Foundation
import Testing
@testable import Briefeed

@Suite("Radio ad intelligence")
struct RadioAdDetectionTests {
    @Test func preferencesAndQualificationAreIndependent() {
        #expect(RadioAdPreferences().prepareAhead == false)
        #expect(RadioAdPreferences().skipAds == false)
        #expect(RadioAdSkipPolicy.isReleaseQualified == false)
        #expect(RadioAdPreferences(skipAds: true).preparationEnabled)
    }

    @Test func importedSkipPreferenceCannotEnableAnUnqualifiedRelease() throws {
        let name = "briefeed-ad-preferences-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: RadioAdPreferences.skipKey)
        #expect(RadioAdPreferences.load(defaults: defaults).preparationEnabled == false)
        defaults.set(true, forKey: RadioAdPreferences.prepareKey)
        #expect(RadioAdPreferences.load(defaults: defaults).prepareAhead)
        #expect(RadioAdPreferences.load(defaults: defaults).skipAds == false)
    }

    @Test func hourLongLookaheadRequiresExplicitAdPreparation() {
        #expect(RadioAdResourcePolicy.permitsLookahead(duration: 3600, enabled: false) == false)
        #expect(RadioAdResourcePolicy.permitsLookahead(duration: 3600, enabled: true))
        #expect(RadioAdResourcePolicy.permitsLookahead(duration: nil, enabled: true) == false)
        #expect(RadioAdResourcePolicy.permitsLookahead(duration: .nan, enabled: true) == false)
        #expect(RadioAdResourcePolicy.permitsLookahead(duration: 6000, enabled: true) == false)
    }

    @Test func sourceAnchorsCoverAnHourWithoutInventedTimes() throws {
        let anchors = (0..<900).map {
            AdTranscriptAnchor(index: $0, startSeconds: Double($0 * 4), endSeconds: Double($0 * 4 + 3), text: "Speech \($0)")
        }
        let windows = try AdTranscriptWindows.make(anchors, maximumUTF8Bytes: 1200, overlap: 3)
        #expect(windows.count > 1)
        #expect(Set(windows.flatMap { $0.anchors.map(\.index) }) == Set(0..<900))
        #expect(windows.allSatisfy { $0.encodedInput.utf8.count <= 1200 })
        #expect(windows[0].sourceRange(firstIndex: 0, lastIndex: 2) == 0..<11)
        #expect(windows[0].sourceRange(firstIndex: -1, lastIndex: 2) == nil)
        #expect(windows[0].sourceRange(firstIndex: 2, lastIndex: 0) == nil)
    }

    @Test func adPreparationPrioritizesUpcomingStoriesWithoutChangingDefaultOrder() {
        func job(_ priority: RadioTranscriptJobPriority, enabled: Bool) -> RadioTranscriptJob {
            .init(episodeKey: key().episodeKey, remoteURL: URL(string: "https://example.invalid/audio.mp3")!,
                  expectedDurationSeconds: 3600, languageTag: "en-US", priority: priority, prepareAds: enabled)
        }
        #expect(job(.current, enabled: false).executionRank < job(.nextOne, enabled: false).executionRank)
        #expect(job(.nextOne, enabled: true).executionRank < job(.nextTwo, enabled: true).executionRank)
        #expect(job(.nextTwo, enabled: true).executionRank < job(.current, enabled: true).executionRank)
        #expect(job(.nextOne, enabled: true).audioPurpose == .automaticAdLookahead)
        #expect(job(.nextOne, enabled: false).audioPurpose == .automaticLookahead)
    }

    @Test func storeIsRenditionBoundAndCorrectionsAreRevisionChecked() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("briefeed-ad-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try RadioAdStore(rootDirectory: root)
        let key = key()
        let original = try record(key: key)
        try await store.save(original)
        #expect(try await store.load(for: key) == original)
        #expect(try await store.load(for: self.key(hash: String(repeating: "b", count: 64))) == nil)
        let corrected = try await store.review(
            key: key, spanID: original.spans[0].id, expectedRevision: 0,
            kind: .sponsorship, start: 1, end: 8, boundariesReviewed: true
        )
        #expect(corrected.revision == 1)
        #expect(corrected.spans[0].categoryReviewed)
        #expect(corrected.spans[0].boundariesReviewed)
        #expect(corrected.spans[0].startSeconds == 1)
        await #expect(throws: RadioAdStore.StoreError.staleRevision) {
            try await store.review(key: key, spanID: original.spans[0].id, expectedRevision: 0,
                                   kind: .editorial, start: 1, end: 8, boundariesReviewed: true)
        }
    }

    @Test func corruptDecodedRecordsCannotAuthorizePlayback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("briefeed-ad-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try RadioAdStore(rootDirectory: root)
        var invalid = try record(key: key())
        invalid.spans[0].endSeconds = 200
        await #expect(throws: RadioAdValidationError.invalidSpan) { try await store.save(invalid) }
        #expect(try await store.load(for: invalid.key) == nil)
    }

    @Test func manualSkipRequiresReviewedRangeAndExactOwnedAudio() throws {
        var record = try record(key: key())
        #expect(RadioAdSkipPolicy.manualTarget(record: record, spanID: record.spans[0].id,
                                             playingFingerprint: record.key.assetFingerprint, isOwnedAudio: true) == nil)
        record.spans[0].categoryReviewed = true
        record.spans[0].boundariesReviewed = true
        #expect(RadioAdSkipPolicy.manualTarget(record: record, spanID: record.spans[0].id,
                                             playingFingerprint: record.key.assetFingerprint, isOwnedAudio: true) == 9.75)
        #expect(RadioAdSkipPolicy.manualTarget(record: record, spanID: record.spans[0].id,
                                             playingFingerprint: String(repeating: "b", count: 64), isOwnedAudio: true) == nil)
        #expect(RadioAdSkipPolicy.manualTarget(record: record, spanID: record.spans[0].id,
                                             playingFingerprint: record.key.assetFingerprint, isOwnedAudio: false) == nil)
        record.spans[0].kind = .editorial
        #expect(RadioAdSkipPolicy.manualTarget(record: record, spanID: record.spans[0].id,
                                             playingFingerprint: record.key.assetFingerprint, isOwnedAudio: true) == nil)
    }

    @Test func editorialConflictBlocksAnOtherwiseReviewedSponsor() throws {
        var record = try record(key: key())
        record.spans[0].categoryReviewed = true
        record.spans[0].boundariesReviewed = true
        record.spans.append(.init(kind: .editorial, startSeconds: 5, endSeconds: 9,
                                  categoryReviewed: true, boundariesReviewed: true))
        #expect(RadioAdSkipPolicy.manualTarget(record: record, spanID: record.spans[0].id,
                                             playingFingerprint: record.key.assetFingerprint, isOwnedAudio: true) == nil)
    }

    @Test func estimatesRequireSuccessfulMeasuredWork() {
        let timing = RadioAdTiming(audioSeconds: 1800, speechSeconds: 180, classifierSeconds: 120,
                                   completedWindows: 30, failedWindows: 0)
        #expect(timing.estimatedProcessingSeconds(for: 3600) == 600)
        let failed = RadioAdTiming(audioSeconds: 1800, speechSeconds: 180, classifierSeconds: 120,
                                   completedWindows: 30, failedWindows: 1)
        #expect(failed.estimatedProcessingSeconds(for: 3600) == nil)
        #expect(timing.estimatedProcessingSeconds(for: .nan) == nil)
        let overflow = RadioAdTiming(audioSeconds: 100, speechSeconds: .greatestFiniteMagnitude,
                                     classifierSeconds: .greatestFiniteMagnitude,
                                     completedWindows: 1, failedWindows: 0)
        #expect(overflow.estimatedProcessingSeconds(for: 3600) == nil)
    }

    @Test func preparationCachesExactTranscriptAndNeverApprovesModelOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("briefeed-ad-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let classifier = FixtureAdClassifier()
        let service = RadioAdPreparationService(store: try RadioAdStore(rootDirectory: root), classifier: classifier,
                                               shouldDefer: { false })
        let transcript = try TimedTranscript(assetFingerprint: key().assetFingerprint, engineIdentifier: "fixture",
                                              engineVersion: "1", localeIdentifier: "en-US", recognizedText: "Sponsor",
                                              audioDurationSeconds: 100, processingDurationSeconds: 1,
                                              units: [.init(text: "This episode is sponsored by Acme.", startSeconds: 0,
                                                            endSeconds: 10, confidence: 1, granularity: .phrase)])
        let prepared = try await service.prepare(transcript: transcript, episodeKey: key().episodeKey, onProgress: { _ in })
        #expect(prepared.spans.count == 1)
        #expect(prepared.spans[0].categoryReviewed == false)
        #expect(prepared.spans[0].boundariesReviewed == false)
        let cached = try await service.prepare(transcript: transcript, episodeKey: key().episodeKey, onProgress: { _ in })
        #expect(cached == prepared)
        #expect(await classifier.callCount == 1)
    }

    @Test func unavailableClassifierLeavesNoFalseReadyRecord() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("briefeed-ad-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let classifier = FixtureAdClassifier(available: false)
        let service = RadioAdPreparationService(store: try RadioAdStore(rootDirectory: root), classifier: classifier,
                                               shouldDefer: { false })
        let transcript = try TimedTranscript(assetFingerprint: key().assetFingerprint, engineIdentifier: "fixture",
                                              engineVersion: "1", localeIdentifier: "en-US", recognizedText: "Sponsor",
                                              audioDurationSeconds: 100, processingDurationSeconds: 1,
                                              units: [.init(text: "Sponsor", startSeconds: 0, endSeconds: 10,
                                                            confidence: 1, granularity: .phrase)])
        await #expect(throws: RadioAdPreparationError.modelUnavailable) {
            try await service.prepare(transcript: transcript, episodeKey: self.key().episodeKey, onProgress: { _ in })
        }
        #expect(await classifier.callCount == 0)
    }

    private func key(hash: String = String(repeating: "a", count: 64)) -> RadioAdCacheKey {
        .init(episodeKey: .init(feedID: "synthetic", episodeID: "one"), assetFingerprint: hash,
              transcriptEngine: "fixture", transcriptVersion: "1", locale: "en-US",
              detectorVersion: "1", modelVersion: "fixture")
    }

    private func record(key: RadioAdCacheKey) throws -> RadioAdRecord {
        try .init(key: key, audioDurationSeconds: 100,
                  spans: [.init(kind: .sponsorship, startSeconds: 0, endSeconds: 10)],
                  timing: .init(audioSeconds: 100, speechSeconds: 1, classifierSeconds: 1,
                                completedWindows: 1, failedWindows: 0))
    }
}

private actor FixtureAdClassifier: RadioAdClassifying {
    nonisolated let modelVersion = "fixture"
    nonisolated let isAvailable: Bool
    private(set) var callCount = 0
    init(available: Bool = true) { isAvailable = available }
    func classify(_ window: AdTranscriptWindow) async throws -> [RadioAdSpan] {
        callCount += 1
        return [.init(kind: .sponsorship, startSeconds: window.anchors[0].startSeconds,
                      endSeconds: window.anchors[0].endSeconds)]
    }
}
