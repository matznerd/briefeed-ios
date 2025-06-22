//
//  MarqueeText.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    let startDelay: Double
    
    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var animationDuration: Double = 0
    
    init(_ text: String, font: Font = .system(size: 14), startDelay: Double = 3.0) {
        self.text = text
        self.font = font
        self.startDelay = startDelay
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Hidden text to measure width
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(GeometryReader { textGeometry in
                        Color.clear
                            .onAppear {
                                textWidth = textGeometry.size.width
                                containerWidth = geometry.size.width
                                
                                // Only animate if text is wider than container
                                if textWidth > containerWidth {
                                    // Calculate animation duration based on text length
                                    // Approximately 50 points per second
                                    animationDuration = Double(textWidth + containerWidth) / 50.0
                                    startAnimation()
                                }
                            }
                    })
                    .opacity(0)
                
                // Visible scrolling text
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.1),
                                .init(color: .black, location: 0.9),
                                .init(color: .clear, location: 1)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width)
                    )
            }
            .frame(width: geometry.size.width, alignment: .leading)
            .clipped()
        }
    }
    
    private func startAnimation() {
        // Initial delay before starting
        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
            withAnimation(.linear(duration: animationDuration).repeatForever(autoreverses: true)) {
                offset = -(textWidth - containerWidth)
            }
        }
    }
}

// Preview
struct MarqueeText_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            MarqueeText("This is a short text")
                .frame(width: 200, height: 20)
                .background(Color.gray.opacity(0.2))
            
            MarqueeText("This is a very long text that needs to scroll because it doesn't fit in the container")
                .frame(width: 200, height: 20)
                .background(Color.gray.opacity(0.2))
        }
        .padding()
    }
}