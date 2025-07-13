//
//  RSSParser.swift
//  Briefeed
//
//  Created by Briefeed Team on 7/13/25.
//

import Foundation

// MARK: - RSS Parser
class RSSParser: NSObject {
    
    // MARK: - Properties
    private var currentElement = ""
    private var currentItem: ParsedRSSEpisode?
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var currentGuid = ""
    private var currentDuration = ""
    private var currentEnclosureUrl = ""
    
    private var items: [ParsedRSSEpisode] = []
    private var feedId: String = ""
    private var isInsideItem = false
    
    // MARK: - Public Methods
    
    /// Parse RSS feed data
    func parse(data: Data, feedId: String) async throws -> [ParsedRSSEpisode] {
        self.feedId = feedId
        self.items = []
        
        let parser = XMLParser(data: data)
        parser.delegate = self
        
        if parser.parse() {
            return items
        } else if let error = parser.parserError {
            throw error
        } else {
            throw RSSParserError.parsingFailed
        }
    }
}

// MARK: - XML Parser Delegate
extension RSSParser: XMLParserDelegate {
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        
        if currentElement == "item" || currentElement == "entry" {
            isInsideItem = true
            currentItem = nil
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
            currentPubDate = ""
            currentGuid = ""
            currentDuration = ""
            currentEnclosureUrl = ""
        }
        
        // Handle enclosure tag for audio URL
        if currentElement == "enclosure" && isInsideItem {
            if let url = attributeDict["url"],
               let type = attributeDict["type"],
               type.contains("audio") {
                currentEnclosureUrl = url
            }
        }
        
        // Handle media:content for some feeds
        if currentElement == "media:content" && isInsideItem {
            if let url = attributeDict["url"],
               let type = attributeDict["type"],
               type.contains("audio") {
                currentEnclosureUrl = url
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }
        
        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch currentElement {
        case "title":
            currentTitle += trimmedString
        case "link":
            currentLink += trimmedString
        case "description", "summary", "content:encoded":
            currentDescription += trimmedString
        case "pubdate", "published", "dc:date":
            currentPubDate += trimmedString
        case "guid", "id":
            currentGuid += trimmedString
        case "itunes:duration", "duration":
            currentDuration += trimmedString
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = elementName.lowercased()
        
        if element == "item" || element == "entry" {
            // Create episode if we have required fields
            if !currentTitle.isEmpty && !currentEnclosureUrl.isEmpty {
                let episode = ParsedRSSEpisode(
                    guid: currentGuid.isEmpty ? "\(feedId)-\(currentPubDate)" : currentGuid,
                    title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    audioUrl: currentEnclosureUrl,
                    pubDate: parseDate(currentPubDate) ?? Date(),
                    duration: parseDuration(currentDuration),
                    description: cleanDescription(currentDescription)
                )
                items.append(episode)
            }
            
            isInsideItem = false
        }
    }
    
    // MARK: - Helper Methods
    
    private func parseDate(_ dateString: String) -> Date? {
        let trimmedDate = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Common RSS date formats
        let formatters = [
            DateFormatter.rfc822,
            DateFormatter.rfc3339,
            DateFormatter.iso8601
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: trimmedDate) {
                return date
            }
        }
        
        return nil
    }
    
    private func parseDuration(_ durationString: String) -> Int? {
        let trimmed = durationString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle HH:MM:SS format
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").compactMap { Int($0) }
            
            switch parts.count {
            case 1: // Seconds only
                return parts[0]
            case 2: // MM:SS
                return parts[0] * 60 + parts[1]
            case 3: // HH:MM:SS
                return parts[0] * 3600 + parts[1] * 60 + parts[2]
            default:
                return nil
            }
        }
        
        // Handle plain seconds
        return Int(trimmed)
    }
    
    private func cleanDescription(_ description: String) -> String {
        // Remove HTML tags
        let htmlRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive)
        var cleaned = htmlRegex?.stringByReplacingMatches(
            in: description,
            options: [],
            range: NSRange(location: 0, length: description.count),
            withTemplate: ""
        ) ?? description
        
        // Decode HTML entities
        cleaned = cleaned
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        
        // Trim and limit length
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > 500 {
            let index = cleaned.index(cleaned.startIndex, offsetBy: 497)
            cleaned = String(cleaned[..<index]) + "..."
        }
        
        return cleaned
    }
}

// MARK: - Date Formatter Extensions
private extension DateFormatter {
    static let rfc822: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    static let rfc3339: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

// MARK: - RSS Parser Error
enum RSSParserError: LocalizedError {
    case parsingFailed
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .parsingFailed:
            return "Failed to parse RSS feed"
        case .invalidData:
            return "Invalid RSS data"
        }
    }
}