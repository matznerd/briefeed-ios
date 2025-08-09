//
//  TestMinimalView.swift
//  Briefeed
//
//  Minimal test view to isolate UI freeze issue
//

import SwiftUI
import Combine

// MARK: - Test 1: Absolute Minimal (No Dependencies)
struct TestMinimalView: View {
    @State private var selectedTab = 0
    @State private var counter = 0
    
    var body: some View {
        VStack {
            Text("Test Minimal View")
                .font(.largeTitle)
                .padding()
            
            Text("Counter: \(counter)")
                .font(.title2)
            
            Button("Tap to Test Response") {
                counter += 1
                print("✅ UI is responsive! Counter: \(counter)")
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            
            TabView(selection: $selectedTab) {
                Text("Feed Tab")
                    .tabItem {
                        Label("Feed", systemImage: "newspaper")
                    }
                    .tag(0)
                
                Text("Brief Tab")
                    .tabItem {
                        Label("Brief", systemImage: "music.note.list")
                    }
                    .tag(1)
                
                Text("Live Tab")
                    .tabItem {
                        Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .tag(2)
                
                Text("Settings Tab")
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(3)
            }
        }
        .onAppear {
            print("🟢 TestMinimalView appeared - UI should be responsive")
        }
    }
}

// MARK: - Test 2: With UserDefaults Only
struct TestWithUserDefaultsView: View {
    @StateObject private var userDefaultsManager = UserDefaultsManager.shared
    @State private var selectedTab = 0
    @State private var counter = 0
    
    var body: some View {
        VStack {
            Text("Test With UserDefaults")
                .font(.largeTitle)
                .padding()
            
            Text("Dark Mode: \(userDefaultsManager.isDarkMode ? "ON" : "OFF")")
            
            Button("Toggle Dark Mode") {
                counter += 1
                userDefaultsManager.isDarkMode.toggle()
                print("✅ UserDefaults test - Counter: \(counter)")
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            
            TabView(selection: $selectedTab) {
                Text("Feed").tag(0)
                Text("Brief").tag(1)
                Text("Live").tag(2)
                Text("Settings").tag(3)
            }
        }
        .onAppear {
            print("🟢 TestWithUserDefaultsView appeared")
        }
    }
}

// MARK: - Test 3: With Empty AppViewModel
struct TestWithEmptyAppViewModel: View {
    @StateObject private var appViewModel = TestEmptyAppViewModel()
    @State private var selectedTab = 0
    
    var body: some View {
        VStack {
            Text("Test With Empty AppViewModel")
                .font(.largeTitle)
                .padding()
            
            Text("Is Loading: \(appViewModel.isLoading ? "YES" : "NO")")
            
            Button("Test State Update") {
                appViewModel.testStateUpdate()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            
            TabView(selection: $selectedTab) {
                Text("Feed").tag(0)
                Text("Brief").tag(1)
                Text("Live").tag(2)
                Text("Settings").tag(3)
            }
        }
        .onAppear {
            print("🟢 TestWithEmptyAppViewModel appeared")
        }
    }
}

// Empty AppViewModel for testing
@MainActor
class TestEmptyAppViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var counter = 0
    
    init() {
        print("📦 TestEmptyAppViewModel init - no services")
    }
    
    func testStateUpdate() {
        counter += 1
        print("✅ State update works - Counter: \(counter)")
    }
}

// MARK: - Test 4: Progressive Service Test
struct TestProgressiveServicesView: View {
    @StateObject private var testViewModel = TestProgressiveViewModel()
    @State private var selectedTab = 0
    
    var body: some View {
        VStack {
            Text("Progressive Service Test")
                .font(.largeTitle)
                .padding()
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Audio Service: \(testViewModel.audioServiceStatus)")
                Text("Queue Service: \(testViewModel.queueServiceStatus)")
                Text("State Manager: \(testViewModel.stateManagerStatus)")
                Text("RSS Service: \(testViewModel.rssServiceStatus)")
            }
            .padding()
            
            HStack(spacing: 20) {
                Button("Test Audio") {
                    Task {
                        await testViewModel.testAudioService()
                    }
                }
                
                Button("Test Queue") {
                    testViewModel.testQueueService()
                }
                
                Button("Test State") {
                    Task {
                        await testViewModel.testStateManager()
                    }
                }
            }
            .padding()
            
            TabView(selection: $selectedTab) {
                Text("Feed").tag(0)
                Text("Brief").tag(1)
                Text("Live").tag(2)
                Text("Settings").tag(3)
            }
        }
    }
}

@MainActor
class TestProgressiveViewModel: ObservableObject {
    @Published var audioServiceStatus = "Not Tested"
    @Published var queueServiceStatus = "Not Tested"
    @Published var stateManagerStatus = "Not Tested"
    @Published var rssServiceStatus = "Not Tested"
    
    func testAudioService() async {
        audioServiceStatus = "Testing..."
        
        // Test accessing the singleton
        let start = CFAbsoluteTimeGetCurrent()
        _ = BriefeedAudioService.shared
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        if elapsed > 0.1 {
            audioServiceStatus = "❌ SLOW: \(String(format: "%.2f", elapsed))s"
        } else {
            audioServiceStatus = "✅ OK: \(String(format: "%.3f", elapsed))s"
        }
    }
    
    func testQueueService() {
        queueServiceStatus = "Testing..."
        
        let start = CFAbsoluteTimeGetCurrent()
        _ = QueueServiceV2.shared
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        if elapsed > 0.1 {
            queueServiceStatus = "❌ SLOW: \(String(format: "%.2f", elapsed))s"
        } else {
            queueServiceStatus = "✅ OK: \(String(format: "%.3f", elapsed))s"
        }
    }
    
    func testStateManager() async {
        stateManagerStatus = "Testing..."
        
        let start = CFAbsoluteTimeGetCurrent()
        _ = await ArticleStateManager.shared
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        if elapsed > 0.1 {
            stateManagerStatus = "❌ SLOW: \(String(format: "%.2f", elapsed))s"
        } else {
            stateManagerStatus = "✅ OK: \(String(format: "%.3f", elapsed))s"
        }
    }
}

// MARK: - Test 5: Combine Subscription Test
struct TestCombineSubscriptionsView: View {
    @StateObject private var testViewModel = TestCombineViewModel()
    @State private var selectedTab = 0
    
    var body: some View {
        VStack {
            Text("Combine Subscription Test")
                .font(.largeTitle)
                .padding()
            
            Text("Updates Received: \(testViewModel.updateCount)")
            Text("Is Looping: \(testViewModel.isLooping ? "⚠️ YES" : "✅ NO")")
            
            Button("Enable Subscriptions") {
                testViewModel.enableSubscriptions()
            }
            .padding()
            
            Button("Trigger Update") {
                testViewModel.triggerUpdate()
            }
            .padding()
            
            TabView(selection: $selectedTab) {
                Text("Feed").tag(0)
                Text("Brief").tag(1)
                Text("Live").tag(2)
                Text("Settings").tag(3)
            }
        }
    }
}

@MainActor
class TestCombineViewModel: ObservableObject {
    @Published var updateCount = 0
    @Published var isLooping = false
    @Published var testValue = 0
    
    private var updateTimer: Timer?
    private var lastUpdateTime = CFAbsoluteTimeGetCurrent()
    private var cancellables = Set<AnyCancellable>()
    
    func enableSubscriptions() {
        // Monitor for rapid updates (potential infinite loop)
        $testValue
            .sink { [weak self] _ in
                guard let self = self else { return }
                let now = CFAbsoluteTimeGetCurrent()
                let timeSinceLastUpdate = now - self.lastUpdateTime
                
                if timeSinceLastUpdate < 0.01 { // Less than 10ms between updates
                    self.isLooping = true
                    print("⚠️ POTENTIAL INFINITE LOOP DETECTED")
                }
                
                self.lastUpdateTime = now
                self.updateCount += 1
            }
            .store(in: &cancellables)
    }
    
    func triggerUpdate() {
        testValue += 1
    }
}

#Preview("Minimal") {
    TestMinimalView()
}

#Preview("With UserDefaults") {
    TestWithUserDefaultsView()
}

#Preview("With Empty AppViewModel") {
    TestWithEmptyAppViewModel()
}

#Preview("Progressive Services") {
    TestProgressiveServicesView()
}

#Preview("Combine Subscriptions") {
    TestCombineSubscriptionsView()
}