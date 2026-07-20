import Foundation
import Testing
@testable import Briefeed

@Suite("Radio session store")
@MainActor
struct RadioSessionStoreTests {
    private let suiteName: String
    private let defaults: UserDefaults

    init() {
        suiteName = "RadioSessionStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func restoreRepairsTransientStateAndCurrentKey() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let failed = RadioQueueEntry(
            key: .init(feedID: "bbc", episodeID: "b"),
            positionSeconds: .nan,
            disposition: .failedThisSession,
            playbackFailureCount: 2,
            lastPlaybackError: "timeout"
        )
        let snapshot = PersistedRadioSession(
            schemaVersion: 1,
            entries: [failed],
            currentKey: .init(feedID: "missing", episodeID: "x"),
            savedAt: .distantPast
        )

        let restored = try RadioSessionStore.validate(snapshot, durations: [failed.key: 300])

        #expect(restored.entries[0].positionSeconds == 0)
        #expect(restored.entries[0].disposition == .pending)
        #expect(restored.entries[0].playbackFailureCount == 0)
        #expect(restored.entries[0].lastPlaybackError == nil)
        #expect(restored.currentKey == failed.key)
    }

    @Test func validateRejectsUnsupportedSchemaAndOversizedQueue() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = RadioEpisodeKey(feedID: "feed", episodeID: "episode")
        let entry = RadioQueueEntry(key: key, positionSeconds: 0, disposition: .pending, playbackFailureCount: 0, lastPlaybackError: nil)
        let unsupported = PersistedRadioSession(schemaVersion: 2, entries: [entry], currentKey: key, savedAt: .now)
        let oversized = PersistedRadioSession(schemaVersion: 1, entries: Array(repeating: entry, count: 201), currentKey: key, savedAt: .now)

        #expect(throws: RadioSessionStore.ValidationError.self) {
            try RadioSessionStore.validate(unsupported, durations: [:])
        }
        #expect(throws: RadioSessionStore.ValidationError.self) {
            try RadioSessionStore.validate(oversized, durations: [:])
        }
    }

    @Test func validateRepairsDuplicatesPositionsAndKnownDurations() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = RadioEpisodeKey(feedID: "feed", episodeID: "first")
        let second = RadioEpisodeKey(feedID: "feed", episodeID: "second")
        let snapshot = PersistedRadioSession(
            schemaVersion: 1,
            entries: [
                .init(key: first, positionSeconds: -5, disposition: .playing, playbackFailureCount: 3, lastPlaybackError: "old"),
                .init(key: first, positionSeconds: 12, disposition: .deferred, playbackFailureCount: 0, lastPlaybackError: nil),
                .init(key: second, positionSeconds: 999, disposition: .pending, playbackFailureCount: 0, lastPlaybackError: nil)
            ],
            currentKey: second,
            savedAt: .now
        )

        let repaired = try RadioSessionStore.validate(snapshot, durations: [first: 100, second: 120])

        #expect(repaired.entries.count == 2)
        #expect(repaired.entries[0].key == first)
        #expect(repaired.entries[0].positionSeconds == 0)
        #expect(repaired.entries[0].disposition == .pending)
        #expect(repaired.entries[0].playbackFailureCount == 0)
        #expect(repaired.entries[1].positionSeconds == 120)
        #expect(repaired.currentKey == second)
    }

    @Test func loadDiscardsCorruptData() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: RadioSessionStore.storageKey)
        let store = RadioSessionStore(defaults: defaults)

        #expect(try store.load(durations: [:]) == nil)
        #expect(defaults.object(forKey: RadioSessionStore.storageKey) == nil)
    }

    @Test func forcedSaveInvalidatesOlderDebounce() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scheduler = TestDebounceScheduler()
        let store = RadioSessionStore(defaults: defaults, scheduler: scheduler)
        let keyA = RadioEpisodeKey(feedID: "feed", episodeID: "a")
        let keyB = RadioEpisodeKey(feedID: "feed", episodeID: "b")

        store.saveDebounced(session(current: keyA, position: 10))
        try store.saveNow(session(current: keyB, position: 40))
        scheduler.fireCanceledActionAnyway()

        #expect(try store.load(durations: [:])?.currentKey == keyB)
        #expect(try store.load(durations: [:])?.entries.first?.positionSeconds == 40)
    }

    private func session(current key: RadioEpisodeKey, position: TimeInterval) -> PersistedRadioSession {
        PersistedRadioSession(
            schemaVersion: 1,
            entries: [.init(key: key, positionSeconds: position, disposition: .pending, playbackFailureCount: 0, lastPlaybackError: nil)],
            currentKey: key,
            savedAt: .now
        )
    }
}

@MainActor
private final class TestDebounceScheduler: RadioDebounceScheduling {
    private var action: (@MainActor () -> Void)?

    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func cancel() {}

    func fireCanceledActionAnyway() {
        action?()
    }
}
