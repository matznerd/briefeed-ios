//
//  ArticleSummary.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import Foundation

// MARK: - Article Summary Response
struct ArticleSummaryResponse: Codable {
    let quickFacts: QuickFacts?
    let theStory: String?
    let error: String?
}

// MARK: - Quick Facts
struct QuickFacts: Codable {
    let whatHappened: String
    let who: String
    let whenWhere: String
    let keyNumbers: String
    let mostStrikingDetail: String
    
    // Filter out N/A values for display
    var displayItems: [(label: String, value: String)] {
        var items: [(String, String)] = []
        
        if whatHappened != "N/A" && !whatHappened.isEmpty {
            items.append(("What happened", whatHappened))
        }
        if who != "N/A" && !who.isEmpty {
            items.append(("Who", who))
        }
        if whenWhere != "N/A" && !whenWhere.isEmpty {
            items.append(("When & Where", whenWhere))
        }
        if keyNumbers != "N/A" && !keyNumbers.isEmpty {
            items.append(("Key numbers", keyNumbers))
        }
        if mostStrikingDetail != "N/A" && !mostStrikingDetail.isEmpty {
            items.append(("Most striking detail", mostStrikingDetail))
        }
        
        return items
    }
}

// MARK: - Formatted Article Summary
struct FormattedArticleSummary {
    let quickFacts: QuickFacts?
    let story: String?
    let error: String?
    
    var hasContent: Bool {
        return quickFacts != nil || story != nil
    }
    
    var hasError: Bool {
        return error != nil
    }
}