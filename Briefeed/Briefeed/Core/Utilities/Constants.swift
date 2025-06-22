//
//  Constants.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import Foundation
import SwiftUI

enum Constants {
    enum API {
        static let redditBaseURL = "https://www.reddit.com"
        static let firecrawlBaseURL = "https://api.firecrawl.dev/v0"
        static let geminiBaseURL = "https://generativelanguage.googleapis.com/v1beta"
        
        // API Keys are now managed through UserDefaultsManager
        static var firecrawlAPIKey: String? {
            UserDefaultsManager.shared.firecrawlAPIKey
        }
        static var geminiAPIKey: String? {
            UserDefaultsManager.shared.geminiAPIKey
        }
        
        static let defaultTimeout: TimeInterval = 30
        static let maxRetries = 3
    }
    
    enum Reddit {
        static let postsPerPage = 25
        static let initialLoadLimit = 10
        static let loadMoreLimit = 25
        static let userAgent = "ios:com.briefeed.app:v1.0.0 (by /u/briefeedapp)"
        
        // Default feeds configuration
        // For subreddits: use format "/r/{subreddit_name}" or "/r/{subreddit_name}/{sort}"
        // For multireddits: use format "/user/{username}/m/{multireddit_name}"
        static let defaultFeeds: [(name: String, type: String, path: String)] = [
            (name: "r/news", type: "subreddit", path: "/r/news/top"),
            (name: "enviromonitor", type: "multireddit", path: "/user/matznerd/m/enviromonitor"),
            (name: "r/futurology", type: "subreddit", path: "/r/futurology/hot")
        ]
        
        // Sort options
        enum SortOption: String, CaseIterable {
            case hot = "hot"
            case new = "new"
            case top = "top"
            case rising = "rising"
            
            var displayName: String {
                switch self {
                case .hot: return "Hot"
                case .new: return "New"
                case .top: return "Top"
                case .rising: return "Rising"
                }
            }
        }
        
        // Content types to filter out
        static let filteredDomains = [
            "v.redd.it",
            "i.redd.it",
            "i.imgur.com",
            "imgur.com",
            "gfycat.com",
            "youtube.com",
            "youtu.be",
            "twitch.tv",
            "clips.twitch.tv",
            "streamable.com"
        ]
    }
    
    enum Storage {
        static let maxCachedArticles = 500
        static let maxCacheSize: Int64 = 100 * 1024 * 1024 // 100MB
        static let cacheExpirationDays = 30
    }
    
    enum UI {
        static let animationDuration = 0.3
        static let cornerRadius: CGFloat = 12
        static let padding: CGFloat = 16
        static let minTextSize: CGFloat = 12
        static let maxTextSize: CGFloat = 24
    }
    
    enum Audio {
        static let defaultSpeechRate: Float = 1.0
        static let minSpeechRate: Float = 0.5
        static let maxSpeechRate: Float = 2.0
    }
    
    enum Summary {
        enum Length: String, CaseIterable {
            case brief = "brief"
            case standard = "standard"
            case detailed = "detailed"
            
            var maxTokens: Int {
                switch self {
                case .brief: return 100
                case .standard: return 250
                case .detailed: return 500
                }
            }
            
            var displayName: String {
                switch self {
                case .brief: return "Brief"
                case .standard: return "Standard"
                case .detailed: return "Detailed"
                }
            }
        }
    }
    
    enum UserDefaultsKeys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let lastRefreshDate = "lastRefreshDate"
        static let selectedFeedID = "selectedFeedID"
        static let hasCreatedDefaultFeeds = "hasCreatedDefaultFeeds"
        static let feedPaginationTokens = "feedPaginationTokens"
    }
}

// MARK: - App Colors
extension Color {
    static let briefeedRed = Color(red: 1.0, green: 0, blue: 0)
    static let briefeedBackground = Color(UIColor.systemBackground)
    static let briefeedSecondaryBackground = Color(UIColor.secondarySystemBackground)
    static let briefeedLabel = Color(UIColor.label)
    static let briefeedSecondaryLabel = Color(UIColor.secondaryLabel)
    static let briefeedTertiaryLabel = Color(UIColor.tertiaryLabel)
}