import Combine
import Foundation

@MainActor
protocol BriefQueueCoordinating: AnyObject {
    var queue: [QueueItem] { get }
    var currentIndex: Int { get }
    var currentPosition: TimeInterval { get }
    var currentItem: QueueItem? { get }
    var itemCount: Int { get }
    var queuePublisher: AnyPublisher<[QueueItem], Never> { get }
    var currentIndexPublisher: AnyPublisher<Int, Never> { get }

    func addArticle(_ article: Article, playNow: Bool, playNext: Bool)
    func addEpisode(_ episode: RSSEpisode, playNow: Bool, playNext: Bool)
    func removeItem(at index: Int)
    func clearQueue()
    func setCurrentIndex(_ index: Int)
    func updateCurrentPosition(_ position: TimeInterval)
    func markCurrentAsListened()
    func updateCachedAudioURL(for itemID: UUID, url: URL?)
    func markItemFailed(for itemID: UUID, error: String)
    func autoRemoveIfListened(at index: Int) -> UUID?
    func saveStateNow()
}

extension QueueCoordinator: BriefQueueCoordinating {
    var queuePublisher: AnyPublisher<[QueueItem], Never> { $queue.eraseToAnyPublisher() }
    var currentIndexPublisher: AnyPublisher<Int, Never> { $currentIndex.eraseToAnyPublisher() }
}
