import Combine
import Foundation
import Testing
@testable import Briefeed

@Suite("Radio service container") @MainActor
struct RadioServiceContainerTests {
    @Test func injectedMonitorIsTheSingleCoordinatorMonitor() async {
        let monitor = TestConnectivityMonitor()
        let coordinator = RadioSessionCoordinator(store: FakeRadioSessionStore(), repository: FakeRadioEpisodeRepository(candidates: []), connectivity: monitor)
        let container = RadioServiceContainer(connectivity: monitor, coordinator: coordinator)
        #expect(container.connectivity === monitor)
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.refreshStarted(enabledSourceCount: 1)
        monitor.send(.offline)
        #expect(container.coordinator.state == .waitingForNetwork)
    }
}

@MainActor private final class TestConnectivityMonitor: ConnectivityMonitoring {
    private let subject = CurrentValueSubject<ConnectivityStatus, Never>(.unknown)
    var status: ConnectivityStatus { subject.value }
    var statusPublisher: AnyPublisher<ConnectivityStatus, Never> { subject.eraseToAnyPublisher() }
    func send(_ status: ConnectivityStatus) { subject.send(status) }
}
