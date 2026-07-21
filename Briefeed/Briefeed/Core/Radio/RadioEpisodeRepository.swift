import CoreData
import Foundation

struct RadioEpisodeCandidate: Equatable, Sendable {
    let key: RadioEpisodeKey
    let originalPlaybackURL: URL
    let canonicalEnclosureURL: String
    let title: String
    let sourceName: String
    let publicationDate: Date
    let durationSeconds: TimeInterval?
    let normalizedCoreDataProgress: Double
    let isCompleted: Bool
    let sourcePriority: Int
    let sourceFrequency: RSSUpdateFrequencyValue

    @MainActor
    init?(episode: RSSEpisode) {
        guard let feed = episode.feed, feed.isEnabled,
              let originalURL = URL(string: episode.audioUrl),
              let canonicalURL = try? RSSEpisodeIdentity.canonicalEnclosureURL(episode.audioUrl) else {
            return nil
        }
        let duration = episode.duration > 0 ? TimeInterval(episode.duration) : nil
        self.init(
            key: RadioEpisodeKey(feedID: episode.feedId, episodeID: episode.id),
            originalPlaybackURL: originalURL,
            canonicalEnclosureURL: canonicalURL,
            title: episode.title,
            sourceName: feed.displayName,
            publicationDate: episode.pubDate,
            durationSeconds: duration,
            normalizedCoreDataProgress: episode.lastPosition,
            isCompleted: episode.isListened,
            sourcePriority: Int(feed.priority),
            sourceFrequency: feed.updateFrequencyEnum == .hourly ? .hourly : .daily
        )
    }

    init(
        key: RadioEpisodeKey,
        originalPlaybackURL: URL,
        canonicalEnclosureURL: String,
        title: String,
        sourceName: String,
        publicationDate: Date,
        durationSeconds: TimeInterval?,
        normalizedCoreDataProgress: Double,
        isCompleted: Bool,
        sourcePriority: Int,
        sourceFrequency: RSSUpdateFrequencyValue
    ) {
        self.key = key
        self.originalPlaybackURL = originalPlaybackURL
        self.canonicalEnclosureURL = canonicalEnclosureURL
        self.title = title
        self.sourceName = sourceName
        self.publicationDate = publicationDate
        self.durationSeconds = durationSeconds
        self.normalizedCoreDataProgress = normalizedCoreDataProgress
        self.isCompleted = isCompleted
        self.sourcePriority = sourcePriority
        self.sourceFrequency = sourceFrequency
    }
}

extension RadioEpisodeCandidate {
    func displayTitle(
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard sourceFrequency == .hourly else { return title }
        let time = DateFormatter()
        time.locale = locale
        time.timeZone = timeZone
        time.dateFormat = "h a zzz"
        let date = DateFormatter()
        date.locale = locale
        date.timeZone = timeZone
        date.dateFormat = "M/d/yy"
        return "\(sourceIdentity): \(time.string(from: publicationDate)) · \(date.string(from: publicationDate))"
    }

    var sourceIdentity: String {
        switch key.feedID {
        case "npr-news-now": "NPR"
        case "abc-news-update": "ABC"
        case "cbs-on-the-hour": "CBS"
        case "cbc-world-this-hour": "CBC"
        default: sourceName
        }
    }
}

@MainActor
protocol RadioEpisodeRepository: AnyObject {
    func candidates() throws -> [RadioEpisodeCandidate]
    func candidate(for key: RadioEpisodeKey) throws -> RadioEpisodeCandidate?
    func saveProgress(key: RadioEpisodeKey, seconds: TimeInterval, duration: TimeInterval?) throws
    func markCompleted(key: RadioEpisodeKey, at date: Date) throws
    func restartForReplay(key: RadioEpisodeKey) throws -> RadioEpisodeCandidate?
}

@MainActor
final class CoreDataRadioEpisodeRepository: RadioEpisodeRepository {
    private let context: NSManagedObjectContext
    private let saveContext: () throws -> Void

    init(context: NSManagedObjectContext, saveContext: (() throws -> Void)? = nil) {
        self.context = context
        self.saveContext = saveContext ?? { try context.save() }
    }

    func candidates() throws -> [RadioEpisodeCandidate] {
        let request: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
        request.predicate = NSPredicate(format: "feed.isEnabled == YES")
        return try context.fetch(request).compactMap(RadioEpisodeCandidate.init(episode:))
    }

    func candidate(for key: RadioEpisodeKey) throws -> RadioEpisodeCandidate? {
        try episode(for: key).flatMap { RadioEpisodeCandidate(episode: $0) }
    }

    func saveProgress(key: RadioEpisodeKey, seconds: TimeInterval, duration: TimeInterval?) throws {
        guard let episode = try episode(for: key) else { return }
        guard !episode.isListened else { return }
        guard let duration, duration.isFinite, duration > 0, seconds.isFinite else { return }
        episode.lastPosition = min(max(seconds / duration, 0), 1)
        try saveContext()
    }

    func markCompleted(key: RadioEpisodeKey, at date: Date) throws {
        guard let episode = try episode(for: key) else { return }
        let previousIsListened = episode.isListened
        let previousListenedDate = episode.listenedDate
        let previousLastPosition = episode.lastPosition
        episode.isListened = true
        episode.listenedDate = date
        episode.lastPosition = 1
        do {
            try saveContext()
        } catch {
            episode.isListened = previousIsListened
            episode.listenedDate = previousListenedDate
            episode.lastPosition = previousLastPosition
            throw error
        }
    }

    func restartForReplay(key: RadioEpisodeKey) throws -> RadioEpisodeCandidate? {
        guard let episode = try episode(for: key) else { return nil }
        let previousIsListened = episode.isListened
        let previousListenedDate = episode.listenedDate
        let previousLastPosition = episode.lastPosition
        episode.isListened = false
        episode.listenedDate = nil
        episode.lastPosition = 0
        do {
            try saveContext()
            return RadioEpisodeCandidate(episode: episode)
        } catch {
            episode.isListened = previousIsListened
            episode.listenedDate = previousListenedDate
            episode.lastPosition = previousLastPosition
            throw error
        }
    }

    private func episode(for key: RadioEpisodeKey) throws -> RSSEpisode? {
        let request: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "feedId == %@ AND id == %@", key.feedID, key.episodeID)
        return try context.fetch(request).first
    }

}
