//
//  ContentView.swift
//  Briefeed
//
//  Created by Eric M on 6/21/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0 {
        didSet {
            perfLog.log("ContentView.selectedTab changed: \(oldValue) -> \(selectedTab)", category: .view)
        }
    }
    @EnvironmentObject var userDefaultsManager: UserDefaultsManager
    // FIX: Using AppViewModel instead of singleton services
    @StateObject private var appViewModel = AppViewModel()
    // REMOVED: All singleton @StateObject references that caused UI freeze
    
    var body: some View {
        let _ = perfLog.logView("ContentView", event: .bodyExecuted)
        VStack(spacing: 0) {
            // Status banner at the top
            if appViewModel.showStatusBanner {
                ProcessingStatusBanner()
                    .environmentObject(appViewModel)
                    .padding(.horizontal)
                    .padding(.top, 5)
                    .zIndex(1)
            }
            
            // Main content with tab view
            TabView(selection: $selectedTab) {
                FeedView()
                    .environmentObject(appViewModel)
                    .tabItem {
                        Label("Feed", systemImage: "newspaper")
                    }
                    .tag(0)
                
                FilteredBriefViewV2()  // Using V2
                    .environmentObject(appViewModel)
                    .tabItem {
                        Label("Brief", systemImage: "music.note.list")
                    }
                    .tag(1)
                
                LiveNewsViewV2()  // Using V2
                    .environmentObject(appViewModel)
                    .tabItem {
                        Label("Live News", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .tag(2)
                
                SettingsViewV2()  // Using V2
                    .environmentObject(appViewModel)
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(3)
            }
            .accentColor(.briefeedRed)
            
            // Audio player always visible at bottom
            MiniAudioPlayerV3()
                .environmentObject(appViewModel)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
            .onAppear {
                perfLog.logView("ContentView", event: .appeared)
                perfLog.startOperation("ContentView.onAppear")
                // Apply theme settings when view appears
                applyThemePreference()
                perfLog.endOperation("ContentView.onAppear")
            }
            .task {
                perfLog.logView("ContentView", event: .taskStarted)
                perfLog.startOperation("ContentView.task")
                print("🚀 ContentView: Starting .task modifier")
                
                // Run service connection on background to avoid blocking UI
                await Task.detached(priority: .userInitiated) {
                    await self.appViewModel.connectToServices()
                }.value
                
                print("✅ ContentView: .task modifier complete")
                perfLog.endOperation("ContentView.task")
                perfLog.logView("ContentView", event: .taskCompleted)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ThemeChanged"))) { _ in
                perfLog.logView("ContentView", event: .onReceive)
                // Update theme when notification is received
                applyThemePreference()
            }
        // .ignoresSafeArea(.keyboard) // TESTING: Commenting out to see if this causes hang
    }
    
    private func applyThemePreference() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.windows.forEach { window in
                window.overrideUserInterfaceStyle = userDefaultsManager.isDarkMode ? .dark : .light
            }
        }
    }
}

struct FeedView: View {
    var body: some View {
        CombinedFeedViewV2()  // Using V2 without singleton @StateObject
    }
}


#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserDefaultsManager.shared)
}