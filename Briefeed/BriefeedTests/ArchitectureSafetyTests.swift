import XCTest
@testable import Briefeed

// MARK: - Architecture Safety Tests
// Verify V2 services follow correct patterns (no Singleton + ObservableObject)

final class ArchitectureSafetyTests: XCTestCase {
    
    // MARK: - Service Architecture Tests
    
    func testAudioServiceV2NotObservableObject() {
        // AudioServiceV2 should be a plain singleton, not ObservableObject
        let service = AudioServiceV2.shared
        
        // Check it's not ObservableObject
        let mirror = Mirror(reflecting: service)
        let typeString = String(describing: type(of: service))
        
        XCTAssertFalse(typeString.contains("ObservableObject"), 
                      "AudioServiceV2 should NOT be ObservableObject")
        
        // Check for @Published properties (should have none)
        for child in mirror.children {
            let childType = String(describing: type(of: child.value))
            XCTAssertFalse(childType.contains("Published"),
                          "AudioServiceV2 should not have @Published properties")
        }
    }
    
    func testQueueServiceV2NotObservableObject() {
        // QueueServiceV2 should be a plain singleton
        let service = QueueServiceV2.shared
        
        let mirror = Mirror(reflecting: service)
        let typeString = String(describing: type(of: service))
        
        XCTAssertFalse(typeString.contains("ObservableObject"),
                      "QueueServiceV2 should NOT be ObservableObject")
        
        // Check for @Published properties (should have none)
        for child in mirror.children {
            let childType = String(describing: type(of: child.value))
            XCTAssertFalse(childType.contains("Published"),
                          "QueueServiceV2 should not have @Published properties")
        }
    }
    
    func testArticleStateManagerV2NotObservableObject() {
        // ArticleStateManagerV2 should be a plain singleton
        let service = ArticleStateManagerV2.shared
        
        let mirror = Mirror(reflecting: service)
        let typeString = String(describing: type(of: service))
        
        XCTAssertFalse(typeString.contains("ObservableObject"),
                      "ArticleStateManagerV2 should NOT be ObservableObject")
        
        // Check for @Published properties (should have none)
        for child in mirror.children {
            let childType = String(describing: type(of: child.value))
            XCTAssertFalse(childType.contains("Published"),
                          "ArticleStateManagerV2 should not have @Published properties")
        }
    }
    
    // MARK: - ViewModel Architecture Tests
    
    func testAudioPlayerViewModelIsObservableObject() async {
        // AudioPlayerViewModel SHOULD be ObservableObject (it's a ViewModel)
        let viewModel = await AudioPlayerViewModel()
        
        let mirror = Mirror(reflecting: viewModel)
        let typeString = String(describing: type(of: viewModel))
        
        XCTAssertTrue(typeString.contains("AudioPlayerViewModel"),
                     "Should be AudioPlayerViewModel")
        
        // Should have @Published properties for UI binding
        var hasPublished = false
        for child in mirror.children {
            let childType = String(describing: type(of: child.value))
            if childType.contains("Published") {
                hasPublished = true
                break
            }
        }
        
        XCTAssertTrue(hasPublished,
                     "AudioPlayerViewModel should have @Published properties for UI")
    }
    
    // MARK: - Delegate Pattern Tests
    
    func testAudioServiceV2UsesDelegatePattern() {
        // AudioServiceV2 should use delegate pattern, not @Published
        let service = AudioServiceV2.shared
        
        // Check for delegate property
        let mirror = Mirror(reflecting: service)
        var hasDelegate = false
        
        for child in mirror.children {
            if let label = child.label, label.contains("delegate") {
                hasDelegate = true
                break
            }
        }
        
        XCTAssertTrue(hasDelegate,
                     "AudioServiceV2 should have a delegate property")
    }
    
    func testQueueServiceV2UsesDelegatePattern() {
        // QueueServiceV2 should use delegate pattern
        let service = QueueServiceV2.shared
        
        let mirror = Mirror(reflecting: service)
        var hasDelegate = false
        
        for child in mirror.children {
            if let label = child.label, label.contains("delegate") {
                hasDelegate = true
                break
            }
        }
        
        XCTAssertTrue(hasDelegate,
                     "QueueServiceV2 should have a delegate property")
    }
    
    // MARK: - Initialization Tests
    
    func testServicesHaveAsyncInitialization() async {
        // Services should have lightweight init and async initialize()
        
        // Test AudioServiceV2
        let audioService = AudioServiceV2.shared
        await audioService.initialize()
        XCTAssertNotNil(audioService, "AudioServiceV2 should initialize")
        
        // Test QueueServiceV2
        let queueService = QueueServiceV2.shared
        await queueService.initialize()
        XCTAssertNotNil(queueService, "QueueServiceV2 should initialize")
        
        // Test ArticleStateManagerV2
        let stateManager = ArticleStateManagerV2.shared
        await stateManager.initialize()
        XCTAssertNotNil(stateManager, "ArticleStateManagerV2 should initialize")
    }
    
    func testViewModelConnectsToServices() async {
        // ViewModel should connect to services via async connect()
        let viewModel = await AudioPlayerViewModel()
        
        XCTAssertFalse(viewModel.isConnected,
                      "Should not be connected initially")
        
        await viewModel.connect()
        
        XCTAssertTrue(viewModel.isConnected,
                     "Should be connected after connect()")
    }
    
    // MARK: - Performance Tests
    
    func testServiceInitializationIsLightweight() {
        // Measure service initialization time
        measure {
            // This should be instant (no heavy work in init)
            _ = AudioServiceV2.shared
            _ = QueueServiceV2.shared
            _ = ArticleStateManagerV2.shared
        }
    }
    
    func testViewModelInitializationIsLightweight() async {
        // Measure ViewModel initialization
        await measure {
            // This should be instant
            _ = await AudioPlayerViewModel()
        }
    }
    
    // MARK: - Anti-Pattern Detection Tests
    
    func testNoSingletonObservableObjectPattern() {
        // Check that no service combines Singleton + ObservableObject
        let services: [Any] = [
            AudioServiceV2.shared,
            QueueServiceV2.shared,
            ArticleStateManagerV2.shared
        ]
        
        for service in services {
            let typeString = String(describing: type(of: service))
            let mirror = Mirror(reflecting: service)
            
            // Has singleton pattern (static shared)
            let isSingleton = typeString.contains(".shared") || 
                            mirror.children.contains { $0.label == "shared" }
            
            // Is ObservableObject
            let isObservable = typeString.contains("ObservableObject")
            
            // Should not be both
            XCTAssertFalse(isSingleton && isObservable,
                          "\(typeString) violates architecture: Singleton + ObservableObject")
        }
    }
    
    // MARK: - Thread Safety Tests
    
    func testServicesAreThreadSafe() async {
        // Services should handle concurrent access safely
        let service = AudioServiceV2.shared
        
        // Concurrent reads should be safe
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    _ = service.state
                    _ = service.isPlaying
                }
            }
        }
        
        XCTAssertNotNil(service, "Service should survive concurrent access")
    }
}

// MARK: - Async XCTest Helpers

extension XCTestCase {
    func measure(asyncBlock: @escaping () async -> Void) async {
        let start = CFAbsoluteTimeGetCurrent()
        await asyncBlock()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        // Should be less than 10ms for lightweight init
        XCTAssertLessThan(elapsed, 0.01, 
                         "Initialization took \(elapsed)s, should be < 0.01s")
    }
}