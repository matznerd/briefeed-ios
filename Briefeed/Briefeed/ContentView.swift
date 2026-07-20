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
    @EnvironmentObject var audioPlayerViewModel: AudioPlayerViewModelV2
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

                    LiveNewsViewV2()
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
            }
            
            if !audioPlayerViewModel.radioEntries.isEmpty || !audioPlayerViewModel.queueItems.isEmpty {
                VStack(spacing: 0) {
                    Spacer()
                    MiniAudioPlayerV4()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(
                            .easeInOut(duration: 0.3),
                            value: !audioPlayerViewModel.radioEntries.isEmpty || !audioPlayerViewModel.queueItems.isEmpty
                        )
                        .padding(.bottom, 49) // Height of tab bar
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            // Apply theme settings when view appears
            applyThemePreference()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ThemeChanged"))) { _ in
            // Update theme when notification is received
            applyThemePreference()
        }
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
