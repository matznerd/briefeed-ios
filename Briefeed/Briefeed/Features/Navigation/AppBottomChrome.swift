import SwiftUI

struct AppBottomChrome: View {
    @Binding var selection: AppTab
    let showsMiniPlayer: Bool

    var body: some View {
        VStack(spacing: 2) {
            RadioTabRail(selection: $selection)

            if showsMiniPlayer {
                MiniAudioPlayerV4(bottomDocked: true)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.top, 2)
        .background {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.easeInOut(duration: 0.2), value: showsMiniPlayer)
    }
}
