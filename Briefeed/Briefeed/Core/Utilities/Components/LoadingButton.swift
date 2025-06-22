//
//  LoadingButton.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import SwiftUI

struct LoadingButton: View {
    let title: String
    let systemImage: String?
    let isLoading: Bool
    let action: () async -> Void
    
    @State private var isPressed = false
    
    init(
        title: String,
        systemImage: String? = nil,
        isLoading: Bool = false,
        action: @escaping () async -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.action = action
    }
    
    var body: some View {
        Button {
            if !isLoading {
                Task {
                    await action()
                }
            }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                } else if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16))
                }
                
                Text(isLoading ? "Loading..." : title)
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(isLoading ? .briefeedSecondaryLabel : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: Constants.UI.cornerRadius)
                    .fill(isLoading ? Color.briefeedSecondaryBackground : Color.briefeedRed)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Constants.UI.cornerRadius)
                    .stroke(Color.briefeedRed.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .disabled(isLoading)
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Convenience Initializers

extension LoadingButton {
    init(_ title: String, isLoading: Bool = false, action: @escaping () async -> Void) {
        self.init(title: title, systemImage: nil, isLoading: isLoading, action: action)
    }
}

// MARK: - Style Modifiers

struct LoadingButtonStyle: ViewModifier {
    let style: LoadingButton.Style
    
    func body(content: Content) -> some View {
        content
    }
}

extension LoadingButton {
    enum Style {
        case primary
        case secondary
        case destructive
        
        var backgroundColor: Color {
            switch self {
            case .primary:
                return .briefeedRed
            case .secondary:
                return .briefeedSecondaryBackground
            case .destructive:
                return .red
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .primary:
                return .white
            case .secondary:
                return .briefeedLabel
            case .destructive:
                return .white
            }
        }
    }
}

// MARK: - Preview

#Preview("Loading Button") {
    VStack(spacing: 20) {
        LoadingButton(title: "Generate Summary", systemImage: "sparkles") {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        
        LoadingButton(title: "Generate Summary", systemImage: "sparkles", isLoading: true) {
            // Action
        }
        
        LoadingButton(title: "Fetch Content", systemImage: "arrow.down.circle") {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        
        LoadingButton(title: "Play Audio", systemImage: "play.fill") {
            // Action
        }
    }
    .padding()
    .background(Color.briefeedBackground)
}