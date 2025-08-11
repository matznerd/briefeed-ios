//
//  MinimalTestRunner.swift
//  BriefeedTests
//
//  Minimal test runner to validate the new audio system
//

import XCTest
@testable import Briefeed

@MainActor
final class MinimalTestRunner: XCTestCase {
    
    var viewModel: AudioPlayerViewModelV2!
    
    override func setUp() async throws {
        try await super.setUp()
        viewModel = AudioPlayerViewModelV2()
    }
    
    override func tearDown() async throws {
        viewModel?.stop()
        viewModel = nil
        try await super.tearDown()
    }
    
    // Test 1: Basic initialization
    func testAudioPlayerInitialization() async throws {
        XCTAssertNotNil(viewModel)
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertEqual(viewModel.queueItems.count, 0)
        XCTAssertNil(viewModel.currentTitle)
    }
    
    // Test 2: Queue management
    func testBasicQueueManagement() async throws {
        // Create test article
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Test Article"
        article.content = "Test content"
        article.url = "https://example.com"
        article.createdAt = Date()
        
        // Add to queue
        await viewModel.addToQueue(article)
        
        // Verify
        XCTAssertEqual(viewModel.queueItems.count, 1)
        XCTAssertEqual(viewModel.queueItems[0].title, "Test Article")
    }
    
    // Test 3: Play/pause controls
    func testPlayPauseControls() async throws {
        // Create and add test article
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Play Test"
        article.content = "Content for play test"
        article.url = "https://example.com"
        article.createdAt = Date()
        
        await viewModel.addToQueue(article)
        
        // Test play
        await viewModel.play()
        // Wait a bit for state to update
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Can't assert isPlaying without TTS generation
        // Just verify no crash
        XCTAssertEqual(viewModel.queueItems.count, 1)
        
        // Test pause
        viewModel.pause()
        XCTAssertFalse(viewModel.isPlaying)
        
        // Test stop
        viewModel.stop()
        XCTAssertFalse(viewModel.isPlaying)
    }
    
    // Test 4: Queue persistence
    func testQueuePersistence() async throws {
        // Create test items
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        
        let article1 = Article(context: context)
        article1.id = UUID()
        article1.title = "Article 1"
        article1.content = "Content 1"
        article1.url = "https://example.com/1"
        article1.createdAt = Date()
        
        let article2 = Article(context: context)
        article2.id = UUID()
        article2.title = "Article 2"
        article2.content = "Content 2"
        article2.url = "https://example.com/2"
        article2.createdAt = Date()
        
        // Add to queue
        await viewModel.addToQueue(article1)
        await viewModel.addToQueue(article2)
        
        XCTAssertEqual(viewModel.queueItems.count, 2)
        
        // Save state
        await viewModel.saveQueueState()
        
        // Create new view model (simulates app restart)
        let newViewModel = AudioPlayerViewModelV2()
        
        // Queue should be restored
        XCTAssertEqual(newViewModel.queueItems.count, 2)
        XCTAssertEqual(newViewModel.queueItems[0].title, "Article 1")
        XCTAssertEqual(newViewModel.queueItems[1].title, "Article 2")
    }
    
    // Test 5: Skip controls
    func testSkipControls() async throws {
        // Create multiple test items
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        
        for i in 1...3 {
            let article = Article(context: context)
            article.id = UUID()
            article.title = "Article \(i)"
            article.content = "Content \(i)"
            article.url = "https://example.com/\(i)"
            article.createdAt = Date()
            
            await viewModel.addToQueue(article)
        }
        
        XCTAssertEqual(viewModel.queueItems.count, 3)
        XCTAssertEqual(viewModel.currentQueueIndex, -1)
        
        // Play first item
        await viewModel.play()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(viewModel.currentQueueIndex, 0)
        
        // Skip to next
        await viewModel.playNext()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(viewModel.currentQueueIndex, 1)
        
        // Skip to next again
        await viewModel.playNext()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(viewModel.currentQueueIndex, 2)
        
        // Go back
        await viewModel.playPrevious()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(viewModel.currentQueueIndex, 1)
    }
    
    // Test 6: Clear queue
    func testClearQueue() async throws {
        // Create test items
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        
        for i in 1...5 {
            let article = Article(context: context)
            article.id = UUID()
            article.title = "Article \(i)"
            article.content = "Content \(i)"
            article.url = "https://example.com/\(i)"
            article.createdAt = Date()
            
            await viewModel.addToQueue(article)
        }
        
        XCTAssertEqual(viewModel.queueItems.count, 5)
        
        // Clear queue
        await viewModel.clearQueue()
        
        XCTAssertEqual(viewModel.queueItems.count, 0)
        XCTAssertNil(viewModel.currentTitle)
        XCTAssertEqual(viewModel.currentQueueIndex, -1)
    }
}