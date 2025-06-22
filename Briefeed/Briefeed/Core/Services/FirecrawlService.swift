//
//  FirecrawlService.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import Foundation

// MARK: - Firecrawl Models
struct FirecrawlResponse: Codable {
    let success: Bool
    let data: FirecrawlData?
    let error: String?
}

struct FirecrawlData: Codable {
    let content: String
    let markdown: String?
    let html: String?
    let metadata: FirecrawlMetadata?
    let screenshot: String?
}

struct FirecrawlMetadata: Codable {
    let title: String?
    let description: String?
    let language: String?
    let ogTitle: String?
    let ogDescription: String?
    let ogImage: String?
    let author: String?
    let publishedTime: String?
}

// MARK: - Firecrawl Error Types
enum FirecrawlError: LocalizedError {
    case invalidAPIKey
    case scrapeFailure(String)
    case contentNotFound
    case rateLimitExceeded
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid Firecrawl API key"
        case .scrapeFailure(let message):
            return "Failed to scrape content: \(message)"
        case .contentNotFound:
            return "No content found at the provided URL"
        case .rateLimitExceeded:
            return "Firecrawl rate limit exceeded. Please try again later"
        }
    }
}

// MARK: - Firecrawl Service Protocol
protocol FirecrawlServiceProtocol {
    func scrapeURL(_ url: String) async throws -> FirecrawlData
    func scrapeURLWithRetry(_ url: String, maxRetries: Int) async throws -> FirecrawlData
    func fetchArticleContent(from url: String) async throws -> FirecrawlData
}

// MARK: - Firecrawl Service Implementation
class FirecrawlService: FirecrawlServiceProtocol {
    private let networkService: NetworkServiceProtocol
    private let apiKey: String
    
    init(networkService: NetworkServiceProtocol = NetworkService.shared, apiKey: String? = nil) {
        self.networkService = networkService
        self.apiKey = apiKey ?? Constants.API.firecrawlAPIKey ?? ""
    }
    
    func scrapeURL(_ url: String) async throws -> FirecrawlData {
        guard !apiKey.isEmpty else {
            throw FirecrawlError.invalidAPIKey
        }
        
        let endpoint = "\(Constants.API.firecrawlBaseURL)/scrape"
        
        let parameters: [String: Any] = [
            "url": url,
            "formats": ["markdown", "html"],
            "onlyMainContent": true,
            "includeHtml": true,
            "includeMarkdown": true,
            "waitFor": 5000, // Wait up to 5 seconds for content to load
            "screenshot": false
        ]
        
        let headers = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        
        do {
            let response: FirecrawlResponse = try await networkService.request(
                endpoint,
                method: .post,
                parameters: parameters,
                headers: headers
            )
            
            guard response.success, let data = response.data else {
                throw FirecrawlError.scrapeFailure(response.error ?? "Unknown error")
            }
            
            if data.content.isEmpty && data.markdown?.isEmpty != false {
                throw FirecrawlError.contentNotFound
            }
            
            return data
        } catch let error as NetworkError {
            if case .rateLimited = error {
                throw FirecrawlError.rateLimitExceeded
            }
            throw error
        }
    }
    
    func scrapeURLWithRetry(_ url: String, maxRetries: Int = Constants.API.maxRetries) async throws -> FirecrawlData {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                return try await scrapeURL(url)
            } catch let error as FirecrawlError {
                if case .rateLimitExceeded = error {
                    // Don't retry on rate limit errors
                    throw error
                }
                lastError = error
            } catch {
                lastError = error
            }
            
            // Exponential backoff
            if attempt < maxRetries - 1 {
                let delay = pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw lastError ?? FirecrawlError.scrapeFailure("Failed after \(maxRetries) attempts")
    }
    
    func fetchArticleContent(from url: String) async throws -> FirecrawlData {
        // This is an alias for scrapeURL to match the expected method name
        return try await scrapeURL(url)
    }
}

// MARK: - Content Processing Extensions
extension FirecrawlData {
    /// Returns the best available content format
    var bestContent: String {
        // Prefer markdown over HTML over plain content
        if let markdown = markdown, !markdown.isEmpty {
            return markdown
        } else if let html = html, !html.isEmpty {
            return html
        } else {
            return content
        }
    }
    
    /// Extracts a clean title from metadata
    var extractedTitle: String? {
        metadata?.ogTitle ?? metadata?.title
    }
    
    /// Extracts a clean description from metadata
    var extractedDescription: String? {
        metadata?.ogDescription ?? metadata?.description
    }
    
    /// Extracts the author if available
    var extractedAuthor: String? {
        metadata?.author
    }
    
    /// Extracts the publish date if available
    var publishDate: Date? {
        guard let publishedTime = metadata?.publishedTime else { return nil }
        
        // Try to parse ISO 8601 date
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: publishedTime)
    }
}