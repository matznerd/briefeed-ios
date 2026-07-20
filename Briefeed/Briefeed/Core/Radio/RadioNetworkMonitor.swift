import Combine
import Foundation
import Network

protocol RadioPathMonitoring: AnyObject {
    var statusHandler: ((ConnectivityStatus) -> Void)? { get set }
    func start(queue: DispatchQueue)
    func cancel()
}

private final class NWRadioPathMonitor: RadioPathMonitoring {
    private let monitor: NWPathMonitor
    var statusHandler: ((ConnectivityStatus) -> Void)?

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            self?.statusHandler?(path.status == .satisfied ? .online : .offline)
        }
    }

    func start(queue: DispatchQueue) { monitor.start(queue: queue) }
    func cancel() { monitor.cancel() }
}

@MainActor
protocol ConnectivityMonitoring: AnyObject {
    var status: ConnectivityStatus { get }
    var statusPublisher: AnyPublisher<ConnectivityStatus, Never> { get }
}

@MainActor
final class RadioNetworkMonitor: ConnectivityMonitoring {
    private let monitor: RadioPathMonitoring
    private let subject = CurrentValueSubject<ConnectivityStatus, Never>(.unknown)

    var status: ConnectivityStatus { subject.value }
    var statusPublisher: AnyPublisher<ConnectivityStatus, Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    init(monitor: RadioPathMonitoring? = nil) {
        let monitor = monitor ?? NWRadioPathMonitor()
        self.monitor = monitor
        monitor.statusHandler = { [weak subject] status in
            DispatchQueue.main.async { subject?.send(status) }
        }
        monitor.start(queue: DispatchQueue(label: "Briefeed.RadioNetworkMonitor"))
    }

    deinit { monitor.cancel() }
}
