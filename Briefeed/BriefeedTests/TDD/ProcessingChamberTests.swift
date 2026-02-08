//
//  ProcessingChamberTests.swift
//  BriefeedTests
//
//  Tests for the Processing Chamber: auto-remove played items + bookmark
//

import XCTest
@testable import Briefeed

final class ProcessingChamberTests: XCTestCase {

    private func makeQueueItem(
        isListened: Bool = false,
        isBookmarked: Bool = false,
        summaryState: SummaryState = .ready
    ) -> QueueItem {
        QueueItem(
            id: UUID(),
            type: .article,
            title: "Test Article",
            source: "Test Source",
            addedAt: Date(),
            expiresAt: nil,
            articleID: UUID(),
            summaryState: summaryState,
            cachedAudioURL: nil,
            episodeID: nil,
            streamURL: nil,
            lastPosition: 0,
            isListened: isListened,
            isBookmarked: isBookmarked
        )
    }

    // MARK: - Auto-Remove Tests

    @MainActor
    func testAutoRemove_UnbookmarkedListenedItem_IsRemoved() {
        let coordinator = QueueCoordinator.shared
        coordinator.clearQueue()

        let item = makeQueueItem(isListened: true, isBookmarked: false)
        coordinator.injectForTesting([item])
        coordinator.setCurrentIndex(0)

        let removedID = coordinator.autoRemoveIfListened(at: 0)
        XCTAssertNotNil(removedID, "Listened, unbookmarked item should be removed")
        XCTAssertEqual(removedID, item.id)
    }

    @MainActor
    func testAutoRemove_BookmarkedListenedItem_IsKept() {
        let coordinator = QueueCoordinator.shared
        coordinator.clearQueue()

        let item = makeQueueItem(isListened: true, isBookmarked: true)
        coordinator.injectForTesting([item])
        coordinator.setCurrentIndex(0)

        let removedID = coordinator.autoRemoveIfListened(at: 0)
        XCTAssertNil(removedID, "Bookmarked item should NOT be removed even if listened")
        XCTAssertEqual(coordinator.queue.count, 1)
    }

    @MainActor
    func testAutoRemove_UnlistenedItem_IsKept() {
        let coordinator = QueueCoordinator.shared
        coordinator.clearQueue()

        let item = makeQueueItem(isListened: false, isBookmarked: false)
        coordinator.injectForTesting([item])

        let removedID = coordinator.autoRemoveIfListened(at: 0)
        XCTAssertNil(removedID, "Unlistened item should NOT be removed")
        XCTAssertEqual(coordinator.queue.count, 1)
    }

    // MARK: - Bookmark Tests

    @MainActor
    func testToggleBookmark_TogglesCorrectly() {
        let coordinator = QueueCoordinator.shared
        coordinator.clearQueue()

        let item = makeQueueItem(isBookmarked: false)
        coordinator.injectForTesting([item])

        // Toggle on
        coordinator.toggleBookmark(for: item.id)
        XCTAssertTrue(coordinator.queue[0].isBookmarked, "Bookmark should be toggled ON")

        // Toggle off
        coordinator.toggleBookmark(for: item.id)
        XCTAssertFalse(coordinator.queue[0].isBookmarked, "Bookmark should be toggled OFF")
    }

    // MARK: - Persistence Tests

    func testBookmarkPersistence_SurvivesReencode() throws {
        let item = makeQueueItem(isBookmarked: true)

        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(QueueItem.self, from: encoded)

        XCTAssertTrue(decoded.isBookmarked, "isBookmarked should survive encode/decode")
    }

    func testBackwardCompat_OldDataDefaultsBookmarkFalse() throws {
        // Encode a real QueueItem, strip isBookmarked from the JSON, then decode.
        // This simulates old persisted data that predates the isBookmarked field.
        let item = makeQueueItem(isBookmarked: false)
        let fullData = try JSONEncoder().encode(item)

        var dict = try JSONSerialization.jsonObject(with: fullData) as! [String: Any]
        dict.removeValue(forKey: "isBookmarked")
        let strippedData = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(QueueItem.self, from: strippedData)
        XCTAssertFalse(decoded.isBookmarked, "Missing isBookmarked should default to false")
    }

    // MARK: - Index Adjustment Tests

    @MainActor
    func testAutoRemove_IndexAdjustment_CurrentIndexCorrect() {
        let coordinator = QueueCoordinator.shared
        coordinator.clearQueue()

        // Add 3 items
        let item1 = makeQueueItem(isListened: true, isBookmarked: false)
        let item2 = makeQueueItem(isListened: false, isBookmarked: false)
        let item3 = makeQueueItem(isListened: false, isBookmarked: false)
        coordinator.injectForTesting([item1, item2, item3])
        coordinator.setCurrentIndex(1) // Point to item2

        // Remove item1 (before current)
        let _ = coordinator.autoRemoveIfListened(at: 0)

        // Current index should have adjusted down
        XCTAssertEqual(coordinator.currentIndex, 0, "Index should adjust when item before current is removed")
        XCTAssertEqual(coordinator.queue.count, 2)
    }

    @MainActor
    func testAutoRemove_CurrentItemRemoved_PointsToNextItem() {
        let coordinator = QueueCoordinator.shared
        coordinator.clearQueue()

        // Add 3 items
        let item1 = makeQueueItem(isListened: true, isBookmarked: false)
        let item2 = makeQueueItem(isListened: false, isBookmarked: false)
        let item3 = makeQueueItem(isListened: false, isBookmarked: false)
        coordinator.injectForTesting([item1, item2, item3])
        coordinator.setCurrentIndex(0) // Point to item1

        // Remove current item (item1)
        let _ = coordinator.autoRemoveIfListened(at: 0)

        // Should now point to what was item2 (now at index 0)
        XCTAssertEqual(coordinator.currentIndex, 0)
        XCTAssertEqual(coordinator.queue.count, 2)
        XCTAssertEqual(coordinator.queue[0].id, item2.id, "After removing current, should point to next item")
    }
}
