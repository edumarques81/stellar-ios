import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .player

    enum Tab { case player, library, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            NowPlayingView()
                .tabItem { Label("Now Playing", systemImage: "music.note") }
                .tag(Tab.player)

            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(Tab.library)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
        .tint(Stellar.Color.gold)
    }
}
