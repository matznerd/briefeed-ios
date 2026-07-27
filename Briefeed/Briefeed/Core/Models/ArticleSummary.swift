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

    init(quickFacts: QuickFacts?, theStory: String?, error: String?) {
        self.quickFacts = quickFacts
        self.theStory = theStory
        self.error = error
    }
}

// MARK: - Quick Facts
struct QuickFacts: Codable {
    let whatHappened: String
    let who: String
    let whenWhere: String
    let keyNumbers: String
    let mostStrikingDetail: String

    // Backward-compatible decoding with defaults for missing fields
    enum CodingKeys: String, CodingKey {
        case whatHappened, who, whenWhere, keyNumbers, mostStrikingDetail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        whatHappened = try container.decodeIfPresent(String.self, forKey: .whatHappened) ?? "N/A"
        who = try container.decodeIfPresent(String.self, forKey: .who) ?? "N/A"
        whenWhere = try container.decodeIfPresent(String.self, forKey: .whenWhere) ?? "N/A"
        keyNumbers = try container.decodeIfPresent(String.self, forKey: .keyNumbers) ?? "N/A"
        mostStrikingDetail = try container.decodeIfPresent(String.self, forKey: .mostStrikingDetail) ?? "N/A"
    }

    init(whatHappened: String, who: String, whenWhere: String, keyNumbers: String, mostStrikingDetail: String) {
        self.whatHappened = whatHappened
        self.who = who
        self.whenWhere = whenWhere
        self.keyNumbers = keyNumbers
        self.mostStrikingDetail = mostStrikingDetail
    }

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