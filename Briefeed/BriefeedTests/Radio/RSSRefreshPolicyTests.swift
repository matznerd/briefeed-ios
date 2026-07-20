import Foundation
import Testing
@testable import Briefeed

@Suite("RSS refresh policy")
struct RSSRefreshPolicyTests {
    @Test func stalenessUsesThirtyMinutesAndSixHours() {
        let now = Date(timeIntervalSince1970: 10_000_000)

        #expect(RSSRefreshPolicy.isStale(.hourly, lastSuccess: now.addingTimeInterval(-1_801), now: now))
        #expect(!RSSRefreshPolicy.isStale(.hourly, lastSuccess: now.addingTimeInterval(-1_799), now: now))
        #expect(RSSRefreshPolicy.isStale(.daily, lastSuccess: now.addingTimeInterval(-21_601), now: now))
        #expect(!RSSRefreshPolicy.isStale(.daily, lastSuccess: now.addingTimeInterval(-21_599), now: now))
    }

    @Test func skippedFreshSourceEvidenceRequiresARecordedSuccess() {
        let date = Date(timeIntervalSince1970: 10_000_000)
        let batch = RSSRefreshBatchResult(results: [
            RSSFeedRefreshResult(feedID: "fresh", outcome: .skippedFresh(lastSuccessfulRefresh: date)),
            RSSFeedRefreshResult(feedID: "offline", outcome: .skippedOffline)
        ])

        #expect(batch.successfulSourceEvidenceCount == 1)
        #expect(batch.attemptedFailureCount == 0)
    }
}
