//
//  FreezeDetector.swift
//  Briefeed
//
//  Main thread freeze detector
//

import Foundation
import UIKit

/// Detects when the main thread is blocked
final class FreezeDetector {
    static let shared = FreezeDetector()
    
    private var watchdogTimer: Timer?
    private var lastPingTime = CFAbsoluteTimeGetCurrent()
    private let threshold: TimeInterval = 0.1 // 100ms threshold
    private var isMonitoring = false
    
    private init() {}
    
    /// Start monitoring for main thread blocks
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        print("🔍 FreezeDetector: Starting main thread monitoring")
        
        // Create a timer on a background queue
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            self.watchdogTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                self.checkMainThread()
            }
            
            // Keep the run loop alive
            RunLoop.current.run()
        }
        
        // Also monitor using CADisplayLink for frame drops
        DispatchQueue.main.async {
            let displayLink = CADisplayLink(target: self, selector: #selector(self.frameUpdate))
            displayLink.add(to: .main, forMode: .common)
        }
    }
    
    private func checkMainThread() {
        let now = CFAbsoluteTimeGetCurrent()
        var isBlocked = false
        
        // Try to execute on main thread with timeout
        let semaphore = DispatchSemaphore(value: 0)
        
        DispatchQueue.main.async {
            self.lastPingTime = CFAbsoluteTimeGetCurrent()
            semaphore.signal()
        }
        
        // Wait for up to threshold time
        let result = semaphore.wait(timeout: .now() + threshold)
        
        if result == .timedOut {
            isBlocked = true
            let blockDuration = CFAbsoluteTimeGetCurrent() - now
            print("🔴 MAIN THREAD BLOCKED for \(String(format: "%.3f", blockDuration))s")
            
            // Try to get stack trace
            print("📍 Main thread stack trace:")
            Thread.callStackSymbols.prefix(10).forEach { print($0) }
        }
    }
    
    @objc private func frameUpdate(displayLink: CADisplayLink) {
        let frameDuration = displayLink.duration
        let actualFrameTime = displayLink.targetTimestamp - displayLink.timestamp
        
        if actualFrameTime > frameDuration * 2 {
            print("⚠️ FRAME DROP: Expected \(String(format: "%.1f", frameDuration * 1000))ms, got \(String(format: "%.1f", actualFrameTime * 1000))ms")
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        print("🔍 FreezeDetector: Stopped monitoring")
    }
}

// MARK: - Service Timing Profiler
final class ServiceProfiler {
    static let shared = ServiceProfiler()
    
    private var operationStarts: [String: CFAbsoluteTime] = [:]
    private let queue = DispatchQueue(label: "com.briefeed.profiler", attributes: .concurrent)
    
    private init() {}
    
    func startOperation(_ name: String) {
        queue.async(flags: .barrier) {
            self.operationStarts[name] = CFAbsoluteTimeGetCurrent()
            print("⏱️ START: \(name)")
        }
    }
    
    func endOperation(_ name: String) {
        queue.async(flags: .barrier) {
            guard let start = self.operationStarts[name] else {
                print("⚠️ END: \(name) - No start time found")
                return
            }
            
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            self.operationStarts.removeValue(forKey: name)
            
            let emoji = elapsed > 1.0 ? "🔴" : elapsed > 0.1 ? "🟡" : "🟢"
            print("\(emoji) END: \(name) - \(String(format: "%.3f", elapsed))s")
            
            if elapsed > 0.1 && Thread.isMainThread {
                print("⚠️ WARNING: \(name) blocked main thread for \(String(format: "%.3f", elapsed))s")
            }
        }
    }
    
    func measure<T>(_ name: String, block: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            if elapsed > 0.016 {
                print("⏱️ \(name): \(String(format: "%.3f", elapsed))s")
            }
        }
        return try block()
    }
    
    func measureAsync<T>(_ name: String, block: () async throws -> T) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            if elapsed > 0.016 {
                print("⏱️ \(name): \(String(format: "%.3f", elapsed))s")
            }
        }
        return try await block()
    }
}

// MARK: - Deadlock Detector
final class DeadlockDetector {
    static let shared = DeadlockDetector()
    
    private var activeOperations: Set<String> = []
    private let queue = DispatchQueue(label: "com.briefeed.deadlock", attributes: .concurrent)
    
    private init() {}
    
    func enterOperation(_ name: String, file: String = #file, line: Int = #line) {
        queue.async(flags: .barrier) {
            if self.activeOperations.contains(name) {
                print("⚠️ POTENTIAL DEADLOCK: Re-entering \(name) at \(file):\(line)")
                print("   Active operations: \(self.activeOperations)")
            }
            self.activeOperations.insert(name)
        }
    }
    
    func exitOperation(_ name: String) {
        queue.async(flags: .barrier) {
            self.activeOperations.remove(name)
        }
    }
    
    func checkCircularDependency(from: String, to: String) {
        queue.sync {
            if activeOperations.contains(to) && activeOperations.contains(from) {
                print("🔴 CIRCULAR DEPENDENCY DETECTED: \(from) -> \(to)")
                print("   This could cause a deadlock!")
            }
        }
    }
}