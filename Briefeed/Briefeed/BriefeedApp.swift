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
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        print("🚀 BriefeedApp initializing...")
        
        // Initialize UserDefaults on app launch
        UserDefaultsManager.shared.loadSettings()
        
        // Apply dark mode preference early
        applyThemeSettings()
        
        // MOVED TO AppViewModel: Initialize RSS features
        // initializeRSSFeatures() // This was accessing ObservableObject singletons!
        
        // Create default feeds on first launch
        Task {
            do {
                try await DefaultDataService.shared.createDefaultFeedsIfNeeded()
            } catch {
                print("Failed to create default feeds: \(error)")
            }
        }
        
        print("✅ BriefeedApp initialization complete")
    }

    var body: some Scene {
        WindowGroup {
            // FIXED: Using ContentView with AppViewModel
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(userDefaultsManager)
                .preferredColorScheme(userDefaultsManager.isDarkMode ? .dark : .light)
                .onAppear {
                    // Apply theme settings when window is ready
                    applyThemeSettings()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // MIGRATION: QueueServiceV2 handles this automatically
                    // queueService.handleAppDidBecomeActive()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    // MIGRATION: QueueServiceV2 handles this automatically
                    // queueService.handleAppWillResignActive()
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
        // Audio session is now configured by BriefeedAudioService
        // configureAudioSession()
        
        // Configure app appearance
        configureAppearance()
        
        return true
    }
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // Configure for Bluetooth and AirPlay support
            // Note: .mixWithOthers is incompatible with .spokenAudio mode
            // Using .default mode for better compatibility with RSS podcasts
            try session.setCategory(
                .playback,
                mode: .default,  // Changed from .spokenAudio for compatibility
                options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
            )
            
            // Don't activate the session here - let AudioService do it when needed
            // This prevents conflicts when the app launches
            
            print("✅ Audio session category configured at app launch")
            print("📱 Category: \(session.category.rawValue)")
            print("📱 Mode: \(session.mode.rawValue)")
        } catch {
            print("❌ Failed to configure audio session at app launch: \(error)")
            print("📱 Error code: \((error as NSError).code)")
            print("📱 Error domain: \((error as NSError).domain)")
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
