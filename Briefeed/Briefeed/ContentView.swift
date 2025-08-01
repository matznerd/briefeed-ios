//
//  ContentView.swift
//  Briefeed
//
//  Created by Eric M on 6/21/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @EnvironmentObject var userDefaultsManager: UserDefaultsManager
    @ObservedObject private var audioService = AudioService.shared
    @ObservedObject private var statusService = ProcessingStatusService.shared
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content with tab view
            VStack(spacing: 0) {
                // Status banner at the top
                if statusService.showStatusBanner {
                    ProcessingStatusBanner()
                        .padding(.horizontal)
                        .padding(.top, 5)
                        .zIndex(1)
                }
                
                TabView(selection: $selectedTab) {
                    FeedView()
                        .tabItem {
                            Label("Feed", systemImage: "newspaper")
                        }
                        .tag(0)
                    
                    FilteredBriefView()
                        .tabItem {
                            Label("Brief", systemImage: "music.note.list")
                        }
                        .tag(1)
                    
                    LiveNewsView()
                        .tabItem {
                            Label("Live News", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .tag(2)
                    
                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag(3)
                }
                .accentColor(.briefeedRed)
                
                // Audio player always visible
                MiniAudioPlayer()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .onAppear {
                // Apply theme settings when view appears
                applyThemePreference()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ThemeChanged"))) { _ in
                // Update theme when notification is received
                applyThemePreference()
            }
        }
        .ignoresSafeArea(.keyboard)
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
        CombinedFeedView()
    }
}


#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserDefaultsManager.shared)
}