import Foundation
import os.log

/// Runtime safety monitoring for development
/// Catches architecture violations and performance issues
final class SafetyMonitor {
    static let shared = SafetyMonitor()
    private let logger = Logger(subsystem: "com.briefeed", category: "safety")
    
    private init() {}
    
    // MARK: - Thread Safety
    
    /// Ensure code is running on main thread
    func assertMainThread(
        function: String = #function,
        file: String = #fileID,
        line: Int = #line
    ) {
        #if DEBUG
        if !Thread.isMainThread {
            let violation = "⚠️ \(function) must run on main thread (\(file):\(line))"
            logger.error("\(violation)")
            assertionFailure(violation)
        }
        #endif
    }
    
    /// Ensure code is NOT running on main thread
    func assertNotMainThread(
        function: String = #function,
        file: String = #fileID,
        line: Int = #line
    ) {
        #if DEBUG
        if Thread.isMainThread {
            let violation = "⚠️ \(function) blocking main thread (\(file):\(line))"
            logger.error("\(violation)")
            assertionFailure(violation)
        }
        #endif
    }
    
    // MARK: - Performance Monitoring
    
    /// Measure and warn about slow operations
    func measureBlock<T>(
        name: String,
        threshold: TimeInterval = 0.016, // 60fps = 16ms per frame
        _ block: () throws -> T
    ) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            if elapsed > threshold {
                logger.warning("⚠️ Slow operation '\(name)': \(elapsed)s (threshold: \(threshold)s)")
                #if DEBUG
                print("🐌 SLOW: \(name) took \(String(format: "%.3f", elapsed))s")
                #endif
            }
        }
        return try block()
    }
    
    /// Async version of measureBlock
    func measureAsyncBlock<T>(
        name: String,
        threshold: TimeInterval = 0.016,
        _ block: () async throws -> T
    ) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            if elapsed > threshold {
                logger.warning("⚠️ Slow async operation '\(name)': \(elapsed)s")
                #if DEBUG
                print("🐌 SLOW ASYNC: \(name) took \(String(format: "%.3f", elapsed))s")
                #endif
            }
        }
        return try await block()
    }
    
    // MARK: - Architecture Violations
    
    /// Check that singleton is not ObservableObject
    func checkSingletonNotObservable(_ object: Any, name: String? = nil) {
        #if DEBUG
        let objectName = name ?? String(describing: type(of: object))
        
        // Check if object conforms to ObservableObject
        let mirror = Mirror(reflecting: object)
        let typeString = String(describing: type(of: object))
        
        if typeString.contains("ObservableObject") {
            let violation = "Architecture violation: \(objectName) is a Singleton ObservableObject"
            logger.error("\(violation)")
            assertionFailure(violation)
        }
        
        // Check for static shared property
        for child in mirror.children {
            if let label = child.label, label == "shared" {
                logger.info("✅ \(objectName) has singleton pattern")
            }
        }
        #endif
    }
    
    /// Check that service doesn't have @Published properties
    func checkNoPublishedInService(_ object: Any, name: String? = nil) {
        #if DEBUG
        let objectName = name ?? String(describing: type(of: object))
        let mirror = Mirror(reflecting: object)
        
        for child in mirror.children {
            let childType = String(describing: type(of: child.value))
            if childType.contains("Published") {
                let violation = "Architecture violation: \(objectName) has @Published property '\(child.label ?? "unknown")'"
                logger.error("\(violation)")
                assertionFailure(violation)
            }
        }
        #endif
    }
    
    /// Check that ViewModel is ObservableObject
    func checkViewModelIsObservable(_ object: Any, name: String? = nil) {
        #if DEBUG
        let objectName = name ?? String(describing: type(of: object))
        let typeString = String(describing: type(of: object))
        
        if !typeString.contains("ObservableObject") && !typeString.contains("ViewModel") {
            let violation = "Architecture violation: \(objectName) ViewModel should be ObservableObject"
            logger.error("\(violation)")
            assertionFailure(violation)
        }
        #endif
    }
    
    // MARK: - Initialization Monitoring
    
    /// Monitor service initialization time
    func monitorInitialization<T>(
        of type: T.Type,
        threshold: TimeInterval = 0.01,
        _ initializer: () -> T
    ) -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let instance = initializer()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        if elapsed > threshold {
            logger.warning("⚠️ \(type) init took \(elapsed)s (threshold: \(threshold)s)")
            #if DEBUG
            print("⚠️ SLOW INIT: \(type) took \(String(format: "%.3f", elapsed))s")
            #endif
        }
        
        return instance
    }
}

// MARK: - Main Thread Monitor

/// Monitors main thread for blocking operations
final class MainThreadMonitor {
    static let shared = MainThreadMonitor()
    private var timer: Timer?
    private var lastPing = Date()
    private let threshold: TimeInterval = 0.1 // 100ms
    private let logger = Logger(subsystem: "com.briefeed", category: "main-thread")
    
    private init() {}
    
    /// Start monitoring main thread responsiveness
    func startMonitoring() {
        #if DEBUG
        guard timer == nil else { return }
        
        logger.info("🔍 Starting main thread monitoring")
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastPing)
            
            if elapsed > self.threshold {
                let message = "🔴 MAIN THREAD BLOCKED for \(String(format: "%.3f", elapsed))s"
                self.logger.error("\(message)")
                print(message)
                
                // In debug, we could trigger a breakpoint
                // raise(SIGINT)
            }
            
            self.lastPing = now
        }
        #endif
    }
    
    /// Stop monitoring
    func stopMonitoring() {
        #if DEBUG
        timer?.invalidate()
        timer = nil
        logger.info("🛑 Stopped main thread monitoring")
        #endif
    }
}

// MARK: - Performance Tracker

/// Track performance metrics across the app
final class PerformanceTracker {
    static let shared = PerformanceTracker()
    private var metrics: [String: [TimeInterval]] = [:]
    private let queue = DispatchQueue(label: "com.briefeed.performance", attributes: .concurrent)
    private let logger = Logger(subsystem: "com.briefeed", category: "performance")
    
    private init() {}
    
    /// Track a performance metric
    func track(_ name: String, time: TimeInterval) {
        queue.async(flags: .barrier) {
            if self.metrics[name] == nil {
                self.metrics[name] = []
            }
            self.metrics[name]?.append(time)
            
            #if DEBUG
            // Alert if consistently slow
            if let times = self.metrics[name], times.count >= 3 {
                let recent = Array(times.suffix(3))
                let average = recent.reduce(0, +) / Double(recent.count)
                
                if average > 0.1 {
                    self.logger.warning("⚠️ PERFORMANCE: \(name) averaging \(average)s")
                    print("⚠️ PERFORMANCE: \(name) averaging \(String(format: "%.3f", average))s")
                }
            }
            #endif
        }
    }
    
    /// Generate performance report
    func generateReport() -> String {
        var report = "📊 Performance Report:\n"
        
        queue.sync {
            for (name, times) in metrics.sorted(by: { $0.key < $1.key }) {
                guard !times.isEmpty else { continue }
                
                let average = times.reduce(0, +) / Double(times.count)
                let max = times.max() ?? 0
                let min = times.min() ?? 0
                
                report += "  \(name):\n"
                report += "    • Average: \(String(format: "%.3f", average))s\n"
                report += "    • Min: \(String(format: "%.3f", min))s\n"
                report += "    • Max: \(String(format: "%.3f", max))s\n"
                report += "    • Samples: \(times.count)\n"
            }
        }
        
        return report
    }
    
    /// Clear all metrics
    func reset() {
        queue.async(flags: .barrier) {
            self.metrics.removeAll()
            self.logger.info("Performance metrics reset")
        }
    }
}