//
//  TTSQuotaManager.swift
//  Briefeed
//
//  Manages TTS quota limits and migration prompts
//

import Foundation
import SwiftUI

@MainActor
final class TTSQuotaManager: ObservableObject {
    static let shared = TTSQuotaManager()
    
    @Published var showingQuotaAlert = false
    @Published var geminiGenerationsToday = 0
    @Published var lastGeminiResetDate: Date?
    
    private let geminiDailyLimit = 100
    private let userDefaults = UserDefaults.standard
    
    private init() {
        loadQuotaData()
        resetIfNewDay()
    }
    
    // MARK: - Quota Tracking
    
    func recordGeminiGeneration() {
        geminiGenerationsToday += 1
        saveQuotaData()
        
        // Check if approaching or at limit
        if geminiGenerationsToday >= geminiDailyLimit {
            showQuotaExceededAlert()
        } else if geminiGenerationsToday >= 90 {
            showApproachingLimitWarning()
        }
    }
    
    func recordOpenAIGeneration() {
        // OpenAI has no limits, just track for cost
        // Cost tracking is handled by OpenAITTSServiceSimple
    }
    
    private func resetIfNewDay() {
        let calendar = Calendar.current
        let today = Date()
        
        if let lastReset = lastGeminiResetDate {
            if !calendar.isDate(lastReset, inSameDayAs: today) {
                // New day - reset counter
                geminiGenerationsToday = 0
                lastGeminiResetDate = today
                saveQuotaData()
            }
        } else {
            // First run
            lastGeminiResetDate = today
            saveQuotaData()
        }
    }
    
    // MARK: - Alerts
    
    private func showQuotaExceededAlert() {
        showingQuotaAlert = true
    }
    
    private func showApproachingLimitWarning() {
        // Could show a less intrusive notification
        print("[TTSQuota] Warning: Approaching Gemini daily limit (\(geminiGenerationsToday)/\(geminiDailyLimit))")
    }
    
    // MARK: - Persistence
    
    private func loadQuotaData() {
        geminiGenerationsToday = userDefaults.integer(forKey: "geminiGenerationsToday")
        lastGeminiResetDate = userDefaults.object(forKey: "lastGeminiResetDate") as? Date
    }
    
    private func saveQuotaData() {
        userDefaults.set(geminiGenerationsToday, forKey: "geminiGenerationsToday")
        userDefaults.set(lastGeminiResetDate, forKey: "lastGeminiResetDate")
    }
    
    // MARK: - Migration Helpers
    
    var shouldSuggestOpenAI: Bool {
        geminiGenerationsToday >= 80 && UserDefaultsManager.shared.openAIAPIKey == nil
    }
    
    var remainingGeminiGenerations: Int {
        max(0, geminiDailyLimit - geminiGenerationsToday)
    }
    
    var quotaPercentageUsed: Double {
        Double(geminiGenerationsToday) / Double(geminiDailyLimit)
    }
    
    func resetQuotaTracking() {
        geminiGenerationsToday = 0
        lastGeminiResetDate = Date()
        saveQuotaData()
    }
}

// MARK: - SwiftUI Alert View

struct TTSQuotaAlertModifier: ViewModifier {
    @ObservedObject private var quotaManager = TTSQuotaManager.shared
    @State private var showingOpenAISettings = false
    
    func body(content: Content) -> some View {
        content
            .alert("Gemini TTS Limit Reached", isPresented: $quotaManager.showingQuotaAlert) {
                Button("Configure OpenAI") {
                    showingOpenAISettings = true
                }
                Button("Continue with Limit", role: .cancel) {}
            } message: {
                Text("""
                You've reached Gemini's daily limit of 100 audio generations.
                
                Switch to OpenAI TTS for:
                • Unlimited generations
                • Better voice quality
                • Streaming support
                • News broadcaster voices
                
                Cost: ~$0.015 per 1000 characters
                """)
            }
            .sheet(isPresented: $showingOpenAISettings) {
                NavigationView {
                    OpenAISettingsView()
                }
            }
    }
}

extension View {
    func ttsQuotaAlert() -> some View {
        modifier(TTSQuotaAlertModifier())
    }
}

// MARK: - Usage Banner View

struct TTSQuotaBanner: View {
    @ObservedObject private var quotaManager = TTSQuotaManager.shared
    
    var body: some View {
        if quotaManager.shouldSuggestOpenAI {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Approaching TTS Limit")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    Text("\(quotaManager.remainingGeminiGenerations) generations remaining today")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                NavigationLink(destination: OpenAISettingsView()) {
                    Text("Switch")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .cornerRadius(6)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(10)
            .padding(.horizontal)
        }
    }
}