//
//  SettingsView.swift
//  Briefeed
//
//  Created by Assistant on 6/21/25.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingResetAlert = false
    @State private var showingDocumentPicker = false
    @State private var showingProcessingHistory = false
    @Environment(\.colorScheme) var colorScheme
    // MIGRATION: Feature flags removed - using new services directly
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Appearance Section
                Section {
                    Toggle("Dark Mode", isOn: $viewModel.userDefaultsManager.isDarkMode)
                        .onChange(of: viewModel.userDefaultsManager.isDarkMode) { _, newValue in
                            updateColorScheme(isDark: newValue)
                        }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Text Size")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("A")
                                .font(.system(size: 12))
                            
                            Slider(
                                value: $viewModel.userDefaultsManager.textSize,
                                in: 12...24,
                                step: 1
                            )
                            
                            Text("A")
                                .font(.system(size: 20))
                        }
                        
                        Text("Current: \(Int(viewModel.userDefaultsManager.textSize))pt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Appearance", systemImage: "paintbrush")
                }
                
                // MARK: - Reading Section
                Section {
                    Picker("Summary Length", selection: $viewModel.userDefaultsManager.summaryLength) {
                        ForEach(SummaryLength.allCases, id: \.self) { length in
                            Text(length.rawValue).tag(length)
                        }
                    }
                    
                    Picker("Reading Font", selection: $viewModel.userDefaultsManager.preferredReadingFont) {
                        ForEach(viewModel.availableFonts, id: \.self) { font in
                            Text(font).tag(font)
                        }
                    }
                    
                    HStack {
                        Text("Articles per Page")
                        Spacer()
                        Picker("", selection: $viewModel.userDefaultsManager.articlesPerPage) {
                            Text("10").tag(10)
                            Text("20").tag(20)
                            Text("30").tag(30)
                            Text("50").tag(50)
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Label("Reading", systemImage: "book")
                }
                
                // MARK: - Audio Section
                Section {
                    Toggle("Enable Audio", isOn: $viewModel.userDefaultsManager.audioEnabled)
                    
                    if viewModel.userDefaultsManager.audioEnabled {
                        Toggle("Auto-play Audio", isOn: $viewModel.userDefaultsManager.autoPlayAudio)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Speech Rate")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Image(systemName: "tortoise")
                                    .foregroundColor(.secondary)
                                
                                Slider(
                                    value: $viewModel.userDefaultsManager.speechRate,
                                    in: 0.5...2.0,
                                    step: 0.1
                                )
                                
                                Image(systemName: "hare")
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Speed: \(viewModel.userDefaultsManager.speechRate, specifier: "%.1f")x")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label("Audio", systemImage: "speaker.wave.2")
                }
                
                // MARK: - Developer Settings Section
                #if DEBUG
                Section {
                    // MIGRATION: Feature flags removed
                    // Toggle("Use New Audio System", isOn: $featureFlags.useNewAudioService)
                    
                    // Toggle("Use New Audio Player UI", isOn: $featureFlags.useNewAudioPlayerUI)
                    
                    // Toggle("Enable Playback History", isOn: $featureFlags.enablePlaybackHistory)
                    
                    // Toggle("Enable Audio Caching", isOn: $featureFlags.enableAudioCaching)
                    
                    // Toggle("Enable Sleep Timer", isOn: $featureFlags.enableSleepTimer)
                    
                    HStack {
                        Text("Rollout Percentage")
                        Spacer()
                        Text("100%") // All features enabled
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { 100.0 },
                            set: { _ in } // No-op, all features enabled
                        ),
                        in: 0...100,
                        step: 10
                    )
                    
                    HStack(spacing: 12) {
                        Button("Enable All") {
                            // All features already enabled
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.green)
                        
                        Button("Disable All") {
                            // Feature flags removed
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    }
                    .frame(maxWidth: .infinity)
                } header: {
                    Label("Developer Settings", systemImage: "hammer")
                } footer: {
                    Text("These settings control the new audio system migration. Changes take effect immediately.")
                        .font(.caption)
                }
                #endif
                
                // MARK: - API Keys Section
                Section {
                    APIKeyRow(
                        service: .gemini,
                        apiKey: $viewModel.tempGeminiKey,
                        isValidating: viewModel.isValidatingGeminiKey,
                        isValid: viewModel.geminiKeyValid,
                        onSave: { viewModel.saveAPIKey(for: .gemini) },
                        onRemove: { viewModel.removeAPIKey(for: .gemini) }
                    )
                    
                    APIKeyRow(
                        service: .firecrawl,
                        apiKey: $viewModel.tempFirecrawlKey,
                        isValidating: viewModel.isValidatingFirecrawlKey,
                        isValid: viewModel.firecrawlKeyValid,
                        onSave: { viewModel.saveAPIKey(for: .firecrawl) },
                        onRemove: { viewModel.removeAPIKey(for: .firecrawl) }
                    )
                } header: {
                    Label("API Keys", systemImage: "key")
                } footer: {
                    Text("API keys are stored securely on your device and never shared.")
                        .font(.caption)
                }
                
                // MARK: - Diagnostics Section
                Section {
                    Button(action: {
                        showingProcessingHistory = true
                    }) {
                        Label("Processing History", systemImage: "clock.arrow.circlepath")
                            .foregroundColor(.primary)
                    }
                } header: {
                    Label("Diagnostics", systemImage: "stethoscope")
                } footer: {
                    Text("View detailed logs of article processing and API calls")
                }
                
                // MARK: - Data Section
                Section {
                    HStack {
                        Label("Cache Size", systemImage: "externaldrive")
                        Spacer()
                        Text(viewModel.cacheSize)
                            .foregroundColor(.secondary)
                    }
                    
                    if let lastClear = viewModel.userDefaultsManager.lastCacheClear {
                        HStack {
                            Text("Last Cleared")
                            Spacer()
                            Text(lastClear.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    
                    Button(action: {
                        viewModel.clearCache()
                    }) {
                        HStack {
                            Text("Clear Cache")
                            Spacer()
                            if viewModel.showingClearCacheSuccess {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .foregroundColor(.red)
                    
                    Button(action: {
                        viewModel.exportSettings()
                    }) {
                        HStack {
                            Label("Export Settings", systemImage: "square.and.arrow.up")
                            Spacer()
                            if viewModel.showingExportSuccess {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    
                    Button(action: {
                        showingDocumentPicker = true
                    }) {
                        HStack {
                            Label("Import Settings", systemImage: "square.and.arrow.down")
                            Spacer()
                            if viewModel.showingImportSuccess {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                } header: {
                    Label("Data", systemImage: "externaldrive")
                }
                
                // MARK: - About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(viewModel.appVersion) (\(viewModel.buildNumber))")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://briefeed.app/privacy")!) {
                        HStack {
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Link(destination: URL(string: "https://briefeed.app/terms")!) {
                        HStack {
                            Text("Terms of Service")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: {
                        showingResetAlert = true
                    }) {
                        Text("Reset All Settings")
                            .foregroundColor(.red)
                    }
                } header: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .navigationTitle("Settings")
            .alert("Reset Settings?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    viewModel.userDefaultsManager.resetToDefaults()
                }
            } message: {
                Text("This will reset all settings to their default values. API keys will be removed.")
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .sheet(isPresented: $showingProcessingHistory) {
                ProcessingStatusHistoryView()
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker(
                    onPick: { url in
                        viewModel.importSettings(from: url)
                    }
                )
            }
        }
    }
    
    private func updateColorScheme(isDark: Bool) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.windows.forEach { window in
                window.overrideUserInterfaceStyle = isDark ? .dark : .light
            }
        }
    }
}

// MARK: - API Key Row Component
struct APIKeyRow: View {
    let service: APIService
    @Binding var apiKey: String
    let isValidating: Bool
    let isValid: Bool?
    let onSave: () -> Void
    let onRemove: () -> Void
    
    @State private var isEditing = false
    @State private var showKey = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(service.name)
                Spacer()
                
                if isValidating {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let isValid = isValid {
                    Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isValid ? .green : .red)
                }
            }
            
            if isEditing {
                HStack {
                    if showKey {
                        TextField(service.placeholder, text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    } else {
                        SecureField(service.placeholder, text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    
                    Button(action: { showKey.toggle() }) {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Button("Cancel") {
                        isEditing = false
                        showKey = false
                    }
                    .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Save") {
                        onSave()
                        isEditing = false
                        showKey = false
                    }
                    .disabled(apiKey.isEmpty)
                }
                .font(.caption)
            } else {
                HStack {
                    if apiKey.isEmpty {
                        Text("Not configured")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        Text("••••••••••••")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    Spacer()
                    
                    if !apiKey.isEmpty {
                        Button("Remove") {
                            onRemove()
                        }
                        .foregroundColor(.red)
                        .font(.caption)
                    }
                    
                    Button(apiKey.isEmpty ? "Add" : "Edit") {
                        isEditing = true
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Document Picker
struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
    }
}

#Preview {
    SettingsView()
}