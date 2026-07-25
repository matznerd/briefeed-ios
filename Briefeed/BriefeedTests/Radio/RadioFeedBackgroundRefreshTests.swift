import Foundation
import Testing
@testable import Briefeed

@Suite("Radio feed background refresh") @MainActor
struct RadioFeedBackgroundRefreshTests {
    @Test func registrationAndSchedulingRequestTheNextHourlyRefreshWindow() {
        let now = Date(timeIntervalSince1970: 10_000)
        let scheduler = FakeRadioFeedBackgroundScheduler()
        let driver = RadioFeedBackgroundRefreshDriver(
            scheduler: scheduler,
            identifier: "com.example.Briefeed.radio-refresh",
            now: { now },
            refresh: { true }
        )

        #expect(driver.register())
        #expect(driver.schedule())
        #expect(scheduler.registeredIdentifiers == ["com.example.Briefeed.radio-refresh"])
        #expect(scheduler.cancelledIdentifiers == ["com.example.Briefeed.radio-refresh"])
        #expect(scheduler.submissions == [
            RadioFeedBackgroundRefreshRequest(
                identifier: "com.example.Briefeed.radio-refresh",
                earliestBeginDate: now.addingTimeInterval(45 * 60)
            )
        ])
    }

    @Test func launchReschedulesThenCompletesAfterRefresh() async {
        let scheduler = FakeRadioFeedBackgroundScheduler()
        var refreshCount = 0
        let driver = RadioFeedBackgroundRefreshDriver(
            scheduler: scheduler,
            identifier: "com.example.Briefeed.radio-refresh",
            refresh: {
                refreshCount += 1
                return true
            }
        )
        let task = FakeRadioFeedBackgroundTask()

        #expect(driver.register())
        scheduler.launch(task)
        await settle()

        #expect(refreshCount == 1)
        #expect(scheduler.submissions.count == 1)
        #expect(task.completions == [true])
    }

    @Test func expirationCancelsRefreshAndCompletesOnlyOnce() async {
        let scheduler = FakeRadioFeedBackgroundScheduler()
        let gate = BackgroundRefreshGate()
        let driver = RadioFeedBackgroundRefreshDriver(
            scheduler: scheduler,
            identifier: "com.example.Briefeed.radio-refresh",
            refresh: { await gate.wait() }
        )
        let task = FakeRadioFeedBackgroundTask()

        #expect(driver.register())
        scheduler.launch(task)
        await settle()
        task.expirationHandler?()
        gate.release(true)
        await settle()

        #expect(task.completions == [false])
    }

    private func settle() async {
        for _ in 0..<12 { await Task.yield() }
    }
}

@MainActor
private final class FakeRadioFeedBackgroundScheduler:
    RadioFeedBackgroundScheduling
{
    private var launchHandler: (@MainActor (any RadioFeedBackgroundTask) -> Void)?
    private(set) var registeredIdentifiers: [String] = []
    private(set) var submissions: [RadioFeedBackgroundRefreshRequest] = []
    private(set) var cancelledIdentifiers: [String] = []

    func register(
        identifier: String,
        launchHandler: @escaping @MainActor (any RadioFeedBackgroundTask) -> Void
    ) -> Bool {
        registeredIdentifiers.append(identifier)
        self.launchHandler = launchHandler
        return true
    }

    func submit(_ request: RadioFeedBackgroundRefreshRequest) throws {
        submissions.append(request)
    }

    func cancel(identifier: String) {
        cancelledIdentifiers.append(identifier)
    }

    func launch(_ task: any RadioFeedBackgroundTask) {
        launchHandler?(task)
    }
}

@MainActor
private final class FakeRadioFeedBackgroundTask: RadioFeedBackgroundTask {
    var expirationHandler: (@MainActor () -> Void)?
    private(set) var completions: [Bool] = []

    func setTaskCompleted(success: Bool) {
        completions.append(success)
    }
}

@MainActor
private final class BackgroundRefreshGate {
    private var continuation: CheckedContinuation<Bool, Never>?

    func wait() async -> Bool {
        await withCheckedContinuation { continuation = $0 }
    }

    func release(_ value: Bool) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
