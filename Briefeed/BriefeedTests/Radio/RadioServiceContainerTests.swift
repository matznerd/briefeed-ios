import Combine
import Foundation
import Testing
@testable import Briefeed

@Suite("Radio service container") @MainActor
struct RadioServiceContainerTests {
    @Test func injectedMonitorIsTheSingleCoordinatorMonitor() async {
        let monitor = ContainerConnectivityMonitor()
        let coordinator = RadioSessionCoordinator(store: FakeRadioSessionStore(), repository: FakeRadioEpisodeRepository(candidates: []), connectivity: monitor)
        let container = RadioServiceContainer(connectivity: monitor, coordinator: coordinator)
        #expect(container.connectivity === monitor)
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.refreshStarted(enabledSourceCount: 1)
        monitor.send(.offline)
        #expect(container.coordinator.state == .waitingForNetwork)
    }

    @Test func networkMonitorStartsPublishesAndCancelsItsSingleWrapper() async {
        let pathMonitor = TestPathMonitor()
        var monitor: RadioNetworkMonitor? = RadioNetworkMonitor(monitor: pathMonitor)
        #expect(pathMonitor.startCount == 1)
        pathMonitor.send(.online)
        await Task.yield()
        #expect(monitor?.status == .online)
        monitor = nil
        #expect(pathMonitor.cancelCount == 1)
    }

    #if DEBUG
    @Test func fixtureContainerSharesOneInjectedMonitorWithCoordinator() async throws {
        let persistence = PersistenceController(inMemory: true)
        let suiteName = "RadioServiceContainerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let definition = RadioFixtureScenarioDefinition.make(
            scenario: .offline,
            now: Date(timeIntervalSince1970: 3_600)
        )
        let container = RadioServiceContainer.makeFixtureContainer(
            definition: definition,
            context: persistence.container.viewContext,
            defaults: defaults
        )

        #expect(container.connectivity.status == .offline)
        _ = await container.coordinator.restore(autoplayEnabled: false)
        container.coordinator.refreshStarted(enabledSourceCount: 1)
        #expect(container.coordinator.state == .waitingForNetwork)
    }
    #endif
}

@MainActor private final class ContainerConnectivityMonitor: ConnectivityMonitoring {
    private let subject = CurrentValueSubject<ConnectivityStatus, Never>(.unknown)
    var status: ConnectivityStatus { subject.value }
    var statusPublisher: AnyPublisher<ConnectivityStatus, Never> { subject.eraseToAnyPublisher() }
    func send(_ status: ConnectivityStatus) { subject.send(status) }
}

private final class TestPathMonitor: RadioPathMonitoring {
    var statusHandler: ((ConnectivityStatus) -> Void)?
    var startCount = 0
    var cancelCount = 0
    func start(queue: DispatchQueue) { startCount += 1 }
    func cancel() { cancelCount += 1 }
    func send(_ status: ConnectivityStatus) { statusHandler?(status) }
}
