//
//  GeminiService.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import Foundation

// MARK: - Gemini Models
struct GeminiRequest: Codable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig?
    let safetySettings: [GeminiSafetySetting]?
}

struct GeminiContent: Codable {
    let parts: [GeminiPart]?  // Made optional as response might not always have parts
    let role: String? // "user" or "model"
    let text: String? // Some responses might have direct text instead of parts
}

struct GeminiPart: Codable {
    let text: String
}

struct GeminiGenerationConfig: Codable {
    let temperature: Double?
    let topK: Int?
    let topP: Double?
    let maxOutputTokens: Int?
    let stopSequences: [String]?
    let responseMimeType: String?
}

struct GeminiSafetySetting: Codable {
    let category: String
    let threshold: String
}

struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]?
    let promptFeedback: GeminiPromptFeedback?
    let error: GeminiError?
}

struct GeminiCandidate: Codable {
    let content: GeminiContent
    let finishReason: String?
    let index: Int?
    let safetyRatings: [GeminiSafetyRating]?
}

struct GeminiSafetyRating: Codable {
    let category: String
    let probability: String
}

struct GeminiPromptFeedback: Codable {
    let safetyRatings: [GeminiSafetyRating]?
}

struct GeminiError: Codable {
    let code: Int
    let message: String
    let status: String?
}

// MARK: - Gemini Stream Models
struct GeminiStreamResponse: Codable {
    let candidates: [GeminiCandidate]?
    let error: GeminiError?
}

// MARK: - Gemini Error Types
enum GeminiServiceError: LocalizedError {
    case invalidAPIKey
    case contentFiltered
    case quotaExceeded
    case modelError(String)
    case streamingError
    case invalidResponse
    case timeout
    case serverError(Int) // 5xx errors

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid Gemini API key"
        case .contentFiltered:
            return "Content was filtered due to safety settings"
        case .quotaExceeded:
            return "API quota exceeded. Please try again later"
        case .modelError(let message):
            return "Model error: \(message)"
        case .streamingError:
            return "Error during streaming response"
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .timeout:
            return "Request timed out"
        case .serverError(let code):
            return "Server error (\(code))"
        }
    }

    /// Whether this error is transient and worth retrying
    var isRetryable: Bool {
        switch self {
        case .quotaExceeded, .timeout, .serverError:
            return true
        case .invalidAPIKey, .contentFiltered, .modelError, .streamingError, .invalidResponse:
            return false
        }
    }
}

// MARK: - Usage Tracking
struct GeminiUsage {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let estimatedCost: Double
    
    // Rough cost estimation based on Gemini pricing
    init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = promptTokens + completionTokens
        
        // Gemini 1.5 Flash pricing (as of 2024)
        // $0.35 per 1M input tokens, $1.05 per 1M output tokens
        let inputCost = Double(promptTokens) / 1_000_000 * 0.35
        let outputCost = Double(completionTokens) / 1_000_000 * 1.05
        self.estimatedCost = inputCost + outputCost
    }
}

// MARK: - Retry Configuration
struct RetryConfig {
    let maxAttempts: Int
    let baseDelayMs: Int
    let maxDelayMs: Int

    static let `default` = RetryConfig(maxAttempts: 3, baseDelayMs: 1000, maxDelayMs: 10000)

    /// Calculate delay for attempt (0-indexed), using exponential backoff with jitter
    func delay(for attempt: Int) -> UInt64 {
        let exponentialDelay = baseDelayMs * (1 << attempt) // 1s, 2s, 4s...
        let cappedDelay = min(exponentialDelay, maxDelayMs)
        // Add jitter: ±25%
        let jitter = Int.random(in: -cappedDelay/4...cappedDelay/4)
        let finalDelay = max(0, cappedDelay + jitter)
        return UInt64(finalDelay) * 1_000_000 // Convert to nanoseconds
    }
}

// MARK: - Gemini Service Protocol
protocol GeminiServiceProtocol {
    func summarize(text: String, length: Constants.Summary.Length) async throws -> String
    func summarizeWithRetry(text: String, length: Constants.Summary.Length, config: RetryConfig) async throws -> String
    func summarizeWithStream(text: String, length: Constants.Summary.Length, onChunk: @escaping (String) -> Void) async throws
    func getUsageStats() -> GeminiUsage?
    func generateStructuredSummary(text: String, title: String?) async throws -> FormattedArticleSummary
}

// MARK: - Gemini Service Implementation
class GeminiService: GeminiServiceProtocol {
    private let networkService: NetworkServiceProtocol
    private let apiKey: String
    private let model = "gemini-2.5-flash" // Use Gemini 2.5 Flash for summarization
    // Note: Thinking tokens count against output limit - see docs/GEMINI-API-REFERENCE.md
    private var currentUsage: GeminiUsage?
    
    init(networkService: NetworkServiceProtocol = NetworkService.shared, apiKey: String? = nil) {
        self.networkService = networkService
        self.apiKey = apiKey ?? Constants.API.geminiAPIKey ?? ""
    }
    
    func summarize(text: String, length: Constants.Summary.Length) async throws -> String {
        guard !apiKey.isEmpty else {
            print("[GeminiService] ERROR: No API key configured")
            throw GeminiServiceError.invalidAPIKey
        }
        
        print("[GeminiService] Starting summarization with model: \(model)")
        print("[GeminiService] Input text length: \(text.count) characters")
        
        let prompt = createSummarizationPrompt(text: text, length: length)
        let endpoint = "\(Constants.API.geminiBaseURL)/models/\(model):generateContent?key=\(apiKey)"
        
        print("[GeminiService] Using endpoint: \(endpoint.replacingOccurrences(of: apiKey, with: "***"))")
        
        let request = GeminiRequest(
            contents: [
                GeminiContent(
                    parts: [GeminiPart(text: prompt)],
                    role: "user",
                    text: nil
                )
            ],
            generationConfig: GeminiGenerationConfig(
                temperature: 0.7,
                topK: 40,
                topP: 0.95,
                maxOutputTokens: 4096,  // Increased per PRD v2.1 (4000+)
                stopSequences: nil,
                responseMimeType: "text/plain"  // Use plain text for summary generation
            ),
            safetySettings: [
                GeminiSafetySetting(category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_MEDIUM_AND_ABOVE"),
                GeminiSafetySetting(category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_MEDIUM_AND_ABOVE"),
                GeminiSafetySetting(category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_MEDIUM_AND_ABOVE"),
                GeminiSafetySetting(category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_MEDIUM_AND_ABOVE")
            ]
        )
        
        do {
            let response: GeminiResponse = try await networkService.request(
                endpoint,
                method: .post,
                parameters: try JSONEncoder().jsonObject(from: request),
                headers: ["Content-Type": "application/json"],
                timeout: nil
            )
            
            if let error = response.error {
                throw handleGeminiError(error)
            }
            
            guard let candidates = response.candidates,
                  !candidates.isEmpty,
                  let firstCandidate = candidates.first else {
                throw GeminiServiceError.invalidResponse
            }
            
            // Check if we hit MAX_TOKENS with empty response (known Gemini 2.5 issue)
            if firstCandidate.finishReason == "MAX_TOKENS" {
                print("[GeminiService] Hit MAX_TOKENS limit with empty response - this is a known Gemini 2.5 API issue")
                // The thinking tokens are counted against output limit but not returned
                // This causes empty responses when hitting token limit
                throw GeminiServiceError.modelError("Token limit reached. The article may be too complex or long for summarization.")
            }
            
            // Try to get text from parts first, then direct text field
            let text: String
            if let parts = firstCandidate.content.parts,
               !parts.isEmpty,
               let partText = parts.first?.text {
                text = partText
            } else if let directText = firstCandidate.content.text {
                text = directText
            } else {
                print("[GeminiService] No text found in response candidate")
                print("[GeminiService] Finish reason: \(firstCandidate.finishReason ?? "unknown")")
                throw GeminiServiceError.invalidResponse
            }
            
            // Update usage tracking (rough estimation)
            let promptTokens = prompt.count / 4 // Rough token estimation
            let completionTokens = text.count / 4
            currentUsage = GeminiUsage(promptTokens: promptTokens, completionTokens: completionTokens)
            
            print("[GeminiService] Successfully generated summary: \(text.count) characters")
            print("[GeminiService] Summary preview: \(text.prefix(500))...")
            
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            if let networkError = error as? NetworkError {
                throw handleNetworkError(networkError)
            }
            throw error
        }
    }

    func summarizeWithRetry(text: String, length: Constants.Summary.Length, config: RetryConfig = .default) async throws -> String {
        var lastError: Error?

        for attempt in 0..<config.maxAttempts {
            do {
                return try await summarize(text: text, length: length)
            } catch let error as GeminiServiceError {
                lastError = error
                print("[GeminiService] Attempt \(attempt + 1)/\(config.maxAttempts) failed: \(error.localizedDescription)")

                if !error.isRetryable {
                    print("[GeminiService] Error is not retryable, failing immediately")
                    throw error
                }

                if attempt < config.maxAttempts - 1 {
                    let delay = config.delay(for: attempt)
                    print("[GeminiService] Retrying in \(delay / 1_000_000)ms...")
                    try await Task.sleep(nanoseconds: delay)
                }
            } catch {
                // Non-GeminiServiceError - check if it's a network timeout or server error
                lastError = error
                print("[GeminiService] Attempt \(attempt + 1)/\(config.maxAttempts) failed with unexpected error: \(error)")

                let isRetryable = isRetryableError(error)
                if !isRetryable {
                    throw error
                }

                if attempt < config.maxAttempts - 1 {
                    let delay = config.delay(for: attempt)
                    print("[GeminiService] Retrying in \(delay / 1_000_000)ms...")
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }

        throw lastError ?? GeminiServiceError.invalidResponse
    }

    /// Check if a generic error is retryable (timeout, network issues)
    private func isRetryableError(_ error: Error) -> Bool {
        let nsError = error as NSError
        // URLError codes for timeout and network issues
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
                return true
            default:
                return false
            }
        }
        return false
    }

    func summarizeWithStream(text: String, length: Constants.Summary.Length, onChunk: @escaping (String) -> Void) async throws {
        guard !apiKey.isEmpty else {
            throw GeminiServiceError.invalidAPIKey
        }
        
        // Note: This is a simplified version. In production, you'd want to implement
        // proper SSE (Server-Sent Events) streaming using URLSession's data task
        // with delegate methods for streaming support.
        
        // For now, we'll use the regular summarize method
        let summary = try await summarize(text: text, length: length)
        
        // Simulate streaming by chunking the response
        let chunkSize = 20
        for i in stride(from: 0, to: summary.count, by: chunkSize) {
            let startIndex = summary.index(summary.startIndex, offsetBy: i)
            let endIndex = summary.index(startIndex, offsetBy: min(chunkSize, summary.count - i))
            let chunk = String(summary[startIndex..<endIndex])
            onChunk(chunk)
            
            // Small delay to simulate streaming
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }
    
    func getUsageStats() -> GeminiUsage? {
        return currentUsage
    }
    
    func generateStructuredSummary(text: String, title: String?) async throws -> FormattedArticleSummary {
        guard !apiKey.isEmpty else {
            throw GeminiServiceError.invalidAPIKey
        }
        
        let prompt = createStructuredSummaryPrompt(text: text, title: title)
        let endpoint = "\(Constants.API.geminiBaseURL)/models/\(model):generateContent?key=\(apiKey)"
        
        let request = GeminiRequest(
            contents: [
                GeminiContent(
                    parts: [GeminiPart(text: prompt)],
                    role: "user",
                    text: nil
                )
            ],
            generationConfig: GeminiGenerationConfig(
                temperature: 0.3, // Lower temperature for more consistent JSON
                topK: 40,
                topP: 0.95,
                maxOutputTokens: 4096,  // Increased per PRD v2.1 (4000+)
                stopSequences: nil,
                responseMimeType: "application/json"
            ),
            safetySettings: [
                GeminiSafetySetting(category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_MEDIUM_AND_ABOVE"),
                GeminiSafetySetting(category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_MEDIUM_AND_ABOVE"),
                GeminiSafetySetting(category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_MEDIUM_AND_ABOVE"),
                GeminiSafetySetting(category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_MEDIUM_AND_ABOVE")
            ]
        )
        
        var responseText = ""
        
        do {
            let response: GeminiResponse = try await networkService.request(
                endpoint,
                method: .post,
                parameters: try JSONEncoder().jsonObject(from: request),
                headers: ["Content-Type": "application/json"],
                timeout: nil
            )
            
            if let error = response.error {
                throw handleGeminiError(error)
            }
            
            guard let candidates = response.candidates,
                  !candidates.isEmpty,
                  let firstCandidate = candidates.first else {
                throw GeminiServiceError.invalidResponse
            }
            
            // Try to get text from parts first, then direct text field
            let text: String
            if let parts = firstCandidate.content.parts,
               !parts.isEmpty,
               let partText = parts.first?.text {
                text = partText
            } else if let directText = firstCandidate.content.text {
                text = directText
            } else {
                print("[GeminiService] No text found in response candidate")
                throw GeminiServiceError.invalidResponse
            }
            
            responseText = text
            
            // Parse JSON response with robust extraction
            let cleanedResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)

            print("📝 Gemini raw response: \(cleanedResponse)")

            // Extract JSON using robust helper
            let jsonString = extractJSON(from: cleanedResponse)

            guard let data = jsonString.data(using: .utf8) else {
                print("❌ Failed to convert to data: \(jsonString)")
                throw GeminiServiceError.invalidResponse
            }

            let summaryResponse: ArticleSummaryResponse
            do {
                summaryResponse = try JSONDecoder().decode(ArticleSummaryResponse.self, from: data)
            } catch {
                print("❌ JSON decode failed, attempting lenient parse: \(error)")
                // Try lenient parsing - extract what we can
                if let lenientResponse = tryLenientParse(jsonString: jsonString) {
                    summaryResponse = lenientResponse
                } else {
                    throw GeminiServiceError.invalidResponse
                }
            }
            
            // Update usage tracking
            let promptTokens = prompt.count / 4
            let completionTokens = responseText.count / 4
            currentUsage = GeminiUsage(promptTokens: promptTokens, completionTokens: completionTokens)
            
            return FormattedArticleSummary(
                quickFacts: summaryResponse.quickFacts,
                story: summaryResponse.theStory,
                error: summaryResponse.error
            )
        } catch let decodingError as DecodingError {
            print("❌ Failed to decode Gemini response: \(decodingError)")
            print("❌ Response text was: \(responseText)")
            throw GeminiServiceError.invalidResponse
        } catch {
            if let networkError = error as? NetworkError {
                throw handleNetworkError(networkError)
            }
            throw error
        }
    }
    
    /// Generates a summary from a URL by fetching and processing its content
    func generateSummary(from url: String) async -> String? {
        do {
            // First, fetch the content using FirecrawlService
            let firecrawlService = FirecrawlService()
            let firecrawlData = try await firecrawlService.scrapeURL(url)
            
            // If we got content, summarize it
            let content = firecrawlData.markdown ?? firecrawlData.content
            if !content.isEmpty {
                await ProcessingStatusService.shared.updateGeneratingSummary()
                let summary = try await summarize(text: content, length: .standard)
                await ProcessingStatusService.shared.updateSummaryGenerated(summaryLength: summary.count)
                return summary
            }
            
            return nil
        } catch {
            print("Error generating summary for URL \(url): \(error)")
            await ProcessingStatusService.shared.updateError("Failed to generate summary")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func createStructuredSummaryPrompt(text: String, title: String?) -> String {
        var prompt = "Your SOLE task is to analyze the provided news article content and extract specific information.\n"
        
        if let title = title {
            prompt += "Title: \"\(title)\"\n"
        }
        
        prompt += """
        
        Article Content:
        \"\"\"
        \(text)
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
            "theStory": "Your two-paragraph summary here. The first paragraph should cover the main event and immediate context. The second paragraph should provide background or broader implications if available in the text."
          }
        - If the provided "Article Content" is insufficient, unclear, not a news article, or if you cannot reasonably extract the required fields:
          Respond ONLY with this exact JSON object:
          {
            "error": "The provided content could not be processed to extract the required information or generate a news summary."
          }
        ABSOLUTELY DO NOT provide 'quickFacts' or 'theStory' if you are returning an 'error'. Do NOT use external knowledge.
        Your response MUST be one of these two JSON structures.
        """
        
        return prompt
    }
    
    private func createSummarizationPrompt(text: String, length: Constants.Summary.Length) -> String {
        let wordCount: String
        let maxSentences: String
        switch length {
        case .brief:
            wordCount = "70-100"
            maxSentences = "5"
        case .standard:
            wordCount = "120-180"
            maxSentences = "8"
        case .detailed:
            wordCount = "220-300"
            maxSentences = "12"
        }

        print("[GeminiService] Creating summary prompt for \(text.count) characters of content")

        // Note: Content truncation is handled upstream in UnifiedAudioPlayer (20k chars, sentence-boundary aware)
        // No additional truncation here to avoid double truncation

        return """
        Create a concise spoken news briefing from this article in \(wordCount) words, with no more than \(maxSentences) sentences.

        Focus on the key facts: who, what, when, where, why, and any important numbers. Use plain radio-host language that can be read aloud immediately. Do not add external facts, intro phrases, bullets, markdown, or the article title. Start directly with the main content.

        Article:
        \(text)

        Spoken briefing:
        """
    }
    
    private func handleGeminiError(_ error: GeminiError) -> Error {
        switch error.code {
        case 403:
            return GeminiServiceError.invalidAPIKey
        case 429:
            return GeminiServiceError.quotaExceeded
        case 500...599:
            return GeminiServiceError.serverError(error.code)
        default:
            return GeminiServiceError.modelError(error.message)
        }
    }
    
    private func handleNetworkError(_ error: NetworkError) -> Error {
        switch error {
        case .rateLimited:
            return GeminiServiceError.quotaExceeded
        case .unauthorized:
            return GeminiServiceError.invalidAPIKey
        default:
            return error
        }
    }

    // MARK: - JSON Extraction Helpers

    /// Extracts JSON from a response that may contain markdown code blocks or other formatting
    private func extractJSON(from response: String) -> String {
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code blocks (various formats)
        // Handle: ```json, ``` json, ```JSON, ```\n{, etc.
        let codeBlockPattern = #"```(?:json|JSON)?\s*\n?([\s\S]*?)\n?```"#
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []),
           let match = regex.firstMatch(in: jsonString, options: [], range: NSRange(jsonString.startIndex..., in: jsonString)),
           let range = Range(match.range(at: 1), in: jsonString) {
            jsonString = String(jsonString[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // If no code block found, try to extract JSON object directly
        // Find first { and last } to extract JSON object
        if !jsonString.hasPrefix("{") {
            if let startIdx = jsonString.firstIndex(of: "{"),
               let endIdx = jsonString.lastIndex(of: "}") {
                jsonString = String(jsonString[startIdx...endIdx])
            }
        }

        // Fix unescaped control characters in JSON string values
        jsonString = fixUnescapedControlChars(in: jsonString)

        return jsonString
    }

    /// Fixes unescaped newlines, tabs, and other control characters inside JSON string values
    private func fixUnescapedControlChars(in jsonString: String) -> String {
        var result = ""
        var inString = false
        var escaped = false

        for char in jsonString {
            if char == "\"" && !escaped {
                inString = !inString
                result += String(char)
            } else if inString && !escaped {
                switch char {
                case "\n": result += "\\n"
                case "\r": result += "\\r"
                case "\t": result += "\\t"
                default: result += String(char)
                }
            } else {
                result += String(char)
            }
            escaped = (char == "\\" && !escaped)
        }

        return result
    }

    /// Attempts lenient JSON parsing - extracts what fields are available
    private func tryLenientParse(jsonString: String) -> ArticleSummaryResponse? {
        // Try to parse as dictionary and extract fields manually
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Check for error response first
        if let errorMsg = dict["error"] as? String {
            return ArticleSummaryResponse(quickFacts: nil, theStory: nil, error: errorMsg)
        }

        // Extract theStory
        let theStory = dict["theStory"] as? String

        // Extract quickFacts if present
        var quickFacts: QuickFacts?
        if let qfDict = dict["quickFacts"] as? [String: Any] {
            quickFacts = QuickFacts(
                whatHappened: qfDict["whatHappened"] as? String ?? "N/A",
                who: qfDict["who"] as? String ?? "N/A",
                whenWhere: qfDict["whenWhere"] as? String ?? "N/A",
                keyNumbers: qfDict["keyNumbers"] as? String ?? "N/A",
                mostStrikingDetail: qfDict["mostStrikingDetail"] as? String ?? "N/A"
            )
        }

        // Only return if we have some content
        if quickFacts != nil || theStory != nil {
            return ArticleSummaryResponse(quickFacts: quickFacts, theStory: theStory, error: nil)
        }

        return nil
    }
}

// MARK: - JSON Encoder Extension
private extension JSONEncoder {
    func jsonObject<T: Encodable>(from object: T) throws -> [String: Any] {
        let data = try encode(object)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiServiceError.invalidResponse
        }
        return json
    }
}
