//
//  PerformanceTests.swift
//  BriefeedTests
//
//  Performance testing to catch UI and memory issues
//

import XCTest
@testable import Briefeed

final class PerformanceTests: XCTestCase {
    
    // MARK: - UI Performance Tests
    
    func testMainViewRenderingPerformance() {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            // Measure ContentView rendering
            let _ = ContentView()
        }
    }
    
    func testQueueOperationsPerformance() {
        let queue = QueueServiceV2.shared
        
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            // Add 100 items to queue
            for i in 0..<100 {
                let item = EnhancedQueueItem(
                    id: UUID(),
                    type: .article,
                    title: "Test Article \(i)",
                    author: "Test Author",
                    dateAdded: Date(),
                    articleID: UUID(),
                    audioUrl: nil,
                    feedTitle: "Test Feed"
                )
                queue.queue.append(item)
            }
            
            // Clear queue
            queue.clearQueue()
        }
    }
    
    // MARK: - Memory Leak Tests
    
    func testAudioServiceMemoryLeak() {
        weak var weakService: BriefeedAudioService?
        
        autoreleasepool {
            let service = BriefeedAudioService()
            weakService = service
            
            // Simulate usage
            service.play()
            service.pause()
            service.stop()
        }
        
        // Service should be deallocated
        XCTAssertNil(weakService, "BriefeedAudioService has a memory leak")
    }
    
    func testViewModelMemoryLeak() {
        weak var weakViewModel: AppViewModel?
        
        autoreleasepool {
            let viewModel = AppViewModel()
            weakViewModel = viewModel
            
            // Simulate usage
            Task {
                await viewModel.connectToServices()
            }
        }
        
        // Wait for async operations
        let expectation = expectation(description: "ViewModel deallocation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)
        
        XCTAssertNil(weakViewModel, "AppViewModel has a memory leak")
    }
    
    // MARK: - Combine Performance Tests
    
    func testCombineSubscriptionPerformance() {
        let viewModel = AppViewModel()
        
        measure(metrics: [XCTMemoryMetric()]) {
            // Create and destroy many subscriptions
            for _ in 0..<1000 {
                let _ = viewModel.$isPlaying.sink { _ in }
                // Without storing in cancellables, should not leak
            }
        }
    }
    
    // MARK: - SwiftUI Update Performance
    
    func testFrequentStateUpdates() {
        let startTime = CFAbsoluteTimeGetCurrent()
        var updateCount = 0
        
        // Simulate rapid state updates
        let viewModel = AppViewModel()
        
        for _ in 0..<1000 {
            viewModel.debugQueueState()
            updateCount += 1
        }
        
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        let updatesPerSecond = Double(updateCount) / timeElapsed
        
        // Should handle at least 100 updates per second without issue
        XCTAssertGreaterThan(updatesPerSecond, 100, "State updates are too slow")
    }
    
    // MARK: - Timer Performance Tests
    
    func testTimerCleanup() {
        var timers: [Timer] = []
        
        measure(metrics: [XCTMemoryMetric()]) {
            // Create timers
            for _ in 0..<10 {
                let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in }
                timers.append(timer)
            }
            
            // Cleanup
            timers.forEach { $0.invalidate() }
            timers.removeAll()
        }
    }
    
    // MARK: - Core Data Performance
    
    func testArticleFetchPerformance() {
        let context = PersistenceController.shared.container.viewContext
        
        measure(metrics: [XCTClockMetric()]) {
            let request = Article.fetchRequest()
            request.fetchLimit = 100
            
            do {
                let _ = try context.fetch(request)
            } catch {
                XCTFail("Failed to fetch articles: \(error)")
            }
        }
    }
}

// MARK: - UI Testing Extensions

extension XCTestCase {
    /// Helper to detect UI freezes
    func assertNoUIFreeze(timeout: TimeInterval = 1.0, action: () -> Void) {
        let expectation = expectation(description: "UI should not freeze")
        
        DispatchQueue.main.async {
            action()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: timeout)
    }
    
    /// Helper to detect memory leaks
    func assertNoMemoryLeak<T: AnyObject>(_ object: T, file: StaticString = #file, line: UInt = #line) {
        addTeardownBlock { [weak object] in
            XCTAssertNil(object, "Memory leak detected", file: file, line: line)
        }
    }
}