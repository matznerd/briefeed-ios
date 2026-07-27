# Gemini API Reference (January 2025)

## Executive Summary

This document provides a comprehensive reference for the Google Gemini API as of January 2025, focusing on the 2.5 series models and their capabilities. It addresses critical implementation details discovered during development of the Briefeed iOS app.

## Critical Finding: Token Counting Issue

### The Problem
**Thinking tokens ARE counted against output token limits**, contrary to what documentation initially suggests. This is a confirmed behavior across all Gemini 2.5 models when thinking is enabled.

### Evidence
- When `maxOutputTokens` is set to 250, and the model uses ~249 tokens for thinking, only 1 token remains for actual output
- This causes "MAX_TOKENS" errors even for small summary requests
- The issue manifests as empty responses or API errors

### Solution
Increase `maxOutputTokens` significantly when using thinking models:
- Brief summaries: 500 tokens (was 100)
- Standard summaries: 1000 tokens (was 250)
- Detailed summaries: 2000 tokens (was 500)

## Gemini 2.5 Series Models

### Model Overview

| Model | Code | Best For | Token Limits |
|-------|------|----------|--------------|
| **2.5 Pro** | `gemini-2.5-pro` | Complex reasoning, coding, analysis | Input: 1M, Output: 65K |
| **2.5 Flash** | `gemini-2.5-flash` | Balanced performance, cost-effective | Input: 1M, Output: 65K |
| **2.5 Flash-Lite** | `gemini-2.5-flash-lite` | High throughput, cost efficiency | Input: 1M, Output: 65K |

### Thinking Capabilities

All 2.5 series models support "thinking" - an internal reasoning process that improves output quality but consumes tokens.

#### Thinking Budget Configuration

```swift
// Swift Example
config: types.GenerateContentConfig(
    thinking_config: types.ThinkingConfig(
        thinking_budget: 1024  // Allocate 1024 tokens for thinking
    )
)
```

| Model | Default | Range | Disable | Dynamic |
|-------|---------|-------|---------|---------|
| **2.5 Pro** | Dynamic | 128-32768 | N/A | -1 |
| **2.5 Flash** | Dynamic | 0-24576 | 0 | -1 |
| **2.5 Flash-Lite** | None | 512-24576 | 0 | -1 |

### Pricing (Paid Tier)

#### With Thinking Enabled
**Output price includes thinking tokens**

| Model | Input (per 1M) | Output + Thinking (per 1M) |
|-------|----------------|---------------------------|
| **2.5 Pro** | $1.25 (≤200k)<br>$2.50 (>200k) | $10.00 (≤200k)<br>$15.00 (>200k) |
| **2.5 Flash** | $0.30 text<br>$1.00 audio | $2.50 |
| **2.5 Flash-Lite** | $0.10 text<br>$0.30 audio | $0.40 |

## API Implementation Best Practices

### 1. Token Management

```json
{
  "generationConfig": {
    "maxOutputTokens": 1000,  // Must account for thinking
    "temperature": 0.7,
    "topK": 40,
    "topP": 0.95,
    "responseMimeType": "text/plain"
  },
  "thinkingConfig": {
    "thinkingBudget": 512  // Separate allocation for thinking
  }
}
```

### 2. Content Truncation Strategy

For large inputs that may exceed token limits:

```swift
let maxContentLength = 20000  // ~5000 tokens
if content.count > maxContentLength {
    // Truncate at sentence boundary
    let truncated = String(content.prefix(maxContentLength))
    if let lastPeriod = truncated.lastIndex(of: ".") {
        processedContent = String(truncated[...lastPeriod])
    } else {
        processedContent = truncated + "..."
    }
}
```

### 3. Error Handling

Common errors and solutions:

| Error | Cause | Solution |
|-------|-------|----------|
| `MAX_TOKENS` | Output tokens exhausted by thinking | Increase `maxOutputTokens` |
| `QUOTA_EXCEEDED` | API rate limit hit | Implement exponential backoff |
| `INVALID_ARGUMENT` | Prompt too long | Truncate input content |
| `CONTENT_FILTERED` | Safety filters triggered | Adjust safety settings |

### 4. Optimal Model Selection

- **Use 2.5 Flash** for most tasks - best price/performance ratio
- **Use 2.5 Pro** only for complex reasoning requiring maximum accuracy
- **Use 2.5 Flash-Lite** for high-volume, simple tasks
- **Disable thinking** (`thinkingBudget: 0`) for simple tasks to save tokens

## iOS/Swift Implementation

### Service Configuration

```swift
class GeminiService {
    private let model = "gemini-2.5-flash"  // Best for summaries
    
    func summarize(text: String, length: SummaryLength) async throws -> String {
        let request = GeminiRequest(
            contents: [/* ... */],
            generationConfig: GeminiGenerationConfig(
                temperature: 0.7,
                topK: 40,
                topP: 0.95,
                maxOutputTokens: length.maxTokens,  // Use increased values
                responseMimeType: "text/plain"
            )
        )
        // ...
    }
}
```

### Token Limits by Summary Type

```swift
enum SummaryLength {
    case brief
    case standard
    case detailed
    
    var maxTokens: Int {
        switch self {
        case .brief: return 500      // Increased from 100
        case .standard: return 1000   // Increased from 250
        case .detailed: return 2000   // Increased from 500
        }
    }
}
```

## Content Processing Pipeline

### For Article Summarization

1. **Fetch content** (if not cached)
2. **Truncate to 20,000 chars** (prevents token overflow)
3. **Generate summary** with appropriate token allocation
4. **Handle thinking tokens** in output budget
5. **Parse response** (may be JSON or plain text)
6. **Cache result** for future use

### Token Usage Monitoring

```swift
// Track actual usage
let promptTokens = prompt.count / 4  // Rough estimate
let completionTokens = response.text.count / 4
let thinkingTokens = response.usageMetadata?.thoughtsTokenCount ?? 0
let totalOutputTokens = completionTokens + thinkingTokens
```

## Known Issues and Workarounds

### Issue 1: Thinking Tokens Count Against Output
**Status:** Confirmed behavior, not a bug
**Workaround:** Always allocate extra output tokens when thinking is enabled

### Issue 2: JSON Response Parsing
**Problem:** Gemini sometimes adds markdown formatting to JSON
**Solution:** Strip markdown before parsing:
```swift
if jsonString.hasPrefix("```json") {
    jsonString = jsonString
        .replacingOccurrences(of: "```json", with: "")
        .replacingOccurrences(of: "```", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
```

### Issue 3: Empty Responses
**Cause:** Usually token exhaustion
**Solution:** Check token allocation and increase if needed

## Recommendations

1. **Default to Flash 2.5** for production use
2. **Set `maxOutputTokens` to at least 1000** for standard tasks
3. **Monitor token usage** via `usageMetadata` in responses
4. **Implement retry logic** with exponential backoff
5. **Cache responses** to minimize API calls
6. **Use dynamic thinking** (`-1`) for variable complexity tasks
7. **Test with various content lengths** to ensure robustness

## Migration Guide (From 1.5 to 2.5)

### Key Changes
- Thinking capability requires token budget management
- Output pricing includes thinking tokens
- Better multimodal support
- Improved reasoning capabilities

### Code Updates Required
1. Increase `maxOutputTokens` values
2. Add `thinkingConfig` for optimal performance
3. Update error handling for thinking-related issues
4. Adjust pricing calculations

## Conclusion

The Gemini 2.5 series offers powerful capabilities but requires careful token management, especially when thinking is enabled. The key insight is that thinking tokens consume output token budget, necessitating higher allocations than initially expected. With proper configuration, these models provide excellent performance for text summarization and reasoning tasks.

## References

- [Gemini API Models Documentation](https://ai.google.dev/gemini-api/docs/models)
- [Thinking Documentation](https://ai.google.dev/gemini-api/docs/thinking)
- [Pricing Guide](https://ai.google.dev/gemini-api/docs/pricing)
- [API Reference](https://ai.google.dev/api)

---
*Last Updated: January 2025*
*Validated through production usage in Briefeed iOS app*