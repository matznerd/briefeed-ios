import Foundation
import Testing
@testable import Briefeed

@Suite("Radio queue builder")
struct RadioQueueBuilderTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func initialBuildUsesSourcePriorityThenIDAndNewestPerSource() {
        let result = RadioQueueBuilder(now: now).buildInitial(candidates: [
            candidate("z", "old", priority: 1, date: now.addingTimeInterval(-10)),
            candidate("z", "new", priority: 1, date: now),
            candidate("a", "one", priority: 1, date: now),
            candidate("later", "one", priority: 2, date: now)
        ])

        #expect(result.entries.map(\.key) == [key("a", "one"), key("z", "new"), key("later", "one")])
        #expect(result.currentKey == key("a", "one"))
    }

    @Test func initialBuildUsesFreshnessAndDoesNotBackfillCompletedNewest() {
        let hourlyOld = candidate("hourly", "old", priority: 1, date: now.addingTimeInterval(-7_201))
        let dailyOld = candidate("daily", "old", priority: 2, date: now.addingTimeInterval(-86_401), frequency: .daily)
        let completedNewest = candidate("completed", "new", priority: 3, date: now, completed: true)
        let olderIncomplete = candidate("completed", "old", priority: 3, date: now.addingTimeInterval(-1))

        let result = RadioQueueBuilder(now: now).buildInitial(candidates: [hourlyOld, dailyOld, completedNewest, olderIncomplete])

        #expect(result.entries.isEmpty)
        #expect(result.currentKey == nil)
    }

    @Test func initialBuildAcceptsExactFreshnessBoundaryAndUsesEpisodeIDForEqualDates() {
        let first = candidate("feed", "a", priority: 1, date: now.addingTimeInterval(-7_200))
        let second = candidate("other", "b", priority: 1, date: now.addingTimeInterval(-7_200))
        let third = candidate("other", "a", priority: 1, date: now.addingTimeInterval(-7_200))

        let result = RadioQueueBuilder(now: now).buildInitial(candidates: [second, first, third])

        #expect(result.entries.map(\.key) == [first.key, third.key])
    }

    @Test func initialBuildAcceptsExactDailyFreshnessAndClampsCoreDataProgressOnlyWithDuration() {
        let daily = candidate("daily", "one", priority: 1, date: now.addingTimeInterval(-86_400), frequency: .daily, duration: 60, progress: 1.5)
        let unknownDuration = candidate("unknown", "one", priority: 2, date: now, duration: nil, progress: 0.5)

        let result = RadioQueueBuilder(now: now).buildInitial(candidates: [daily, unknownDuration])

        #expect(result.entries.map(\.positionSeconds) == [60, 0])
    }

    @Test func restoreDropsDuplicateCompletedAndExpiredEntriesButPreservesCurrentOrder() {
        let current = candidate("hourly", "current", priority: 1, date: now.addingTimeInterval(-86_399))
        let deferred = candidate("daily", "deferred", priority: 2, date: now.addingTimeInterval(-604_799), frequency: .daily)
        let duplicateEnclosure = candidate("other", "duplicate", priority: 3, date: now, enclosure: current.canonicalEnclosureURL)
        let expired = candidate("hourly", "expired", priority: 4, date: now.addingTimeInterval(-86_401))
        let snapshot = session(entries: [
            entry(current.key, .playing), entry(deferred.key, .deferred), entry(duplicateEnclosure.key, .pending), entry(expired.key, .pending)
        ], current: current.key)

        let result = RadioQueueBuilder(now: now).restore(snapshot: snapshot, candidates: [current, deferred, duplicateEnclosure, expired])

        #expect(result.entries.map(\.key) == [current.key, deferred.key])
        #expect(result.entries.first?.disposition == .pending)
        #expect(result.currentKey == current.key)
    }

    @Test func restoreAcceptsExactRetentionBoundaryAndAppendsNewCandidates() {
        let retained = candidate("retained", "one", priority: 9, date: now.addingTimeInterval(-86_400))
        let deferred = candidate("deferred", "one", priority: 1, date: now)
        let appended = candidate("appended", "one", priority: 0, date: now)
        let snapshot = session(entries: [entry(retained.key, .playing), entry(deferred.key, .deferred)], current: retained.key)

        let result = RadioQueueBuilder(now: now).restore(snapshot: snapshot, candidates: [retained, deferred, appended])

        #expect(result.entries.map(\.key) == [retained.key, appended.key, deferred.key])
        #expect(result.currentKey == retained.key)
    }

    @Test func restoreAcceptsExactDailySevenDayRetentionBoundary() {
        let daily = candidate("daily", "one", priority: 1, date: now.addingTimeInterval(-604_800), frequency: .daily)
        let snapshot = session(entries: [entry(daily.key, .pending)], current: daily.key)

        let result = RadioQueueBuilder(now: now).restore(snapshot: snapshot, candidates: [daily])

        #expect(result.entries.map(\.key) == [daily.key])
        #expect(result.currentKey == daily.key)
    }

    @Test func restoreResetsFailedCurrentToPendingAndPreservesIt() {
        let failed = candidate("failed", "one", priority: 0, date: now)
        let deferred = candidate("deferred", "one", priority: 0, date: now)
        let pending = candidate("pending", "one", priority: 0, date: now)
        let snapshot = session(entries: [entry(failed.key, .failedThisSession), entry(deferred.key, .deferred), entry(pending.key, .pending)], current: failed.key)

        let result = RadioQueueBuilder(now: now).restore(snapshot: snapshot, candidates: [failed, deferred, pending])

        #expect(result.currentKey == failed.key)
        #expect(result.entries.first?.disposition == .pending)
    }

    @Test func restoreMovesCurrentFirstAndSortsAllPendingBeforeDeferred() {
        let current = candidate("current", "one", priority: 9, date: now)
        let pendingLate = candidate("z", "one", priority: 2, date: now)
        let pendingEarly = candidate("a", "one", priority: 1, date: now)
        let deferred = candidate("deferred", "one", priority: 0, date: now)
        let appended = candidate("appended", "one", priority: 0, date: now)
        let snapshot = session(entries: [entry(deferred.key, .deferred), entry(pendingLate.key, .pending), entry(current.key, .playing), entry(pendingEarly.key, .pending)], current: current.key)

        let result = RadioQueueBuilder(now: now).restore(snapshot: snapshot, candidates: [current, pendingLate, pendingEarly, deferred, appended])

        #expect(result.entries.map(\.key) == [current.key, appended.key, pendingEarly.key, pendingLate.key, deferred.key])
    }

    @Test func restoreMissingCurrentSelectsAppendedPendingBeforeSavedDeferred() {
        let deferred = candidate("deferred", "one", priority: 1, date: now)
        let appended = candidate("appended", "one", priority: 0, date: now)
        let snapshot = session(entries: [entry(deferred.key, .deferred)], current: key("missing", "one"))

        let result = RadioQueueBuilder(now: now).restore(snapshot: snapshot, candidates: [deferred, appended])

        #expect(result.currentKey == appended.key)
        #expect(result.entries.map(\.key) == [appended.key, deferred.key])
    }

    @Test func reconcilePreservesCurrentAndPartitionsNewPendingBeforeDeferred() {
        let current = candidate("npr", "1", priority: 1, date: now)
        let deferred = candidate("bbc", "old", priority: 2, date: now.addingTimeInterval(-60))
        let fresh = candidate("bbc", "new", priority: 2, date: now)
        let snapshot = session(entries: [entry(current.key, .playing), entry(deferred.key, .deferred)], current: current.key)

        let result = RadioQueueBuilder(now: now).reconcile(snapshot: snapshot, candidates: [current, deferred, fresh])

        #expect(result.entries.map(\.key) == [current.key, fresh.key, deferred.key])
        #expect(result.currentKey == current.key)
    }

    @Test func reconcileReordersOnlyPendingAndKeepsFailedIneligible() {
        let current = candidate("current", "one", priority: 9, date: now)
        let pending = candidate("pending", "one", priority: 3, date: now)
        let deferred = candidate("deferred", "one", priority: 1, date: now)
        let failed = candidate("failed", "one", priority: 0, date: now)
        let snapshot = session(entries: [
            entry(current.key, .playing), entry(pending.key, .pending), entry(deferred.key, .deferred), entry(failed.key, .failedThisSession)
        ], current: current.key)

        let result = RadioQueueBuilder(now: now).reconcile(snapshot: snapshot, candidates: [current, pending, deferred, failed])

        #expect(result.entries.map(\.key) == [current.key, pending.key, deferred.key, failed.key])
        #expect(RadioQueueBuilder(now: now).nextEligible(in: result) == pending.key)
    }

    @Test func reconcilePreservesLivePlayingCurrentAndStableDeferredAndFailedOrder() {
        let current = candidate("current", "one", priority: 9, date: now)
        let deferredOne = candidate("deferred", "one", priority: 0, date: now)
        let deferredTwo = candidate("deferred", "two", priority: 0, date: now)
        let failedOne = candidate("failed", "one", priority: 0, date: now)
        let failedTwo = candidate("failed", "two", priority: 0, date: now)
        let snapshot = session(entries: [entry(current.key, .playing), entry(deferredOne.key, .deferred), entry(deferredTwo.key, .deferred), entry(failedOne.key, .failedThisSession), entry(failedTwo.key, .failedThisSession)], current: current.key)

        let result = RadioQueueBuilder(now: now).reconcile(snapshot: snapshot, candidates: [current, deferredOne, deferredTwo, failedOne, failedTwo])

        #expect(result.entries.first?.disposition == .playing)
        #expect(result.entries.map(\.key) == [current.key, deferredOne.key, deferredTwo.key, failedOne.key, failedTwo.key])
    }

    @Test func reconcileExcludesFailedCurrentAndSelectsPending() {
        let failed = candidate("failed", "one", priority: 0, date: now)
        let pending = candidate("pending", "one", priority: 1, date: now)
        let snapshot = session(entries: [entry(failed.key, .failedThisSession), entry(pending.key, .pending)], current: failed.key)

        let result = RadioQueueBuilder(now: now).reconcile(snapshot: snapshot, candidates: [failed, pending])

        #expect(result.currentKey == pending.key)
        #expect(result.entries.map(\.key) == [pending.key, failed.key])
    }

    @Test func reconcileMissingCurrentSelectsAppendedPendingBeforeSavedDeferred() {
        let deferred = candidate("deferred", "one", priority: 1, date: now)
        let appended = candidate("appended", "one", priority: 0, date: now)
        let snapshot = session(entries: [entry(deferred.key, .deferred)], current: key("missing", "one"))

        let result = RadioQueueBuilder(now: now).reconcile(snapshot: snapshot, candidates: [deferred, appended])

        #expect(result.currentKey == appended.key)
        #expect(result.entries.map(\.key) == [appended.key, deferred.key])
    }

    @Test func reconcileAppendsWithoutInsertingBeforeCurrentAndDeduplicatesKeysAndEnclosures() {
        let current = candidate("current", "one", priority: 10, date: now)
        let duplicateKey = candidate("current", "one", priority: 0, date: now)
        let duplicateEnclosure = candidate("dup", "one", priority: 0, date: now, enclosure: current.canonicalEnclosureURL)
        let added = candidate("added", "one", priority: 0, date: now)
        let snapshot = session(entries: [entry(current.key, .playing)], current: current.key)

        let result = RadioQueueBuilder(now: now).reconcile(snapshot: snapshot, candidates: [duplicateKey, duplicateEnclosure, added, current])

        #expect(result.entries.map(\.key) == [current.key, added.key])
    }

    private func key(_ feedID: String, _ episodeID: String) -> RadioEpisodeKey {
        RadioEpisodeKey(feedID: feedID, episodeID: episodeID)
    }

    private func candidate(_ feedID: String, _ episodeID: String, priority: Int, date: Date, frequency: RSSUpdateFrequencyValue = .hourly, completed: Bool = false, enclosure: String? = nil, duration: TimeInterval? = 60, progress: Double = 0) -> RadioEpisodeCandidate {
        RadioEpisodeCandidate(key: key(feedID, episodeID), originalPlaybackURL: URL(string: "https://example.com/\(feedID)-\(episodeID).mp3")!, canonicalEnclosureURL: enclosure ?? "https://example.com/\(feedID)-\(episodeID).mp3", title: episodeID, sourceName: feedID, publicationDate: date, durationSeconds: duration, normalizedCoreDataProgress: progress, isCompleted: completed, sourcePriority: priority, sourceFrequency: frequency)
    }

    private func entry(_ key: RadioEpisodeKey, _ disposition: RadioEntryDisposition) -> RadioQueueEntry {
        RadioQueueEntry(key: key, positionSeconds: 0, disposition: disposition, playbackFailureCount: 0, lastPlaybackError: nil)
    }

    private func session(entries: [RadioQueueEntry], current: RadioEpisodeKey?) -> PersistedRadioSession {
        PersistedRadioSession(schemaVersion: PersistedRadioSession.schemaVersion, entries: entries, currentKey: current, savedAt: now)
    }
}
