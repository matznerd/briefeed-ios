import CoreData
import Foundation

@MainActor
final class RadioServiceContainer {
    typealias Factory = @MainActor () -> RadioServiceContainer

    private static var instance: RadioServiceContainer?
    private static var factory: Factory = makeProduction

    let connectivity: ConnectivityMonitoring
    let coordinator: RadioSessionCoordinator
    let feedSpeechMetadataStore: any RadioFeedSpeechMetadataStoring
    let transcriptCoordinator: (any RadioTranscriptCoordinating)?
    let transcriptAssetProvider:
        (any RadioTranscriptAssetProviding)?
    let transcriptAssetService: RadioTranscriptAssetService?
    private var adPreferenceObserver: NSObjectProtocol?
    private let adPreferenceDefaults: UserDefaults?

    init(
        connectivity: ConnectivityMonitoring,
        coordinator: RadioSessionCoordinator,
        feedSpeechMetadataStore: (any RadioFeedSpeechMetadataStoring)? = nil,
        transcriptCoordinator: (any RadioTranscriptCoordinating)? = nil,
        transcriptAssetService: RadioTranscriptAssetService? = nil,
        preferenceDefaults: UserDefaults? = nil
    ) {
        self.connectivity = connectivity
        self.coordinator = coordinator
        self.feedSpeechMetadataStore =
            feedSpeechMetadataStore ?? InMemoryRadioFeedSpeechMetadataStore()
        self.transcriptCoordinator = transcriptCoordinator
        self.transcriptAssetService = transcriptAssetService
        adPreferenceDefaults = preferenceDefaults
        transcriptAssetProvider = transcriptAssetService
        if preferenceDefaults != nil {
            adPreferenceObserver = NotificationCenter.default.addObserver(forName: .radioAdPreferencesChanged,
                                                                          object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let defaults = self.adPreferenceDefaults else { return }
                    self.transcriptCoordinator?.setAdPreferences(.load(defaults: defaults))
                }
            }
        }
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
        return RadioServiceContainer(
            connectivity: connectivity,
            coordinator: coordinator,
            feedSpeechMetadataStore:
                InMemoryRadioFeedSpeechMetadataStore(),
            transcriptCoordinator:
                RadioFixtureTranscriptCoordinator()
        )
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
        let speechMetadataStore: any RadioFeedSpeechMetadataStoring
        do {
            speechMetadataStore = try RadioFeedSpeechMetadataStore()
        } catch {
            print("Could not open Radio speech metadata store: \(error)")
            speechMetadataStore = InMemoryRadioFeedSpeechMetadataStore()
        }
        let transcriptAssetService: RadioTranscriptAssetService?
        let transcriptCoordinator: RadioTranscriptCoordinator?
        do {
            let store = try RadioTranscriptStore()
            let assets = try RadioTranscriptAssetService.makeProduction()
            let adStore = try? RadioAdStore.makeProduction()
            let adService = adStore.map { RadioAdPreparationService(store: $0) }
            let pipeline = RadioTranscriptPreparationPipeline(
                assetProvider: assets,
                store: store,
                adService: adService
            )
            transcriptAssetService = assets
            transcriptCoordinator = RadioTranscriptCoordinator(
                pipeline: pipeline,
                store: store,
                assetProvider: assets,
                metadataStore: speechMetadataStore,
                backgroundDriver: RadioTranscriptBackgroundTaskDriver(),
                adStore: adStore,
                adPreferences: .load(defaults: .standard)
            )
        } catch {
            print("Could not open Radio transcript services: \(error)")
            transcriptAssetService = nil
            transcriptCoordinator = nil
        }
        return RadioServiceContainer(
            connectivity: connectivity,
            coordinator: coordinator,
            feedSpeechMetadataStore: speechMetadataStore,
            transcriptCoordinator: transcriptCoordinator,
            transcriptAssetService: transcriptAssetService,
            preferenceDefaults: .standard
        )
    }
}
