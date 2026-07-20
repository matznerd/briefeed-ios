#if DEBUG
import AVFoundation
import Combine
import CoreData
import Foundation

enum RadioFixtureScenario: String, CaseIterable, Sendable {
    case partial
    case completed
    case offline
    case allFailed = "all-failed"
    case degraded
    case noSources = "no-sources"
    case refreshing
    case exhausted
}

@MainActor
final class RadioFixtureConnectivityMonitor: ConnectivityMonitoring {
    private let subject: CurrentValueSubject<ConnectivityStatus, Never>

    var status: ConnectivityStatus { subject.value }
    var statusPublisher: AnyPublisher<ConnectivityStatus, Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    init(initialStatus: ConnectivityStatus) {
        subject = CurrentValueSubject(initialStatus)
    }

    func send(_ status: ConnectivityStatus) {
        subject.send(status)
    }
}

struct RadioFixtureScenarioDefinition {
    let scenario: RadioFixtureScenario
    let now: Date
    let initialConnectivity: ConnectivityStatus
    let enabledSourceCount: Int

    static func make(scenario: RadioFixtureScenario, now: Date) -> Self {
        Self(
            scenario: scenario,
            now: now,
            initialConnectivity: scenario == .offline ? .offline : .online,
            enabledSourceCount: scenario == .noSources ? 0 : RadioFixtureSeeder.feedIDs.count
        )
    }

    @MainActor
    func applyPostRestore(to coordinator: RadioSessionCoordinating) -> RadioPlaybackIntent? {
        switch scenario {
        case .partial, .completed:
            return nil

        case .offline:
            return coordinator.beginCurrent()

        case .refreshing:
            coordinator.refreshStarted(enabledSourceCount: enabledSourceCount)
            return nil

        case .allFailed:
            coordinator.refreshStarted(enabledSourceCount: enabledSourceCount)
            return coordinator.applyRefresh(
                RSSRefreshBatchResult(results: RadioFixtureSeeder.feedIDs.map {
                    RSSFeedRefreshResult(feedID: $0, outcome: .failed(message: "Fixture source unavailable"))
                })
            )

        case .degraded:
            coordinator.refreshStarted(enabledSourceCount: enabledSourceCount)
            return coordinator.applyRefresh(
                RSSRefreshBatchResult(results: [
                    RSSFeedRefreshResult(
                        feedID: RadioFixtureSeeder.feedIDs[2],
                        outcome: .failed(message: "Fixture source unavailable")
                    )
                ])
            )

        case .noSources:
            return coordinator.sourceConfigurationDidChange(enabledSourceCount: 0)

        case .exhausted:
            coordinator.refreshStarted(enabledSourceCount: enabledSourceCount)
            return coordinator.applyRefresh(
                RSSRefreshBatchResult(results: RadioFixtureSeeder.feedIDs.map {
                    RSSFeedRefreshResult(feedID: $0, outcome: .skippedFresh(lastSuccessfulRefresh: now))
                })
            )
        }
    }
}

@MainActor
struct RadioFixtureSeeder {
    enum EpisodeID {
        static let partial = "fixture-partial"
        static let fresh = "fixture-fresh"
        static let completed = "fixture-completed"
        static let stale = "fixture-stale"
        static let malformed = "fixture-malformed"
        static let duplicateGUID = "fixture-duplicate-guid"
        static let duplicateEnclosure = "fixture-duplicate-enclosure"
    }

    static let feedIDs = ["fixture-npr", "fixture-bbc", "fixture-world"]
    private static let audioDuration: TimeInterval = 90
    private static let sampleRate = 44_100.0

    private let context: NSManagedObjectContext
    private let applicationSupportDirectory: URL
    private let now: () -> Date

    init(
        context: NSManagedObjectContext,
        applicationSupportDirectory: URL? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.now = now
    }

    func seed(scenario: RadioFixtureScenario, reset: Bool) throws {
        if reset {
            try deleteIsolatedRadioContent()
        } else if try hasSeededFixtureContent() {
            return
        }

        let audioURL = try makeAudioFileIfNeeded()
        let clock = now()
        let shouldHavePlayableEntries = ![.allFailed, .refreshing, .exhausted].contains(scenario)
        let feeds = try makeFeeds(scenario: scenario, clock: clock)

        makeEpisode(
            feed: feeds[0],
            id: EpisodeID.partial,
            title: "Morning Update",
            audioURL: "https://fixtures.briefeed.test/npr/morning-update.wav",
            publicationDate: clock.addingTimeInterval(-10 * 60),
            downloadedFilePath: scenario == .offline ? nil : audioURL.path,
            normalizedPosition: scenario == .partial || scenario == .degraded ? 0.2 : 0,
            completed: scenario == .completed || !shouldHavePlayableEntries
        )
        makeEpisode(
            feed: feeds[1],
            id: EpisodeID.fresh,
            title: "World Service Brief",
            audioURL: "https://fixtures.briefeed.test/bbc/world-service.wav",
            publicationDate: clock.addingTimeInterval(-12 * 60),
            downloadedFilePath: scenario == .offline ? nil : audioURL.path,
            completed: !shouldHavePlayableEntries
        )
        makeEpisode(
            feed: feeds[0],
            id: EpisodeID.completed,
            title: "Completed Hourly Update",
            audioURL: "https://fixtures.briefeed.test/npr/completed.wav",
            publicationDate: clock.addingTimeInterval(-35 * 60),
            downloadedFilePath: audioURL.path,
            normalizedPosition: 1,
            completed: true
        )
        makeEpisode(
            feed: feeds[1],
            id: EpisodeID.stale,
            title: "Stale Bulletin",
            audioURL: "https://fixtures.briefeed.test/bbc/stale.wav",
            publicationDate: clock.addingTimeInterval(-3 * 60 * 60),
            downloadedFilePath: audioURL.path
        )
        makeEpisode(
            feed: feeds[2],
            id: EpisodeID.malformed,
            title: "Malformed Enclosure",
            audioURL: "http://[",
            publicationDate: clock.addingTimeInterval(-15 * 60)
        )
        makeEpisode(
            feed: feeds[0],
            id: EpisodeID.duplicateGUID,
            title: "NPR Shared GUID",
            audioURL: "https://fixtures.briefeed.test/npr/shared-guid.wav",
            publicationDate: clock.addingTimeInterval(-50 * 60),
            downloadedFilePath: audioURL.path,
            completed: !shouldHavePlayableEntries
        )
        makeEpisode(
            feed: feeds[2],
            id: EpisodeID.duplicateGUID,
            title: "World Shared GUID",
            audioURL: "https://fixtures.briefeed.test/world/shared-guid.wav",
            publicationDate: clock.addingTimeInterval(-45 * 60),
            downloadedFilePath: audioURL.path,
            completed: !shouldHavePlayableEntries
        )
        makeEpisode(
            feed: feeds[2],
            id: EpisodeID.duplicateEnclosure,
            title: "Duplicate Enclosure",
            audioURL: "https://fixtures.briefeed.test/bbc/world-service.wav",
            publicationDate: clock.addingTimeInterval(-20 * 60),
            downloadedFilePath: audioURL.path,
            completed: !shouldHavePlayableEntries
        )

        if context.hasChanges { try context.save() }
    }

    private func hasSeededFixtureContent() throws -> Bool {
        let request: NSFetchRequest<RSSFeed> = RSSFeed.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id IN %@", Self.feedIDs)
        return try context.fetch(request).first != nil
    }

    private func deleteIsolatedRadioContent() throws {
        for episode in try context.fetch(RSSEpisode.fetchRequest()) {
            context.delete(episode)
        }
        for feed in try context.fetch(RSSFeed.fetchRequest()) {
            context.delete(feed)
        }
        if context.hasChanges { try context.save() }
        context.reset()
    }

    private func makeFeeds(scenario: RadioFixtureScenario, clock: Date) throws -> [RSSFeed] {
        let names = ["NPR News Now", "BBC World Service", "World Radio"]
        return zip(Self.feedIDs, names).enumerated().map { index, pair in
            let feed = RSSFeed(context: context)
            feed.id = pair.0
            feed.url = "https://fixtures.briefeed.test/\(pair.0).xml"
            feed.displayName = pair.1
            feed.updateFrequency = "hourly"
            feed.priority = Int16(index)
            feed.isEnabled = scenario != .noSources
            feed.lastFetchDate = clock.addingTimeInterval(-60 * 60)
            feed.createdDate = clock.addingTimeInterval(-24 * 60 * 60)
            return feed
        }
    }

    private func makeEpisode(
        feed: RSSFeed,
        id: String,
        title: String,
        audioURL: String,
        publicationDate: Date,
        downloadedFilePath: String? = nil,
        normalizedPosition: Double = 0,
        completed: Bool = false
    ) {
        let episode = RSSEpisode(context: context)
        episode.id = id
        episode.feedId = feed.id
        episode.title = title
        episode.audioUrl = audioURL
        episode.pubDate = publicationDate
        episode.duration = Int32(Self.audioDuration)
        episode.episodeDescription = "Deterministic local Radio fixture."
        episode.isListened = completed
        episode.listenedDate = completed ? now() : nil
        episode.lastPosition = completed ? 1 : normalizedPosition
        episode.hasBeenQueued = false
        episode.downloadedFilePath = downloadedFilePath
        episode.feed = feed
        feed.addToEpisodes(episode)
    }

    private func makeAudioFileIfNeeded() throws -> URL {
        let directory = applicationSupportDirectory
            .appendingPathComponent("BriefeedRadioFixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("radio-fixture-90s.wav")
        if FileManager.default.isReadableFile(atPath: url.path),
           let audio = try? AVAudioFile(forReading: url),
           Double(audio.length) / audio.processingFormat.sampleRate >= Self.audioDuration {
            return url
        }
        try? FileManager.default.removeItem(at: url)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw FixtureError.audioFormatUnavailable
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let framesPerChunk = AVAudioFrameCount(Self.sampleRate)

        for second in 0..<Int(Self.audioDuration) {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerChunk),
                  let samples = buffer.floatChannelData?[0] else {
                throw FixtureError.audioBufferUnavailable
            }
            buffer.frameLength = framesPerChunk
            let frequency = second.isMultiple(of: 2) ? 440.0 : 660.0
            for frame in 0..<Int(framesPerChunk) {
                let phase = Double(frame) / Self.sampleRate
                samples[frame] = Float(sin(2 * Double.pi * frequency * phase) * 0.025)
            }
            try file.write(from: buffer)
        }
        return url
    }

    private enum FixtureError: Error {
        case audioFormatUnavailable
        case audioBufferUnavailable
    }
}
#endif
