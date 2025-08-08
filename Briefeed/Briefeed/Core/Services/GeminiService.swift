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
    let parts: [GeminiPart]
    let role: String? // "user" or "model"
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

// MARK: - Gemini Service Protocol
protocol GeminiServiceProtocol {
    func summarize(text: String, length: Constants.Summary.Length) async throws -> String
    func summarizeWithStream(text: String, length: Constants.Summary.Length, onChunk: @escaping (String) -> Void) async throws
    func getUsageStats() -> GeminiUsage?
    func generateStructuredSummary(text: String, title: String?) async throws -> FormattedArticleSummary
}

// MARK: - Gemini Service Implementation
class GeminiService: GeminiServiceProtocol {
    private let networkService: NetworkServiceProtocol
    private let apiKey: String
    private let model = "gemini-2.0-flash-exp" // Latest fast model for summarization
    private var currentUsage: GeminiUsage?
    
    init(networkService: NetworkServiceProtocol = NetworkService.shared, apiKey: String? = nil) {
        self.networkService = networkService
        self.apiKey = apiKey ?? Constants.API.geminiAPIKey ?? ""
    }
    
    func summarize(text: String, length: Constants.Summary.Length) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GeminiServiceError.invalidAPIKey
        }
        
        let prompt = createSummarizationPrompt(text: text, length: length)
        let endpoint = "\(Constants.API.geminiBaseURL)/models/\(model):generateContent?key=\(apiKey)"
        
        let request = GeminiRequest(
            contents: [
                GeminiContent(
                    parts: [GeminiPart(text: prompt)],
                    role: "user"
                )
            ],
            generationConfig: GeminiGenerationConfig(
                temperature: 0.7,
                topK: 40,
                topP: 0.95,
                maxOutputTokens: length.maxTokens,
                stopSequences: nil,
                responseMimeType: nil
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
                  let firstCandidate = candidates.first,
                  !firstCandidate.content.parts.isEmpty,
                  let text = firstCandidate.content.parts.first?.text else {
                throw GeminiServiceError.invalidResponse
            }
            
            // Update usage tracking (rough estimation)
            let promptTokens = prompt.count / 4 // Rough token estimation
            let completionTokens = text.count / 4
            currentUsage = GeminiUsage(promptTokens: promptTokens, completionTokens: completionTokens)
            
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            if let networkError = error as? NetworkError {
                throw handleNetworkError(networkError)
            }
            throw error
        }
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
                    role: "user"
                )
            ],
            generationConfig: GeminiGenerationConfig(
                temperature: 0.3, // Lower temperature for more consistent JSON
                topK: 40,
                topP: 0.95,
                maxOutputTokens: 1000,
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
                  let firstCandidate = candidates.first,
                  !firstCandidate.content.parts.isEmpty,
                  let text = firstCandidate.content.parts.first?.text else {
                throw GeminiServiceError.invalidResponse
            }
            
            responseText = text
            
            // Parse JSON response
            let cleanedResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            print("📝 Gemini raw response: \(cleanedResponse)")
            
            // Try to extract JSON from the response
            // Sometimes Gemini adds markdown formatting
            var jsonString = cleanedResponse
            if jsonString.hasPrefix("```json") && jsonString.hasSuffix("```") {
                jsonString = jsonString
                    .replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Fix unescaped newlines in JSON string values - character by character parsing
            var fixedJson = ""
            var inString = false
            var escaped = false
            
            for (i, char) in jsonString.enumerated() {
                if char == "\"" && !escaped {
                    inString = !inString
                    fixedJson += String(char)
                } else if inString && char == "\n" && !escaped {
                    // Replace unescaped newline with escaped version
                    fixedJson += "\\n"
                } else if inString && char == "\r" && !escaped {
                    // Replace unescaped carriage return with escaped version
                    fixedJson += "\\r"
                } else if inString && char == "\t" && !escaped {
                    // Replace unescaped tab with escaped version
                    fixedJson += "\\t"
                } else {
                    fixedJson += String(char)
                }
                
                // Track escape state
                escaped = (char == "\\" && !escaped)
            }
            
            jsonString = fixedJson
            
            guard let data = jsonString.data(using: .utf8) else {
                print("❌ Failed to convert to data: \(jsonString)")
                throw GeminiServiceError.invalidResponse
            }
            
            let summaryResponse = try JSONDecoder().decode(ArticleSummaryResponse.self, from: data)
            
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
        
        return prompt
    }
    
    private func createSummarizationPrompt(text: String, length: Constants.Summary.Length) -> String {
        // Using the exact same prompt structure as the Capacitor app
        return """
        Your SOLE task is to analyze the provided news article content and extract specific information.
        
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
    }
    
    private func handleGeminiError(_ error: GeminiError) -> Error {
        switch error.code {
        case 403:
            return GeminiServiceError.invalidAPIKey
        case 429:
            return GeminiServiceError.quotaExceeded
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