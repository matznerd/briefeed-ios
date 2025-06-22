//
//  ArticleView.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import SwiftUI

struct ArticleView: View {
    let article: Article
    @StateObject private var viewModel: ArticleViewModel
    @State private var showShareSheet = false
    @State private var showReaderSettings = false
    @Environment(\.dismiss) private var dismiss
    
    init(article: Article) {
        self.article = article
        self._viewModel = StateObject(wrappedValue: ArticleViewModel(article: article))
    }
    
    var body: some View {
        ZStack {
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(error: error)
            } else {
                contentView
            }
        }
        // Don't stop audio when leaving - it should continue playing
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                toolbarButtons
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = URL(string: article.url ?? "") {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showReaderSettings) {
            readerSettingsView
        }
        .task {
            // Only load content if it's not already available
            if viewModel.articleContent == nil || viewModel.articleContent?.isEmpty == true {
                await viewModel.loadArticleContent()
            }
            await viewModel.markAsRead()
        }
    }
    
    // MARK: - Views
    
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    Text(article.title ?? "Untitled")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.briefeedLabel)
                    
                    // Metadata
                    HStack(spacing: 12) {
                        // Subreddit
                        Label(article.subreddit ?? "", systemImage: "bubble.left")
                            .font(.subheadline)
                            .foregroundColor(.briefeedSecondaryLabel)
                        
                        // Author
                        if let author = article.author {
                            Label("u/\(author)", systemImage: "person")
                                .font(.subheadline)
                                .foregroundColor(.briefeedSecondaryLabel)
                        }
                        
                        // Time
                        if let createdAt = article.createdAt {
                            Label(createdAt.timeAgoDisplay, systemImage: "clock")
                                .font(.subheadline)
                                .foregroundColor(.briefeedSecondaryLabel)
                        }
                    }
                    
                    // Structured summary if available
                    if let structuredSummary = viewModel.structuredSummary, structuredSummary.hasContent {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundColor(.briefeedRed)
                                Text("AI Summary")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.briefeedRed)
                            }
                            
                            ArticleSummaryView(summary: structuredSummary)
                        }
                    } else if let summary = viewModel.summary, !summary.isEmpty {
                        // Fallback to plain text summary
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundColor(.briefeedRed)
                                Text("AI Summary")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.briefeedRed)
                            }
                            
                            Text(summary)
                                .font(.body)
                                .foregroundColor(.briefeedSecondaryLabel)
                                .padding()
                                .background(Color.briefeedSecondaryBackground)
                                .cornerRadius(Constants.UI.cornerRadius)
                        }
                    }
                    
                    // Show error if there's one but not showing loading view
                    if !viewModel.isLoading && !viewModel.isGeneratingSummary && !viewModel.isLoadingContent,
                       let error = viewModel.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(Constants.UI.cornerRadius)
                    }
                }
                .padding(.horizontal, Constants.UI.padding)
                .padding(.top)
                
                Divider()
                    .padding(.horizontal, Constants.UI.padding)
                
                // Article content
                if viewModel.isLoadingContent {
                    VStack(spacing: 20) {
                        ProgressView("Fetching article content...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.2)
                        
                        Text("This may take a few moments")
                            .font(.caption)
                            .foregroundColor(.briefeedSecondaryLabel)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 400)
                    .background(Color.briefeedSecondaryBackground)
                    .cornerRadius(Constants.UI.cornerRadius)
                    .padding(.horizontal, Constants.UI.padding)
                } else if let content = viewModel.articleContent, !content.isEmpty {
                    ArticleReaderView(
                        content: content,
                        fontSize: viewModel.fontSize,
                        isReaderMode: viewModel.isReaderMode
                    )
                    .frame(minHeight: 400)
                } else if let url = article.url {
                    // Show fetch content button if no content is available
                    VStack(spacing: 20) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 50))
                            .foregroundColor(.briefeedSecondaryLabel)
                        
                        Text("Article content not loaded")
                            .font(.headline)
                            .foregroundColor(.briefeedLabel)
                        
                        LoadingButton(title: "Fetch Full Article", systemImage: "arrow.down.circle", isLoading: viewModel.isLoadingContent) {
                            await viewModel.loadArticleContent()
                        }
                        .frame(maxWidth: 200)
                        
                        Text("or")
                            .font(.caption)
                            .foregroundColor(.briefeedSecondaryLabel)
                        
                        // Fallback to web view
                        ArticleReaderView(
                            url: url,
                            fontSize: viewModel.fontSize,
                            isReaderMode: viewModel.isReaderMode
                        )
                        .frame(minHeight: 300)
                    }
                    .padding(.horizontal, Constants.UI.padding)
                }
            }
        }
        .background(Color.briefeedBackground)
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading article...")
                .font(.headline)
                .foregroundColor(.briefeedSecondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.briefeedBackground)
    }
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("Failed to load article")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(error)
                .font(.body)
                .foregroundColor(.briefeedSecondaryLabel)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                Task {
                    await viewModel.loadArticleContent()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.briefeedRed)
            
            if let url = article.url {
                Button("Open in Browser") {
                    if let webURL = URL(string: url) {
                        UIApplication.shared.open(webURL)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.briefeedBackground)
    }
    
    private var toolbarButtons: some View {
        HStack(spacing: 16) {
            // Audio playback button
            if viewModel.canPlayAudio {
                Button(action: {
                    viewModel.toggleAudioPlayback()
                }) {
                    Group {
                        switch viewModel.audioState {
                        case .loading:
                            ProgressView()
                                .scaleEffect(0.8)
                        case .playing:
                            Image(systemName: "pause.fill")
                        case .paused:
                            Image(systemName: "play.fill")
                        default:
                            Image(systemName: "play.fill")
                        }
                    }
                    .foregroundColor(.briefeedRed)
                }
                .disabled(viewModel.audioState == .loading)
            }
            
            // Reader settings
            Button(action: {
                showReaderSettings = true
            }) {
                Image(systemName: "textformat.size")
            }
            
            // Save button
            Button(action: {
                Task {
                    await viewModel.toggleSaved()
                }
            }) {
                Image(systemName: viewModel.article.isSaved ? "bookmark.fill" : "bookmark")
                    .foregroundColor(viewModel.article.isSaved ? .orange : .primary)
            }
            
            // Share button
            Button(action: {
                showShareSheet = true
            }) {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }
    
    private var readerSettingsView: some View {
        NavigationStack {
            Form {
                Section("Text Size") {
                    HStack {
                        Image(systemName: "textformat.size.smaller")
                        Slider(
                            value: $viewModel.fontSize,
                            in: Constants.UI.minTextSize...Constants.UI.maxTextSize,
                            step: 1
                        )
                        .onChange(of: viewModel.fontSize) { newValue in
                            UserDefaults.standard.set(Double(newValue), forKey: "articleFontSize")
                        }
                        Image(systemName: "textformat.size.larger")
                    }
                    
                    Text("Preview")
                        .font(.system(size: viewModel.fontSize))
                        .padding(.vertical, 8)
                }
                
                Section("Display") {
                    Toggle("Reader Mode", isOn: $viewModel.isReaderMode)
                    
                    if viewModel.isReaderMode {
                        Text("Reader mode simplifies the article layout for easier reading")
                            .font(.caption)
                            .foregroundColor(.briefeedSecondaryLabel)
                    }
                }
                
                Section("AI Features") {
                    LoadingButton(title: "Generate Summary", systemImage: "sparkles", isLoading: viewModel.isGeneratingSummary) {
                        await viewModel.generateStructuredSummary()
                    }
                }
                
                if viewModel.canPlayAudio {
                    Section("Audio Playback") {
                        HStack {
                            Image(systemName: "speaker.wave.2")
                            Text("Speed")
                            Spacer()
                            Text("\(String(format: "%.1fx", viewModel.audioRate))")
                                .foregroundColor(.briefeedSecondaryLabel)
                        }
                        
                        Slider(
                            value: $viewModel.audioRate,
                            in: Constants.Audio.minSpeechRate...Constants.Audio.maxSpeechRate,
                            step: 0.25
                        )
                        .onChange(of: viewModel.audioRate) { newValue in
                            viewModel.setAudioRate(newValue)
                        }
                        
                        if viewModel.audioState == .playing || viewModel.audioState == .paused {
                            HStack {
                                Text("Progress")
                                Spacer()
                                Text("\(Int(viewModel.audioProgress * 100))%")
                                    .foregroundColor(.briefeedSecondaryLabel)
                            }
                            
                            ProgressView(value: viewModel.audioProgress)
                                .progressViewStyle(LinearProgressViewStyle())
                                .tint(.briefeedRed)
                        }
                    }
                }
            }
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showReaderSettings = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        ArticleView(article: {
            let context = PersistenceController.preview.container.viewContext
            let article = Article(context: context)
            article.id = UUID()
            article.title = "SwiftUI 5.0 introduces new navigation APIs"
            article.author = "apple_developer"
            article.subreddit = "iOSProgramming"
            article.createdAt = Date().addingTimeInterval(-3600)
            article.isRead = false
            article.isSaved = false
            article.url = "https://developer.apple.com/documentation/swiftui"
            article.content = "SwiftUI 5.0 brings exciting new features..."
            article.summary = "This article discusses the new navigation APIs introduced in SwiftUI 5.0, including NavigationStack and NavigationPath."
            return article
        }())
    }
}