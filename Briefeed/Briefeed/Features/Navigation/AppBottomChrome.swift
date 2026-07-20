import SwiftUI

struct AppBottomChrome: View {
    @Binding var selection: AppTab
    let showsMiniPlayer: Bool

    var body: some View {
        VStack(spacing: 6) {
            RadioTabRail(selection: $selection)

            if showsMiniPlayer {
                MiniAudioPlayerV4()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.top, 6)
        .animation(.easeInOut(duration: 0.2), value: showsMiniPlayer)
    }
}
