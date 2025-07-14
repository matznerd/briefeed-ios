//
//  UserDefaultsManager.swift
//  Briefeed
//
//  Created by Assistant on 6/21/25.
//

import Foundation
import SwiftUI

// MARK: - UserDefaults Keys
enum UserDefaultsKey: String, CaseIterable {
    // Appearance
    case theme = "theme" // system, light, dark
    case isDarkMode = "isDarkMode" // deprecated, kept for migration
    case textSize = "textSize"
    
    // Reading
    case summaryLength = "summaryLength"
    case preferredReadingFont = "preferredReadingFont"
    
    // Audio
    case speechRate = "speechRate"
    case audioEnabled = "audioEnabled"
    case autoPlayAudio = "autoPlayAudio"
    case autoQueueAudio = "autoQueueAudio"
    case ttsVoice = "ttsVoice"
    case ttsLanguage = "ttsLanguage"
    case useDeviceTTS = "useDeviceTTS"
    case selectedVoice = "selectedVoice"
    case autoPlayNext = "autoPlayNext"
    case playbackSpeed = "playbackSpeed"
    
    // API Keys
    case geminiAPIKey = "geminiAPIKey"
    case firecrawlAPIKey = "firecrawlAPIKey"
    
    // Data
    case lastCacheClear = "lastCacheClear"
    case onboardingCompleted = "onboardingCompleted"
    case hasCreatedDefaultFeeds = "hasCreatedDefaultFeeds"
    
    // Preferences
    case defaultFeedRefreshInterval = "defaultFeedRefreshInterval"
    case articlesPerPage = "articlesPerPage"
    case currentFeedSort = "currentFeedSort"
}

// MARK: - Summary Length Options
enum SummaryLength: String, CaseIterable {
    case brief = "Brief"
    case medium = "Medium"
    case detailed = "Detailed"
    
    var maxTokens: Int {
        switch self {
        case .brief: return 150
        case .medium: return 300
        case .detailed: return 500
        }
    }
}

// MARK: - UserDefaults Manager
class UserDefaultsManager: ObservableObject {
    static let shared = UserDefaultsManager()
    internal let userDefaults = UserDefaults.standard
    
    private init() {
        registerDefaults()
        loadSettings()
    }
    
    // MARK: - Register Default Values
    private func registerDefaults() {
        let defaults: [String: Any] = [
            UserDefaultsKey.theme.rawValue: "system",
            UserDefaultsKey.isDarkMode.rawValue: false,
            UserDefaultsKey.textSize.rawValue: 16.0,
            UserDefaultsKey.summaryLength.rawValue: SummaryLength.medium.rawValue,
            UserDefaultsKey.speechRate.rawValue: 1.0,
            UserDefaultsKey.audioEnabled.rawValue: true,
            UserDefaultsKey.autoPlayAudio.rawValue: false,
            UserDefaultsKey.autoQueueAudio.rawValue: true,
            UserDefaultsKey.ttsVoice.rawValue: "com.apple.ttsbundle.Samantha-compact",
            UserDefaultsKey.ttsLanguage.rawValue: "en-US",
            UserDefaultsKey.useDeviceTTS.rawValue: false,
            UserDefaultsKey.selectedVoice.rawValue: "Autonoe",
            UserDefaultsKey.autoPlayNext.rawValue: true,
            UserDefaultsKey.playbackSpeed.rawValue: 1.0,
            UserDefaultsKey.onboardingCompleted.rawValue: false,
            UserDefaultsKey.hasCreatedDefaultFeeds.rawValue: false,
            UserDefaultsKey.defaultFeedRefreshInterval.rawValue: 3600, // 1 hour
            UserDefaultsKey.articlesPerPage.rawValue: 20,
            UserDefaultsKey.preferredReadingFont.rawValue: "System",
            UserDefaultsKey.currentFeedSort.rawValue: "hot",
            // RSS defaults
            "autoPlayLiveNewsOnOpen": false,
            "autoRefreshLiveNewsOnOpen": true,
            "rssPlaybackSpeed": 1.0,
            "defaultBriefFilter": "all",
            "rssRetentionHours": 168
            // API keys should be set by the user, not hardcoded
        ]
        userDefaults.register(defaults: defaults)
    }
    
    // MARK: - Appearance Settings
    @Published var theme: String = "system" {
        didSet {
            userDefaults.set(theme, forKey: UserDefaultsKey.theme.rawValue)
            NotificationCenter.default.post(name: Notification.Name("ThemeChanged"), object: nil)
        }
    }
    
    @Published var isDarkMode: Bool = false {
        didSet {
            userDefaults.set(isDarkMode, forKey: UserDefaultsKey.isDarkMode.rawValue)
            NotificationCenter.default.post(name: Notification.Name("ThemeChanged"), object: nil)
        }
    }
    
    @Published var textSize: Double = 16.0 {
        didSet {
            userDefaults.set(textSize, forKey: UserDefaultsKey.textSize.rawValue)
        }
    }
    
    // MARK: - Reading Settings
    @Published var summaryLength: SummaryLength = .medium {
        didSet {
            userDefaults.set(summaryLength.rawValue, forKey: UserDefaultsKey.summaryLength.rawValue)
        }
    }
    
    @Published var preferredReadingFont: String = "System" {
        didSet {
            userDefaults.set(preferredReadingFont, forKey: UserDefaultsKey.preferredReadingFont.rawValue)
        }
    }
    
    // MARK: - Audio Settings
    @Published var speechRate: Double = 1.0 {
        didSet {
            userDefaults.set(speechRate, forKey: UserDefaultsKey.speechRate.rawValue)
        }
    }
    
    @Published var audioEnabled: Bool = true {
        didSet {
            userDefaults.set(audioEnabled, forKey: UserDefaultsKey.audioEnabled.rawValue)
        }
    }
    
    @Published var autoPlayAudio: Bool = false {
        didSet {
            userDefaults.set(autoPlayAudio, forKey: UserDefaultsKey.autoPlayAudio.rawValue)
        }
    }
    
    // Convenience property for MiniAudioPlayer
    var autoPlayEnabled: Bool {
        get { autoPlayAudio }
        set { autoPlayAudio = newValue }
    }
    
    @Published var autoQueueAudio: Bool = true {
        didSet {
            userDefaults.set(autoQueueAudio, forKey: UserDefaultsKey.autoQueueAudio.rawValue)
        }
    }
    
    @Published var ttsVoice: String = "com.apple.ttsbundle.Samantha-compact" {
        didSet {
            userDefaults.set(ttsVoice, forKey: UserDefaultsKey.ttsVoice.rawValue)
        }
    }
    
    @Published var ttsLanguage: String = "en-US" {
        didSet {
            userDefaults.set(ttsLanguage, forKey: UserDefaultsKey.ttsLanguage.rawValue)
        }
    }
    
    @Published var useDeviceTTS: Bool = false {
        didSet {
            userDefaults.set(useDeviceTTS, forKey: UserDefaultsKey.useDeviceTTS.rawValue)
        }
    }
    
    @Published var selectedVoice: String = "Autonoe" {
        didSet {
            userDefaults.set(selectedVoice, forKey: UserDefaultsKey.selectedVoice.rawValue)
        }
    }
    
    @Published var autoPlayNext: Bool = true {
        didSet {
            userDefaults.set(autoPlayNext, forKey: UserDefaultsKey.autoPlayNext.rawValue)
        }
    }
    
    @Published var playbackSpeed: Float = 1.0 {
        didSet {
            userDefaults.set(playbackSpeed, forKey: UserDefaultsKey.playbackSpeed.rawValue)
        }
    }
    
    // MARK: - RSS Settings
    @Published var autoPlayLiveNewsOnOpen: Bool = false {
        didSet {
            userDefaults.set(autoPlayLiveNewsOnOpen, forKey: "autoPlayLiveNewsOnOpen")
        }
    }
    
    @Published var autoRefreshLiveNewsOnOpen: Bool = true {
        didSet {
            userDefaults.set(autoRefreshLiveNewsOnOpen, forKey: "autoRefreshLiveNewsOnOpen")
        }
    }
    
    @Published var rssPlaybackSpeed: Float = 1.0 {
        didSet {
            userDefaults.set(rssPlaybackSpeed, forKey: "rssPlaybackSpeed")
        }
    }
    
    var defaultBriefFilter: String {
        get {
            userDefaults.string(forKey: "defaultBriefFilter") ?? "all"
        }
        set {
            userDefaults.set(newValue, forKey: "defaultBriefFilter")
        }
    }
    
    @Published var rssRetentionHours: Int = 168 {
        didSet {
            userDefaults.set(rssRetentionHours, forKey: "rssRetentionHours")
        }
    }
    
    // MARK: - API Keys
    var geminiAPIKey: String? {
        get {
            userDefaults.string(forKey: UserDefaultsKey.geminiAPIKey.rawValue)
        }
        set {
            if let newValue = newValue, !newValue.isEmpty {
                userDefaults.set(newValue, forKey: UserDefaultsKey.geminiAPIKey.rawValue)
            } else {
                userDefaults.removeObject(forKey: UserDefaultsKey.geminiAPIKey.rawValue)
            }
        }
    }
    
    var firecrawlAPIKey: String? {
        get {
            userDefaults.string(forKey: UserDefaultsKey.firecrawlAPIKey.rawValue)
        }
        set {
            if let newValue = newValue, !newValue.isEmpty {
                userDefaults.set(newValue, forKey: UserDefaultsKey.firecrawlAPIKey.rawValue)
            } else {
                userDefaults.removeObject(forKey: UserDefaultsKey.firecrawlAPIKey.rawValue)
            }
        }
    }
    
    // MARK: - Data Settings
    var lastCacheClear: Date? {
        get {
            userDefaults.object(forKey: UserDefaultsKey.lastCacheClear.rawValue) as? Date
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultsKey.lastCacheClear.rawValue)
        }
    }
    
    var onboardingCompleted: Bool {
        get {
            userDefaults.bool(forKey: UserDefaultsKey.onboardingCompleted.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultsKey.onboardingCompleted.rawValue)
        }
    }
    
    // MARK: - Additional Preferences
    var defaultFeedRefreshInterval: TimeInterval {
        get {
            userDefaults.double(forKey: UserDefaultsKey.defaultFeedRefreshInterval.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultsKey.defaultFeedRefreshInterval.rawValue)
        }
    }
    
    var articlesPerPage: Int {
        get {
            userDefaults.integer(forKey: UserDefaultsKey.articlesPerPage.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultsKey.articlesPerPage.rawValue)
        }
    }
    
    var hasCreatedDefaultFeeds: Bool {
        get {
            userDefaults.bool(forKey: UserDefaultsKey.hasCreatedDefaultFeeds.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultsKey.hasCreatedDefaultFeeds.rawValue)
        }
    }
    
    var currentFeedSort: String {
        get {
            userDefaults.string(forKey: UserDefaultsKey.currentFeedSort.rawValue) ?? "hot"
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultsKey.currentFeedSort.rawValue)
        }
    }
    
    // MARK: - Load Settings
    func loadSettings() {
        theme = userDefaults.string(forKey: UserDefaultsKey.theme.rawValue) ?? "system"
        isDarkMode = userDefaults.bool(forKey: UserDefaultsKey.isDarkMode.rawValue)
        textSize = userDefaults.double(forKey: UserDefaultsKey.textSize.rawValue)
        
        if let summaryLengthRaw = userDefaults.string(forKey: UserDefaultsKey.summaryLength.rawValue),
           let summaryLength = SummaryLength(rawValue: summaryLengthRaw) {
            self.summaryLength = summaryLength
        } else {
            self.summaryLength = .medium
        }
        
        preferredReadingFont = userDefaults.string(forKey: UserDefaultsKey.preferredReadingFont.rawValue) ?? "System"
        speechRate = userDefaults.double(forKey: UserDefaultsKey.speechRate.rawValue)
        audioEnabled = userDefaults.bool(forKey: UserDefaultsKey.audioEnabled.rawValue)
        autoPlayAudio = userDefaults.bool(forKey: UserDefaultsKey.autoPlayAudio.rawValue)
        autoQueueAudio = userDefaults.bool(forKey: UserDefaultsKey.autoQueueAudio.rawValue)
        ttsVoice = userDefaults.string(forKey: UserDefaultsKey.ttsVoice.rawValue) ?? "com.apple.ttsbundle.Samantha-compact"
        ttsLanguage = userDefaults.string(forKey: UserDefaultsKey.ttsLanguage.rawValue) ?? "en-US"
        useDeviceTTS = userDefaults.bool(forKey: UserDefaultsKey.useDeviceTTS.rawValue)
        selectedVoice = userDefaults.string(forKey: UserDefaultsKey.selectedVoice.rawValue) ?? "Autonoe"
        autoPlayNext = userDefaults.bool(forKey: UserDefaultsKey.autoPlayNext.rawValue)
        playbackSpeed = userDefaults.float(forKey: UserDefaultsKey.playbackSpeed.rawValue)
        
        // Load RSS settings
        autoPlayLiveNewsOnOpen = userDefaults.bool(forKey: "autoPlayLiveNewsOnOpen")
        autoRefreshLiveNewsOnOpen = userDefaults.bool(forKey: "autoRefreshLiveNewsOnOpen")
        rssPlaybackSpeed = userDefaults.float(forKey: "rssPlaybackSpeed")
        rssRetentionHours = userDefaults.integer(forKey: "rssRetentionHours")
    }
    
    // MARK: - Reset Settings
    func resetToDefaults() {
        UserDefaultsKey.allCases.forEach { key in
            userDefaults.removeObject(forKey: key.rawValue)
        }
        registerDefaults()
        loadSettings()
    }
    
    // MARK: - Export/Import Settings
    func exportSettings() -> [String: Any] {
        var settings: [String: Any] = [:]
        
        UserDefaultsKey.allCases.forEach { key in
            if let value = userDefaults.object(forKey: key.rawValue) {
                // Don't export sensitive API keys
                if key != .geminiAPIKey && key != .firecrawlAPIKey {
                    settings[key.rawValue] = value
                }
            }
        }
        
        return settings
    }
    
    func importSettings(_ settings: [String: Any]) {
        settings.forEach { key, value in
            // Don't import API keys for security
            if key != UserDefaultsKey.geminiAPIKey.rawValue && 
               key != UserDefaultsKey.firecrawlAPIKey.rawValue {
                userDefaults.set(value, forKey: key)
            }
        }
        loadSettings()
    }
}

// MARK: - Property Wrapper for UserDefaults
@propertyWrapper
struct UserDefault<T> {
    let key: UserDefaultsKey
    let defaultValue: T
    
    init(_ key: UserDefaultsKey, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }
    
    var wrappedValue: T {
        get {
            UserDefaults.standard.object(forKey: key.rawValue) as? T ?? defaultValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key.rawValue)
        }
    }
}