//
//  RedditService.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import Foundation
import CoreData

// MARK: - Reddit Models
struct RedditResponse: Codable {
    let data: RedditData
}

struct RedditData: Codable {
    let children: [RedditChild]
    let after: String?
    let before: String?
}

struct RedditChild: Codable {
    let kind: String
    let data: RedditPost
}

struct RedditPost: Codable {
    let id: String
    let title: String
    let author: String?
    let subreddit: String
    let url: String?
    let thumbnail: String?
    let created: TimeInterval
    let createdUtc: TimeInterval
    let selftext: String?
    let score: Int
    let numComments: Int
    let permalink: String
    let isVideo: Bool?
    let isSelf: Bool?
}

// MARK: - Reddit Service
protocol RedditServiceProtocol {
    func fetchSubreddit(name: String, after: String?, limit: Int) async throws -> RedditResponse
    func fetchMultireddit(path: String, after: String?, limit: Int) async throws -> RedditResponse
    func searchSubreddits(query: String) async throws -> [SubredditInfo]
    func fetchFeedWithURL(_ url: String) async throws -> RedditResponse
}

struct SubredditInfo: Codable {
    let displayName: String
    let title: String
    let subscribers: Int
    let publicDescription: String
    let iconImg: String?
}

class RedditService: RedditServiceProtocol {
    private let networkService: NetworkServiceProtocol
    
    init(networkService: NetworkServiceProtocol = NetworkService.shared) {
        self.networkService = networkService
    }
    
    func fetchSubreddit(name: String, after: String? = nil, limit: Int = Constants.Reddit.postsPerPage) async throws -> RedditResponse {
        var endpoint = "\(Constants.API.redditBaseURL)/r/\(name).json?limit=\(limit)&raw_json=1"
        if let after = after {
            endpoint += "&after=\(after)"
        }
        
        let headers = ["User-Agent": Constants.Reddit.userAgent]
        let response: RedditResponse = try await networkService.request(endpoint, method: .get, parameters: nil, headers: headers, timeout: nil)
        
        // Filter out non-article content
        return filterResponse(response)
    }
    
    func fetchMultireddit(path: String, after: String? = nil, limit: Int = Constants.Reddit.postsPerPage) async throws -> RedditResponse {
        var endpoint: String
        if path.contains("://") {
            // Path already contains full URL
            endpoint = path
        } else {
            // Build URL from path
            endpoint = path.contains("old.reddit.com") ? "https://old.reddit.com" : Constants.API.redditBaseURL
            endpoint += path
        }
        
        if !endpoint.hasSuffix(".json") {
            endpoint += ".json"
        }
        
        endpoint += "?limit=\(limit)&raw_json=1"
        
        if let after = after {
            endpoint += "&after=\(after)"
        }
        
        let headers = ["User-Agent": Constants.Reddit.userAgent]
        let response: RedditResponse = try await networkService.request(endpoint, method: .get, parameters: nil, headers: headers, timeout: nil)
        
        // Filter out non-article content
        return filterResponse(response)
    }
    
    func searchSubreddits(query: String) async throws -> [SubredditInfo] {
        let endpoint = "\(Constants.API.redditBaseURL)/subreddits/search.json?q=\(query)&limit=10&raw_json=1"
        let headers = ["User-Agent": Constants.Reddit.userAgent]
        
        let response: RedditResponse = try await networkService.request(endpoint, method: .get, parameters: nil, headers: headers, timeout: nil)
        
        // Parse subreddit info from the response
        return response.data.children.compactMap { child -> SubredditInfo? in
            guard let data = try? JSONSerialization.data(withJSONObject: child.data),
                  let info = try? JSONDecoder().decode(SubredditInfo.self, from: data) else {
                return nil
            }
            return info
        }
    }
    
    func fetchFeedWithURL(_ url: String) async throws -> RedditResponse {
        // The URL should already be properly formatted by generateFeedURL
        // Just validate it and make the request
        guard !url.isEmpty else {
            throw NetworkError.invalidURL
        }
        
        print("📡 Reddit API Request: \(url)")
        
        let headers = ["User-Agent": Constants.Reddit.userAgent]
        
        do {
            let response: RedditResponse = try await networkService.request(url, method: .get, parameters: nil, headers: headers, timeout: nil)
            print("✅ Reddit API Success: Got \(response.data.children.count) posts")
            
            // Filter out non-article content
            let filtered = filterResponse(response)
            print("  📊 After filtering: \(filtered.data.children.count) posts remain")
            
            return filtered
        } catch {
            print("❌ Reddit API Error for URL: \(url)")
            print("   Error: \(error)")
            throw error
        }
    }
    
    // MARK: - Content Filtering
    private func filterResponse(_ response: RedditResponse) -> RedditResponse {
        let filteredChildren = response.data.children.filter { child in
            // Filter out self posts - we only want external articles
            if child.data.isSelf == true {
                return false
            }
            
            // Also apply any other filters
            return !DefaultDataService.shared.shouldFilterPost(child.data)
        }
        
        let filteredData = RedditData(
            children: filteredChildren,
            after: response.data.after,
            before: response.data.before
        )
        
        return RedditResponse(data: filteredData)
    }
}

// MARK: - Reddit Post to Article Conversion
extension RedditPost {
    func toArticle(feedID: UUID? = nil) -> Article {
        let article = Article(context: PersistenceController.shared.container.viewContext)
        article.id = UUID()
        article.title = self.title
        article.author = self.author
        article.subreddit = self.subreddit
        // Only set URL if it's an external link
        if let url = self.url, self.isSelf != true {
            article.url = url
        }
        article.thumbnail = self.thumbnail
        article.createdAt = Date(timeIntervalSince1970: self.createdUtc)
        article.isRead = false
        article.isSaved = false
        
        // If it's a self post, use the selftext as content
        if self.isSelf == true, let selftext = self.selftext, !selftext.isEmpty {
            article.content = selftext
        }
        
        // Set feed relationship if provided
        if let feedID = feedID {
            let fetchRequest: NSFetchRequest<Feed> = Feed.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", feedID as CVarArg)
            fetchRequest.fetchLimit = 1
            
            if let feed = try? PersistenceController.shared.container.viewContext.fetch(fetchRequest).first {
                article.feed = feed
            }
        }
        
        return article
    }
}

