//
//  SpeedPicker.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import SwiftUI

struct SpeedPicker: View {
    @Binding var selectedSpeed: Float
    @State private var isExpanded = false
    
    let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    
    var body: some View {
        VStack(spacing: 0) {
            // Current speed button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Text(formatSpeed(selectedSpeed))
                        .font(.system(size: 14, weight: .medium))
                    
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 0 : 180))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Speed options
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(speeds, id: \.self) { speed in
                        Button(action: {
                            selectedSpeed = speed
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isExpanded = false
                            }
                        }) {
                            HStack {
                                Text(formatSpeed(speed))
                                    .font(.system(size: 14, weight: speed == selectedSpeed ? .semibold : .regular))
                                
                                Spacer()
                                
                                if speed == selectedSpeed {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .foregroundColor(speed == selectedSpeed ? .accentColor : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if speed != speeds.last {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                )
                .padding(.top, 8)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 0.8).combined(with: .opacity)
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
            return String(format: "%.2fx", speed).replacingOccurrences(of: ".00", with: "")
        }
    }
}

// MARK: - Compact Speed Picker (for inline use)
struct CompactSpeedPicker: View {
    @Binding var selectedSpeed: Float
    let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(speeds, id: \.self) { speed in
                    Button(action: {
                        selectedSpeed = speed
                    }) {
                        Text(formatSpeed(speed))
                            .font(.system(size: 13, weight: speed == selectedSpeed ? .semibold : .regular))
                            .foregroundColor(speed == selectedSpeed ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(speed == selectedSpeed ? Color.accentColor : Color.gray.opacity(0.1))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 2)
        }
    }
    
    private func formatSpeed(_ speed: Float) -> String {
        if speed == 1.0 {
            return "1x"
        } else if speed == floor(speed) {
            return "\(Int(speed))x"
        } else {
            return String(format: "%.2fx", speed).replacingOccurrences(of: ".00", with: "")
        }
    }
}

// MARK: - Preview
struct SpeedPicker_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            Text("Dropdown Speed Picker")
                .font(.headline)
            
            HStack {
                Spacer()
                SpeedPicker(selectedSpeed: .constant(1.0))
                Spacer()
            }
            
            Divider()
            
            Text("Compact Speed Picker")
                .font(.headline)
            
            CompactSpeedPicker(selectedSpeed: .constant(1.25))
                .padding()
            
            Spacer()
        }
        .padding()
        .background(Color(UIColor.systemBackground))
    }
}