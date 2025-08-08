//
//  DiagnosticsView.swift
//  Briefeed
//
//  Debug diagnostics panel for development
//

import SwiftUI
import os.log

struct DiagnosticsView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var memoryUsage: String = "Calculating..."
    @State private var cpuUsage: String = "Calculating..."
    @State private var renderCount = 0
    @State private var updateFrequency: Double = 0
    @State private var lastUpdateTime = Date()
    @State private var timerCount = 0
    @State private var subscriptionCount = 0
    
    private let updateTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    private let logger = Logger(subsystem: "com.briefeed", category: "diagnostics")
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("🔍 Diagnostics")
                    .font(.largeTitle)
                    .bold()
                
                // Performance Section
                GroupBox(label: Label("Performance", systemImage: "speedometer")) {
                    VStack(alignment: .leading, spacing: 10) {
                        DiagnosticRow(label: "Memory Usage", value: memoryUsage)
                        DiagnosticRow(label: "CPU Usage", value: cpuUsage)
                        DiagnosticRow(label: "Render Count", value: "\(renderCount)")
                        DiagnosticRow(label: "Update Frequency", value: String(format: "%.2f Hz", updateFrequency))
                    }
                }
                
                // Audio System
                GroupBox(label: Label("Audio System", systemImage: "speaker.wave.2")) {
                    VStack(alignment: .leading, spacing: 10) {
                        DiagnosticRow(label: "Is Playing", value: appViewModel.isPlaying ? "✅" : "❌")
                        DiagnosticRow(label: "Queue Count", value: "\(appViewModel.queueCount)")
                        DiagnosticRow(label: "Current Index", value: "\(appViewModel.currentQueueIndex)")
                        DiagnosticRow(label: "Audio Loading", value: appViewModel.isAudioLoading ? "⏳" : "✅")
                    }
                }
                
                // Memory Management
                GroupBox(label: Label("Memory Management", systemImage: "memorychip")) {
                    VStack(alignment: .leading, spacing: 10) {
                        DiagnosticRow(label: "Active Timers", value: "\(timerCount)")
                        DiagnosticRow(label: "Combine Subscriptions", value: "\(subscriptionCount)")
                        DiagnosticRow(label: "Services Connected", value: appViewModel.servicesConnected ? "✅" : "❌")
                    }
                }
                
                // SwiftUI State
                GroupBox(label: Label("SwiftUI State", systemImage: "rectangle.stack")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Force State Update") {
                            Task {
                                await appViewModel.debugQueueState()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Clear All Caches") {
                            clearCaches()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Run Diagnostics") {
                            runFullDiagnostics()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // Warnings
                if hasWarnings {
                    GroupBox(label: Label("⚠️ Warnings", systemImage: "exclamationmark.triangle")) {
                        VStack(alignment: .leading, spacing: 5) {
                            if updateFrequency > 60 {
                                WarningRow(text: "High update frequency detected")
                            }
                            if timerCount > 5 {
                                WarningRow(text: "Too many active timers")
                            }
                            if subscriptionCount > 50 {
                                WarningRow(text: "Too many Combine subscriptions")
                            }
                        }
                    }
                    .foregroundColor(.orange)
                }
            }
            .padding()
        }
        .onAppear {
            startMonitoring()
            renderCount += 1
        }
        .onReceive(updateTimer) { _ in
            updateMetrics()
        }
    }
    
    private var hasWarnings: Bool {
        updateFrequency > 60 || timerCount > 5 || subscriptionCount > 50
    }
    
    private func startMonitoring() {
        logger.info("Started diagnostics monitoring")
    }
    
    private func updateMetrics() {
        // Memory usage
        memoryUsage = formatMemoryUsage()
        
        // CPU usage
        cpuUsage = formatCPUUsage()
        
        // Update frequency
        let now = Date()
        let timeDiff = now.timeIntervalSince(lastUpdateTime)
        if timeDiff > 0 {
            updateFrequency = 1.0 / timeDiff
        }
        lastUpdateTime = now
        
        // Count active timers (approximate)
        timerCount = countActiveTimers()
        
        // Count subscriptions (approximate)
        subscriptionCount = countActiveSubscriptions()
    }
    
    private func formatMemoryUsage() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let usedMemory = Double(info.resident_size) / 1024.0 / 1024.0
            return String(format: "%.1f MB", usedMemory)
        }
        return "Unknown"
    }
    
    private func formatCPUUsage() -> String {
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0
        
        let result = host_processor_info(mach_host_self(),
                                        PROCESSOR_CPU_LOAD_INFO,
                                        &numCpus,
                                        &cpuInfo,
                                        &numCpuInfo)
        
        guard result == KERN_SUCCESS else {
            return "Unknown"
        }
        
        return "~\(numCpus) cores"
    }
    
    private func countActiveTimers() -> Int {
        // This is an approximation
        // In production, you'd track this properly
        return 0 // Placeholder - proper timer tracking would be needed
    }
    
    private func countActiveSubscriptions() -> Int {
        // This is an approximation
        // In production, you'd track this properly
        return 10 // Placeholder
    }
    
    private func clearCaches() {
        URLCache.shared.removeAllCachedResponses()
        logger.info("Cleared all caches")
    }
    
    private func runFullDiagnostics() {
        logger.info("Running full diagnostics...")
        
        // Check for common issues
        if updateFrequency > 60 {
            logger.warning("High update frequency: \(updateFrequency)")
        }
        
        if timerCount > 5 {
            logger.warning("Too many timers: \(timerCount)")
        }
        
        appViewModel.debugQueueState()
    }
}

struct DiagnosticRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
    }
}

struct WarningRow: View {
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
            Text(text)
                .font(.caption)
        }
    }
}

// MARK: - Debug Menu Integration

struct DebugMenuModifier: ViewModifier {
    @State private var showDiagnostics = false
    
    func body(content: Content) -> some View {
        content
            #if DEBUG
            .onShake {
                showDiagnostics = true
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
            }
            #endif
    }
}

// Shake gesture detection
extension View {
    func onShake(perform: @escaping () -> Void) -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            perform()
        }
    }
}

// Shake detection
extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name("deviceDidShakeNotification")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
    }
}