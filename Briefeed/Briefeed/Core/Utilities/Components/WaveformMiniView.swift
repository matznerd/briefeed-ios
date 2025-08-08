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
                    .animation(
                        isPlaying ?
                            Animation
                                .easeInOut(duration: Double.random(in: 0.3...0.6))
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.05)
                        : .easeOut(duration: 0.2),
                        value: animationAmounts[index]
                    )
            }
        }
        .frame(height: 16)
        .onAppear {
            if isPlaying {
                startAnimating()
            }
        }
        .onChange(of: isPlaying) { _, newValue in
            if newValue {
                startAnimating()
            } else {
                stopAnimating()
            }
        }
    }
    
    private func startAnimating() {
        // Cancel any existing timer
        animationTimer?.invalidate()
        
        for index in 0..<numberOfBars {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) {
                withAnimation {
                    animationAmounts[index] = CGFloat.random(in: 0.4...1.0)
                }
            }
        }
        
        // Continue updating animation values
        if isPlaying {
            animationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                if !isPlaying {
                    animationTimer?.invalidate()
                    animationTimer = nil
                    return
                }
                
                for index in 0..<numberOfBars {
                    withAnimation(.easeInOut(duration: Double.random(in: 0.3...0.6))) {
                        animationAmounts[index] = CGFloat.random(in: 0.4...1.0)
                    }
                }
            }
        }
    }
    
    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        
        for index in 0..<numberOfBars {
            withAnimation(.easeOut(duration: 0.2)) {
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