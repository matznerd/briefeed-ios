import XCTest
@testable import Briefeed

// MARK: - TDD Test Helpers

extension XCTestCase {
    /// Assert service initialization is lightweight
    func assertLightweightInit<T>(
        _ type: T.Type,
        threshold: TimeInterval = 0.01,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ initializer: () -> T
    ) where T: AnyObject {
        let start = CFAbsoluteTimeGetCurrent()
        _ = initializer()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        XCTAssertLessThan(
            elapsed,
            threshold,
            "\(type) init took \(elapsed)s, exceeding \(threshold)s threshold",
            file: file,
            line: line
        )
    }
    
    /// Assert no main thread blocking
    func assertNoMainThreadBlock(
        timeout: TimeInterval = 0.1,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ block: @escaping () async -> Void
    ) async {
        let expectation = expectation(description: "No main thread block")
        
        Task.detached {
            await block()
            await MainActor.run {
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: timeout)
    }
    
    /// Memory leak detection
    func assertNoMemoryLeak(
        _ instance: AnyObject,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        addTeardownBlock { [weak instance] in
            XCTAssertNil(
                instance,
                "Memory leak detected - instance should be deallocated",
                file: file,
                line: line
            )
        }
    }
    
    /// Assert not ObservableObject (for services)
    func assertNotObservableObject(
        _ object: Any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let mirror = Mirror(reflecting: object)
        let superclassMirror = mirror.superclassMirror
        
        // Check if type conforms to ObservableObject
        if String(describing: type(of: object)).contains("ObservableObject") {
            XCTFail(
                "\(type(of: object)) should NOT be ObservableObject. Services should be plain singletons.",
                file: file,
                line: line
            )
        }
        
        // Also check superclass
        if let superMirror = superclassMirror,
           String(describing: superMirror.subjectType).contains("ObservableObject") {
            XCTFail(
                "\(type(of: object)) inherits from ObservableObject. Services should be plain singletons.",
                file: file,
                line: line
            )
        }
    }
    
    /// Assert is ObservableObject (for ViewModels)
    func assertIsObservableObject(
        _ object: Any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // ViewModels SHOULD be ObservableObject
        let typeString = String(describing: type(of: object))
        if !typeString.contains("ObservableObject") && !typeString.contains("ViewModel") {
            XCTFail(
                "\(type(of: object)) should be ObservableObject. ViewModels need @Published properties.",
                file: file,
                line: line
            )
        }
    }
    
    /// Measure operation time
    func measureTime<T>(
        _ operation: () throws -> T,
        threshold: TimeInterval,
        description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try operation()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        XCTAssertLessThan(
            elapsed,
            threshold,
            "\(description) took \(elapsed)s (limit: \(threshold)s)",
            file: file,
            line: line
        )
        
        return result
    }
}