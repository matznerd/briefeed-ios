//
//  SettingsViewModel.swift
//  Briefeed
//
//  Created by Assistant on 6/21/25.
//

import Foundation
import SwiftUI
import Combine

class SettingsViewModel: ObservableObject {
    @Published var userDefaultsManager = UserDefaultsManager.shared
    @Published var cacheSize: String = "Calculating..."
    @Published var isValidatingGeminiKey = false
    @Published var isValidatingFirecrawlKey = false
    @Published var geminiKeyValid: Bool?
    @Published var firecrawlKeyValid: Bool?
    @Published var showingExportSuccess = false
    @Published var showingImportSuccess = false
    @Published var showingClearCacheSuccess = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    private let fileManager = FileManager.default
    
    // Temporary storage for API keys during editing
    @Published var tempGeminiKey: String = ""
    @Published var tempFirecrawlKey: String = ""
    
    init() {
        loadAPIKeys()
        calculateCacheSize()
        setupBindings()
    }
    
    private func setupBindings() {
        // Load settings on init
        userDefaultsManager.loadSettings()
    }
    
    private func loadAPIKeys() {
        tempGeminiKey = userDefaultsManager.geminiAPIKey ?? ""
        tempFirecrawlKey = userDefaultsManager.firecrawlAPIKey ?? ""
    }
    
    // MARK: - Cache Management
    func calculateCacheSize() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            let cacheSize = self?.getCacheDirectorySize() ?? 0
            let formattedSize = self?.formatBytes(cacheSize) ?? "0 MB"
            
            DispatchQueue.main.async {
                self?.cacheSize = formattedSize
            }
        }
    }
    
    private func getCacheDirectorySize() -> Int64 {
        guard let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return 0
        }
        
        return directorySize(at: cacheURL)
    }
    
    private func directorySize(at url: URL) -> Int64 {
        var size: Int64 = 0
        
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) {
            for case let fileURL as URL in enumerator {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
                    size += Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
                } catch {
                    continue
                }
            }
        }
        
        return size
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    func clearCache() {
        guard let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)
            for url in contents {
                try fileManager.removeItem(at: url)
            }
            
            userDefaultsManager.lastCacheClear = Date()
            calculateCacheSize()
            showingClearCacheSuccess = true
            
            // Hide success message after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.showingClearCacheSuccess = false
            }
        } catch {
            errorMessage = "Failed to clear cache: \(error.localizedDescription)"
        }
    }
    
    // MARK: - API Key Validation
    func validateGeminiKey() {
        guard !tempGeminiKey.isEmpty else {
            geminiKeyValid = false
            return
        }
        
        isValidatingGeminiKey = true
        geminiKeyValid = nil
        
        // Simulate API validation (in real app, make actual API call)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            
            // Basic validation - check if key matches expected format
            let isValid = self.tempGeminiKey.count >= 39 && self.tempGeminiKey.starts(with: "AI")
            
            self.geminiKeyValid = isValid
            self.isValidatingGeminiKey = false
            
            if isValid {
                self.userDefaultsManager.geminiAPIKey = self.tempGeminiKey
            }
        }
    }
    
    func validateFirecrawlKey() {
        guard !tempFirecrawlKey.isEmpty else {
            firecrawlKeyValid = false
            return
        }
        
        isValidatingFirecrawlKey = true
        firecrawlKeyValid = nil
        
        // Simulate API validation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            
            // Basic validation - check if key matches expected format
            let isValid = self.tempFirecrawlKey.count >= 32
            
            self.firecrawlKeyValid = isValid
            self.isValidatingFirecrawlKey = false
            
            if isValid {
                self.userDefaultsManager.firecrawlAPIKey = self.tempFirecrawlKey
            }
        }
    }
    
    func saveAPIKey(for service: APIService) {
        switch service {
        case .gemini:
            if !tempGeminiKey.isEmpty {
                userDefaultsManager.geminiAPIKey = tempGeminiKey
                validateGeminiKey()
            }
        case .firecrawl:
            if !tempFirecrawlKey.isEmpty {
                userDefaultsManager.firecrawlAPIKey = tempFirecrawlKey
                validateFirecrawlKey()
            }
        }
    }
    
    func removeAPIKey(for service: APIService) {
        switch service {
        case .gemini:
            userDefaultsManager.geminiAPIKey = nil
            tempGeminiKey = ""
            geminiKeyValid = nil
        case .firecrawl:
            userDefaultsManager.firecrawlAPIKey = nil
            tempFirecrawlKey = ""
            firecrawlKeyValid = nil
        }
    }
    
    // MARK: - Export/Import Settings
    func exportSettings() {
        let settings = userDefaultsManager.exportSettings()
        
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = documentsURL.appendingPathComponent("briefeed_settings.json")
            
            try data.write(to: fileURL)
            showingExportSuccess = true
            
            // Hide success message after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.showingExportSuccess = false
            }
        } catch {
            errorMessage = "Failed to export settings: \(error.localizedDescription)"
        }
    }
    
    func importSettings(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            if let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                userDefaultsManager.importSettings(settings)
                loadAPIKeys() // Reload API keys to UI
                showingImportSuccess = true
                
                // Hide success message after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.showingImportSuccess = false
                }
            }
        } catch {
            errorMessage = "Failed to import settings: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Font Options
    var availableFonts: [String] {
        ["System", "San Francisco", "New York", "Georgia", "Times New Roman", "Helvetica", "Arial"]
    }
    
    // MARK: - About Info
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - API Service Enum
enum APIService {
    case gemini
    case firecrawl
    
    var name: String {
        switch self {
        case .gemini: return "Gemini"
        case .firecrawl: return "Firecrawl"
        }
    }
    
    var placeholder: String {
        switch self {
        case .gemini: return "Enter your Gemini API key"
        case .firecrawl: return "Enter your Firecrawl API key"
        }
    }
}