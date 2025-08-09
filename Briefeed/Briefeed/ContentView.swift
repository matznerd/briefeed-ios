//
//  ContentView.swift
//  Briefeed
//
//  Created by Eric M on 6/21/25.
//

import SwiftUI

struct ContentView: View {
    // TESTING FLAGS - Change these to isolate the issue
    static let USE_TEST_MODE = true  // ← CHANGE THIS TO TEST
    static let TEST_SCENARIO = TestScenario.bypassLoading  // ← CHANGE THIS TO TEST DIFFERENT SCENARIOS
    
    enum TestScenario {
        case normal           // Original behavior
        case bypassLoading   // Skip loading screen check
        case minimalView     // Use minimal test view
        case noServices      // Don't connect to any services
        case delayedServices // Connect services after 2 second delay
    }
    
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
        
        Group {
            if Self.USE_TEST_MODE {
                // TESTING MODE - Use different scenarios
                switch Self.TEST_SCENARIO {
                case .minimalView:
                    // Test with absolutely minimal view
                    testMinimalView()
                    
                case .bypassLoading:
                    // Skip loading screen entirely
                    normalAppContent()
                        .task {
                            print("🧪 TEST: Bypassing loading screen")
                            await appViewModel.connectToServices()
                        }
                    
                case .noServices:
                    // Show UI without any service connections
                    normalAppContent()
                        .onAppear {
                            print("🧪 TEST: No services mode - UI should be responsive")
                        }
                    
                case .delayedServices:
                    // Delay service connection by 2 seconds
                    normalAppContent()
                        .task {
                            print("🧪 TEST: Delaying service connection by 2 seconds")
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await appViewModel.connectToServices()
                        }
                    
                case .normal:
                    // Original implementation with loading check
                    originalImplementation()
                }
            } else {
                // PRODUCTION MODE - Original implementation
                originalImplementation()
            }
        }
    }
    
    @ViewBuilder
    private func originalImplementation() -> some View {
        Group {
            // Show loading screen while services are connecting
            if appViewModel.isConnectingServices && appViewModel.queueCount == 0 {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading Briefeed...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemBackground))
            } else {
                // Normal app content
                normalAppContent()
            }
        }
        .task {
            await appViewModel.connectToServices()
        }
    }
    
    @ViewBuilder
    private func normalAppContent() -> some View {
        VStack(spacing: 0) {
            // Test mode banner
            if Self.USE_TEST_MODE {
                HStack {
                    Text("🧪 TEST MODE: \(String(describing: Self.TEST_SCENARIO))")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(4)
                }
                .frame(maxWidth: .infinity)
                .background(Color.red)
            }
            
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
        } // End of normal app VStack
        .onAppear {
            perfLog.logView("ContentView", event: .appeared)
            perfLog.startOperation("ContentView.onAppear")
            // Apply theme settings when view appears
            applyThemePreference()
            perfLog.endOperation("ContentView.onAppear")
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ThemeChanged"))) { _ in
            perfLog.logView("ContentView", event: .onReceive)
            // Update theme when notification is received
            applyThemePreference()
        }
        // .ignoresSafeArea(.keyboard) // TESTING: Commenting out to see if this causes hang
    }
    
    @ViewBuilder
    private func testMinimalView() -> some View {
        VStack {
            Text("🧪 MINIMAL TEST VIEW")
                .font(.largeTitle)
                .padding()
            
            Text("If you can tap this button, the UI is responsive:")
                .padding()
            
            Button(action: {
                print("✅ UI IS RESPONSIVE! Button tapped at \(Date())")
            }) {
                Text("TAP TO TEST")
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            
            TabView(selection: $selectedTab) {
                Text("Feed (No Services)").tag(0)
                Text("Brief (No Services)").tag(1)
                Text("Live (No Services)").tag(2)
                Text("Settings (No Services)").tag(3)
            }
        }
        .onAppear {
            print("🧪 Minimal test view appeared - checking responsiveness")
            
            // Start a timer to verify UI is updating
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                print("⏰ Timer tick at \(Date()) - UI should be responsive")
            }
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
        CombinedFeedViewV2()  // Using V2 without singleton @StateObject
    }
}


#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserDefaultsManager.shared)
}