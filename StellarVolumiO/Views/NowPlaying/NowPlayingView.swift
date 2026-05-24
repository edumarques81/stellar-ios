import SwiftUI

struct NowPlayingView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(LastPlayedStore.self) private var lastPlayed

    var body: some View {
        ZStack {
            StellarGlassyBackground()

            ScrollView {
                VStack(spacing: 0) {
                    content
                        .padding(.top, 24)
                        .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, 16, for: .scrollContent)
        }
    }

    @ViewBuilder
    private var content: some View {
        if player.hasTrack && player.state.status != .stop {
            NowPlayingPlayingView()
        } else if let last = lastPlayed.album {
            NowPlayingIdleView(album: last)
        } else {
            NowPlayingEmptyView()
        }
    }
}
