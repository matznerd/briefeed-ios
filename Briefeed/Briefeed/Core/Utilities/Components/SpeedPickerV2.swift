//
//  SpeedPickerV2.swift
//  Briefeed
//
//  Enhanced speed picker supporting up to 20x playback with SwiftAudioEx
//

import SwiftUI

struct SpeedPickerV2: View {
    @Binding var selectedSpeed: Float
    @State private var isExpanded = false
    
    // Organized speed options with sections
    let standardSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    let fastSpeeds: [Float] = [2.5, 3.0, 4.0, 5.0]
    let ultraFastSpeeds: [Float] = [8.0, 10.0, 15.0, 20.0]
    
    var allSpeeds: [Float] {
        standardSpeeds + fastSpeeds + ultraFastSpeeds
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Current speed button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                HapticManager.shared.impact(style: .light)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: speedIcon(for: selectedSpeed))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(speedColor(for: selectedSpeed))
                    
                    Text(formatSpeed(selectedSpeed))
                        .font(.system(size: 14, weight: .semibold))
                    
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 0 : 180))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(speedColor(for: selectedSpeed).opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Speed options popup
            if isExpanded {
                VStack(spacing: 0) {
                    // Standard speeds section
                    SpeedSection(
                        title: "Standard",
                        speeds: standardSpeeds,
                        selectedSpeed: $selectedSpeed,
                        onSelect: { 
                            isExpanded = false
                            HapticManager.shared.impact(style: .light)
                        }
                    )
                    
                    Divider()
                        .padding(.horizontal, 16)
                    
                    // Fast speeds section
                    SpeedSection(
                        title: "Fast",
                        speeds: fastSpeeds,
                        selectedSpeed: $selectedSpeed,
                        onSelect: { 
                            isExpanded = false
                            HapticManager.shared.impact(style: .medium)
                        }
                    )
                    
                    Divider()
                        .padding(.horizontal, 16)
                    
                    // Ultra fast speeds section
                    SpeedSection(
                        title: "Ultra Fast 🚀",
                        speeds: ultraFastSpeeds,
                        selectedSpeed: $selectedSpeed,
                        onSelect: { 
                            isExpanded = false
                            HapticManager.shared.impact(style: .heavy)
                        }
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
                )
                .padding(.top, 8)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8, anchor: .top).combined(with: .opacity),
                    removal: .scale(scale: 0.8, anchor: .top).combined(with: .opacity)
                ))
            }
        }
    }
    
    private func formatSpeed(_ speed: Float) -> String {
        if speed == 1.0 {
            return "1x"
        } else if speed == floor(speed) {
            return "\(Int(speed))x"
        } else {
            // Format with up to 2 decimal places, removing trailing zeros
            let formatted = String(format: "%.2f", speed)
            let trimmed = formatted.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
            let final = trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
            return "\(final)x"
        }
    }
    
    private func speedIcon(for speed: Float) -> String {
        switch speed {
        case 0..<1:
            return "tortoise.fill"
        case 1..<2:
            return "hare.fill"
        case 2..<5:
            return "bolt.fill"
        case 5..<10:
            return "bolt.circle.fill"
        default:
            return "bolt.badge.checkmark.fill"
        }
    }
    
    private func speedColor(for speed: Float) -> Color {
        switch speed {
        case 0..<1:
            return .blue
        case 1..<2:
            return .green
        case 2..<5:
            return .orange
        case 5..<10:
            return .red
        default:
            return .purple
        }
    }
}

// MARK: - Speed Section Component

struct SpeedSection: View {
    let title: String
    let speeds: [Float]
    @Binding var selectedSpeed: Float
    let onSelect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Section header
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            
            // Speed options
            ForEach(speeds, id: \.self) { speed in
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        selectedSpeed = speed
                    }
                    onSelect()
                }) {
                    HStack {
                        Image(systemName: speedIcon(for: speed))
                            .font(.system(size: 14))
                            .foregroundColor(speedColor(for: speed))
                            .frame(width: 20)
                        
                        Text(formatSpeed(speed))
                            .font(.system(size: 14, weight: speed == selectedSpeed ? .semibold : .regular))
                        
                        Spacer()
                        
                        if speed == selectedSpeed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .foregroundColor(speed == selectedSpeed ? .accentColor : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if title == "Ultra Fast 🚀" {
                // Add a note about ultra fast speeds
                Text("Powered by SwiftAudioEx")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                // Just padding for other sections
                Color.clear.frame(height: 8)
            }
        }
    }
    
    private func formatSpeed(_ speed: Float) -> String {
        if speed == 1.0 {
            return "1x"
        } else if speed == floor(speed) {
            return "\(Int(speed))x"
        } else {
            let formatted = String(format: "%.2f", speed)
            let trimmed = formatted.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
            let final = trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
            return "\(final)x"
        }
    }
    
    private func speedIcon(for speed: Float) -> String {
        switch speed {
        case 0..<1:
            return "tortoise.fill"
        case 1..<2:
            return "hare.fill"
        case 2..<5:
            return "bolt.fill"
        case 5..<10:
            return "bolt.circle.fill"
        default:
            return "bolt.badge.checkmark.fill"
        }
    }
    
    private func speedColor(for speed: Float) -> Color {
        switch speed {
        case 0..<1:
            return .blue
        case 1..<2:
            return .green
        case 2..<5:
            return .orange
        case 5..<10:
            return .red
        default:
            return .purple
        }
    }
}

// MARK: - Horizontal Speed Selector (for audio player)

struct HorizontalSpeedSelector: View {
    @Binding var selectedSpeed: Float
    @State private var showAllSpeeds = false
    
    // Quick access speeds
    let quickSpeeds: [Float] = [0.5, 1.0, 1.5, 2.0, 3.0]
    let allSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0, 5.0, 8.0, 10.0, 15.0, 20.0]
    
    var displayedSpeeds: [Float] {
        showAllSpeeds ? allSpeeds : quickSpeeds
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Speed selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(displayedSpeeds, id: \.self) { speed in
                        SpeedButton(
                            speed: speed,
                            isSelected: speed == selectedSpeed,
                            action: {
                                selectedSpeed = speed
                                HapticManager.shared.impact(style: .light)
                            }
                        )
                    }
                    
                    // More button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showAllSpeeds.toggle()
                        }
                        HapticManager.shared.impact(style: .light)
                    }) {
                        Image(systemName: showAllSpeeds ? "chevron.left.circle.fill" : "ellipsis.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.1))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)
            }
            
            // Current speed indicator
            if selectedSpeed > 2.0 {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                    Text("Playing at \(formatSpeed(selectedSpeed)) speed")
                        .font(.system(size: 11))
                }
                .foregroundColor(speedColor(for: selectedSpeed))
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func formatSpeed(_ speed: Float) -> String {
        if speed == 1.0 {
            return "1x"
        } else if speed == floor(speed) {
            return "\(Int(speed))x"
        } else {
            let formatted = String(format: "%.2f", speed)
            let trimmed = formatted.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
            let final = trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
            return "\(final)x"
        }
    }
    
    private func speedColor(for speed: Float) -> Color {
        switch speed {
        case 0..<1:
            return .blue
        case 1..<2:
            return .green
        case 2..<5:
            return .orange
        case 5..<10:
            return .red
        default:
            return .purple
        }
    }
}

// MARK: - Speed Button Component

struct SpeedButton: View {
    let speed: Float
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(formatSpeed(speed))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                
                if speed >= 10 {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8))
                }
            }
            .foregroundColor(isSelected ? .white : .primary)
            .frame(width: 52, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? speedColor(for: speed) : Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatSpeed(_ speed: Float) -> String {
        if speed == 1.0 {
            return "1x"
        } else if speed == floor(speed) {
            return "\(Int(speed))x"
        } else {
            let formatted = String(format: "%.1f", speed)
            return "\(formatted)x"
        }
    }
    
    private func speedColor(for speed: Float) -> Color {
        switch speed {
        case 0..<1:
            return .blue
        case 1..<2:
            return .green
        case 2..<5:
            return .orange
        case 5..<10:
            return .red
        default:
            return .purple
        }
    }
}

// MARK: - Preview

struct SpeedPickerV2_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            Text("Enhanced Speed Picker V2")
                .font(.headline)
            
            HStack {
                Spacer()
                SpeedPickerV2(selectedSpeed: .constant(1.0))
                Spacer()
            }
            
            Divider()
            
            Text("Horizontal Speed Selector")
                .font(.headline)
            
            HorizontalSpeedSelector(selectedSpeed: .constant(2.0))
            
            Spacer()
        }
        .padding()
        .background(Color(UIColor.systemBackground))
    }
}