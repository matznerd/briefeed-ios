# Reddit JSON Processing & Feed Wrapping

## Overview
The app fetches content from Reddit's JSON API and transforms it into Article entities for display and playback.

## Reddit API Integration

### Service: `RedditService.swift`

#### API Endpoints
- Subreddit: `https://www.reddit.com/r/{subreddit}.json`
- Multireddit: Custom paths with `.json` suffix
- Search: `/subreddits/search.json`

#### Request Parameters
- `limit`: Posts per page (default: 25)
- `after`: Pagination token
- `raw_json`: Set to 1 to avoid HTML entities

#### Headers
```swift
["User-Agent": "ios:com.example.briefeed:v1.0.0 (by /u/example)"]
```

## JSON Structure Mapping

### Reddit Response Model
```swift
RedditResponse {
    data: RedditData {
        children: [RedditChild]
        after: String?  // Pagination token
        before: String?
    }
}

RedditChild {
    kind: String
    data: RedditPost
}

RedditPost {
    id: String
    title: String
    author: String?
    subreddit: String
    url: String?        // External link
    thumbnail: String?
    created: TimeInterval
    createdUtc: TimeInterval
    selftext: String?   // Self post content
    score: Int
    numComments: Int
    permalink: String
    isVideo: Bool?
    isSelf: Bool?       // True for text posts
}
```

## Content Filtering

### Filter Logic (`RedditService.filterResponse`)
1. **Remove self posts** - Only external articles wanted
   ```swift
   if child.data.isSelf == true { return false }
   ```

2. **Apply DefaultDataService filters**
   - Removes video content
   - Filters NSFW content
   - Removes promotional posts

## Conversion to Article

### RedditPost → Article Transformation
```swift
extension RedditPost {
    func toArticle(feedID: UUID? = nil) -> Article {
        let article = Article(context: CoreDataContext)
        article.id = UUID()
        article.title = self.title
        article.author = self.author
        article.subreddit = self.subreddit
        
        // Only set URL for external links
        if let url = self.url, self.isSelf != true {
            article.url = url
        }
        
        article.thumbnail = self.thumbnail
        article.createdAt = Date(timeIntervalSince1970: self.createdUtc)
        article.isRead = false
        article.isSaved = false
        
        // Self posts use selftext as content
        if self.isSelf == true, let selftext = self.selftext {
            article.content = selftext
        }
        
        // Link to feed if provided
        if let feedID = feedID {
            article.feed = fetchFeedByID(feedID)
        }
        
        return article
    }
}
```

## Feed URL Generation

### Feed Types Supported
1. **Subreddit**: `/r/technology`
2. **Multireddit**: `/user/example/m/tech`
3. **User posts**: `/user/example`
4. **Search**: `/search?q=query`
5. **Front page**: `/` or `/hot`

### URL Building Logic
```swift
func generateFeedURL(for feed: Feed) -> String {
    var endpoint = Constants.API.redditBaseURL
    
    if feed.path.contains("://") {
        // Already full URL
        endpoint = feed.path
    } else {
        // Build from path
        endpoint += feed.path
    }
    
    if !endpoint.hasSuffix(".json") {
        endpoint += ".json"
    }
    
    endpoint += "?limit=25&raw_json=1"
    
    if let paginationToken = feed.lastPaginationToken {
        endpoint += "&after=\(paginationToken)"
    }
    
    return endpoint
}
```

## Error Handling

### Network Errors
- **Invalid URL**: Validation before request
- **Timeout**: 10 second timeout per request
- **Rate limiting**: Handled by NetworkService
- **API errors**: Logged and propagated

### Content Errors
- **Empty response**: Returns empty article list
- **Malformed JSON**: Caught by decoder
- **Missing fields**: Optional properties handle gracefully

## Pagination

### Implementation
1. Store `after` token from response
2. Include in next request as query parameter
3. Append new articles to existing list
4. Update feed's `lastPaginationToken`

## Performance Considerations

### Optimizations
- **Batch processing**: Process all posts at once
- **Filtering early**: Remove unwanted content before conversion
- **Caching**: Articles stored in Core Data
- **Pagination**: Load 25 posts at a time

### Known Issues
- No deduplication of articles across requests
- Pagination tokens can expire
- Rate limiting not explicitly handled