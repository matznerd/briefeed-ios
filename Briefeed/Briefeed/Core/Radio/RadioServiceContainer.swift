import CoreData
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

    static func installFixtureOverride(definition: RadioFixtureScenarioDefinition) {
        installProcessOverride {
            makeFixtureContainer(
                definition: definition,
                context: PersistenceController.shared.container.viewContext,
                defaults: .standard
            )
        }
    }

    static func makeFixtureContainer(
        definition: RadioFixtureScenarioDefinition,
        context: NSManagedObjectContext,
        defaults: UserDefaults
    ) -> RadioServiceContainer {
        let connectivity = RadioFixtureConnectivityMonitor(
            initialStatus: definition.initialConnectivity
        )
        let coordinator = RadioSessionCoordinator(
            store: RadioSessionStore(defaults: defaults),
            repository: CoreDataRadioEpisodeRepository(context: context),
            now: { definition.now },
            connectivity: connectivity
        )
        return RadioServiceContainer(connectivity: connectivity, coordinator: coordinator)
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
