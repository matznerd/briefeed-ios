//
//  RedditIntegrationTests.swift
//  BriefeedTests
//
//  Created by Briefeed Team on 7/24/25.
//

import Testing
@testable import Briefeed

struct RedditIntegrationTests {
    
    @Test("Reddit API returns JSON with proper headers")
    func testRedditAPIReturnsJSON() async throws {
        // This is an integration test that hits the real Reddit API
        // to verify our fix works
        
        let service = RedditService()
        let response = try await service.fetchSubreddit(name: "swift", limit: 1)
        
        #expect(response.data.children.count >= 0)
        #expect(response.kind == "Listing")
    }
    
    @Test("Generate correct Reddit URLs")
    func testGenerateRedditURLs() {
        let service = DefaultDataService.shared
        
        // Test subreddit URL
        let feed1 = Feed(context: PersistenceController.preview.container.viewContext)
        feed1.path = "/r/news"
        feed1.type = "subreddit"
        
        let url1 = service.generateFeedURL(for: feed1)
        #expect(url1.contains("https://www.reddit.com/r/news.json"))
        #expect(url1.contains("raw_json=1"))
        
        // Test multireddit URL
        let feed2 = Feed(context: PersistenceController.preview.container.viewContext)
        feed2.path = "/user/matznerd/m/enviromonitor"
        feed2.type = "multireddit"
        
        let url2 = service.generateFeedURL(for: feed2)
        #expect(url2.contains("https://www.reddit.com/user/matznerd/m/enviromonitor.json"))
    }
}