import SwiftUI

struct ContentView: View {
    @Environment(SocketService.self) private var socket
    @Environment(PlayerStore.self) private var player
    @Environment(ThemeStore.self) private var themeStore
    @State private var selectedTab: Tab = .player

    enum Tab { case player, queue, browse, favourites, settings }

    var body: some View {
        // Reading themeStore.theme ensures SwiftUI re-renders on theme change,
        // which causes all Color.md* computed vars to resolve to the new palette.
        let _ = themeStore.theme

        ZStack {
            Color.mdBackground.ignoresSafeArea()

            TabView(selection: $selectedTab) {
                NowPlayingView()
                    .tabItem { Label("Playing", systemImage: "play.circle.fill") }
                    .tag(Tab.player)

                QueueView()
                    .tabItem { Label("Queue", systemImage: "list.bullet") }
                    .tag(Tab.queue)

                BrowseView()
                    .tabItem { Label("Browse", systemImage: "folder") }
                    .tag(Tab.browse)

                FavoritesView()
                    .tabItem { Label("Favourites", systemImage: "heart.fill") }
                    .tag(Tab.favourites)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }
            .tint(themeStore.theme.accentColor)

            // Connection overlay
            if socket.connectionState != .connected {
                ConnectionOverlay()
            }
        }
    }
}

// MARK: - Connection Overlay
private struct ConnectionOverlay: View {
    @Environment(SocketService.self) private var socket

    var body: some View {
        VStack(spacing: 16) {
            if case .error(let msg) = socket.connectionState {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.mdError)
                Text("Connection error")
                    .font(StellarFont.headlineSmall)
                    .foregroundStyle(.mdOnSurface)
                Text(msg)
                    .font(StellarFont.bodyMedium)
                    .foregroundStyle(.mdOnSurfaceVariant)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
                    .tint(.mdPrimary)
                Text(socket.connectionState == .connecting ? "Connecting to Stellar…" : "Disconnected")
                    .font(StellarFont.bodyMedium)
                    .foregroundStyle(.mdOnSurfaceVariant)
            }

            Button("Try Again") { socket.connect() }
                .buttonStyle(.borderedProminent)
                .tint(.mdPrimary)
        }
        .padding(32)
        .background(.mdSurfaceContainerHigh, in: RoundedRectangle(cornerRadius: .mdShapeExtraLarge))
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.mdBackground.opacity(0.9))
    }
}
