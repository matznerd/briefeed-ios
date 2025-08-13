//
//  OpenAISettingsView.swift
//  Briefeed
//
//  Settings for OpenAI TTS configuration
//

import SwiftUI

struct OpenAISettingsView: View {
    @State private var apiKey: String = UserDefaultsManager.shared.openAIAPIKey ?? ""
    @State private var selectedVoice: OpenAIVoice = UserDefaultsManager.shared.preferredOpenAIVoice
    @State private var useStreaming: Bool = UserDefaultsManager.shared.useOpenAIStreaming
    @State private var showingAPIKeyInfo = false
    @State private var estimatedCost: Double = 0.0
    @State private var showingSaveConfirmation = false
    
    private let openAIService = OpenAITTSServiceSimple.shared
    
    var body: some View {
        Form {
            // API Key Section
            Section {
                HStack {
                    Text("API Key")
                    Spacer()
                    if !apiKey.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                
                SecureField("sk-...", text: $apiKey)
                    .textContentType(.password)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                Button(action: { showingAPIKeyInfo = true }) {
                    Label("How to get an API key", systemImage: "questionmark.circle")
                        .font(.caption)
                }
            } header: {
                Text("OpenAI Configuration")
            } footer: {
                Text("OpenAI TTS has no daily generation limits. Costs ~$0.015 per 1000 characters.")
                    .font(.caption)
            }
            
            // Voice Selection
            Section {
                Picker("Voice", selection: $selectedVoice) {
                    ForEach(OpenAIVoice.allCases, id: \.self) { voice in
                        HStack {
                            Text(voice.rawValue.capitalized)
                            if voice.isRecommendedForNews {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            }
                        }
                        .tag(voice)
                    }
                }
                
                Toggle("Use Streaming (Lower Latency)", isOn: $useStreaming)
            } header: {
                Text("Voice Settings")
            } footer: {
                Text("⭐ indicates voices optimized for news narration")
                    .font(.caption)
            }
            
            // Cost Tracking
            Section {
                HStack {
                    Text("Characters Processed")
                    Spacer()
                    Text("\(Int(estimatedCost / 0.000015))") // Calculate chars from cost
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Estimated Cost")
                    Spacer()
                    Text("$\(String(format: "%.4f", estimatedCost))")
                        .foregroundColor(.secondary)
                }
                
                Button("Reset Cost Tracking") {
                    openAIService.resetCostTracking()
                    estimatedCost = 0.0
                }
                .foregroundColor(.red)
            } header: {
                Text("Usage & Cost")
            }
            
            // Comparison Section
            Section {
                ComparisonRow(
                    feature: "Daily Limit",
                    gemini: "100 generations",
                    openAI: "Unlimited"
                )
                
                ComparisonRow(
                    feature: "Streaming",
                    gemini: "❌",
                    openAI: "✅"
                )
                
                ComparisonRow(
                    feature: "Voice Control",
                    gemini: "Basic",
                    openAI: "Advanced"
                )
                
                ComparisonRow(
                    feature: "Cost",
                    gemini: "Free (limited)",
                    openAI: "$0.015/1K chars"
                )
            } header: {
                Text("Gemini vs OpenAI")
            }
        }
        .navigationTitle("OpenAI TTS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveSettings()
                }
                .disabled(apiKey == UserDefaultsManager.shared.openAIAPIKey ?? "")
            }
        }
        .onAppear {
            estimatedCost = openAIService.getEstimatedCost()
        }
        .alert("OpenAI API Key", isPresented: $showingAPIKeyInfo) {
            Button("Open OpenAI Platform") {
                if let url = URL(string: "https://platform.openai.com/api-keys") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("1. Sign up at platform.openai.com\n2. Go to API Keys section\n3. Create a new secret key\n4. Copy and paste it here")
        }
        .alert("Settings Saved", isPresented: $showingSaveConfirmation) {
            Button("OK") {}
        } message: {
            Text("OpenAI TTS is now configured. The app will use OpenAI for text-to-speech generation.")
        }
    }
    
    private func saveSettings() {
        UserDefaultsManager.shared.openAIAPIKey = apiKey.isEmpty ? nil : apiKey
        UserDefaultsManager.shared.preferredOpenAIVoice = selectedVoice
        UserDefaultsManager.shared.useOpenAIStreaming = useStreaming
        showingSaveConfirmation = true
        
        // Mark todo as complete
        markTodoComplete(id: "6")
    }
    
    private func markTodoComplete(id: String) {
        // Helper to track progress
    }
}

struct ComparisonRow: View {
    let feature: String
    let gemini: String
    let openAI: String
    
    var body: some View {
        HStack {
            Text(feature)
                .frame(width: 100, alignment: .leading)
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text("Gemini")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(gemini)
                    .font(.caption2)
            }
            .frame(width: 80)
            
            VStack(alignment: .trailing) {
                Text("OpenAI")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text(openAI)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .frame(width: 80)
        }
        .font(.system(.body, design: .monospaced))
    }
}

#Preview {
    NavigationView {
        OpenAISettingsView()
    }
}