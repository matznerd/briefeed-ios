//
//  ProcessingStatusService.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import Foundation
import SwiftUI

// MARK: - Processing Status Types
enum ProcessingStage {
    case idle
    case fetchingContent(url: String)
    case contentFetched(wordCount: Int)
    case generatingSummary
    case summaryGenerated
    case generatingAudio
    case audioReady
    case error(String)
    case completed
}

// MARK: - Processing Status Service
class ProcessingStatusService: ObservableObject {
    static let shared = ProcessingStatusService()
    
    @MainActor @Published var currentStatus: ProcessingStage = .idle
    @MainActor @Published var statusHistory: [StatusEntry] = []
    @MainActor @Published var isProcessing: Bool = false
    @MainActor @Published var showStatusBanner: Bool = false
    
    struct StatusEntry {
        let id = UUID()
        let timestamp: Date
        let stage: ProcessingStage
        let message: String
        let isError: Bool
    }
    
    private init() {}
    
    // MARK: - Status Updates
    
    @MainActor func startProcessing(articleTitle: String) {
        isProcessing = true
        showStatusBanner = true
        addStatus(.idle, message: "🎯 Starting to process: \"\(articleTitle.prefix(50))...\"")
    }
    
    @MainActor func updateFetchingContent(url: String) {
        currentStatus = .fetchingContent(url: url)
        let domain = URL(string: url)?.host ?? "website"
        addStatus(.fetchingContent(url: url), message: "🌐 Fetching article from \(domain)...")
    }
    
    @MainActor func updateContentFetched(wordCount: Int, url: String) {
        currentStatus = .contentFetched(wordCount: wordCount)
        let domain = URL(string: url)?.host ?? "website"
        addStatus(.contentFetched(wordCount: wordCount), 
                 message: "✅ Retrieved \(wordCount) words from \(domain)")
    }
    
    @MainActor func updateGeneratingSummary() {
        currentStatus = .generatingSummary
        addStatus(.generatingSummary, message: "🤖 Sending to Gemini AI for summarization...")
    }
    
    @MainActor func updateSummaryGenerated(summaryLength: Int) {
        currentStatus = .summaryGenerated
        addStatus(.summaryGenerated, 
                 message: "✅ Summary created (\(summaryLength) characters)")
    }
    
    @MainActor func updateGeneratingAudio(voiceName: String? = nil) {
        currentStatus = .generatingAudio
        let voiceInfo = voiceName != nil ? " with voice: \(voiceName!)" : ""
        addStatus(.generatingAudio, message: "🎙️ Generating audio\(voiceInfo)...")
    }
    
    @MainActor func updateAudioReady() {
        currentStatus = .audioReady
        addStatus(.audioReady, message: "✅ Audio ready to play!")
    }
    
    @MainActor func updateError(_ error: String) {
        currentStatus = .error(error)
        addStatus(.error(error), message: "❌ Error: \(error)", isError: true)
        
        // Auto-hide error after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.hideStatusIfNotProcessing()
        }
    }
    
    @MainActor func completeProcessing() {
        currentStatus = .completed
        addStatus(.completed, message: "✨ Processing complete!")
        isProcessing = false
        
        // Auto-hide success after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.hideStatusIfNotProcessing()
        }
    }
    
    @MainActor func cancelProcessing() {
        isProcessing = false
        showStatusBanner = false
        currentStatus = .idle
        addStatus(.idle, message: "🛑 Processing cancelled")
    }
    
    // MARK: - Private Methods
    
    @MainActor private func addStatus(_ stage: ProcessingStage, message: String, isError: Bool = false) {
        let entry = StatusEntry(
            timestamp: Date(),
            stage: stage,
            message: message,
            isError: isError
        )
        
        statusHistory.append(entry)
        
        // Keep only last 50 entries
        if statusHistory.count > 50 {
            statusHistory.removeFirst()
        }
        
        // Also log to console for debugging
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[\(timestamp)] \(message)")
    }
    
    @MainActor private func hideStatusIfNotProcessing() {
        if !isProcessing {
            showStatusBanner = false
        }
    }
    
    // MARK: - Status Message Helper
    
    @MainActor func getCurrentStatusMessage() -> String {
        switch currentStatus {
        case .idle:
            return "Ready"
        case .fetchingContent(let url):
            let domain = URL(string: url)?.host ?? "website"
            return "Fetching from \(domain)..."
        case .contentFetched(let wordCount):
            return "Retrieved \(wordCount) words"
        case .generatingSummary:
            return "Generating summary..."
        case .summaryGenerated:
            return "Summary ready"
        case .generatingAudio:
            return "Creating audio..."
        case .audioReady:
            return "Ready to play!"
        case .error(let message):
            return message
        case .completed:
            return "Complete!"
        }
    }
    
    @MainActor func getCurrentStatusColor() -> Color {
        switch currentStatus {
        case .error:
            return .red
        case .completed, .contentFetched, .summaryGenerated, .audioReady:
            return .green
        case .fetchingContent, .generatingSummary, .generatingAudio:
            return .blue
        case .idle:
            return .gray
        }
    }
    
    // MARK: - Clear History
    
    @MainActor func clearHistory() {
        statusHistory.removeAll()
    }
}

// MARK: - Status Banner View
struct ProcessingStatusBanner: View {
    @ObservedObject var statusService = ProcessingStatusService.shared
    
    var body: some View {
        if statusService.showStatusBanner {
            HStack {
                if statusService.isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                }
                
                Text(statusService.getCurrentStatusMessage())
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: {
                    statusService.showStatusBanner = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(statusService.getCurrentStatusColor())
            .cornerRadius(8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: statusService.showStatusBanner)
        }
    }
}

// MARK: - Status History View
struct ProcessingStatusHistoryView: View {
    @ObservedObject var statusService = ProcessingStatusService.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                if statusService.statusHistory.isEmpty {
                    Text("No processing history")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(statusService.statusHistory.reversed(), id: \.id) { entry in
                        HStack {
                            Text(entry.message)
                                .font(.caption)
                                .foregroundColor(entry.isError ? .red : .primary)
                            
                            Spacer()
                            
                            Text(entry.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Processing History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") {
                        statusService.clearHistory()
                    }
                    .disabled(statusService.statusHistory.isEmpty)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}