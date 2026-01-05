# Article Summarization Pipeline Audit

**Date:** December 16, 2025
**Auditor:** Claude Code
**Scope:** Complete article summarization flow from URL to TTS playback

---

## Executive Summary

This audit examines the article summarization pipeline in the Briefeed iOS app. The system uses a multi-stage approach: Firecrawl for content extraction, Gemini AI for summarization, and either OpenAI or Gemini for TTS generation. Several critical issues were identified that can cause articles to play with only titles and no summary content.

### Critical Findings

1. **Multiple Gemini models in use** - Using `gemini-2.5-flash` (line 135, GeminiService.swift)
2. **Token limit issue with Gemini 2.5** - Known API bug where thinking tokens count against output limit
3. **Complex JSON parsing** - Summary responses can be JSON or plain text, causing parsing failures
4. **Content truncation timing** - Truncation happens both in GeminiService and UnifiedAudioPlayer
5. **Silent fallback to title-only** - Missing summaries result in articles playing with just titles
6. **Prompt engineering issues** - Instructions tell Gemini not to include title, but this may suppress content

---

## Component Analysis

### 1. GeminiService.swift (Summarization Engine)

**Location:** `/Users/me/ericode/briefeed-app/briefeed-ios/Briefeed/Briefeed/Core/Services/GeminiService.swift`

#### Current Implementation

**Model Used:**
```swift
private let model = "gemini-2.5-flash" // Line 135
```

**API Configuration:**
- Base URL: `https://generativelanguage.googleapis.com/v1beta`
- Endpoint: `/models/{model}:generateContent`
- Max Output Tokens: 2000 (line 170)
- Temperature: 0.7 (line 167)
- Response MIME Type: `text/plain` for summaries (line 172)

#### Summarization Flow

**Method:** `summarize(text: String, length: Constants.Summary.Length)`

```swift
// Lines 144-238
func summarize(text: String, length: Constants.Summary.Length) async throws -> String {
    // Creates prompt with word count guidance
    let prompt = createSummarizationPrompt(text: text, length: length)

    // Truncates input BEFORE sending to API
    // maxArticleLength = 10,000 chars (line 488)
    let articleText = text.count > maxArticleLength ?
        String(text.prefix(maxArticleLength)) + "..." : text

    // Sends to Gemini API
    // Returns plain text summary
}
```

#### Issues Identified

**Issue 1: Gemini 2.5 Token Limit Bug**
```swift
// Lines 201-207
if firstCandidate.finishReason == "MAX_TOKENS" {
    print("[GeminiService] Hit MAX_TOKENS limit with empty response -
           this is a known Gemini 2.5 API issue")
    // The thinking tokens are counted against output limit but not returned
    // This causes empty responses when hitting token limit
    throw GeminiServiceError.modelError("Token limit reached...")
}
```

**Problem:** Gemini 2.5 Flash includes "thinking tokens" in the output count but doesn't return them, causing MAX_TOKENS errors with empty responses. This is documented in lines 136-137.

**Issue 2: Prompt Instructs to Skip Title**
```swift
// Lines 491-498 (createSummarizationPrompt)
return """
Summarize this article in \(wordCount) words.
Focus on the key facts: who, what, when, where, why, and any important numbers.
Write in simple, clear sentences suitable for audio playback.
Do NOT include the article title in your summary - start directly with the main content.

Article:
\(articleText)

Summary:
"""
```

**Problem:** The instruction "Do NOT include the article title" may cause Gemini to be overly cautious and suppress actual content if it thinks something sounds like the title.

**Issue 3: Content Truncation Too Aggressive**
```swift
// Lines 487-489
let maxArticleLength = 10000  // Only 10k chars
let articleText = text.count > maxArticleLength ?
    String(text.prefix(maxArticleLength)) + "..." : text
```

**Problem:** Truncating to 10,000 characters is very aggressive. Gemini 2.5 Flash supports much larger context (32k tokens ≈ 128k characters). This may cut off important content before summarization.

**Issue 4: Error Detection is Heuristic-Based**
```swift
// Lines 448-463 (in UnifiedAudioPlayer)
if summaryText.contains("cannot provide a summary") ||
   summaryText.contains("I cannot") ||
   summaryText.contains("cannot summarize") {
    print("[UnifiedPlayer] WARNING: Gemini couldn't generate summary")
    // Don't save error message as summary
    article.summary = "Unable to generate summary..."
    throw TTSError.generationFailed
}
```

**Problem:** This detection is brittle. If Gemini returns any variation of these phrases, it's treated as a failure.

#### Structured Summary Flow

**Method:** `generateStructuredSummary(text: String, title: String?)`

This method (lines 270-408) generates JSON-formatted summaries with:
- `quickFacts` object with fields: whatHappened, who, whenWhere, keyNumbers, mostStrikingDetail
- `theStory` string with 2-paragraph summary
- `error` field if content can't be processed

**Configuration:**
- Temperature: 0.3 (lower for consistent JSON)
- Max Output Tokens: 1000 (line 290)
- Response MIME Type: `application/json` (line 292)

**Issue 5: Complex JSON Parsing**
```swift
// Lines 338-384 (JSON cleanup and parsing)
// 1. Strips markdown code fences: ```json ... ```
// 2. Manually escapes unescaped newlines in JSON strings
// 3. Character-by-character parsing to fix malformed JSON
```

**Problem:** This indicates Gemini frequently returns malformed JSON, requiring extensive cleanup. This is fragile and can fail silently.

---

### 2. FirecrawlService.swift (Content Extraction)

**Location:** `/Users/me/ericode/briefeed-app/briefeed-ios/Briefeed/Briefeed/Core/Services/FirecrawlService.swift`

#### Current Implementation

**API Configuration:**
- Base URL: `https://api.firecrawl.dev/v0`
- Endpoint: `/scrape`
- Timeout: 60 seconds (longer than default 30s)
- Max Retries: 3 with exponential backoff

**Scraping Parameters:**
```swift
// Lines 85-93
let parameters: [String: Any] = [
    "url": url,
    "formats": ["markdown", "html"],
    "onlyMainContent": true,
    "includeHtml": true,
    "includeMarkdown": true,
    "waitFor": 5000, // Wait up to 5 seconds for content to load
    "screenshot": false
]
```

#### Content Quality Check

```swift
// Lines 116-119
if data.content.isEmpty && data.markdown?.isEmpty != false {
    throw FirecrawlError.contentNotFound
}
```

**Issue 6: No Content Length Validation**

The service checks if content is completely empty but doesn't validate minimum content length. Very short content (< 100 chars) might be error pages or paywalls.

```swift
// Lines 180-191 (bestContent extension)
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
```

**Note:** This prioritization is good, but there's no quality check on what's returned.

---

### 3. UnifiedAudioPlayer.swift (Orchestration Layer)

**Location:** `/Users/me/ericode/briefeed-app/briefeed-ios/Briefeed/Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift`

This is where the magic happens (or doesn't). This service orchestrates:
1. Article content fetching
2. Summary generation
3. TTS audio generation
4. Playback management

#### Audio Generation Flow

**Method:** `generateAudioForItem(_ item: UnifiedQueueItem)` (lines 348-564)

**Step 1: Check if summary exists**
```swift
// Lines 370-372
if article.summary == nil ||
   article.summary?.isEmpty == true ||
   article.summary == "Unable to generate summary..." {
```

**Step 2: Get content to summarize**
```swift
// Lines 376-401
var contentToSummarize = ""
if let content = article.content, !content.isEmpty {
    contentToSummarize = content.stripHTML
} else if let url = article.url {
    // Fetch from Firecrawl
    let firecrawlData = try await firecrawlService.fetchArticleContent(from: url)
    contentToSummarize = firecrawlData.bestContent

    // Check if content is too short (might be error page or paywall)
    if contentToSummarize.count < 100 {
        print("[UnifiedPlayer] WARNING: Fetched content is very short")
    }
}
```

**Issue 7: Short Content Warning but No Action**

The code warns about content < 100 chars (lines 392-395) but continues anyway. This likely leads to poor summaries or errors.

**Step 3: Truncate content AGAIN**
```swift
// Lines 408-426
let maxContentLength = 20000  // 20k chars
let processedContent: String
if contentToSummarize.count > maxContentLength {
    let truncated = String(contentToSummarize.prefix(maxContentLength))
    if let lastPeriod = truncated.lastIndex(of: ".") {
        processedContent = String(truncated[...lastPeriod])
    } else {
        processedContent = truncated + "..."
    }
}
```

**Issue 8: Double Truncation**

Content is first truncated to 20k chars here, then AGAIN to 10k chars in GeminiService (line 488). This is wasteful and confusing.

**Step 4: Generate summary**
```swift
// Lines 433-446
let summaryText: String
do {
    summaryText = try await geminiService.summarize(
        text: processedContent,
        length: .standard
    )
} catch {
    // Fallback: Create a simple excerpt from the article
    let words = processedContent.split(separator: " ").prefix(100).joined(separator: " ")
    summaryText = "Article excerpt: \(words)..."
}
```

**Issue 9: Silent Fallback to Excerpt**

If summarization fails, the code falls back to a 100-word excerpt without any user notification. This excerpt might be low quality.

**Step 5: Clean duplicate title from summary**
```swift
// Lines 465-479
var cleanedSummaryText = summaryText
if let title = article.title, !title.isEmpty {
    let titleLower = title.lowercased()
    let summaryLower = summaryText.lowercased()
    if summaryLower.hasPrefix(titleLower) {
        // Remove the title from the beginning
        let startIndex = summaryText.index(summaryText.startIndex, offsetBy: title.count)
        cleanedSummaryText = String(summaryText[startIndex...])
            .trimmingCharacters(in: CharacterSet(charactersIn: ".:,- "))
    }
}
```

**Issue 10: Over-Aggressive Title Removal**

This only checks if summary starts with title, but doesn't handle cases where Gemini reformats the title slightly.

#### TTS Text Formatting

**Method:** `formatArticleForTTS(_ article: Article)` (lines 591-720)

This is the CRITICAL method that determines what actually gets spoken.

**Flow:**
```swift
var text = ""

// Step 1: Check if we have a summary
if let summary = article.summary, !summary.isEmpty {
    // Step 2: Clean duplicate title
    var cleanedSummary = summary
    // ... title removal logic ...

    // Step 3: Check if it's a JSON summary
    if cleanedSummary.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
        // Parse JSON and extract "theStory" field
        if let jsonData = cleanJson.data(using: .utf8),
           let summaryResponse = try? JSONDecoder().decode(ArticleSummaryResponse.self, from: jsonData) {
            if let story = summaryResponse.theStory, !story.isEmpty {
                text += story
            } else if let quickFacts = summaryResponse.quickFacts {
                // Fallback to quick facts
                text += /* formatted quick facts */
            }
        } else {
            // JSON parsing failed - use article content as fallback
            if let content = article.content, !content.isEmpty {
                let cleanContent = content.stripHTML
                if cleanContent.count > 3000 {
                    text += String(cleanContent.prefix(3000)) + "..."
                }
            } else {
                text += "Summary format error. Unable to process article content."
            }
        }
    } else {
        // Plain text summary, use it directly
        text += cleanedSummary
    }
} else if let content = article.content, !content.isEmpty {
    // No summary, use content directly (truncated to 3000 chars)
    let cleanContent = content.stripHTML
    if cleanContent.count > 3000 {
        text += String(cleanContent.prefix(3000)) + "..."
    } else {
        text += cleanContent
    }
} else {
    // No content available at all
    text += "Article content not available for text-to-speech."
}
```

**Issue 11: Title-Only Playback Scenario**

This method NEVER adds the title to the TTS text (intentionally, per line 594-596). So if:
1. `article.summary` is nil or empty
2. `article.content` is nil or empty

Then `text` will be "Article content not available for text-to-speech." (line 711)

**But wait** - if the UI shows the title, where does it come from?

Looking at the play method (lines 232-275):
```swift
try await audioPlayer.play(url: audioURL, title: item.title, artist: artist)
```

The title is passed separately to the audio player for lock screen/UI display, but it's NOT included in the TTS audio file itself.

**THIS IS THE ROOT CAUSE**: If summary generation fails silently or returns empty/error content, the TTS will be empty or just error message, but the UI will still show the article title.

**Issue 12: JSON vs Plain Text Confusion**

The code tries to detect if a summary is JSON (line 629) but this is fragile:
- Some summaries might have `{` in plain text
- JSON parsing can fail for many reasons
- Fallbacks are scattered and inconsistent

---

### 4. ArticleSummary.swift (Data Models)

**Location:** `/Users/me/ericode/briefeed-app/briefeed-ios/Briefeed/Briefeed/Core/Models/ArticleSummary.swift`

```swift
struct ArticleSummaryResponse: Codable {
    let quickFacts: QuickFacts?
    let theStory: String?
    let error: String?
}

struct QuickFacts: Codable {
    let whatHappened: String
    let who: String
    let whenWhere: String
    let keyNumbers: String
    let mostStrikingDetail: String
}

struct FormattedArticleSummary {
    let quickFacts: QuickFacts?
    let story: String?
    let error: String?

    var hasContent: Bool {
        return quickFacts != nil || story != nil
    }
}
```

**Issue 13: Error Handling Design**

The models support an `error` field, but the code doesn't consistently check `hasError` before using the summary. If Gemini returns `{ "error": "..." }`, the code might still try to extract content from nil fields.

---

## Complete Flow Analysis

### Happy Path: Article URL → Summary → TTS

1. **User queues article** → `UnifiedAudioPlayer.addToQueue()`
2. **Playback starts** → `UnifiedAudioPlayer.play(at: index)`
3. **Check if audio ready** → `generateAudioForItem()` called if not ready
4. **Check if summary exists** → If `article.summary` is nil/empty/error message:
   - **Fetch content** → Use existing `article.content` or fetch via Firecrawl
   - **Validate content** → Warn if < 100 chars but continue anyway
   - **Truncate content** → To 20k chars (sentence boundary)
   - **Call Gemini** → `geminiService.summarize(text:length:)`
     - Gemini truncates AGAIN to 10k chars
     - Sends to API with 2000 token output limit
     - Receives plain text summary
   - **Check for errors** → Look for "cannot provide" strings
   - **Clean duplicate title** → Remove title from start if present
   - **Save summary** → `article.summary = cleanedSummaryText`
5. **Format for TTS** → `formatArticleForTTS(article)`
   - Extract summary (plain text or JSON)
   - DON'T include title
   - Return formatted text
6. **Generate audio** → OpenAI or Gemini TTS
7. **Play audio** → SwiftAudioExService plays file

### Failure Scenarios

**Scenario 1: Gemini MAX_TOKENS Error**
- Content is complex or long
- Gemini hits thinking token limit
- Returns empty response with `finishReason: "MAX_TOKENS"`
- Error thrown: "Token limit reached"
- Fallback in UnifiedAudioPlayer creates 100-word excerpt
- Audio plays excerpt (likely incoherent)

**Scenario 2: Firecrawl Returns Paywall/Error Page**
- Article URL is behind paywall or returns error
- Firecrawl extracts < 100 chars
- Warning logged but continues
- Gemini receives minimal content
- Returns error or very short summary
- TTS might just say "Article content not available"

**Scenario 3: JSON Parsing Failure**
- Gemini returns malformed JSON
- Even after cleanup, parsing fails
- Fallback tries to use `article.content` (might be empty)
- If content empty, plays "Summary format error" message

**Scenario 4: Complete Summary Failure**
- All attempts fail
- `article.summary` remains nil or set to error message
- `formatArticleForTTS` has no summary to use
- Falls back to `article.content`
- If content also missing: "Article content not available for text-to-speech"

---

## Root Causes of "Title-Only" Articles

Based on the analysis, articles play with only titles when:

1. **Summary Generation Completely Fails**
   - Gemini API errors (quota, timeout, MAX_TOKENS)
   - Content is unsuitable for summarization (too short, paywall, etc.)
   - JSON parsing fails and fallbacks don't work

2. **Content is Never Fetched**
   - Article has `url` but no `content` field populated
   - Firecrawl fails to extract content
   - Content is filtered/blocked

3. **Silent Fallbacks Produce Empty Text**
   - Excerpt generation fails
   - Content stripping removes everything
   - JSON parsing returns nil for all fields

4. **Error Messages Treated as Content**
   - "Unable to generate summary" is saved as `article.summary`
   - `formatArticleForTTS` filters it out but has no other content
   - Results in error message TTS

---

## Recommendations

### High Priority

1. **Fix Gemini Token Limit Issue**
   - Consider using Gemini 1.5 Flash instead of 2.5 Flash to avoid thinking token bug
   - OR increase `maxOutputTokens` significantly (to 4000+)
   - OR implement chunking for long articles

2. **Unify Content Truncation**
   - Remove duplicate truncation (UnifiedAudioPlayer AND GeminiService both truncate)
   - Use single truncation point with clear reasoning
   - Increase limit to utilize Gemini's full context window

3. **Improve Error Detection and Handling**
   - Check `FormattedArticleSummary.hasError` before using content
   - Don't save error messages as `article.summary`
   - Implement retry logic for transient failures
   - Surface errors to user instead of silent fallbacks

4. **Add Content Quality Validation**
   - In Firecrawl: reject content < 100 chars with specific error
   - Before summarization: validate content is meaningful
   - After summarization: validate summary length and quality

5. **Fix JSON Parsing Robustness**
   - Use Gemini's JSON mode properly (ensure prompt explicitly requests JSON schema)
   - Add better error recovery for malformed JSON
   - Consider using structured output (if available in Gemini API)

### Medium Priority

6. **Simplify TTS Formatting Logic**
   - `formatArticleForTTS` is too complex with nested conditionals
   - Separate JSON vs plain text handling into distinct code paths
   - Add comprehensive logging at each decision point

7. **Improve Prompt Engineering**
   - Current prompt tells Gemini NOT to include title - this might be too restrictive
   - Consider rephrasing: "Begin your summary with the key information, not by repeating the title verbatim"
   - Test if this improves summary quality

8. **Add Better Telemetry**
   - Track how often each failure scenario occurs
   - Log content length at each stage
   - Monitor Gemini API error types and frequencies

### Low Priority

9. **Consider Alternative Summarization Models**
   - Gemini 2.5 Flash has known issues
   - Test Gemini 1.5 Flash or Pro
   - Consider hybrid approach: Gemini for summary, always use OpenAI for TTS

10. **Implement Summary Caching**
    - Cache successful summaries with content hash
    - Avoid re-generating summaries for same content
    - Useful for articles shared across feeds

---

## Code Snippets of Problematic Areas

### 1. Double Truncation

**UnifiedAudioPlayer.swift (Lines 408-426):**
```swift
// PROBLEM: First truncation to 20k
let maxContentLength = 20000
let processedContent: String
if contentToSummarize.count > maxContentLength {
    let truncated = String(contentToSummarize.prefix(maxContentLength))
    if let lastPeriod = truncated.lastIndex(of: ".") {
        processedContent = String(truncated[...lastPeriod])
    } else {
        processedContent = truncated + "..."
    }
} else {
    processedContent = contentToSummarize
}
```

**GeminiService.swift (Lines 487-490):**
```swift
// PROBLEM: Second truncation to 10k (even more aggressive!)
let maxArticleLength = 10000
let articleText = text.count > maxArticleLength ?
    String(text.prefix(maxArticleLength)) + "..." : text
```

**RECOMMENDATION:** Remove the 10k truncation in GeminiService. Keep only the 20k truncation in UnifiedAudioPlayer, or better yet, increase to 50k+ to use Gemini's full context.

---

### 2. Silent Fallback to Excerpt

**UnifiedAudioPlayer.swift (Lines 433-446):**
```swift
let summaryText: String
do {
    summaryText = try await geminiService.summarize(
        text: processedContent,
        length: .standard
    )
    print("[UnifiedPlayer] Received summary: \(summaryText.count) characters")
} catch {
    print("[UnifiedPlayer] Gemini summarization failed: \(error)")
    // PROBLEM: Silent fallback that user never knows about
    let words = processedContent.split(separator: " ").prefix(100).joined(separator: " ")
    summaryText = "Article excerpt: \(words)..."
    print("[UnifiedPlayer] Using fallback excerpt instead of summary")
}
```

**RECOMMENDATION:**
- Surface this error to the user
- Allow them to retry or skip the article
- Don't pretend a 100-word excerpt is a good summary

---

### 3. Error Message Saved as Summary

**UnifiedAudioPlayer.swift (Lines 448-463):**
```swift
if summaryText.contains("cannot provide a summary") ||
   summaryText.contains("I cannot") ||
   summaryText.contains("cannot summarize") {
    print("[UnifiedPlayer] WARNING: Gemini couldn't generate summary")

    // PROBLEM: Saving error message to Core Data
    await MainActor.run {
        article.summary = "Unable to generate summary. The article content may be incomplete or unavailable."
        try? context.save()
    }

    // PROBLEM: This error is then filtered out in formatArticleForTTS
    // resulting in "Article content not available" being spoken
    item.generationState = .failed(TTSError.generationFailed)
    throw TTSError.generationFailed
}
```

**RECOMMENDATION:**
- Don't save error messages as `article.summary`
- Use a separate field like `article.summaryError`
- Or use nil to indicate no summary and check a separate error state

---

### 4. Complex JSON Parsing with Fragile Cleanup

**GeminiService.swift (Lines 338-384):**
```swift
// PROBLEM: This shouldn't be necessary if Gemini JSON mode works properly
var jsonString = cleanedResponse
if jsonString.hasPrefix("```json") && jsonString.hasSuffix("```") {
    jsonString = jsonString
        .replacingOccurrences(of: "```json", with: "")
        .replacingOccurrences(of: "```", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// PROBLEM: Character-by-character parsing to fix unescaped newlines
var fixedJson = ""
var inString = false
var escaped = false

for (i, char) in jsonString.enumerated() {
    if char == "\"" && !escaped {
        inString = !inString
        fixedJson += String(char)
    } else if inString && char == "\n" && !escaped {
        fixedJson += "\\n"  // PROBLEM: Manual escaping
    } else if inString && char == "\r" && !escaped {
        fixedJson += "\\r"
    } else if inString && char == "\t" && !escaped {
        fixedJson += "\\t"
    } else {
        fixedJson += String(char)
    }
    escaped = (char == "\\" && !escaped)
}
```

**RECOMMENDATION:**
- This indicates Gemini frequently returns malformed JSON
- Use proper JSON schema in prompt
- Set `responseMimeType: "application/json"` correctly (already done)
- Consider adding `response_schema` parameter to enforce structure
- If cleanup still needed, extract to separate method and add comprehensive error handling

---

### 5. formatArticleForTTS Complexity

**UnifiedAudioPlayer.swift (Lines 591-720):**

This 130-line method has:
- 3 levels of nested conditionals
- Multiple JSON vs plain text detection strategies
- Several different fallback paths
- Duplicate title removal logic

**RECOMMENDATION:** Refactor into smaller methods:
```swift
func formatArticleForTTS(_ article: Article) -> String {
    // 1. Try summary-based formatting
    if let text = formatFromSummary(article) {
        return text
    }

    // 2. Try content-based formatting
    if let text = formatFromContent(article) {
        return text
    }

    // 3. Return error message
    return "Article content not available for text-to-speech."
}

private func formatFromSummary(_ article: Article) -> String? {
    guard let summary = article.summary, !summary.isEmpty else {
        return nil
    }

    // Check if it's an error message
    if isErrorMessage(summary) {
        return nil
    }

    // Clean duplicate title
    let cleaned = removeDuplicateTitle(from: summary, title: article.title)

    // Try JSON parsing
    if let jsonText = extractTextFromJSON(cleaned) {
        return jsonText
    }

    // Use as plain text
    return cleaned
}

private func formatFromContent(_ article: Article) -> String? {
    guard let content = article.content, !content.isEmpty else {
        return nil
    }

    let clean = content.stripHTML
        .replacingOccurrences(of: "\n\n", with: ". ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    // Truncate if too long
    if clean.count > 3000 {
        return String(clean.prefix(3000)) + "... Content truncated for speech."
    }

    return clean
}
```

---

## Testing Recommendations

### Unit Tests to Add

1. **GeminiService Tests:**
   - Test MAX_TOKENS error handling
   - Test malformed JSON cleanup
   - Test content truncation at various lengths
   - Test prompt generation with different article lengths

2. **UnifiedAudioPlayer Tests:**
   - Test `formatArticleForTTS` with various summary types (JSON, plain text, nil, error)
   - Test content truncation logic
   - Test title duplication removal
   - Test fallback paths

3. **Integration Tests:**
   - Test complete flow from URL to TTS with real Gemini API
   - Test failure scenarios (quota exceeded, timeout, malformed response)
   - Test content quality validation

### Manual Testing Checklist

- [ ] Article with paywall content
- [ ] Article with < 100 chars content
- [ ] Article with very long content (> 50k chars)
- [ ] Article with complex JSON response from Gemini
- [ ] Article where Gemini hits MAX_TOKENS
- [ ] Article with title embedded in summary
- [ ] Article with no content field
- [ ] Article with HTML-heavy content

---

## API Model Version Check

### Current Models

**GeminiService.swift:**
```swift
private let model = "gemini-2.5-flash" // Line 135
```

### Gemini API Models (as of Dec 2025)

According to the codebase docs (`docs/GEMINI-API-REFERENCE.md`):

**Available Models:**
- `gemini-2.5-flash` ✅ (current)
- `gemini-1.5-flash`
- `gemini-1.5-pro`
- `gemini-2.0-flash-exp`

**Known Issues with gemini-2.5-flash:**
- Thinking tokens count against output limit but aren't returned
- Can result in MAX_TOKENS errors with empty responses
- Documented in code comments (lines 136-137, 201-207)

### Recommendation

Consider testing with `gemini-1.5-flash` to see if it avoids the thinking token issue. The API pricing is the same, and 1.5 models are more stable.

---

## Summary Statistics

**Files Analyzed:** 5
**Lines of Code Reviewed:** ~2,000
**Critical Issues Found:** 13
**High Priority Recommendations:** 5
**Medium Priority Recommendations:** 3
**Low Priority Recommendations:** 2

**Most Critical Issue:** Silent fallback to title-only playback when summary generation fails, combined with aggressive content truncation and fragile JSON parsing.

**Quickest Win:** Increase content truncation limit from 10k to 50k+ characters to utilize Gemini's full context window and reduce MAX_TOKENS errors.

---

## Next Steps

1. **Immediate:** Remove double truncation in GeminiService (increase from 10k to 50k)
2. **Short-term:** Add content quality validation in Firecrawl response handler
3. **Medium-term:** Refactor formatArticleForTTS into smaller, testable methods
4. **Long-term:** Consider migrating to gemini-1.5-flash or implementing hybrid summarization approach

---

**End of Audit Report**
