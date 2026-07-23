import BackgroundTasks
import Foundation

struct RadioContinuedProcessingRequest: Equatable, Sendable {
    enum Strategy: Equatable, Sendable {
        case fail
        case queue
    }

    let identifier: String
    let title: String
    let subtitle: String
    let strategy: Strategy
}

@MainActor
protocol RadioContinuedProcessingTask: AnyObject {
    var progress: Progress { get }
    var expirationHandler: (@MainActor @Sendable () -> Void)? { get set }
    func update(title: String, subtitle: String)
    func setTaskCompleted(success: Bool)
}

@MainActor
protocol RadioContinuedProcessingScheduling: AnyObject {
    func submit(
        _ request: RadioContinuedProcessingRequest,
        launchHandler: @escaping @MainActor (
            any RadioContinuedProcessingTask
        ) -> Void
    ) throws
    func cancel(identifier: String)
}

enum RadioTranscriptBackgroundSubmission: Equatable, Sendable {
    case accepted(identifier: String)
    case unavailableOS
    case rejected(message: String)
}

@MainActor
protocol RadioTranscriptBackgroundDriving: AnyObject {
    func submit(
        batchID: UUID,
        total: Int,
        onExpiration: @escaping @MainActor @Sendable () -> Void
    ) -> RadioTranscriptBackgroundSubmission
    func update(completed: Int, total: Int)
    func complete(success: Bool)
    func cancel()
}

@MainActor
final class RadioTranscriptBackgroundTaskDriver:
    RadioTranscriptBackgroundDriving
{
    private struct ActiveSubmission {
        let identifier: String
        let total: Int
        let onExpiration: @MainActor @Sendable () -> Void
        var completed: Int
        weak var task: (any RadioContinuedProcessingTask)?
    }

    private let scheduler: any RadioContinuedProcessingScheduling
    private let bundleIdentifier: String
    private let availability: @Sendable () -> Bool
    private var active: ActiveSubmission?

    init(
        scheduler: (any RadioContinuedProcessingScheduling)? = nil,
        bundleIdentifier: String =
            Bundle.main.bundleIdentifier ?? "Matznerd.Briefeed",
        availability: @escaping @Sendable () -> Bool = {
            if #available(iOS 26.0, *) {
                return true
            }
            return false
        }
    ) {
        self.scheduler =
            scheduler ?? SystemRadioContinuedProcessingScheduler()
        self.bundleIdentifier = bundleIdentifier
        self.availability = availability
    }

    func submit(
        batchID: UUID,
        total: Int,
        onExpiration: @escaping @MainActor @Sendable () -> Void
    ) -> RadioTranscriptBackgroundSubmission {
        guard availability() else { return .unavailableOS }
        if active != nil {
            cancel()
        }

        let identifier = [
            bundleIdentifier,
            "radio-transcripts",
            batchID.uuidString.lowercased(),
            UUID().uuidString.lowercased()
        ].joined(separator: ".")
        let normalizedTotal = max(total, 1)
        let request = RadioContinuedProcessingRequest(
            identifier: identifier,
            title: "Preparing Radio",
            subtitle: "0 of \(normalizedTotal) ready",
            strategy: .fail
        )
        active = ActiveSubmission(
            identifier: identifier,
            total: normalizedTotal,
            onExpiration: onExpiration,
            completed: 0,
            task: nil
        )

        do {
            try scheduler.submit(request) { [weak self] task in
                self?.attach(task, identifier: identifier)
            }
            return .accepted(identifier: identifier)
        } catch {
            active = nil
            return .rejected(message: error.localizedDescription)
        }
    }

    func update(completed: Int, total: Int) {
        guard var submission = active else { return }
        let effectiveTotal = max(total, submission.total, 1)
        let clamped = min(max(completed, 0), effectiveTotal)
        submission.completed = max(submission.completed, clamped)
        active = submission
        publishProgress(submission, total: effectiveTotal)
    }

    func complete(success: Bool) {
        guard let submission = active else { return }
        active = nil
        if let task = submission.task {
            task.expirationHandler = nil
            task.setTaskCompleted(success: success)
        } else {
            scheduler.cancel(identifier: submission.identifier)
        }
    }

    func cancel() {
        guard let submission = active else { return }
        active = nil
        scheduler.cancel(identifier: submission.identifier)
        if let task = submission.task {
            task.expirationHandler = nil
            task.setTaskCompleted(success: false)
        }
    }

    private func attach(
        _ task: any RadioContinuedProcessingTask,
        identifier: String
    ) {
        guard var submission = active,
              submission.identifier == identifier else {
            task.setTaskCompleted(success: false)
            return
        }
        submission.task = task
        active = submission
        task.expirationHandler = { [weak self] in
            self?.expire(identifier: identifier)
        }
        publishProgress(submission, total: submission.total)
    }

    private func expire(identifier: String) {
        guard let submission = active,
              submission.identifier == identifier else {
            return
        }
        active = nil
        submission.task?.expirationHandler = nil
        submission.task?.setTaskCompleted(success: false)
        submission.onExpiration()
    }

    private func publishProgress(
        _ submission: ActiveSubmission,
        total: Int
    ) {
        guard let task = submission.task else { return }
        task.progress.totalUnitCount = Int64(total)
        task.progress.completedUnitCount = Int64(submission.completed)
        task.update(
            title: "Preparing Radio",
            subtitle: "\(submission.completed) of \(total) ready"
        )
    }
}

@MainActor
private final class SystemRadioContinuedProcessingScheduler:
    RadioContinuedProcessingScheduling
{
    enum SchedulerError: Error {
        case unavailableOS
        case registrationFailed
    }

    func submit(
        _ request: RadioContinuedProcessingRequest,
        launchHandler: @escaping @MainActor (
            any RadioContinuedProcessingTask
        ) -> Void
    ) throws {
        guard #available(iOS 26.0, *) else {
            throw SchedulerError.unavailableOS
        }
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: request.identifier,
            using: .main
        ) { task in
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            launchHandler(
                SystemRadioContinuedProcessingTask(task: continuedTask)
            )
        }
        guard registered else {
            throw SchedulerError.registrationFailed
        }

        let systemRequest = BGContinuedProcessingTaskRequest(
            identifier: request.identifier,
            title: request.title,
            subtitle: request.subtitle
        )
        switch request.strategy {
        case .fail:
            systemRequest.strategy = .fail
        case .queue:
            systemRequest.strategy = .queue
        }
        try BGTaskScheduler.shared.submit(systemRequest)
    }

    func cancel(identifier: String) {
        guard #available(iOS 26.0, *) else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}

@available(iOS 26.0, *)
@MainActor
private final class SystemRadioContinuedProcessingTask:
    RadioContinuedProcessingTask
{
    private let task: BGContinuedProcessingTask
    var expirationHandler: (@MainActor @Sendable () -> Void)? {
        didSet {
            guard let expirationHandler else {
                task.expirationHandler = nil
                return
            }
            task.expirationHandler = {
                Task { @MainActor in
                    expirationHandler()
                }
            }
        }
    }

    var progress: Progress {
        task.progress
    }

    init(task: BGContinuedProcessingTask) {
        self.task = task
    }

    func update(title: String, subtitle: String) {
        task.updateTitle(title, subtitle: subtitle)
    }

    func setTaskCompleted(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}
