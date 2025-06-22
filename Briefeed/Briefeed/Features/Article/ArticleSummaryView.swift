//
//  ArticleSummaryView.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import SwiftUI

struct ArticleSummaryView: View {
    let summary: FormattedArticleSummary
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Quick Facts section
            if let quickFacts = summary.quickFacts, !quickFacts.displayItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Facts")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(quickFacts.displayItems, id: \.label) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    
                                    Text(item.value)
                                        .font(.system(size: 14))
                                        .foregroundColor(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                                Spacer()
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.gray.opacity(0.1))
                    )
                }
            }
            
            // The Story section
            if let story = summary.story {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The Story")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(story)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            // Error message
            if let error = summary.error {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)
                    
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                )
            }
        }
        .padding(.horizontal, 16)
    }
}

// Preview
struct ArticleSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            ArticleSummaryView(
                summary: FormattedArticleSummary(
                    quickFacts: QuickFacts(
                        whatHappened: "Major tech company announces breakthrough in quantum computing",
                        who: "TechCorp and MIT researchers",
                        whenWhere: "Boston, Massachusetts on Tuesday",
                        keyNumbers: "$2.5 billion investment, 1000x faster processing",
                        mostStrikingDetail: "The quantum computer can solve problems in minutes that would take classical computers thousands of years"
                    ),
                    story: "TechCorp, in collaboration with MIT researchers, unveiled a revolutionary quantum computing system that promises to transform computational capabilities across industries. The breakthrough represents years of research and a massive financial investment in quantum technology.\n\nThe new quantum computer demonstrates unprecedented processing power, capable of solving complex optimization problems and simulating molecular interactions at speeds previously thought impossible. This advancement could accelerate drug discovery, improve financial modeling, and enhance artificial intelligence capabilities, marking a significant milestone in the quantum computing race.",
                    error: nil
                )
            )
            .padding(.vertical)
        }
        .preferredColorScheme(.dark)
    }
}