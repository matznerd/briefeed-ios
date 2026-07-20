import SwiftUI

struct RadioTabRail: View {
    @Binding var selection: AppTab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Group {
            if reduceTransparency {
                railContent
                    .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.primary.opacity(borderOpacity), lineWidth: borderWidth)
                    }
            } else if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 8) {
                    railContent
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
            } else {
                railContent
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.primary.opacity(borderOpacity), lineWidth: borderWidth)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Navigation.rail)
    }

    private var railContent: some View {
        HStack(spacing: 8) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(selectionAnimation) {
                        selection = tab
                    }
                } label: {
                    Image(systemName: tab.systemImage)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(selection == tab ? Color.briefeedRed : Color.primary)
                        .frame(width: 44, height: 44)
                        .background {
                            if selection == tab {
                                Capsule()
                                    .fill(Color.primary.opacity(selectionOpacity))
                                    .padding(3)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier(tab.accessibilityIdentifier)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.18)
    }

    private var selectionOpacity: Double {
        colorSchemeContrast == .increased ? 0.18 : 0.10
    }

    private var borderOpacity: Double {
        colorSchemeContrast == .increased ? 0.34 : 0.14
    }

    private var borderWidth: CGFloat {
        colorSchemeContrast == .increased ? 1.5 : 0.5
    }
}

#Preview {
    @Previewable @State var selection = AppTab.radio
    RadioTabRail(selection: $selection)
        .padding()
}
