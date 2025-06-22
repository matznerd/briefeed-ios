//
//  WaveformView.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import SwiftUI

struct WaveformView: View {
    let numberOfBars: Int = 40
    let isPlaying: Bool
    
    @State private var animationAmounts: [CGFloat]
    
    init(isPlaying: Bool) {
        self.isPlaying = isPlaying
        _animationAmounts = State(initialValue: Array(repeating: 0.3, count: 40))
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: geometry.size.width * 0.01) {
                ForEach(0..<numberOfBars, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.accentColor.opacity(0.8),
                                    Color.accentColor
                                ]),
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: max(2, geometry.size.width / CGFloat(numberOfBars) - 2))
                        .scaleEffect(x: 1, y: animationAmounts[index], anchor: .bottom)
                        .animation(
                            isPlaying ?
                                Animation
                                    .easeInOut(duration: Double.random(in: 0.4...0.8))
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.02)
                            : .default,
                            value: animationAmounts[index]
                        )
                }
            }
            .onAppear {
                startAnimating()
            }
            .onChange(of: isPlaying) { newValue in
                if newValue {
                    startAnimating()
                } else {
                    stopAnimating()
                }
            }
        }
    }
    
    private func startAnimating() {
        for index in 0..<numberOfBars {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.02) {
                withAnimation {
                    animationAmounts[index] = CGFloat.random(in: 0.3...1.0)
                }
            }
        }
        
        // Continue updating animation values
        if isPlaying {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                if !isPlaying {
                    timer.invalidate()
                    return
                }
                
                for index in 0..<numberOfBars {
                    withAnimation(.easeInOut(duration: Double.random(in: 0.4...0.8))) {
                        animationAmounts[index] = CGFloat.random(in: 0.3...1.0)
                    }
                }
            }
        }
    }
    
    private func stopAnimating() {
        for index in 0..<numberOfBars {
            withAnimation(.easeOut(duration: 0.3)) {
                animationAmounts[index] = 0.3
            }
        }
    }
}

// MARK: - Preview
struct WaveformView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            Text("Playing")
                .font(.headline)
            WaveformView(isPlaying: true)
                .frame(height: 60)
                .padding()
            
            Text("Paused")
                .font(.headline)
            WaveformView(isPlaying: false)
                .frame(height: 60)
                .padding()
        }
        .background(Color.gray.opacity(0.1))
    }
}