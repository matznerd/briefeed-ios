//
//  HapticManager.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import UIKit

/// Manages haptic feedback throughout the app
class HapticManager {
    
    // MARK: - Singleton
    static let shared = HapticManager()
    
    // MARK: - Haptic Generators
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()
    
    // MARK: - Initialization
    private init() {
        // Prepare generators for immediate use
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        selection.prepare()
        notification.prepare()
    }
    
    // MARK: - Public Methods
    
    /// Triggers a light impact haptic
    func lightImpact() {
        impactLight.impactOccurred()
        impactLight.prepare() // Prepare for next use
    }
    
    /// Triggers a medium impact haptic
    func mediumImpact() {
        impactMedium.impactOccurred()
        impactMedium.prepare() // Prepare for next use
    }
    
    /// Triggers a heavy impact haptic
    func heavyImpact() {
        impactHeavy.impactOccurred()
        impactHeavy.prepare() // Prepare for next use
    }
    
    /// Triggers a selection haptic
    func selectionChanged() {
        selection.selectionChanged()
        selection.prepare() // Prepare for next use
    }
    
    /// Triggers a success notification haptic
    func notificationSuccess() {
        notification.notificationOccurred(.success)
        notification.prepare() // Prepare for next use
    }
    
    /// Triggers a warning notification haptic
    func notificationWarning() {
        notification.notificationOccurred(.warning)
        notification.prepare() // Prepare for next use
    }
    
    /// Triggers an error notification haptic
    func notificationError() {
        notification.notificationOccurred(.error)
        notification.prepare() // Prepare for next use
    }
    
    /// Triggers haptic feedback for swipe actions
    func swipeAction() {
        mediumImpact()
    }
    
    /// Triggers haptic feedback when swipe threshold is reached
    func swipeThresholdReached() {
        lightImpact()
    }
    
    /// Triggers haptic feedback for archive action
    func archiveAction() {
        notificationSuccess()
    }
    
    /// Triggers haptic feedback for save action
    func saveAction() {
        notificationSuccess()
    }
}