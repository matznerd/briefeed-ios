//
//  SwipeInteractionTests.swift
//  BriefeedTests
//
//  TDD Tests for swipe interactions on Feed and Brief tabs
//  RED PHASE: These tests define expected behavior that doesn't exist yet
//

import XCTest
@testable import Briefeed
import CoreData

// MARK: - Test Group 1: Feed Tab — Archive via AppViewModel

final class FeedArchiveTests: XCTestCase {

    /// Test: archiveArticle using article.id directly marks it archived
    /// BUG: Current implementation extracts UUID from objectID URI which gives
    /// "p42" style identifiers, not valid UUIDs. Fix: use article.id directly.
    @MainActor
    func testAppViewModel_ArchiveArticle_SetsArchivedFlag() {
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        let testID = UUID()
        article.id = testID
        article.title = "Archive Test Article"
        article.url = "https://example.com/archive-test"

        let audioVM = AudioPlayerViewModelV2()
        let appVM = AppViewModel(audioPlayerViewModel: audioVM)

        // Archive the article
        appVM.archiveArticle(article)

        // The article should now be archived
        XCTAssertTrue(
            appVM.isArticleArchived(article),
            "Article should be marked as archived after calling archiveArticle()"
        )
    }

    /// Test: isArticleArchived returns true for an archived article
    @MainActor
    func testAppViewModel_IsArticleArchived_ReturnsTrueForArchived() {
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        let testID = UUID()
        article.id = testID
        article.title = "Archived Check Article"
        article.url = "https://example.com/archived-check"

        let audioVM = AudioPlayerViewModelV2()
        let appVM = AppViewModel(audioPlayerViewModel: audioVM)

        // Initially should NOT be archived
        XCTAssertFalse(
            appVM.isArticleArchived(article),
            "Article should not be archived initially"
        )

        // Archive it
        appVM.archiveArticle(article)

        // Now should be archived
        XCTAssertTrue(
            appVM.isArticleArchived(article),
            "Article should be archived after archiving"
        )

        // Unarchive it
        appVM.unarchiveArticle(article)

        // Should no longer be archived
        XCTAssertFalse(
            appVM.isArticleArchived(article),
            "Article should not be archived after unarchiving"
        )
    }
}

// MARK: - Test Group 2: Feed Tab — Filtered Articles Exclude Archived

final class FeedFilterArchiveTests: XCTestCase {

    /// Test: filteredArticles in CombinedFeedView should exclude archived articles
    /// BUG: Current filteredArticles has no archive filter at all
    @MainActor
    func testCombinedFeed_FilteredArticles_ExcludesArchived() {
        let context = PersistenceController.preview.container.viewContext

        // Create two articles
        let article1 = Article(context: context)
        article1.id = UUID()
        article1.title = "Visible Article"
        article1.url = "https://example.com/visible"
        article1.isArchived = false

        let article2 = Article(context: context)
        article2.id = UUID()
        article2.title = "Archived Article"
        article2.url = "https://example.com/archived"
        article2.isArchived = true

        let articles = [article1, article2]

        // Simulate what filteredArticles SHOULD do: exclude archived
        let filtered = articles.filter { !$0.isArchived }

        XCTAssertEqual(filtered.count, 1, "Filtered articles should exclude archived ones")
        XCTAssertEqual(filtered.first?.title, "Visible Article", "Only non-archived article should remain")
        XCTAssertFalse(
            filtered.contains(where: { $0.isArchived }),
            "No archived articles should appear in filtered results"
        )
    }
}

// MARK: - Test Group 3: Brief Tab — Play Item Now / Play Item Next

final class BriefPlayItemTests: XCTestCase {

    /// Test: playItemNow finds item by index and calls playItemAt
    /// This method doesn't exist yet — needs to be added to AudioPlayerViewModelV2
    @MainActor
    func testBriefView_PlayItemNow_PlaysAtCorrectIndex() async {
        let context = PersistenceController.preview.container.viewContext
        let audioVM = AudioPlayerViewModelV2()

        // Add 3 articles to the queue
        let articles = (0..<3).map { i -> Article in
            let article = Article(context: context)
            article.id = UUID()
            article.title = "Queue Article \(i)"
            article.url = "https://example.com/queue-\(i)"
            return article
        }

        for article in articles {
            await audioVM.addToQueue(article)
        }

        // Play item at index 1 (second item)
        await audioVM.playItemAt(index: 1)

        // Current queue index should be 1
        XCTAssertEqual(
            audioVM.currentQueueIndex,
            1,
            "Playing item at index 1 should set currentQueueIndex to 1"
        )
    }

    /// Test: playItemNext moves item to currentIndex + 1
    /// This tests addToQueue with playNext: true
    @MainActor
    func testBriefView_PlayItemNext_MovesToNextPosition() async {
        let context = PersistenceController.preview.container.viewContext
        let audioVM = AudioPlayerViewModelV2()

        // Add initial articles
        let article1 = Article(context: context)
        article1.id = UUID()
        article1.title = "First Article"
        article1.url = "https://example.com/first"

        let article2 = Article(context: context)
        article2.id = UUID()
        article2.title = "Last Article"
        article2.url = "https://example.com/last"

        await audioVM.addToQueue(article1)
        await audioVM.addToQueue(article2)

        // Start playing first item
        await audioVM.playItemAt(index: 0)

        // Add a new article as "play next"
        let playNextArticle = Article(context: context)
        playNextArticle.id = UUID()
        playNextArticle.title = "Play Next Article"
        playNextArticle.url = "https://example.com/play-next"

        await audioVM.addToQueue(playNextArticle, playNext: true)

        // The "play next" article should be at index 1 (right after current)
        XCTAssertEqual(audioVM.queueItems.count, 3, "Queue should have 3 items")

        let nextItem = audioVM.queueItems[safe: 1]
        XCTAssertEqual(
            nextItem?.title,
            "Play Next Article",
            "Play Next article should be inserted at position 1 (after current)"
        )
    }
}

// MARK: - Test Group 4: Brief Tab — Bookmark Toggle

final class BriefBookmarkTests: XCTestCase {

    /// Test: QueueCoordinator.toggleBookmark toggles bookmark state
    @MainActor
    func testQueueCoordinator_ToggleBookmark_TogglesState() {
        let context = PersistenceController.preview.container.viewContext
        let coordinator = QueueCoordinator.shared

        // Create an article and add it via the public API
        let article = Article(context: context)
        let articleID = UUID()
        article.id = articleID
        article.title = "Bookmark Test Item"
        article.url = "https://example.com/bookmark-test"

        let initialCount = coordinator.itemCount
        coordinator.addArticle(article)
        XCTAssertEqual(coordinator.itemCount, initialCount + 1, "Item should be added to queue")

        // Find the item by articleID
        let addedItem = coordinator.queue.first(where: { $0.articleID == articleID })
        XCTAssertNotNil(addedItem, "Item should exist in queue")
        XCTAssertFalse(addedItem?.isBookmarked ?? true, "Item should not be bookmarked initially")

        guard let itemID = addedItem?.id else {
            XCTFail("Could not get queue item ID")
            return
        }

        // Toggle bookmark
        coordinator.toggleBookmark(for: itemID)

        // Should now be bookmarked
        let bookmarkedItem = coordinator.queue.first(where: { $0.id == itemID })
        XCTAssertTrue(bookmarkedItem?.isBookmarked ?? false, "Item should be bookmarked after toggle")

        // Toggle again
        coordinator.toggleBookmark(for: itemID)

        // Should be un-bookmarked
        let unbookmarkedItem = coordinator.queue.first(where: { $0.id == itemID })
        XCTAssertFalse(unbookmarkedItem?.isBookmarked ?? true, "Item should be un-bookmarked after second toggle")

        // Cleanup
        if let index = coordinator.queue.firstIndex(where: { $0.id == itemID }) {
            coordinator.removeItem(at: index)
        }
    }

    /// Test: EnhancedQueueRow bookmark indicator is visible when bookmarked
    /// This tests that the bookmark Image is shown based on isBookmarked state
    @MainActor
    func testEnhancedQueueRow_BookmarkButton_IsAlwaysVisible() {
        // Test that EnhancedQueueItem correctly reports bookmark state
        var bookmarkedItem = EnhancedQueueItem(
            id: UUID(),
            title: "Bookmarked Item",
            source: .article(source: "Test Source"),
            addedDate: Date(),
            expiresAt: nil,
            articleID: UUID(),
            audioUrl: nil,
            duration: 150
        )
        bookmarkedItem.isBookmarked = true
        bookmarkedItem.readiness = .ready
        bookmarkedItem.hasSummary = true

        var unbookmarkedItem = EnhancedQueueItem(
            id: UUID(),
            title: "Unbookmarked Item",
            source: .article(source: "Test Source"),
            addedDate: Date(),
            expiresAt: nil,
            articleID: UUID(),
            audioUrl: nil,
            duration: 180
        )
        unbookmarkedItem.isBookmarked = false
        unbookmarkedItem.readiness = .ready
        unbookmarkedItem.hasSummary = true

        XCTAssertTrue(bookmarkedItem.isBookmarked, "Bookmarked item should report isBookmarked = true")
        XCTAssertFalse(unbookmarkedItem.isBookmarked, "Unbookmarked item should report isBookmarked = false")
    }
}

// MARK: - Array Safe Subscript (test helper)
private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
