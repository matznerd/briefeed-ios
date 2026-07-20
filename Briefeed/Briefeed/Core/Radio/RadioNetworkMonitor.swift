import Combine
import Foundation
import Network

@MainActor
protocol ConnectivityMonitoring: AnyObject {
    var status: ConnectivityStatus { get }
    var statusPublisher: AnyPublisher<ConnectivityStatus, Never> { get }
}

@MainActor
final class RadioNetworkMonitor: ConnectivityMonitoring {
    private let monitor: NWPathMonitor
    private let subject = CurrentValueSubject<ConnectivityStatus, Never>(.unknown)

    var status: ConnectivityStatus { subject.value }
    var statusPublisher: AnyPublisher<ConnectivityStatus, Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak subject] path in
            let status: ConnectivityStatus = path.status == .satisfied ? .online : .offline
            DispatchQueue.main.async { subject?.send(status) }
        }
        monitor.start(queue: DispatchQueue(label: "Briefeed.RadioNetworkMonitor"))
    }

    deinit { monitor.cancel() }
}
