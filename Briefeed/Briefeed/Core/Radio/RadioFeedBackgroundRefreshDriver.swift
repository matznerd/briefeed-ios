import BackgroundTasks
import Foundation

struct RadioFeedBackgroundRefreshRequest: Equatable, Sendable {
    let identifier: String
    let earliestBeginDate: Date
}

@MainActor
protocol RadioFeedBackgroundTask: AnyObject {
    var expirationHandler: (@MainActor () -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

@MainActor
protocol RadioFeedBackgroundScheduling: AnyObject {
    func register(
        identifier: String,
        launchHandler: @escaping @MainActor (any RadioFeedBackgroundTask) -> Void
    ) -> Bool
    func submit(_ request: RadioFeedBackgroundRefreshRequest) throws
    func cancel(identifier: String)
}

@MainActor
final class RadioFeedBackgroundRefreshDriver {
    typealias Refresh = @MainActor () async -> Bool

    static let shared = RadioFeedBackgroundRefreshDriver(
        refresh: {
            _ = await RSSAudioService.shared.ensureDefaultFeedsExist()
            let result = await RSSAudioService.shared.refreshIfStale(now: Date())
            guard !Task.isCancelled else { return false }
            _ = RadioServiceContainer.shared.coordinator.applyRefresh(result)
            return result.successfulSourceEvidenceCount > 0
        }
    )

    private struct ActiveRefresh {
        let id: UUID
        let work: Task<Void, Never>
    }

    private static let refreshInterval: TimeInterval = 45 * 60

    private let scheduler: any RadioFeedBackgroundScheduling
    private let identifier: String
    private let now: @MainActor () -> Date
    private let refresh: Refresh
    private var activeRefresh: ActiveRefresh?

    init(
        scheduler: (any RadioFeedBackgroundScheduling)? = nil,
        identifier: String = [
            Bundle.main.bundleIdentifier ?? "Matznerd.Briefeed",
            "radio-refresh"
        ].joined(separator: "."),
        now: @escaping @MainActor () -> Date = Date.init,
        refresh: @escaping Refresh
    ) {
        self.scheduler = scheduler ?? SystemRadioFeedBackgroundScheduler()
        self.identifier = identifier
        self.now = now
        self.refresh = refresh
    }

    @discardableResult
    func register() -> Bool {
        scheduler.register(identifier: identifier) { [weak self] task in
            self?.handle(task)
        }
    }

    @discardableResult
    func schedule() -> Bool {
        scheduler.cancel(identifier: identifier)
        let request = RadioFeedBackgroundRefreshRequest(
            identifier: identifier,
            earliestBeginDate: now().addingTimeInterval(Self.refreshInterval)
        )
        do {
            try scheduler.submit(request)
            return true
        } catch {
            print("Radio background refresh could not be scheduled: \(error.localizedDescription)")
            return false
        }
    }

    private func handle(_ task: any RadioFeedBackgroundTask) {
        _ = schedule()
        activeRefresh?.work.cancel()

        let id = UUID()
        let work = Task { @MainActor [weak self, weak task] in
            guard let self, let task else { return }
            let succeeded = await self.refresh()
            guard !Task.isCancelled,
                  self.activeRefresh?.id == id else { return }
            self.activeRefresh = nil
            task.expirationHandler = nil
            task.setTaskCompleted(success: succeeded)
        }
        activeRefresh = ActiveRefresh(id: id, work: work)
        task.expirationHandler = { [weak self, weak task] in
            guard let self,
                  let task,
                  self.activeRefresh?.id == id else { return }
            self.activeRefresh?.work.cancel()
            self.activeRefresh = nil
            task.expirationHandler = nil
            task.setTaskCompleted(success: false)
        }
    }
}

@MainActor
private final class SystemRadioFeedBackgroundScheduler:
    RadioFeedBackgroundScheduling
{
    func register(
        identifier: String,
        launchHandler: @escaping @MainActor (any RadioFeedBackgroundTask) -> Void
    ) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: .main
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            launchHandler(SystemRadioFeedBackgroundTask(task: refreshTask))
        }
    }

    func submit(_ request: RadioFeedBackgroundRefreshRequest) throws {
        let systemRequest = BGAppRefreshTaskRequest(identifier: request.identifier)
        systemRequest.earliestBeginDate = request.earliestBeginDate
        try BGTaskScheduler.shared.submit(systemRequest)
    }

    func cancel(identifier: String) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}

@MainActor
private final class SystemRadioFeedBackgroundTask: RadioFeedBackgroundTask {
    private let task: BGAppRefreshTask

    var expirationHandler: (@MainActor () -> Void)? {
        didSet {
            guard let expirationHandler else {
                task.expirationHandler = nil
                return
            }
            task.expirationHandler = {
                Task { @MainActor in expirationHandler() }
            }
        }
    }

    init(task: BGAppRefreshTask) {
        self.task = task
    }

    func setTaskCompleted(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}
