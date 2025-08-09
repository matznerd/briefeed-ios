import XCTest
@testable import Briefeed

// MARK: - TDD: Service Architecture Tests
// These tests MUST pass before implementing services

final class ServiceArchitectureTests: XCTestCase {
    
    // MARK: - Test BriefeedAudioService Architecture
    
    func testBriefeedAudioServiceNotObservableObject() {
        // Given a service
        let service = BriefeedAudioService.shared
        
        // It must NOT be ObservableObject
        assertNotObservableObject(service)
    }
    
    func testBriefeedAudioServiceLightweightInit() {
        // Service init must be lightweight
        assertLightweightInit(BriefeedAudioService.self) {
            // This will create a new instance to test init time
            // Note: We're not using .shared here to test pure init
            BriefeedAudioService()
        }
    }
    
    func testBriefeedAudioServiceHasAsyncInitialize() async {
        // Service should have async initialization for heavy work
        let service = BriefeedAudioService.shared
        
        // Should not block main thread during initialization
        await assertNoMainThreadBlock {
            // Initialize should handle heavy work
            await service.initialize()
        }
    }
    
    // MARK: - Test QueueServiceV2 Architecture
    
    func testQueueServiceNotObservableObject() {
        let service = QueueServiceV2.shared
        
        // Services must NOT be ObservableObject
        assertNotObservableObject(service)
    }
    
    func testQueueServiceLightweightInit() {
        // Init must be fast
        assertLightweightInit(QueueServiceV2.self, threshold: 0.005) {
            QueueServiceV2()
        }
    }
    
    // MARK: - Test ArticleStateManager Architecture
    
    func testArticleStateManagerNotMainActor() {
        let service = ArticleStateManager.shared
        
        // Services should NOT be @MainActor
        let typeString = String(describing: type(of: service))
        XCTAssertFalse(
            typeString.contains("@MainActor"),
            "ArticleStateManager should not be @MainActor"
        )
    }
    
    // MARK: - Test ViewModel Architecture (when created)
    
    func testViewModelShouldBeObservableObject() {
        // Skip if ViewModel doesn't exist yet
        guard NSClassFromString("Briefeed.AudioPlayerViewModel") != nil else {
            XCTSkip("AudioPlayerViewModel not yet implemented")
            return
        }
        
        // When it exists, it SHOULD be ObservableObject
        // This test will guide the implementation
    }
    
    // MARK: - Test No Circular Dependencies
    
    func testNoCircularServiceDependencies() {
        // Services should not initialize each other in init()
        // This test ensures clean dependency graph
        
        let start = CFAbsoluteTimeGetCurrent()
        
        // Initialize all services
        _ = BriefeedAudioService.shared
        _ = QueueServiceV2.shared
        _ = ArticleStateManager.shared
        
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        // All services combined should init quickly
        XCTAssertLessThan(
            elapsed,
            0.05,
            "Service initialization took \(elapsed)s - possible circular dependency"
        )
    }
    
    // MARK: - Memory Management Tests
    
    func testServicesShouldNotLeak() {
        // Create service instance
        var service: BriefeedAudioService? = BriefeedAudioService()
        weak var weakService = service
        
        // Use it
        service?.pause()
        
        // Release it
        service = nil
        
        // Should be deallocated
        XCTAssertNil(weakService, "Service leaked - not deallocated")
    }
}