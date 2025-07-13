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
    @StateObject private var queueService = QueueService.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Initialize UserDefaults on app launch
        UserDefaultsManager.shared.loadSettings()
        
        // Apply dark mode preference early
        applyThemeSettings()
        
        // Initialize RSS features
        initializeRSSFeatures()
        
        // Create default feeds on first launch
        Task {
            do {
                try await DefaultDataService.shared.createDefaultFeedsIfNeeded()
            } catch {
                print("Failed to create default feeds: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(userDefaultsManager)
                .preferredColorScheme(userDefaultsManager.isDarkMode ? .dark : .light)
                .onAppear {
                    // Apply theme settings when window is ready
                    applyThemeSettings()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    queueService.handleAppDidBecomeActive()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    queueService.handleAppWillResignActive()
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
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
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
