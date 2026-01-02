//
//  WaveformMiniView.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import SwiftUI

struct WaveformMiniView: View {
    let numberOfBars: Int = 5
    let isPlaying: Bool
    let color: Color

    @State private var animationAmounts: [CGFloat]
    @State private var animationTimer: Timer?

    init(isPlaying: Bool, color: Color = .accentColor) {
        self.isPlaying = isPlaying
        self.color = color
        _animationAmounts = State(initialValue: Array(repeating: 0.3, count: 5))
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<numberOfBars, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3)
                    .scaleEffect(x: 1, y: animationAmounts[index], anchor: .bottom)
                    .animation(.easeInOut(duration: 0.15), value: animationAmounts[index])
            }
        }
        .frame(height: 16)
        .onAppear {
            if isPlaying {
                startAnimating()
            }
        }
        .onDisappear {
            stopAnimating()
        }
        .onChange(of: isPlaying) { newValue in
            if newValue {
                startAnimating()
            } else {
                stopAnimating()
            }
        }
    }

    private func startAnimating() {
        // Stop any existing timer
        animationTimer?.invalidate()

        // Create timer that continuously updates bar heights
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                for index in 0..<numberOfBars {
                    animationAmounts[index] = CGFloat.random(in: 0.3...1.0)
                }
            }
        }

        // Fire immediately for responsive start
        animationTimer?.fire()
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil

        withAnimation(.easeOut(duration: 0.2)) {
            for index in 0..<numberOfBars {
                animationAmounts[index] = 0.3
            }
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