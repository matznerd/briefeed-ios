//
//  TranscriptReaderView.swift
//  Briefeed
//
//  Swipe-up transcript view showing Quick Facts + scrolling story text
//  with paragraph highlighting that follows audio playback progress.
//

import SwiftUI

struct TranscriptReaderView: View {
    @EnvironmentObject var audioViewModel: AudioPlayerViewModelV2
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header: title + source
                        headerSection

                        // Quick Facts card
                        if let quickFacts = parsedSummary?.quickFacts,
                           !quickFacts.displayItems.isEmpty {
                            quickFactsSection(quickFacts)
                        }

                        Divider()

                        // The Story text with paragraph highlighting
                        storySection
                    }
                    .padding()
                }
                .onChange(of: audioViewModel.progress) { _, _ in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(highlightedParagraphIndex, anchor: .center)
                    }
                }
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.TranscriptReader.dismiss)
                }
            }
            .accessibilityIdentifier(AccessibilityID.TranscriptReader.container)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(audioViewModel.currentTitle ?? "Unknown Article")
                .font(.title2.bold())
                .accessibilityIdentifier(AccessibilityID.TranscriptReader.title)

            if let artist = audioViewModel.currentArtist {
                Text(artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier(AccessibilityID.TranscriptReader.source)
            }

            // Playback progress indicator
            if audioViewModel.duration > 0 {
                HStack(spacing: 8) {
                    Image(systemName: audioViewModel.isPlaying ? "waveform" : "pause.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.briefeedRed)
                        .symbolEffect(.variableColor.iterative, isActive: audioViewModel.isPlaying)

                    Text("\(formatTime(audioViewModel.currentTime)) / \(formatTime(audioViewModel.duration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Quick Facts

    private func quickFactsSection(_ quickFacts: QuickFacts) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Facts")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(quickFacts.displayItems, id: \.label) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(iconForFact(item.label))
                            .font(.system(size: 14))
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(item.value)
                                .font(.system(size: 14))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.gray.opacity(0.08))
            )
        }
        .accessibilityIdentifier(AccessibilityID.TranscriptReader.quickFacts)
    }

    // MARK: - Story Section

    private var storySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !storyParagraphs.isEmpty {
                Text("The Story")
                    .font(.headline)
                    .padding(.bottom, 4)

                ForEach(Array(storyParagraphs.enumerated()), id: \.offset) { index, paragraph in
                    Text(paragraph)
                        .font(.system(size: 15))
                        .lineSpacing(5)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(index == highlightedParagraphIndex
                                      ? Color.briefeedRed.opacity(0.12)
                                      : Color.clear)
                        )
                        .id(index)
                }
            } else {
                Text("No transcript available for this item.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            }
        }
        .accessibilityIdentifier(AccessibilityID.TranscriptReader.storyText)
    }

    // MARK: - Computed Properties

    private var currentArticle: Article? {
        guard audioViewModel.currentQueueIndex >= 0,
              audioViewModel.currentQueueIndex < audioViewModel.queueItems.count else {
            return nil
        }
        return audioViewModel.queueItems[audioViewModel.currentQueueIndex].article
    }

    private var parsedSummary: ArticleSummaryResponse? {
        guard let summary = currentArticle?.summary,
              !summary.isEmpty else { return nil }

        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try JSON parsing first
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("```json") {
            let cleanJson = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let data = cleanJson.data(using: .utf8),
               let response = try? JSONDecoder().decode(ArticleSummaryResponse.self, from: data) {
                return response
            }
        }

        // Plain text summary — wrap as story
        return ArticleSummaryResponse(quickFacts: nil, theStory: trimmed, error: nil)
    }

    private var storyText: String {
        if let story = parsedSummary?.theStory, !story.isEmpty {
            return story
        }
        // Fallback to raw summary
        return currentArticle?.summary ?? ""
    }

    private var storyParagraphs: [String] {
        let text = storyText
        guard !text.isEmpty else { return [] }

        // Split by double newlines first, then by sentences for long paragraphs
        let rawParagraphs = text.components(separatedBy: "\n\n")
            .flatMap { paragraph -> [String] in
                let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return [] }

                // If paragraph is very long (>300 chars), split by sentences
                if trimmed.count > 300 {
                    return splitIntoSentenceGroups(trimmed, maxLength: 250)
                }
                return [trimmed]
            }

        return rawParagraphs
    }

    private var highlightedParagraphIndex: Int {
        guard !storyParagraphs.isEmpty, audioViewModel.duration > 0 else { return 0 }
        let progress = audioViewModel.progress
        let index = Int(Float(storyParagraphs.count) * progress)
        return min(index, storyParagraphs.count - 1)
    }

    // MARK: - Helpers

    private func splitIntoSentenceGroups(_ text: String, maxLength: Int) -> [String] {
        let sentences = text.components(separatedBy: ". ")
        var groups: [String] = []
        var current = ""

        for sentence in sentences {
            let candidate = current.isEmpty ? sentence : current + ". " + sentence
            if candidate.count > maxLength && !current.isEmpty {
                groups.append(current + ".")
                current = sentence
            } else {
                current = candidate
            }
        }
        if !current.isEmpty {
            groups.append(current.hasSuffix(".") ? current : current + ".")
        }
        return groups
    }

    private func iconForFact(_ label: String) -> String {
        switch label {
        case "What happened": return "📰"
        case "Who": return "👤"
        case "When & Where": return "📍"
        case "Key numbers": return "🔢"
        case "Most striking detail": return "⚡"
        default: return "•"
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
