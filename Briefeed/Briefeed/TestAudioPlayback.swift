//
//  TestAudioPlayback.swift
//  Briefeed
//
//  Test view for verifying end-to-end audio playback with summaries
//

import SwiftUI
import CoreData

struct TestAudioPlayback: View {
    @StateObject private var audioPlayerViewModel = AudioPlayerViewModelV2()
    @State private var testArticle: Article?
    @State private var statusMessage = "Ready to test"
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Audio System Test")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(statusMessage)
                .font(.headline)
                .foregroundColor(isLoading ? .orange : .secondary)
            
            Divider()
            
            // Test Article Info
            if let article = testArticle {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Test Article:")
                        .font(.headline)
                    Text(article.title ?? "No Title")
                        .font(.body)
                    if let summary = article.summary {
                        Text("Summary: \(summary.prefix(100))...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Test Buttons
            VStack(spacing: 16) {
                Button(action: createTestArticle) {
                    Label("Create Test Article", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
                
                Button(action: playTestArticle) {
                    Label("Play Test Article", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(testArticle == nil || isLoading)
                
                Button(action: testWithSummaryGeneration) {
                    Label("Test Full Flow (Fetch + Summary + Audio)", systemImage: "waveform.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isLoading)
            }
            
            Divider()
            
            // Player State
            VStack(alignment: .leading, spacing: 8) {
                Text("Player State:")
                    .font(.headline)
                
                HStack {
                    Text("Playing:")
                    Text(audioPlayerViewModel.isPlaying ? "Yes" : "No")
                        .foregroundColor(audioPlayerViewModel.isPlaying ? .green : .red)
                }
                
                HStack {
                    Text("Current Title:")
                    Text(audioPlayerViewModel.currentTitle ?? "None")
                }
                
                HStack {
                    Text("Generation State:")
                    Text(audioPlayerViewModel.isGenerating ? "Generating..." : "Idle")
                        .foregroundColor(audioPlayerViewModel.isGenerating ? .orange : .secondary)
                }
                
                if !audioPlayerViewModel.generationProgress.isEmpty {
                    Text("Progress: \(audioPlayerViewModel.generationProgress)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            // Player Controls
            HStack(spacing: 20) {
                Button(action: { audioPlayerViewModel.togglePlayPause() }) {
                    Image(systemName: audioPlayerViewModel.isPlaying ? "pause.circle" : "play.circle")
                        .font(.system(size: 44))
                }
                .disabled(audioPlayerViewModel.currentTitle == nil)
                
                Button(action: { audioPlayerViewModel.stop() }) {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 44))
                }
                .disabled(audioPlayerViewModel.currentTitle == nil)
            }
            
            Spacer()
            
            // Mini Player at bottom
            MiniAudioPlayerV4()
                .environmentObject(audioPlayerViewModel)
        }
        .padding()
    }
    
    private func createTestArticle() {
        isLoading = true
        statusMessage = "Creating test article..."
        
        let context = PersistenceController.shared.container.viewContext
        let article = Article(context: context)
        article.id = UUID()
        article.title = "Test Article: SwiftUI and Modern iOS Development"
        article.content = """
        SwiftUI is Apple's modern framework for building user interfaces across all Apple platforms. \
        It provides a declarative syntax that makes it easy to create complex UIs with less code. \
        With features like automatic support for Dark Mode, Dynamic Type, and localization, \
        SwiftUI helps developers build apps that feel native and responsive. \
        The framework integrates seamlessly with existing UIKit code, allowing for gradual adoption \
        in existing projects. SwiftUI's preview feature enables real-time visualization of UI changes, \
        significantly speeding up the development process.
        """
        article.author = "Test Author"
        article.createdAt = Date()
        article.url = "https://example.com/test-article"
        
        testArticle = article
        try? context.save()
        
        isLoading = false
        statusMessage = "Test article created successfully"
    }
    
    private func playTestArticle() {
        guard let article = testArticle else { return }
        
        isLoading = true
        statusMessage = "Starting playback..."
        
        Task {
            await audioPlayerViewModel.play(article: article)
            
            await MainActor.run {
                isLoading = false
                statusMessage = "Playback started"
            }
        }
    }
    
    private func testWithSummaryGeneration() {
        isLoading = true
        statusMessage = "Testing full audio generation flow..."
        
        Task {
            // Create a test article with a real URL
            let context = PersistenceController.shared.container.viewContext
            let article = Article(context: context)
            article.id = UUID()
            article.title = "Testing Audio System with Real Article"
            article.url = "https://www.apple.com/newsroom/2023/06/introducing-apple-vision-pro/"
            article.author = "Apple Newsroom"
            article.createdAt = Date()
            
            testArticle = article
            try? context.save()
            
            await MainActor.run {
                statusMessage = "Article created, generating audio..."
            }
            
            // Play the article (will trigger summary generation)
            await audioPlayerViewModel.play(article: article)
            
            await MainActor.run {
                isLoading = false
                statusMessage = "Full flow completed!"
            }
        }
    }
}

// MARK: - Preview
struct TestAudioPlayback_Previews: PreviewProvider {
    static var previews: some View {
        TestAudioPlayback()
    }
}