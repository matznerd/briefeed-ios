import Foundation

@MainActor
final class RadioServiceContainer {
    typealias Factory = @MainActor () -> RadioServiceContainer

    private static var instance: RadioServiceContainer?
    private static var factory: Factory = makeProduction

    let connectivity: ConnectivityMonitoring
    let coordinator: RadioSessionCoordinator

    init(connectivity: ConnectivityMonitoring, coordinator: RadioSessionCoordinator) {
        self.connectivity = connectivity
        self.coordinator = coordinator
    }

    static var shared: RadioServiceContainer {
        if let instance { return instance }
        let created = factory()
        instance = created
        return created
    }

    #if DEBUG
    static func installProcessOverride(_ override: @escaping Factory) {
        precondition(instance == nil, "Install Radio override before resolving shared services")
        factory = override
    }
    #endif

    private static func makeProduction() -> RadioServiceContainer {
        let connectivity = RadioNetworkMonitor()
        let context = PersistenceController.shared.container.viewContext
        let coordinator = RadioSessionCoordinator(
            store: RadioSessionStore(),
            repository: CoreDataRadioEpisodeRepository(context: context),
            connectivity: connectivity
        )
        return RadioServiceContainer(connectivity: connectivity, coordinator: coordinator)
    }
}
