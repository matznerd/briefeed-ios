//
//  WaveformMiniView.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import SwiftUI

/// Simple playing indicator with smooth pulse animation
/// Replaces the previous random waveform animation
struct WaveformMiniView: View {
    let numberOfBars: Int = 3
    let isPlaying: Bool
    let color: Color

    @State private var isPulsing: Bool = false

    init(isPlaying: Bool, color: Color = .accentColor) {
        self.isPlaying = isPlaying
        self.color = color
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<numberOfBars, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(
                        isPlaying ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.15) : .easeOut(duration: 0.2),
                        value: isPulsing
                    )
            }
        }
        .frame(height: 16)
        .onAppear {
            if isPlaying {
                isPulsing = true
            }
        }
        .onChange(of: isPlaying) { newValue in
            isPulsing = newValue
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        if isPulsing {
            // Staggered heights when playing: short, tall, medium
            let heights: [CGFloat] = [8, 14, 10]
            return heights[index]
        } else {
            // All bars same height when paused
            return 6
        }
    }
}

// MARK: - Preview
struct WaveformMiniView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                Text("Playing:")
                WaveformMiniView(isPlaying: true)
                    .frame(width: 25)
            }
            
            HStack(spacing: 20) {
                Text("Paused:")
                WaveformMiniView(isPlaying: false)
                    .frame(width: 25)
            }
            
            HStack(spacing: 20) {
                Text("Custom Color:")
                WaveformMiniView(isPlaying: true, color: .green)
                    .frame(width: 25)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
}