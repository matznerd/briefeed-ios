# On-Device Content Extraction Cascade — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Firecrawl as the primary article content fetcher with a free, on-device WKWebView + Readability.js pipeline that bypasses anti-bot systems, then cascade to Jina Reader and Firecrawl as fallbacks.

**Architecture:** A new `ContentExtractorService` with a 4-tier cascade (self-post content → on-device WKWebView + Readability.js → Jina Reader API → Firecrawl API). It returns the existing `FirecrawlData` type so the downstream pipeline (Gemini summarization → TTS) is unchanged. A pre-warmed WKWebView pool eliminates cold-start latency.

**Tech Stack:** WebKit (WKWebView), [swift-readability](https://github.com/Ryu0118/swift-readability) SPM package, URLSession (for Jina Reader), existing FirecrawlService.

**Test URLs** (from real feed data — cover easy, medium, and hard sites):
- `https://www.reuters.com/...` — easy, clean HTML
- `https://www.theguardian.com/...` — easy, well-structured
- `https://www.theverge.com/...` — medium, JS-heavy
- `https://www.bloomberg.com/...` — hard, paywall + JWT
- `https://techxplore.com/...` — easy, science site
- `https://www.bbc.com/news/...` — easy, standard news

---

## Chunk 1: On-Device Content Extractor (Core Service + Tests)

### Task 1: Add swift-readability SPM dependency

**Files:**
- Modify: `Briefeed.xcodeproj/project.pbxproj` (via Xcode SPM or manual)

- [ ] **Step 1: Add the package via command line**

```bash
# From the Briefeed/ directory (where .xcodeproj lives)
# Open Xcode and add package: https://github.com/Ryu0118/swift-readability
# OR use swift package manager if Package.swift exists
# Since this project uses .xcodeproj, we add via xcodebuild:
```

Since this project uses `.xcodeproj` (not Package.swift), add the dependency in Xcode:
1. Open `Briefeed.xcodeproj`
2. Project → Package Dependencies → "+"
3. URL: `https://github.com/Ryu0118/swift-readability`
4. Version: Up to Next Major from latest
5. Add `Readability` library to the `Briefeed` target

- [ ] **Step 2: Verify build compiles with new dependency**

```bash
make -C Briefeed build
```

Expected: Build Succeeded

- [ ] **Step 3: Commit**

```bash
git add Briefeed.xcodeproj
git commit -m "deps: add swift-readability SPM package for on-device article extraction"
```

---

### Task 2: Create OnDeviceExtractor service with WKWebView pool

**Files:**
- Create: `Briefeed/Core/Services/Content/OnDeviceExtractor.swift`
- Test: `BriefeedTests/TDD/OnDeviceExtractorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// BriefeedTests/TDD/OnDeviceExtractorTests.swift
import XCTest
@testable import Briefeed

@MainActor
class OnDeviceExtractorTests: XCTestCase {

    func testExtract_ReturnsContentForValidURL() async throws {
        let extractor = OnDeviceExtractor()

        // Use a known-good, simple URL
        let result = try await extractor.extract(
            url: "https://www.reuters.com/world/middle-east/netanyahu-posts-video-response-iran-rumours-that-he-is-dead-2026-03-15/"
        )

        XCTAssertFalse(result.content.isEmpty, "Extracted content should not be empty")
        XCTAssertGreaterThan(result.content.count, 200, "Article content should be substantial")
        print("[Test] Extracted \(result.content.count) chars from Reuters")
    }

    func testExtract_TimesOutForUnreachableURL() async {
        let extractor = OnDeviceExtractor(timeout: 3.0)

        do {
            _ = try await extractor.extract(url: "https://httpstat.us/504?sleep=10000")
            XCTFail("Should have thrown a timeout error")
        } catch {
            // Expected: timeout or load failure
            print("[Test] Got expected error: \(error)")
        }
    }

    func testExtract_ReturnsTitleFromReadability() async throws {
        let extractor = OnDeviceExtractor()

        let result = try await extractor.extract(
            url: "https://techxplore.com/news/2026-03-ai-agents-autonomously-propaganda-campaigns.html"
        )

        XCTAssertNotNil(result.metadata?.title, "Should extract a title")
        print("[Test] Title: \(result.metadata?.title ?? "nil")")
    }
}
```

- [ ] **Step 2: Register test file with xcp**

```bash
xcp add-file Briefeed.xcodeproj \
  --file BriefeedTests/TDD/OnDeviceExtractorTests.swift \
  --targets BriefeedTests --create-groups
```

- [ ] **Step 3: Run test to verify it fails**

```bash
make -C Briefeed test-unit
```

Expected: FAIL — `OnDeviceExtractor` does not exist yet.

- [ ] **Step 4: Implement OnDeviceExtractor**

```swift
// Briefeed/Core/Services/Content/OnDeviceExtractor.swift
import Foundation
import Readability

/// Extracts article content on-device using WKWebView + Mozilla Readability.js.
/// WKWebView uses Safari's rendering engine — anti-bot systems see a real browser.
/// The Readability type from swift-readability is @MainActor and manages WKWebView internally.
@MainActor
final class OnDeviceExtractor {

    private let timeout: TimeInterval

    init(timeout: TimeInterval = 15.0) {
        self.timeout = timeout
    }

    /// Extract article content from a URL using on-device rendering.
    /// Returns a FirecrawlData-compatible result.
    func extract(url urlString: String) async throws -> FirecrawlData {
        guard let url = URL(string: urlString) else {
            throw ContentExtractionError.invalidURL
        }

        let readability = Readability()
        let startTime = CFAbsoluteTimeGetCurrent()
        let timeoutDuration = timeout  // capture for Sendable closure

        // Race the parse against a timeout. Both closures run @MainActor
        // because Readability requires it (it uses WKWebView internally).
        let result: ReadabilityResult = try await withThrowingTaskGroup(of: ReadabilityResult.self) { group in
            group.addTask { @MainActor in
                try await readability.parse(url: url)
            }
            group.addTask { @MainActor in
                try await Task.sleep(for: .seconds(timeoutDuration))
                throw ContentExtractionError.timeout
            }
            guard let first = try await group.next() else {
                throw ContentExtractionError.timeout
            }
            group.cancelAll()
            return first
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let charCount = result.textContent?.count ?? 0
        print("[OnDeviceExtractor] Extracted in \(String(format: "%.2f", elapsed))s: \(charCount) chars")

        // Convert to FirecrawlData for pipeline compatibility
        return FirecrawlData(
            content: result.textContent ?? "",
            markdown: result.content,  // Readability returns clean HTML
            html: result.content,
            metadata: FirecrawlMetadata(
                title: result.title,
                description: result.excerpt,
                language: result.language,
                ogTitle: result.title,
                ogDescription: result.excerpt,
                ogImage: nil,
                author: result.byline,
                publishedTime: result.publishedTime
            ),
            screenshot: nil
        )
    }
}

// MARK: - Errors

enum ContentExtractionError: LocalizedError {
    case invalidURL
    case timeout
    case extractionFailed(String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid article URL"
        case .timeout: return "On-device extraction timed out"
        case .extractionFailed(let msg): return "Extraction failed: \(msg)"
        case .noContent: return "No article content found on page"
        }
    }
}
```

> **Note:** The `Readability` and `ReadabilityResult` types come from the `swift-readability` package ([Ryu0118/swift-readability](https://github.com/Ryu0118/swift-readability)). `Readability` is `@MainActor` (it uses WKWebView internally). `ReadabilityResult` has properties: `title: String`, `content: String?` (clean HTML), `textContent: String?` (plain text), `excerpt: String`, `byline: String?`, `language: String?`, `publishedTime: String?`. If the API has changed, check the package README after adding the dependency.

- [ ] **Step 5: Register source file with xcp**

```bash
xcp add-file Briefeed.xcodeproj \
  --file Briefeed/Core/Services/Content/OnDeviceExtractor.swift \
  --targets Briefeed --create-groups
```

- [ ] **Step 6: Build and run tests**

```bash
make -C Briefeed build && make -C Briefeed test-unit
```

Expected: Build succeeds. The URL-based tests need network so they may pass or fail depending on simulator connectivity. The key validation is that the service compiles and the WKWebView + Readability pipeline executes.

- [ ] **Step 7: Commit**

```bash
git add Briefeed/Core/Services/Content/OnDeviceExtractor.swift \
       BriefeedTests/TDD/OnDeviceExtractorTests.swift \
       Briefeed.xcodeproj
git commit -m "feat: add OnDeviceExtractor using WKWebView + Readability.js"
```

---

### Task 3: Create JinaReaderService as Tier 2 fallback

**Files:**
- Create: `Briefeed/Core/Services/Content/JinaReaderService.swift`
- Test: `BriefeedTests/TDD/JinaReaderServiceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// BriefeedTests/TDD/JinaReaderServiceTests.swift
import XCTest
@testable import Briefeed

class JinaReaderServiceTests: XCTestCase {

    func testFetch_ReturnsMarkdownForValidURL() async throws {
        let service = JinaReaderService()
        let result = try await service.fetch(
            url: "https://www.reuters.com/world/middle-east/netanyahu-posts-video-response-iran-rumours-that-he-is-dead-2026-03-15/"
        )

        XCTAssertFalse(result.content.isEmpty)
        XCTAssertGreaterThan(result.content.count, 100)
        // Jina returns Markdown
        XCTAssertNotNil(result.markdown)
        print("[Test] Jina returned \(result.content.count) chars")
    }

    func testFetch_ThrowsForInvalidURL() async {
        let service = JinaReaderService()
        do {
            _ = try await service.fetch(url: "https://httpstat.us/404")
            XCTFail("Should throw for 404")
        } catch {
            print("[Test] Got expected error: \(error)")
        }
    }
}
```

- [ ] **Step 2: Register test file**

```bash
xcp add-file Briefeed.xcodeproj \
  --file BriefeedTests/TDD/JinaReaderServiceTests.swift \
  --targets BriefeedTests --create-groups
```

- [ ] **Step 3: Implement JinaReaderService**

```swift
// Briefeed/Core/Services/Content/JinaReaderService.swift
import Foundation

/// Fetches article content via Jina Reader API (r.jina.ai).
/// Prepend URL to get clean Markdown. Free tier: 10M tokens.
/// Cost: ~$0.0001/page. No API key needed for basic usage.
final class JinaReaderService {

    private let baseURL = "https://r.jina.ai/"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(url: String) async throws -> FirecrawlData {
        guard let targetURL = URL(string: baseURL + url) else {
            throw ContentExtractionError.invalidURL
        }

        var request = URLRequest(url: targetURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ContentExtractionError.extractionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw ContentExtractionError.extractionFailed("Jina returned HTTP \(httpResponse.statusCode)")
        }

        let content = String(data: data, encoding: .utf8) ?? ""

        guard !content.isEmpty else {
            throw ContentExtractionError.noContent
        }

        print("[JinaReader] Fetched \(content.count) chars from \(url)")

        // Jina returns Markdown by default
        return FirecrawlData(
            content: content,
            markdown: content,
            html: nil,
            metadata: nil,
            screenshot: nil
        )
    }
}
```

- [ ] **Step 4: Register source file and build**

```bash
xcp add-file Briefeed.xcodeproj \
  --file Briefeed/Core/Services/Content/JinaReaderService.swift \
  --targets Briefeed --create-groups
make -C Briefeed build
```

- [ ] **Step 5: Run tests**

```bash
make -C Briefeed test-unit
```

- [ ] **Step 6: Commit**

```bash
git add Briefeed/Core/Services/Content/JinaReaderService.swift \
       BriefeedTests/TDD/JinaReaderServiceTests.swift \
       Briefeed.xcodeproj
git commit -m "feat: add JinaReaderService as Tier 2 content fallback"
```

---

## Chunk 2: Content Extraction Cascade + Pipeline Integration

### Task 4: Create ContentExtractorService cascade

**Files:**
- Create: `Briefeed/Core/Services/Content/ContentExtractorService.swift`
- Test: `BriefeedTests/TDD/ContentExtractorServiceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// BriefeedTests/TDD/ContentExtractorServiceTests.swift
import XCTest
@testable import Briefeed

@MainActor
class ContentExtractorServiceTests: XCTestCase {

    func testCascade_UsesExistingContentFirst() async throws {
        let service = ContentExtractorService()

        // Tier 0: article already has content
        let result = try await service.extractContent(
            url: "https://example.com/article",
            existingContent: "This is pre-existing article content from a Reddit self-post."
        )

        XCTAssertEqual(result.content, "This is pre-existing article content from a Reddit self-post.")
        XCTAssertEqual(result.provider, "self-post")
    }

    func testCascade_FallsThroughTiers() async throws {
        let service = ContentExtractorService()

        // No existing content — should try on-device, then fallbacks
        let result = try await service.extractContent(
            url: "https://www.reuters.com/world/middle-east/netanyahu-posts-video-response-iran-rumours-that-he-is-dead-2026-03-15/",
            existingContent: nil
        )

        XCTAssertFalse(result.content.isEmpty)
        XCTAssertGreaterThan(result.content.count, 100)
        print("[Test] Provider: \(result.provider), Content: \(result.content.count) chars")
    }
}
```

- [ ] **Step 2: Register test file**

```bash
xcp add-file Briefeed.xcodeproj \
  --file BriefeedTests/TDD/ContentExtractorServiceTests.swift \
  --targets BriefeedTests --create-groups
```

- [ ] **Step 3: Implement ContentExtractorService**

```swift
// Briefeed/Core/Services/Content/ContentExtractorService.swift
import Foundation

/// Result of content extraction — wraps FirecrawlData + provider info.
struct ExtractionResult {
    let data: FirecrawlData
    let provider: String       // "self-post", "on-device", "jina", "firecrawl"
    let elapsedSeconds: Double

    var content: String { data.bestContent }
}

/// 4-tier content extraction cascade.
/// Tier 0: Existing content (Reddit self-posts)
/// Tier 1: On-device WKWebView + Readability.js (free, anti-bot proof)
/// Tier 2: Jina Reader API (cheap, ~$0.0001/page)
/// Tier 3: Firecrawl API (existing, uses credits)
@MainActor
final class ContentExtractorService {

    static let shared = ContentExtractorService()

    private let onDeviceExtractor = OnDeviceExtractor()
    private let jinaReader = JinaReaderService()

    func extractContent(url: String, existingContent: String?) async throws -> ExtractionResult {
        let start = CFAbsoluteTimeGetCurrent()

        // Tier 0: Use existing content if available (e.g. Reddit self-posts)
        if let existing = existingContent, !existing.isEmpty, existing.count > 50 {
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            print("[ContentExtractor] Tier 0: Using existing content (\(existing.count) chars)")
            return ExtractionResult(
                data: FirecrawlData(
                    content: existing, markdown: nil, html: nil,
                    metadata: nil, screenshot: nil
                ),
                provider: "self-post",
                elapsedSeconds: elapsed
            )
        }

        // Tier 1: On-device WKWebView + Readability.js
        do {
            print("[ContentExtractor] Tier 1: Trying on-device extraction...")
            let data = try await onDeviceExtractor.extract(url: url)
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            // Validate: did we get real content or an error page?
            if data.bestContent.count > 100 {
                print("[ContentExtractor] Tier 1 SUCCESS: \(data.bestContent.count) chars in \(String(format: "%.2f", elapsed))s")
                return ExtractionResult(data: data, provider: "on-device", elapsedSeconds: elapsed)
            } else {
                print("[ContentExtractor] Tier 1: Content too short (\(data.bestContent.count) chars), trying next tier")
            }
        } catch {
            print("[ContentExtractor] Tier 1 FAILED: \(error.localizedDescription)")
        }

        // Tier 2: Jina Reader API
        do {
            print("[ContentExtractor] Tier 2: Trying Jina Reader...")
            let data = try await jinaReader.fetch(url: url)
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            if data.bestContent.count > 100 {
                print("[ContentExtractor] Tier 2 SUCCESS: \(data.bestContent.count) chars in \(String(format: "%.2f", elapsed))s")
                return ExtractionResult(data: data, provider: "jina", elapsedSeconds: elapsed)
            } else {
                print("[ContentExtractor] Tier 2: Content too short, trying next tier")
            }
        } catch {
            print("[ContentExtractor] Tier 2 FAILED: \(error.localizedDescription)")
        }

        // Tier 3: Firecrawl (existing service)
        // Tier 3: Firecrawl (existing service, uses API credits)
        // FirecrawlService resolves its key from Constants.API.firecrawlAPIKey ?? UserDefaults
        do {
            print("[ContentExtractor] Tier 3: Trying Firecrawl...")
            let firecrawl = FirecrawlService()
            let data = try await firecrawl.fetchArticleContent(from: url)
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            print("[ContentExtractor] Tier 3 SUCCESS: \(data.bestContent.count) chars in \(String(format: "%.2f", elapsed))s")
            return ExtractionResult(data: data, provider: "firecrawl", elapsedSeconds: elapsed)
        } catch {
            print("[ContentExtractor] Tier 3 FAILED: \(error.localizedDescription)")
        }

        // All tiers failed
        throw ContentExtractionError.extractionFailed("All content extraction methods failed for: \(url)")
    }
}
```

- [ ] **Step 4: Register source file and build**

```bash
xcp add-file Briefeed.xcodeproj \
  --file Briefeed/Core/Services/Content/ContentExtractorService.swift \
  --targets Briefeed --create-groups
make -C Briefeed build
```

- [ ] **Step 5: Run tests**

```bash
make -C Briefeed test-unit
```

- [ ] **Step 6: Commit**

```bash
git add Briefeed/Core/Services/Content/ContentExtractorService.swift \
       BriefeedTests/TDD/ContentExtractorServiceTests.swift \
       Briefeed.xcodeproj
git commit -m "feat: add ContentExtractorService with 4-tier cascade"
```

---

### Task 5: Wire cascade into UnifiedAudioPlayer pipeline

**Files:**
- Modify: `Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift:832-861` (the entire content fetch if/else block)

- [ ] **Step 1: Replace the entire content fetch block with ContentExtractorService**

In `UnifiedAudioPlayer.swift`, find the content fetch block (approximately lines 832-861). This is the `if let content = article.content ... else if let url = article.url ...` block. Replace the **entire if/else** so the cascade handles both existing content (Tier 0) and URL fetching (Tiers 1-3):

**Replace this:**
```swift
                    var contentToSummarize = ""
                    if let content = article.content, !content.isEmpty {
                        contentToSummarize = content.stripHTML
                        print("[UnifiedPlayer] Using existing article content: \(contentToSummarize.count) characters")
                    } else if let url = article.url {
                        print("[UnifiedPlayer] No content stored, fetching from URL: \(url)")
                        let domain = URL(string: url)?.host ?? "article"
                        generationPhase = .fetchingContent(domain: domain)
                        let fetchStepIdx = pipelineTimer.startStep("content_fetch")
                        let firecrawlService = FirecrawlService()
                        do {
                            let firecrawlData = try await firecrawlService.fetchArticleContent(from: url)
                            contentToSummarize = firecrawlData.bestContent
                            print("[UnifiedPlayer] Fetched \(contentToSummarize.count) characters from article")
                            if contentToSummarize.count < 100 {
                                print("[UnifiedPlayer] WARNING: Fetched content is very short, might be incomplete")
                                print("[UnifiedPlayer] Short content: \(contentToSummarize)")
                            }
                        } catch {
                            print("[UnifiedPlayer] Failed to fetch article content: \(error)")
                            contentToSummarize = article.content ?? ""
                        }
                        pipelineTimer.endStep(fetchStepIdx)
                    }
```

**With this:**
```swift
                    var contentToSummarize = ""
                    let domain = URL(string: article.url ?? "")?.host ?? "article"
                    generationPhase = .fetchingContent(domain: domain)
                    let fetchStepIdx = pipelineTimer.startStep("content_fetch")
                    do {
                        let result = try await ContentExtractorService.shared.extractContent(
                            url: article.url ?? "",
                            existingContent: article.content
                        )
                        contentToSummarize = result.content.stripHTML
                        print("[UnifiedPlayer] Fetched \(contentToSummarize.count) chars via \(result.provider) in \(String(format: "%.2f", result.elapsedSeconds))s")
                        if contentToSummarize.count < 100 {
                            print("[UnifiedPlayer] WARNING: Content very short (\(result.provider))")
                        }
                    } catch {
                        print("[UnifiedPlayer] All content extraction failed: \(error)")
                        contentToSummarize = article.content?.stripHTML ?? ""
                    }
                    pipelineTimer.endStep(fetchStepIdx)
```

This consolidates all content sourcing (self-post, on-device, Jina, Firecrawl) into one call. Tier 0 now fires correctly for self-posts because `existingContent` is passed unconditionally.

- [ ] **Step 2: Build and run tests**

```bash
make -C Briefeed build && make -C Briefeed test-unit
```

Expected: Build succeeds, existing tests still pass.

- [ ] **Step 3: Commit**

```bash
git add Briefeed/Core/Services/Audio/UnifiedAudioPlayer.swift
git commit -m "feat: wire ContentExtractorService cascade into audio pipeline"
```

---

## Chunk 3: Demo / Proof-of-Concept Test View

### Task 6: Create a content extraction test view in Settings

**Files:**
- Create: `Briefeed/Features/Settings/ContentExtractionTestView.swift`
- Modify: `Briefeed/Features/Settings/SettingsView.swift` (add navigation link)

This view lets you pick a URL from queued articles (or type one in) and test all extraction tiers side-by-side with timing.

- [ ] **Step 1: Implement the test view**

```swift
// Briefeed/Features/Settings/ContentExtractionTestView.swift
import SwiftUI

struct ContentExtractionTestView: View {
    @State private var testURL = "https://www.reuters.com/world/middle-east/netanyahu-posts-video-response-iran-rumours-that-he-is-dead-2026-03-15/"
    @State private var results: [TierResult] = []
    @State private var isRunning = false

    // Sample URLs from real feed data for quick testing
    private let sampleURLs = [
        ("Reuters", "https://www.reuters.com/world/middle-east/netanyahu-posts-video-response-iran-rumours-that-he-is-dead-2026-03-15/"),
        ("The Verge", "https://www.theverge.com/ai-artificial-intelligence/892978/ai-chatbots-investigation-help-teens-plan-violence"),
        ("BBC", "https://www.bbc.com/news/articles/cqxdndz75zvo"),
        ("Guardian", "https://www.theguardian.com/us-news/2026/mar/14/fcc-broadcast-permits-iran-war-news"),
        ("TechXplore", "https://techxplore.com/news/2026-03-ai-agents-autonomously-propaganda-campaigns.html"),
        ("NPR", "https://www.npr.org/2026/03/14/nx-s1-5748020/pentagon-tightens-controls-over-stars-and-stripes-after-calling-it-woke"),
    ]

    var body: some View {
        List {
            Section("Test URL") {
                TextField("Article URL", text: $testURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(sampleURLs, id: \.0) { name, url in
                            Button(name) { testURL = url }
                                .buttonStyle(.bordered)
                                .font(.caption2)
                        }
                    }
                }

                Button {
                    Task { await runAllTiers() }
                } label: {
                    HStack {
                        if isRunning {
                            ProgressView()
                        }
                        Text(isRunning ? "Testing..." : "Test All Tiers")
                    }
                }
                .disabled(isRunning || testURL.isEmpty)
            }

            if !results.isEmpty {
                Section("Results") {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(result.success ? .green : .red)
                                Text("Tier \(result.tier): \(result.provider)")
                                    .font(.headline)
                                Spacer()
                                Text(String(format: "%.2fs", result.elapsed))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if result.success {
                                Text("\(result.contentLength) chars")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let title = result.title {
                                    Text(title)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Text(result.preview)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            } else {
                                Text(result.error ?? "Unknown error")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Content Extraction")
    }

    @MainActor
    private func runAllTiers() async {
        isRunning = true
        results = []

        // Tier 1: On-device
        await testTier(tier: 1, provider: "On-Device (WKWebView)") {
            let extractor = OnDeviceExtractor()
            return try await extractor.extract(url: testURL)
        }

        // Tier 2: Jina Reader
        await testTier(tier: 2, provider: "Jina Reader") {
            let jina = JinaReaderService()
            return try await jina.fetch(url: testURL)
        }

        // Tier 3: Firecrawl
        await testTier(tier: 3, provider: "Firecrawl") {
            let firecrawl = FirecrawlService()
            return try await firecrawl.fetchArticleContent(from: testURL)
        }

        isRunning = false
    }

    @MainActor
    private func testTier(tier: Int, provider: String, fetch: () async throws -> FirecrawlData) async {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let data = try await fetch()
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let content = data.bestContent
            results.append(TierResult(
                tier: tier, provider: provider, success: content.count > 50,
                contentLength: content.count, elapsed: elapsed,
                preview: String(content.prefix(300)),
                title: data.metadata?.title ?? data.metadata?.ogTitle,
                error: content.count <= 50 ? "Content too short (\(content.count) chars)" : nil
            ))
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            results.append(TierResult(
                tier: tier, provider: provider, success: false,
                contentLength: 0, elapsed: elapsed, preview: "",
                title: nil, error: error.localizedDescription
            ))
        }
    }
}

struct TierResult: Identifiable {
    let id = UUID()
    let tier: Int
    let provider: String
    let success: Bool
    let contentLength: Int
    let elapsed: Double
    let preview: String
    let title: String?
    let error: String?
}
```

- [ ] **Step 2: Register file with xcp**

```bash
xcp add-file Briefeed.xcodeproj \
  --file Briefeed/Features/Settings/ContentExtractionTestView.swift \
  --targets Briefeed --create-groups
```

- [ ] **Step 3: Add NavigationLink in SettingsView**

In `SettingsView.swift`, find the Diagnostics section and add a link to the new test view:

```swift
// In the Diagnostics section, add:
NavigationLink(destination: ContentExtractionTestView()) {
    Label("Content Extraction", systemImage: "globe")
}
```

- [ ] **Step 4: Build, run, and test in simulator**

```bash
make -C Briefeed build && make -C Briefeed run
```

Navigate to Settings → Diagnostics → Content Extraction. Tap "Test All Tiers" with a sample URL. Verify each tier shows timing and content length.

Take screenshots:
```bash
peekaboo capture --output screenshots/content_extraction_test.png
```

- [ ] **Step 5: Commit**

```bash
git add Briefeed/Features/Settings/ContentExtractionTestView.swift \
       Briefeed/Features/Settings/SettingsView.swift \
       Briefeed.xcodeproj
git commit -m "feat: add content extraction test view for comparing tiers"
```

---

## Summary

| Task | What | Outcome |
|------|------|---------|
| 1 | Add swift-readability SPM | Dependency available |
| 2 | OnDeviceExtractor service | WKWebView + Readability.js extraction |
| 3 | JinaReaderService | Cheap API fallback (~$0.0001/page) |
| 4 | ContentExtractorService | 4-tier cascade orchestrator |
| 5 | Wire into pipeline | Replace Firecrawl in UnifiedAudioPlayer |
| 6 | Demo test view | Side-by-side comparison in Settings |

**After proof-of-concept validation**, follow-up work:
- WKWebView pre-warming pool (create 2 instances at app launch)
- Metrics: track which tier succeeds per-domain for analytics
- Server-side scraping (Cloudflare Workers) for "scrape once, serve many"
- HTML-to-Markdown with Demark for cleaner summarization input
