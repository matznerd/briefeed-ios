import Foundation
import Testing
@testable import Briefeed

@MainActor
@Suite("Radio transcript background task driver")
struct RadioTranscriptBackgroundTaskDriverTests {
    @Test func submitUsesUniquePermittedIdentifierAndImmediateFailStrategy() {
        let scheduler = TestContinuedProcessingScheduler()
        let driver = RadioTranscriptBackgroundTaskDriver(
            scheduler: scheduler,
            bundleIdentifier: "com.example.Briefeed",
            availability: { true }
        )
        let batchID = UUID()

        let first = driver.submit(
            batchID: batchID,
            total: 3,
            onExpiration: {}
        )
        let second = driver.submit(
            batchID: batchID,
            total: 3,
            onExpiration: {}
        )

        guard case .accepted(let firstIdentifier) = first,
              case .accepted(let secondIdentifier) = second else {
            Issue.record("Expected accepted continued-processing submissions")
            return
        }
        #expect(firstIdentifier != secondIdentifier)
        #expect(
            firstIdentifier.hasPrefix(
                "com.example.Briefeed.radio-transcripts."
            )
        )
        #expect(scheduler.requests.map(\.strategy) == [.fail, .fail])
        #expect(scheduler.requests.allSatisfy { $0.title == "Preparing Radio" })
    }

    @Test func progressIsMonotonicAndUsesDurableCompletionCounts() {
        let scheduler = TestContinuedProcessingScheduler()
        let driver = RadioTranscriptBackgroundTaskDriver(
            scheduler: scheduler,
            bundleIdentifier: "com.example.Briefeed",
            availability: { true }
        )
        _ = driver.submit(batchID: UUID(), total: 4, onExpiration: {})
        let task = scheduler.launchLatest()

        driver.update(completed: 2, total: 4)
        driver.update(completed: 1, total: 4)
        driver.update(completed: 8, total: 4)

        #expect(task.progress.totalUnitCount == 4)
        #expect(task.progress.completedUnitCount == 4)
        #expect(task.subtitles == [
            "0 of 4 ready",
            "2 of 4 ready",
            "2 of 4 ready",
            "4 of 4 ready"
        ])
    }

    @Test func expirationCancelsTheOwnedBatchAndCompletesFailure() {
        let scheduler = TestContinuedProcessingScheduler()
        let driver = RadioTranscriptBackgroundTaskDriver(
            scheduler: scheduler,
            bundleIdentifier: "com.example.Briefeed",
            availability: { true }
        )
        var expirationCount = 0
        _ = driver.submit(batchID: UUID(), total: 2) {
            expirationCount += 1
        }
        let task = scheduler.launchLatest()

        task.expire()

        #expect(expirationCount == 1)
        #expect(task.completions == [false])
    }

    @Test func rejectionIsReportedWithoutOwningOrCancelingForegroundWork() {
        let scheduler = TestContinuedProcessingScheduler()
        scheduler.submissionError = TestSchedulerError.rejected
        let driver = RadioTranscriptBackgroundTaskDriver(
            scheduler: scheduler,
            bundleIdentifier: "com.example.Briefeed",
            availability: { true }
        )
        var expirationCount = 0

        let result = driver.submit(batchID: UUID(), total: 2) {
            expirationCount += 1
        }
        driver.cancel()

        guard case .rejected = result else {
            Issue.record("Expected the driver to surface submission rejection")
            return
        }
        #expect(expirationCount == 0)
        #expect(scheduler.canceledIdentifiers.isEmpty)
    }

    @Test func completionIsDeliveredAtMostOnce() {
        let scheduler = TestContinuedProcessingScheduler()
        let driver = RadioTranscriptBackgroundTaskDriver(
            scheduler: scheduler,
            bundleIdentifier: "com.example.Briefeed",
            availability: { true }
        )
        _ = driver.submit(batchID: UUID(), total: 1, onExpiration: {})
        let task = scheduler.launchLatest()

        driver.complete(success: true)
        driver.complete(success: false)
        task.expire()

        #expect(task.completions == [true])
    }
}

private enum TestSchedulerError: Error {
    case rejected
}

@MainActor
private final class TestContinuedProcessingScheduler:
    RadioContinuedProcessingScheduling
{
    var submissionError: Error?
    private(set) var requests: [RadioContinuedProcessingRequest] = []
    private(set) var canceledIdentifiers: [String] = []
    private var launchHandlers: [
        String: @MainActor (any RadioContinuedProcessingTask) -> Void
    ] = [:]

    func submit(
        _ request: RadioContinuedProcessingRequest,
        launchHandler: @escaping @MainActor (
            any RadioContinuedProcessingTask
        ) -> Void
    ) throws {
        if let submissionError { throw submissionError }
        requests.append(request)
        launchHandlers[request.identifier] = launchHandler
    }

    func cancel(identifier: String) {
        canceledIdentifiers.append(identifier)
    }

    func launchLatest() -> TestContinuedProcessingTask {
        guard let request = requests.last,
              let launch = launchHandlers[request.identifier] else {
            fatalError("No submitted continued-processing request")
        }
        let task = TestContinuedProcessingTask()
        launch(task)
        return task
    }
}

@MainActor
private final class TestContinuedProcessingTask:
    RadioContinuedProcessingTask
{
    let progress = Progress(totalUnitCount: 0)
    var expirationHandler: (@MainActor @Sendable () -> Void)?
    private(set) var subtitles: [String] = []
    private(set) var completions: [Bool] = []

    func update(title: String, subtitle: String) {
        subtitles.append(subtitle)
    }

    func setTaskCompleted(success: Bool) {
        completions.append(success)
    }

    func expire() {
        expirationHandler?()
    }
}
