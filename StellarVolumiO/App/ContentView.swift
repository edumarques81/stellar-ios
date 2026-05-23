import SwiftUI

struct ContentView: View {
    @Environment(SocketService.self) private var socket
    @State private var selectedTab: Tab = .player

    enum Tab { case player, library, settings }

    var body: some View {
        ZStack {
            Color.mdBackground.ignoresSafeArea()

            TabView(selection: $selectedTab) {
                NowPlayingView()
                    .tabItem { Label("Playing", systemImage: "play.circle.fill") }
                    .tag(Tab.player)

                LibraryView()
                    .tabItem { Label("Library", systemImage: "rectangle.stack.fill") }
                    .tag(Tab.library)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(Tab.settings)
            }
            .tint(.mdPrimary)

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
