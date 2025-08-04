//
//  SleepTimerManager.swift
//  Briefeed
//
//  Created by Briefeed Team on 1/8/25.
//

import Foundation
import Combine

// MARK: - Sleep Timer Options
enum SleepTimerOption: CaseIterable {
    case endOfTrack
    case minutes15
    case minutes30
    case minutes45
    case minutes60
    case minutes90
    
    var displayName: String {
        switch self {
        case .endOfTrack:
            return "End of Track"
        case .minutes15:
            return "15 minutes"
        case .minutes30:
            return "30 minutes"
        case .minutes45:
            return "45 minutes"
        case .minutes60:
            return "1 hour"
        case .minutes90:
            return "1.5 hours"
        }
    }
    
    var timeInterval: TimeInterval? {
        switch self {
        case .endOfTrack:
            return nil // Will be handled differently
        case .minutes15:
            return 15 * 60
        case .minutes30:
            return 30 * 60
        case .minutes45:
            return 45 * 60
        case .minutes60:
            return 60 * 60
        case .minutes90:
            return 90 * 60
        }
    }
}

// MARK: - Sleep Timer Manager
final class SleepTimerManager: ObservableObject {
    static let shared = SleepTimerManager()
    
    // Published properties
    @Published private(set) var isActive = false
    @Published private(set) var selectedOption: SleepTimerOption?
    @Published private(set) var remainingTime: TimeInterval = 0
    @Published private(set) var endOfTrackEnabled = false
    
    // Timer management
    private var timer: Timer?
    private var startTime: Date?
    private var duration: TimeInterval?
    
    // Callbacks
    var onTimerExpired: (() -> Void)?
    var onEndOfTrackExpired: (() -> Void)?
    
    // Settings
    private let fadeOutDuration: TimeInterval = 3.0 // 3 seconds fade out
    var enableFadeOut = true
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start sleep timer with selected option
    func startTimer(option: SleepTimerOption) {
        stopTimer()
        
        selectedOption = option
        isActive = true
        
        switch option {
        case .endOfTrack:
            endOfTrackEnabled = true
            // Timer will be triggered by audio player when track ends
            
        default:
            if let interval = option.timeInterval {
                duration = interval
                remainingTime = interval
                startTime = Date()
                
                // Create timer that fires every second
                timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    self?.updateRemainingTime()
                }
            }
        }
    }
    
    /// Stop sleep timer
    func stopTimer() {
        timer?.invalidate()
        timer = nil
        
        isActive = false
        selectedOption = nil
        remainingTime = 0
        endOfTrackEnabled = false
        startTime = nil
        duration = nil
    }
    
    /// Check if should stop at end of current track
    func shouldStopAtEndOfTrack() -> Bool {
        return isActive && endOfTrackEnabled
    }
    
    /// Notify that track has ended (for end of track timer)
    func notifyTrackEnded() {
        if shouldStopAtEndOfTrack() {
            DispatchQueue.main.async {
                self.handleTimerExpired()
            }
        }
    }
    
    /// Get formatted remaining time string
    func formattedRemainingTime() -> String {
        if endOfTrackEnabled {
            return "End of Track"
        }
        
        let minutes = Int(remainingTime) / 60
        let seconds = Int(remainingTime) % 60
        
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%d:%02d:%02d", hours, remainingMinutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Get progress (0.0 to 1.0) for visual indicators
    func getProgress() -> Double {
        guard let duration = duration, duration > 0 else {
            return endOfTrackEnabled ? 1.0 : 0.0
        }
        
        return max(0, min(1, (duration - remainingTime) / duration))
    }
    
    // MARK: - Private Methods
    
    private func updateRemainingTime() {
        guard let startTime = startTime,
              let duration = duration else {
            return
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        remainingTime = max(0, duration - elapsed)
        
        if remainingTime <= 0 {
            handleTimerExpired()
        } else if enableFadeOut && remainingTime <= fadeOutDuration {
            // Start fade out if enabled
            let fadeProgress = remainingTime / fadeOutDuration
            NotificationCenter.default.post(
                name: .sleepTimerFadeOut,
                object: nil,
                userInfo: ["progress": fadeProgress]
            )
        }
    }
    
    private func handleTimerExpired() {
        let wasEndOfTrack = endOfTrackEnabled
        
        stopTimer()
        
        // Notify via callback
        if wasEndOfTrack {
            onEndOfTrackExpired?()
        } else {
            onTimerExpired?()
        }
        
        // Post notification
        NotificationCenter.default.post(name: .sleepTimerExpired, object: nil)
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let sleepTimerExpired = Notification.Name("BriefeedSleepTimerExpired")
    static let sleepTimerFadeOut = Notification.Name("BriefeedSleepTimerFadeOut")
}

// MARK: - User Defaults Extension
extension SleepTimerManager {
    private static let lastUsedOptionKey = "BriefeedLastUsedSleepTimerOption"
    
    /// Save last used option
    func saveLastUsedOption(_ option: SleepTimerOption) {
        let index = SleepTimerOption.allCases.firstIndex(of: option) ?? 0
        UserDefaults.standard.set(index, forKey: Self.lastUsedOptionKey)
    }
    
    /// Get last used option
    func getLastUsedOption() -> SleepTimerOption? {
        let index = UserDefaults.standard.integer(forKey: Self.lastUsedOptionKey)
        guard index < SleepTimerOption.allCases.count else { return nil }
        return SleepTimerOption.allCases[index]
    }
}