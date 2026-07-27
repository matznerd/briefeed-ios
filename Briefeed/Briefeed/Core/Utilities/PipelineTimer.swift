import Foundation

@MainActor
class PipelineTimer: ObservableObject {

    struct StepTiming: Identifiable {
        let id = UUID()
        let step: String
        let startTime: CFAbsoluteTime
        var endTime: CFAbsoluteTime?

        var duration: TimeInterval {
            (endTime ?? CFAbsoluteTimeGetCurrent()) - startTime
        }
    }

    static let shared = PipelineTimer()

    @Published var currentRun: [StepTiming] = []
    private var runStartTime: CFAbsoluteTime = 0

    func beginRun() {
        currentRun.removeAll()
        runStartTime = CFAbsoluteTimeGetCurrent()
        print("[PipelineTimer] === Pipeline run started ===")
    }

    func startStep(_ name: String) -> Int {
        let timing = StepTiming(step: name, startTime: CFAbsoluteTimeGetCurrent())
        currentRun.append(timing)
        print("[PipelineTimer] \(name): started")
        return currentRun.count - 1
    }

    func endStep(_ index: Int) {
        guard index >= 0 && index < currentRun.count else { return }
        currentRun[index].endTime = CFAbsoluteTimeGetCurrent()
        let step = currentRun[index]
        print("[PipelineTimer] \(step.step): \(String(format: "%.2f", step.duration))s")
    }

    func report() -> String {
        let totalDuration = CFAbsoluteTimeGetCurrent() - runStartTime
        var lines = ["[PipelineTimer] === Pipeline Report ==="]
        for step in currentRun {
            let dur = String(format: "%.2f", step.duration)
            let status = step.endTime != nil ? "\(dur)s" : "in progress"
            lines.append("[PipelineTimer] \(step.step): \(status)")
        }
        lines.append("[PipelineTimer] TOTAL: \(String(format: "%.2f", totalDuration))s")
        lines.append("[PipelineTimer] ========================")
        let result = lines.joined(separator: "\n")
        print(result)
        return result
    }
}
