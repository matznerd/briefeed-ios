//
//  FlingTransition.swift
//  Briefeed
//
//  Fling-away animation for auto-removing played items from the Brief queue.
//

import SwiftUI

struct FlingRemovalModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? 0.6 : 1.0)
            .offset(y: isActive ? -400 : 0)
            .rotationEffect(.degrees(isActive ? 15 : 0))
            .opacity(isActive ? 0 : 1)
    }
}

extension AnyTransition {
    static var flingUp: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .modifier(
                active: FlingRemovalModifier(isActive: true),
                identity: FlingRemovalModifier(isActive: false)
            )
        )
    }
}
