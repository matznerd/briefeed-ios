//
//  PerformanceLogger.swift
//  Briefeed
//
//  Ultra-detailed performance logging for debugging UI freezes
//

import Foundation
import os.log

/// Central performance and debugging logger with high-precision timestamps
final class PerformanceLogger {
    static let shared = PerformanceLogger()
    
    private let logger = Logger(subsystem: "com.briefeed.performance", category: "Performance")
    private let startTime = Date()
    private var eventCounter = 0
    private let dateFormatter: DateFormatter
    
    // Track operation durations
    private var operationStarts: [String: Date] = [:]
    private let queue = DispatchQueue(label: "com.briefeed.perflogger", attributes: .concurrent)
    
    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        dateFormatter.timeZone = TimeZone.current
    }
    
    /// Log an event with timestamp and thread info
    func log(_ message: String, 
             category: LogCategory = .general,
             file: String = #file,
             function: String = #function,
             line: Int = #line) {
        
        let timestamp = dateFormatter.string(from: Date())
        let timeSinceStart = Date().timeIntervalSince(startTime)
        let threadInfo = Thread.isMainThread ? "MAIN" : "BG-\(Thread.current.hash)"
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        
        queue.async(flags: .barrier) { [weak self] in
            self?.eventCounter += 1
            let count = self?.eventCounter ?? 0
            
            let logMessage = String(format: "[%@][%.3fs][#%04d][%@][%@] %@:%d - %@",
                                   timestamp,
                                   timeSinceStart,
                                   count,
                                   threadInfo,
                                   category.emoji,
                                   fileName,
                                   line,
                                   message)
            
            print(logMessage)
            
            // Also log to system logger for persistence
            self?.logger.debug("\(logMessage)")
        }
    }
    
    /// Start timing an operation
    func startOperation(_ name: String) {
        let timestamp = dateFormatter.string(from: Date())
        let timeSinceStart = Date().timeIntervalSince(startTime)
        let threadInfo = Thread.isMainThread ? "MAIN" : "BG"
        
        queue.async(flags: .barrier) { [weak self] in
            self?.operationStarts[name] = Date()
            print("⏱️ START[\(timestamp)][\(String(format: "%.3fs", timeSinceStart))][\(threadInfo)] Operation: \(name)")
        }
    }
    
    /// End timing an operation and log duration
    func endOperation(_ name: String) {
        let endTime = Date()
        let timestamp = dateFormatter.string(from: endTime)
        let timeSinceStart = endTime.timeIntervalSince(startTime)
        let threadInfo = Thread.isMainThread ? "MAIN" : "BG"
        
        queue.async(flags: .barrier) { [weak self] in
            if let startTime = self?.operationStarts[name] {
                let duration = endTime.timeIntervalSince(startTime)
                let durationMs = duration * 1000
                
                let emoji = durationMs > 100 ? "🔴" : (durationMs > 50 ? "🟡" : "🟢")
                
                print("\(emoji) END[\(timestamp)][\(String(format: "%.3fs", timeSinceStart))][\(threadInfo)] Operation: \(name) - Duration: \(String(format: "%.1fms", durationMs))")
                
                if durationMs > 100 {
                    print("⚠️ SLOW OPERATION DETECTED: \(name) took \(String(format: "%.1fms", durationMs))")
                }
                
                self?.operationStarts.removeValue(forKey: name)
            } else {
                print("⏱️ END[\(timestamp)][\(String(format: "%.3fs", timeSinceStart))][\(threadInfo)] Operation: \(name) - No start time recorded")
            }
        }
    }
    
    /// Log a publisher event
    func logPublisher(_ name: String, value: String? = nil) {
        let valueStr = value ?? "changed"
        log("📢 Publisher '\(name)' \(valueStr)", category: .publisher)
    }
    
    /// Log a view event
    func logView(_ viewName: String, event: ViewEvent) {
        log("🖼️ \(viewName).\(event.rawValue)", category: .view)
    }
    
    /// Log a service event
    func logService(_ serviceName: String, method: String, detail: String? = nil) {
        let detailStr = detail.map { " - \($0)" } ?? ""
        log("⚙️ \(serviceName).\(method)\(detailStr)", category: .service)
    }
    
    /// Log thread transition
    func logThreadTransition(from: String, to: String) {
        log("🔄 Thread transition: \(from) -> \(to)", category: .thread)
    }
    
    /// Log memory usage
    func logMemoryUsage() {
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
            let memoryMB = Double(info.resident_size) / 1024.0 / 1024.0
            log(String(format: "💾 Memory: %.1f MB", memoryMB), category: .memory)
        }
    }
    
    /// Check if main thread is blocked
    func checkMainThread(_ operation: String) {
        if Thread.isMainThread {
            log("⚠️ MAIN THREAD: \(operation)", category: .warning)
        }
    }
    
    enum LogCategory {
        case general
        case service
        case view
        case publisher
        case thread
        case memory
        case warning
        case error
        case queue
        case audio
        case network
        case coredata
        
        var emoji: String {
            switch self {
            case .general: return "📝"
            case .service: return "⚙️"
            case .view: return "🖼️"
            case .publisher: return "📢"
            case .thread: return "🔄"
            case .memory: return "💾"
            case .warning: return "⚠️"
            case .error: return "❌"
            case .queue: return "📋"
            case .audio: return "🎵"
            case .network: return "🌐"
            case .coredata: return "💿"
            }
        }
    }
    
    enum ViewEvent: String {
        case appeared = "appeared"
        case disappeared = "disappeared"
        case bodyExecuted = "body"
        case taskStarted = "task.started"
        case taskCompleted = "task.completed"
        case onReceive = "onReceive"
        case onChange = "onChange"
        case rendered = "rendered"
    }
}

// MARK: - Convenience Extensions

extension PerformanceLogger {
    /// Log and measure an async operation
    func measureAsync<T>(_ name: String, operation: () async throws -> T) async rethrows -> T {
        startOperation(name)
        defer { endOperation(name) }
        return try await operation()
    }
    
    /// Log and measure a sync operation
    func measure<T>(_ name: String, operation: () throws -> T) rethrows -> T {
        startOperation(name)
        defer { endOperation(name) }
        return try operation()
    }
}

// Global convenience
let perfLog = PerformanceLogger.shared