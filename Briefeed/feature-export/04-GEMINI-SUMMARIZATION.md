# Gemini AI Summarization

## Overview
The app uses Google's Gemini API to generate structured summaries of articles with "Quick Facts" and a two-paragraph story.

## Service: `GeminiService.swift`

### Model Configuration
- **Model**: `gemini-2.0-flash-exp` (latest fast model)
- **Temperature**: 0.3 for structured output, 0.7 for regular summaries
- **Max Tokens**: Varies by summary length (250-1000)

## Summary Generation Flow

1. **Content Fetching** → FirecrawlService scrapes article
2. **Prompt Construction** → Structured prompt with instructions
3. **API Request** → Send to Gemini
4. **JSON Parsing** → Extract structured response
5. **Error Handling** → Fallback messages

## The Summarization Prompt

### Complete Prompt Template
```swift
"""
Your SOLE task is to analyze the provided news article content and extract specific information.

Title: "{article_title}"

Article Content:
\"\"\"
{scraped_content}
\"\"\"

Instructions:
1. Read the "Article Content" carefully.
2. Focus ONLY on the main textual content of the article. Ignore sidebars, navigation links, advertisements, comments, and other non-article elements.
3. Extract the information requested in the JSON format below.
4. For "quickFacts", provide concise answers. If a specific piece of information for a quickFact is not clearly available in the article, use "N/A".
5. For "theStory", provide a two-paragraph summary based EXCLUSIVELY on the provided "Article Content".

Response Format (JSON Object ONLY):
- If you can successfully extract the information and summarize the "Article Content":
  {
    "quickFacts": {
      "whatHappened": "Brief description of the core event.",
      "who": "Main people or organizations involved.",
      "whenWhere": "Time and location of the event.",
      "keyNumbers": "Any significant numbers, statistics, or monetary amounts, or 'N/A'.",
      "mostStrikingDetail": "The most interesting or surprising single fact from the article."
    },
    "theStory": "Your two-paragraph summary. First paragraph: main event and context. Second: background or implications."
  }
- If the provided "Article Content" is insufficient, unclear, not a news article, or if you cannot reasonably extract the required fields:
  Respond ONLY with this exact JSON object:
  {
    "error": "The provided content could not be processed to extract the required information or generate a news summary."
  }
ABSOLUTELY DO NOT provide 'quickFacts' or 'theStory' if you are returning an 'error'. Do NOT use external knowledge.
Your response MUST be one of these two JSON structures.
"""
```

## Response Structure

### Successful Summary
```json
{
  "quickFacts": {
    "whatHappened": "Apple announced new iPhone 16 with AI features",
    "who": "Apple Inc., Tim Cook",
    "whenWhere": "September 2024, Cupertino California",
    "keyNumbers": "$999 starting price, 48-hour battery life",
    "mostStrikingDetail": "First iPhone to run local LLM models"
  },
  "theStory": "Apple unveiled the iPhone 16 today, marking a significant shift in smartphone technology with the integration of on-device AI capabilities. The new device features a dedicated neural processing unit capable of running large language models locally, eliminating the need for cloud processing for many AI tasks.\n\nThe announcement represents Apple's aggressive push into artificial intelligence, directly competing with Google and Samsung's AI offerings. Industry analysts suggest this could reshape user expectations for privacy and performance in AI-powered mobile experiences."
}
```

### Error Response
```json
{
  "error": "The provided content could not be processed to extract the required information or generate a news summary."
}
```

## API Configuration

### Request Settings
```swift
GeminiGenerationConfig {
    temperature: 0.3,           // Lower for consistency
    topK: 40,
    topP: 0.95,
    maxOutputTokens: 1000,
    responseMimeType: "application/json"  // Forces JSON output
}
```

### Safety Settings
```swift
[
    GeminiSafetySetting(category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_MEDIUM_AND_ABOVE"),
    GeminiSafetySetting(category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_MEDIUM_AND_ABOVE"),
    GeminiSafetySetting(category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_MEDIUM_AND_ABOVE"),
    GeminiSafetySetting(category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_MEDIUM_AND_ABOVE")
]
```

## JSON Response Parsing

### Cleaning Logic
```swift
// 1. Remove markdown formatting if present
if jsonString.hasPrefix("```json") && jsonString.hasSuffix("```") {
    jsonString = jsonString
        .replacingOccurrences(of: "```json", with: "")
        .replacingOccurrences(of: "```", with: "")
}

// 2. Fix unescaped characters in JSON strings
var fixedJson = ""
var inString = false
var escaped = false

for char in jsonString {
    if char == "\"" && !escaped {
        inString = !inString
    } else if inString && !escaped {
        // Escape newlines, tabs, etc.
        if char == "\n" {
            fixedJson += "\\n"
            continue
        } else if char == "\r" {
            fixedJson += "\\r"
            continue
        } else if char == "\t" {
            fixedJson += "\\t"
            continue
        }
    }
    fixedJson += String(char)
    escaped = (char == "\\" && !escaped)
}
```

## Error Handling

### API Errors
- **403**: Invalid API key → Show settings prompt
- **429**: Rate limited → Retry with backoff
- **Content filtered**: Safety violation → Generic error message
- **Invalid response**: Parsing failed → Fallback message

### Fallback Summary
```swift
// When summarization fails
article.summary = """
Unable to generate summary at this time.
Title: \(article.title ?? "Unknown")
Source: \(article.subreddit ?? "Unknown")
"""
```

## Usage Tracking

### Token Estimation
```swift
struct GeminiUsage {
    let promptTokens: Int      // Rough: text.count / 4
    let completionTokens: Int   // Rough: response.count / 4
    let totalTokens: Int
    let estimatedCost: Double   // $0.35/1M input, $1.05/1M output
}
```

## Summary Length Options

### Constants.Summary.Length
```swift
enum Length {
    case brief      // 250 tokens
    case standard   // 500 tokens
    case detailed   // 1000 tokens
    
    var maxTokens: Int {
        switch self {
        case .brief: return 250
        case .standard: return 500
        case .detailed: return 1000
        }
    }
}
```

## Performance Considerations

### Optimizations
- **Parallel requests**: Multiple articles simultaneously
- **Caching**: Store summaries in Core Data
- **Token limits**: Prevent excessive API costs
- **Timeout**: 30 second timeout per request

### Known Issues
- JSON parsing can fail with complex content
- Some articles produce generic summaries
- Rate limiting during heavy usage
- No streaming support for real-time generation