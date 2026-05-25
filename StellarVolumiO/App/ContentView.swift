import SwiftUI

struct ContentView: View {
    @Environment(SocketService.self) private var socket

    @State private var selectedTab: Tab = .player
    @State private var focusBackendInSettings = false

    enum Tab { case player, library, settings }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                NowPlayingView()
                    .tabItem { Label("Now Playing", systemImage: "music.note") }
                    .tag(Tab.player)

                LibraryView()
                    .tabItem { Label("Library", systemImage: "square.stack") }
                    .tag(Tab.library)

                SettingsView(focusBackendOnAppear: $focusBackendInSettings)
                    .tabItem { Label("Settings", systemImage: "gear") }
                    .tag(Tab.settings)
            }
            .tint(Stellar.Color.gold)

            // Connection-failure banner — appears only when the socket is
            // truly disconnected (post grace period) AND we have a captured
            // error to show. Non-blocking; sits above the safe area so it
            // doesn't fight the tab bar.
            if shouldShowFailureBanner {
                connectionFailureBanner
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowFailureBanner)
    }

    // MARK: - Failure banner

    /// True when the resolved (post-grace) state is .disconnected or .error
    /// AND we have a populated `lastConnectionError` to display.
    private var shouldShowFailureBanner: Bool {
        guard socket.lastConnectionError != nil else { return false }
        switch socket.reportedConnectionState {
        case .disconnected, .error: return true
        case .connected, .connecting: return false
        }
    }

    private var connectionFailureBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Stellar.Color.statusRed)
                Text("Can't reach backend")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            if let err = socket.lastConnectionError {
                Text(err)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                Button {
                    socket.connect()
                } label: {
                    Text("Retry")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minHeight: Stellar.Metric.minTouchTarget * 0.65)
                        .background(Stellar.Color.gold, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)

                Button {
                    selectedTab = .settings
                    // Trigger the SettingsView ScrollViewReader to scroll
                    // to the Backend Server section on its next render.
                    focusBackendInSettings = true
                } label: {
                    Text("Server Settings")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minHeight: Stellar.Metric.minTouchTarget * 0.65)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Stellar.Color.gold, lineWidth: 1)
                        )
                        .foregroundStyle(Stellar.Color.gold)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Stellar.Color.statusRed.opacity(0.6), lineWidth: 1)
                )
        )
    }
}
