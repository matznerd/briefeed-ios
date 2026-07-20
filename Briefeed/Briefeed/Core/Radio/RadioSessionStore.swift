import Foundation

@MainActor
protocol RadioDebounceScheduling: AnyObject {
    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
private final class RadioDebounceScheduler: RadioDebounceScheduling {
    private var task: Task<Void, Never>?

    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () -> Void) {
        cancel()
        task = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

@MainActor
final class RadioSessionStore: RadioSessionStoreProtocol {
    enum ValidationError: Error, Equatable {
        case unsupportedSchema(Int)
        case tooManyEntries(Int)
    }

    static let storageKey = "briefeed_radio_session_v1"
    private static let maximumEntryCount = 200

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let scheduler: RadioDebounceScheduling
    private var writeGeneration = 0

    init(
        defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        scheduler: RadioDebounceScheduling? = nil
    ) {
        self.defaults = defaults
        self.encoder = encoder
        self.decoder = decoder
        self.scheduler = scheduler ?? RadioDebounceScheduler()
    }

    func load(durations: [RadioEpisodeKey: TimeInterval]) throws -> PersistedRadioSession? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }

        do {
            let snapshot = try decoder.decode(PersistedRadioSession.self, from: data)
            return try Self.validate(snapshot, durations: durations)
        } catch {
            defaults.removeObject(forKey: Self.storageKey)
            return nil
        }
    }

    func saveDebounced(_ session: PersistedRadioSession) {
        writeGeneration &+= 1
        let generation = writeGeneration
        scheduler.cancel()
        scheduler.schedule(after: 10) { [weak self] in
            guard let self, self.writeGeneration == generation else { return }
            try? self.write(session)
        }
    }

    func saveNow(_ session: PersistedRadioSession) throws {
        writeGeneration &+= 1
        scheduler.cancel()
        try write(session)
    }

    func clear() {
        writeGeneration &+= 1
        scheduler.cancel()
        defaults.removeObject(forKey: Self.storageKey)
    }

    static func validate(
        _ snapshot: PersistedRadioSession,
        durations: [RadioEpisodeKey: TimeInterval]
    ) throws -> PersistedRadioSession {
        guard snapshot.schemaVersion == PersistedRadioSession.schemaVersion else {
            throw ValidationError.unsupportedSchema(snapshot.schemaVersion)
        }
        guard snapshot.entries.count <= maximumEntryCount else {
            throw ValidationError.tooManyEntries(snapshot.entries.count)
        }

        var seen = Set<RadioEpisodeKey>()
        var entries: [RadioQueueEntry] = []
        entries.reserveCapacity(snapshot.entries.count)

        for var entry in snapshot.entries where seen.insert(entry.key).inserted {
            if !entry.positionSeconds.isFinite || entry.positionSeconds < 0 {
                entry.positionSeconds = 0
            }
            if let duration = durations[entry.key], duration.isFinite, duration >= 0 {
                entry.positionSeconds = min(entry.positionSeconds, duration)
            }
            if entry.disposition == .playing || entry.disposition == .failedThisSession {
                entry.disposition = .pending
            }
            entry.playbackFailureCount = 0
            entry.lastPlaybackError = nil
            entries.append(entry)
        }

        let currentKey: RadioEpisodeKey?
        if let candidate = snapshot.currentKey {
            currentKey = entries.contains(where: {
                $0.key == candidate && $0.disposition != .retired
            }) ? candidate : entries.first(where: { $0.disposition != .retired })?.key
        } else {
            currentKey = nil
        }
        return PersistedRadioSession(
            schemaVersion: PersistedRadioSession.schemaVersion,
            entries: entries,
            currentKey: currentKey,
            savedAt: snapshot.savedAt
        )
    }

    private func write(_ session: PersistedRadioSession) throws {
        let normalized = try Self.validate(session, durations: [:])
        defaults.set(try encoder.encode(normalized), forKey: Self.storageKey)
    }
}
