//
//  BriefeedApp.swift
//  Briefeed
//
//  Created by Eric M on 6/21/25.
//

import SwiftUI
import AVFoundation

@main
struct BriefeedApp: App {
    @Environment(\.scenePhase) private var scenePhase

    let persistenceController: PersistenceController
    @StateObject private var userDefaultsManager: UserDefaultsManager
    @StateObject private var audioPlayerViewModel: AudioPlayerViewModelV2
    @StateObject private var appViewModel: AppViewModel
    let radioLifecycleDriver: RadioAppLifecycleDriver
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        #if DEBUG
        AppRuntime.prepareRadioFixturePreferencesIfNeeded()
        if let definition = AppRuntime.radioFixtureDefinition {
            RadioFixtureDiagnostics.shared.reset()
            RadioServiceContainer.installFixtureOverride(definition: definition)
        }
        #endif

        print("🚀 BriefeedApp initializing...")
        persistenceController = PersistenceController.shared
        let defaultsManager = UserDefaultsManager.shared
        defaultsManager.loadSettings()

        let audioVM = AudioPlayerViewModelV2()
        _userDefaultsManager = StateObject(wrappedValue: defaultsManager)
        _audioPlayerViewModel = StateObject(wrappedValue: audioVM)
        _appViewModel = StateObject(wrappedValue: AppViewModel(audioPlayerViewModel: audioVM))

        let radioServices = RadioServiceContainer.shared
        radioLifecycleDriver = RadioAppLifecycleDriver(
            connectivity: radioServices.connectivity,
            cancelPendingColdLaunchAutoplay: {
                radioServices.coordinator.cancelPendingColdLaunchAutoplay()
            },
            forceSave: { reason in
                switch reason {
                case .background:
                    UnifiedAudioPlayer.shared.handleAppBackground()
                case .termination:
                    UnifiedAudioPlayer.shared.handleAppTermination()
                }
            }
        )

        applyThemeSettings()
        print("✅ BriefeedApp initialization complete")
    }

    var body: some Scene {
        WindowGroup {
            ContentView(onRadioHomeAppear: handleRadioHomeAppeared)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(userDefaultsManager)
                .environmentObject(audioPlayerViewModel)
                .environmentObject(appViewModel)
                .preferredColorScheme(userDefaultsManager.isDarkMode ? .dark : .light)
                .onAppear {
                    print("🎯 ContentView appeared")
                    applyThemeSettings()
                }
                .task {
                    #if DEBUG
                    if let scenario = AppRuntime.radioFixtureScenario {
                        do {
                            try RadioFixtureSeeder(
                                context: persistenceController.container.viewContext,
                                now: { AppRuntime.radioFixtureNow }
                            ).seed(
                                scenario: scenario,
                                reset: AppRuntime.shouldResetRadioFixtureStore
                            )
                            await startRadioFixtureSession()
                        } catch {
                            print("🧪 Radio fixture failed: \(error.localizedDescription)")
                        }
                        return
                    }
                    #endif

                    guard !AppRuntime.shouldSkipAutomaticStartupWork else {
                        print("🧪 Skipping automatic startup services for hosted XCTest")
                        return
                    }

                    await appViewModel.connect()

                    handleScenePhase(scenePhase)
                    if RadioStartupPolicy.shouldStartServices(for: scenePhase) {
                        await startRadioServices()
                    }
                    await AudioServiceV2.shared.initialize()
                    _ = QueueCoordinator.shared
                    await ArticleStateManagerV2.shared.initialize()

                    do {
                        try await DefaultDataService.shared.createDefaultFeedsIfNeeded()
                    } catch {
                        print("Failed to create default feeds: \(error)")
                    }

                    #if DEBUG
                    await SimulatorAudioQueueProbe.runIfRequested(audioPlayerViewModel: audioPlayerViewModel)
                    #endif
                }
                .onChange(of: scenePhase) {
                    let newPhase = scenePhase
                    let transcriptCoordinator =
                        RadioServiceContainer.shared.transcriptCoordinator
                    #if DEBUG
                    if AppRuntime.radioFixtureScenario != nil {
                        if newPhase == .background {
                            UnifiedAudioPlayer.shared.handleAppBackground()
                            transcriptCoordinator?.handleBackground()
                        } else if newPhase == .active {
                            UnifiedAudioPlayer.shared.handleAppForeground()
                            transcriptCoordinator?.handleActive()
                        }
                        return
                    }
                    #endif
                    guard !AppRuntime.shouldSkipAutomaticStartupWork else { return }
                    handleScenePhase(newPhase)
                    if newPhase == .active {
                        UnifiedAudioPlayer.shared.handleAppForeground()
                        transcriptCoordinator?.handleActive()
                        Task { await startRadioServices() }
                    } else if newPhase == .background {
                        transcriptCoordinator?.handleBackground()
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didReceiveMemoryWarningNotification
                    )
                ) { _ in
                    RadioServiceContainer.shared.transcriptCoordinator?
                        .handleMemoryWarning()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    #if DEBUG
                    if AppRuntime.radioFixtureScenario != nil {
                        UnifiedAudioPlayer.shared.handleAppTermination()
                        return
                    }
                    #endif
                    guard !AppRuntime.shouldSkipAutomaticStartupWork else { return }
                    radioLifecycleDriver.handleTermination()
                }
        }
    }
    
    private func applyThemeSettings() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.windows.forEach { window in
                window.overrideUserInterfaceStyle = UserDefaultsManager.shared.isDarkMode ? .dark : .light
            }
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Configure audio session for text-to-speech
        configureAudioSession()
        
        // Configure app appearance
        configureAppearance()

        let backgroundRefresh = RadioFeedBackgroundRefreshDriver.shared
        if backgroundRefresh.register(),
           !AppRuntime.shouldSkipAutomaticStartupWork {
            _ = backgroundRefresh.schedule()
        }
        
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        guard !AppRuntime.shouldSkipAutomaticStartupWork else { return }
        _ = RadioFeedBackgroundRefreshDriver.shared.schedule()
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier ==
                RadioTranscriptBackgroundDownloader.sessionIdentifier else {
            completionHandler()
            return
        }
        Task { @MainActor in
            guard let service =
                    RadioServiceContainer.shared.transcriptAssetService else {
                completionHandler()
                return
            }
            await service.handleEventsForBackgroundURLSession(
                completionHandler: completionHandler
            )
        }
    }
    
    private func configureAudioSession() {
        do {
            try AudioSessionConfiguration.activatePlayback()
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    private func configureAppearance() {
        // Configure navigation bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        
        // Configure tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }
}
