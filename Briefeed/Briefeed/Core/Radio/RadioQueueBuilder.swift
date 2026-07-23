import Foundation

struct RadioEpisodeFreshnessPolicy {
    static func isFresh(
        _ candidate: RadioEpisodeCandidate,
        at now: Date
    ) -> Bool {
        guard !candidate.isCompleted else { return false }
        return now.timeIntervalSince(candidate.publicationDate)
            <= freshness(for: candidate.sourceFrequency)
    }

    static func isRetained(
        _ candidate: RadioEpisodeCandidate,
        at now: Date
    ) -> Bool {
        guard !candidate.isCompleted else { return false }
        return now.timeIntervalSince(candidate.publicationDate)
            <= retention(for: candidate.sourceFrequency)
    }

    private static func freshness(
        for frequency: RSSUpdateFrequencyValue
    ) -> TimeInterval {
        frequency == .hourly ? 2 * 60 * 60 : 24 * 60 * 60
    }

    private static func retention(
        for frequency: RSSUpdateFrequencyValue
    ) -> TimeInterval {
        frequency == .hourly ? 24 * 60 * 60 : 7 * 24 * 60 * 60
    }
}

struct RadioQueueBuilder {
    let now: Date

    func buildInitial(candidates: [RadioEpisodeCandidate]) -> PersistedRadioSession {
        let selected = newestCandidatePerSource(from: candidates)
            .filter(isFresh)
        return makeSession(entries: selected.map(makePendingEntry), currentKey: selected.first?.key)
    }

    func restore(snapshot: PersistedRadioSession, candidates: [RadioEpisodeCandidate]) -> PersistedRadioSession {
        let restored = validated(
            snapshot: snapshot,
            candidates: candidates,
            normalizePlaying: true,
            resetSessionFailures: true
        )
        let candidatesByKey = dictionaryByKey(candidates)
        let existingKeys = Set(restored.entries.map(\.key))
        let existingEnclosures = Set(restored.entries.compactMap { candidatesByKey[$0.key]?.canonicalEnclosureURL })
        let reservedSources = reservedAutomaticSourceIDs(in: restored)
        let appended = newestCandidatePerSource(from: candidates)
            .filter(isFresh)
            .filter { !existingKeys.contains($0.key) }
            .filter { !existingEnclosures.contains($0.canonicalEnclosureURL) }
            .filter { !reservedSources.contains($0.key.feedID) }
            .map(makePendingEntry)
        let preservedCurrent = restored.entries.first { entry in
            entry.key == snapshot.currentKey
                && entry.disposition != .failedThisSession
                && entry.disposition != .retired
        }
        let nonCurrent = restored.entries.filter { $0.key != preservedCurrent?.key }
        let pending = sortPending(nonCurrent.filter { $0.disposition == .pending } + appended, candidatesByKey: candidatesByKey)
        let deferred = nonCurrent.filter { $0.disposition == .deferred }
        let retired = nonCurrent.filter { $0.disposition == .retired }
        let failed = nonCurrent.filter { $0.disposition == .failedThisSession }
        let entries = (preservedCurrent.map { [$0] } ?? []) + pending + deferred + retired + failed
        let currentKey = preservedCurrent?.key ?? pending.first?.key ?? deferred.first?.key
        return makeSession(entries: entries, currentKey: currentKey)
    }

    func reconcile(snapshot: PersistedRadioSession, candidates: [RadioEpisodeCandidate]) -> PersistedRadioSession {
        let restored = validated(
            snapshot: snapshot,
            candidates: candidates,
            normalizePlaying: false,
            resetSessionFailures: false
        )
        let candidatesByKey = dictionaryByKey(candidates)
        let currentEntry = restored.entries.first { entry in
            entry.key == snapshot.currentKey
                && entry.disposition != .failedThisSession
                && entry.disposition != .retired
        }
        let nonCurrent = restored.entries.filter { $0.key != currentEntry?.key }
        let deferred = nonCurrent.filter { $0.disposition == .deferred }
        let retired = nonCurrent.filter { $0.disposition == .retired }
        let failed = nonCurrent.filter { $0.disposition == .failedThisSession }
        let existingEnclosures = Set(restored.entries.compactMap { candidatesByKey[$0.key]?.canonicalEnclosureURL })
        let existingKeys = Set(restored.entries.map(\.key))
        let reservedSources = reservedAutomaticSourceIDs(in: restored)
        let appended = newestCandidatePerSource(from: candidates)
            .filter(isFresh)
            .filter { !existingKeys.contains($0.key) }
            .filter { !existingEnclosures.contains($0.canonicalEnclosureURL) }
            .filter { !reservedSources.contains($0.key.feedID) }

        let pending = sortPending(nonCurrent.filter { $0.disposition == .pending } + appended.map(makePendingEntry), candidatesByKey: candidatesByKey)

        let entries = (currentEntry.map { [$0] } ?? []) + pending + deferred + retired + failed
        let currentKey = currentEntry?.key ?? pending.first?.key ?? deferred.first?.key
        return makeSession(entries: entries, currentKey: currentKey)
    }

    private func validated(
        snapshot: PersistedRadioSession,
        candidates: [RadioEpisodeCandidate],
        normalizePlaying: Bool,
        resetSessionFailures: Bool
    ) -> PersistedRadioSession {
        let candidatesByKey = dictionaryByKey(candidates)
        let latestAutomaticBySource = Dictionary(
            uniqueKeysWithValues: newestCandidatePerSource(from: candidates).map { ($0.key.feedID, $0.key) }
        )
        let protectedCurrentKey: RadioEpisodeKey? = {
            guard !normalizePlaying,
                  let currentKey = snapshot.currentKey,
                  snapshot.entries.contains(where: {
                      $0.key == currentKey && $0.disposition == .playing
                  }) else { return nil }
            return currentKey
        }()
        let protectedCurrentSource = protectedCurrentKey?.feedID
        var seenKeys = Set<RadioEpisodeKey>()
        var seenEnclosures = Set<String>()
        var seenAutomaticSources = Set<String>()
        var retained: [RadioQueueEntry] = []

        for entry in snapshot.entries where seenKeys.insert(entry.key).inserted {
            guard let candidate = candidatesByKey[entry.key], isRetained(candidate) else { continue }
            if !entry.isManuallyQueued {
                if candidate.key.feedID == protectedCurrentSource {
                    guard candidate.key == protectedCurrentKey else { continue }
                } else {
                    guard latestAutomaticBySource[candidate.key.feedID] == candidate.key else { continue }
                }
                guard seenAutomaticSources.insert(candidate.key.feedID).inserted else { continue }
            }
            guard seenEnclosures.insert(candidate.canonicalEnclosureURL).inserted else { continue }
            retained.append(repaired(
                entry,
                candidate: candidate,
                normalizePlaying: normalizePlaying,
                resetSessionFailures: resetSessionFailures
            ))
        }

        let currentKey = retained.contains(where: {
            $0.key == snapshot.currentKey
                && $0.disposition != .failedThisSession
                && $0.disposition != .retired
        })
            ? snapshot.currentKey
            : retained.first(where: { $0.disposition == .pending })?.key
                ?? retained.first(where: { $0.disposition == .deferred })?.key
        return makeSession(entries: retained, currentKey: currentKey)
    }

    func nextEligible(in session: PersistedRadioSession) -> RadioEpisodeKey? {
        session.entries.first(where: { $0.key != session.currentKey && $0.disposition == .pending })?.key
            ?? session.entries.first(where: { $0.key != session.currentKey && $0.disposition == .deferred })?.key
    }

    func isEligibleForManualSelection(_ candidate: RadioEpisodeCandidate) -> Bool {
        isRetained(candidate)
    }

    private func newestCandidatePerSource(from candidates: [RadioEpisodeCandidate]) -> [RadioEpisodeCandidate] {
        Dictionary(grouping: candidates, by: { $0.key.feedID })
            .values
            .compactMap { $0.sorted(by: candidateSort).first }
            .filter { !$0.isCompleted }
            .sorted(by: candidateSort)
            .reduce(into: (seenKeys: Set<RadioEpisodeKey>(), seenEnclosures: Set<String>(), result: [RadioEpisodeCandidate]())) { state, candidate in
                guard state.seenKeys.insert(candidate.key).inserted,
                      state.seenEnclosures.insert(candidate.canonicalEnclosureURL).inserted else { return }
                state.result.append(candidate)
            }.result
    }

    private func dictionaryByKey(_ candidates: [RadioEpisodeCandidate]) -> [RadioEpisodeKey: RadioEpisodeCandidate] {
        candidates.sorted(by: candidateSort).reduce(into: [:]) { result, candidate in
            result[candidate.key] = result[candidate.key] ?? candidate
        }
    }

    private func reservedAutomaticSourceIDs(in session: PersistedRadioSession) -> Set<String> {
        Set(session.entries.compactMap { entry in
            (!entry.isManuallyQueued || entry.key == session.currentKey) ? entry.key.feedID : nil
        })
    }

    private func candidateSort(_ lhs: RadioEpisodeCandidate, _ rhs: RadioEpisodeCandidate) -> Bool {
        if lhs.sourcePriority != rhs.sourcePriority { return lhs.sourcePriority < rhs.sourcePriority }
        if lhs.key.feedID != rhs.key.feedID { return lhs.key.feedID < rhs.key.feedID }
        if lhs.publicationDate != rhs.publicationDate { return lhs.publicationDate > rhs.publicationDate }
        return lhs.key.episodeID < rhs.key.episodeID
    }

    private func sortPending(
        _ entries: [RadioQueueEntry],
        candidatesByKey: [RadioEpisodeKey: RadioEpisodeCandidate]
    ) -> [RadioQueueEntry] {
        entries.sorted { lhs, rhs in
            guard let left = candidatesByKey[lhs.key], let right = candidatesByKey[rhs.key] else {
                return lhs.key.feedID == rhs.key.feedID ? lhs.key.episodeID < rhs.key.episodeID : lhs.key.feedID < rhs.key.feedID
            }
            return candidateSort(left, right)
        }
    }

    private func isFresh(_ candidate: RadioEpisodeCandidate) -> Bool {
        RadioEpisodeFreshnessPolicy.isFresh(candidate, at: now)
    }

    private func isRetained(_ candidate: RadioEpisodeCandidate) -> Bool {
        RadioEpisodeFreshnessPolicy.isRetained(candidate, at: now)
    }

    private func repaired(
        _ entry: RadioQueueEntry,
        candidate: RadioEpisodeCandidate,
        normalizePlaying: Bool,
        resetSessionFailures: Bool
    ) -> RadioQueueEntry {
        var repaired = entry
        repaired.positionSeconds = entry.positionSeconds.isFinite && entry.positionSeconds > 0 ? entry.positionSeconds : 0
        if let duration = candidate.durationSeconds, duration.isFinite, duration > 0 {
            repaired.positionSeconds = min(repaired.positionSeconds, duration)
        }
        if normalizePlaying && repaired.disposition == .playing { repaired.disposition = .pending }
        if resetSessionFailures && repaired.disposition == .failedThisSession {
            repaired.disposition = .pending
            repaired.playbackFailureCount = 0
            repaired.lastPlaybackError = nil
        }
        return repaired
    }

    private func makePendingEntry(_ candidate: RadioEpisodeCandidate) -> RadioQueueEntry {
        let progress = candidate.normalizedCoreDataProgress
        let position: TimeInterval
        if let duration = candidate.durationSeconds, duration.isFinite, duration > 0, progress.isFinite {
            position = min(max(progress, 0), 1) * duration
        } else {
            position = 0
        }
        return RadioQueueEntry(key: candidate.key, positionSeconds: position, disposition: .pending, playbackFailureCount: 0, lastPlaybackError: nil)
    }

    private func makeSession(entries: [RadioQueueEntry], currentKey: RadioEpisodeKey?) -> PersistedRadioSession {
        PersistedRadioSession(schemaVersion: PersistedRadioSession.schemaVersion, entries: entries, currentKey: currentKey, savedAt: now)
    }
}
