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
    let persistenceController = PersistenceController.shared
    @StateObject private var userDefaultsManager = UserDefaultsManager.shared
    @StateObject private var audioPlayerViewModel = AudioPlayerViewModelV2()
    @StateObject private var appViewModel: AppViewModel
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        print("🚀 BriefeedApp initializing...")
        
        // Create NEW audio player view model V2
        let audioVM = AudioPlayerViewModelV2()
        _audioPlayerViewModel = StateObject(wrappedValue: audioVM)
        
        // Create app view model with the SAME V2 audio player
        _appViewModel = StateObject(wrappedValue: AppViewModel(audioPlayerViewModel: audioVM))
        
        // Initialize UserDefaults on app launch
        UserDefaultsManager.shared.loadSettings()
        
        // Apply dark mode preference early
        applyThemeSettings()
        
        // Initialize RSS features (using V2 version)
        initializeRSSFeatures()
        
        // Initialize V2 services asynchronously (no UI freeze!)
        Task {
            // Initialize services in background
            await AudioServiceV2.shared.initialize()
            // QueueCoordinator initializes automatically with persistence on access
            _ = await MainActor.run { QueueCoordinator.shared }
            await ArticleStateManagerV2.shared.initialize()

            // Create default feeds
            do {
                try await DefaultDataService.shared.createDefaultFeedsIfNeeded()
            } catch {
                print("Failed to create default feeds: \(error)")
            }

            #if DEBUG
            await SimulatorAudioQueueProbe.runIfRequested(audioPlayerViewModel: audioVM)
            #endif
        }
        
        print("✅ BriefeedApp initialization complete")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(userDefaultsManager)
                .environmentObject(audioPlayerViewModel)
                .environmentObject(appViewModel)
                .preferredColorScheme(userDefaultsManager.isDarkMode ? .dark : .light)
                .onAppear {
                    print("🎯 ContentView appeared")
                    // Apply theme settings when window is ready
                    applyThemeSettings()
                    
                    // Connect ViewModels to services
                    Task {
                        // AudioPlayerViewModelV2 doesn't need connect - it's lightweight
                        await appViewModel.connect()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // App became active - could refresh queue state if needed
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    // App going to background - save queue state immediately
                    QueueCoordinator.shared.saveStateNow()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    // App terminating - save queue state immediately
                    QueueCoordinator.shared.saveStateNow()
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
        
        return true
    }
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.allowBluetooth, .allowAirPlay])
            try AVAudioSession.sharedInstance().setActive(true)
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
