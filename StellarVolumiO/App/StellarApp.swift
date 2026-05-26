import SwiftUI

@main
struct StellarApp: App {
    // The backend config store is built first because SocketService takes
    // it as a constructor argument — keeps the host/port/scheme source
    // chain coherent from the moment the app launches.
    @State private var backendConfig = BackendConfigStore()
    @State private var discovery = BackendDiscoveryService()
    @State private var socketService: SocketService
    @State private var playerStore = PlayerStore()
    @State private var airplayStore = AirplayStore()
    @State private var albumStore = AlbumPickerStore()
    @State private var artistStore = ArtistPickerStore()
    @State private var albumTracksStore = AlbumTracksStore()
    @State private var lcdStore = LcdStore()
    @State private var lastPlayedStore = LastPlayedStore()

    init() {
        // Configure the shared URLCache with a large disk-backed store before
        // any URLSession.shared traffic happens. This is what makes album-art
        // covers survive across app launches — see AlbumArtCache for details.
        AlbumArtCache.configureSharedCache()

        // SocketService is a `let`-injected dependency of every store's
        // `bind(to:)`. We feed it the same BackendConfigStore we instantiated
        // above so the resolved host/port/scheme stays consistent across the
        // app — Settings edits and Bonjour discovery updates flow through one
        // path.
        let config = BackendConfigStore()
        _backendConfig = State(wrappedValue: config)
        _socketService = State(wrappedValue: SocketService(config: config))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(socketService)
                .environment(backendConfig)
                .environment(discovery)
                .environment(playerStore)
                .environment(airplayStore)
                .environment(albumStore)
                .environment(artistStore)
                .environment(albumTracksStore)
                .environment(lcdStore)
                .environment(lastPlayedStore)
                .preferredColorScheme(.dark)
                .onAppear {
                    playerStore.bind(to: socketService)
                    airplayStore.bind(to: socketService)
                    albumStore.bind(to: socketService)
                    artistStore.bind(to: socketService)
                    albumTracksStore.bind(to: socketService)
                    lcdStore.bind(to: socketService)
                    lastPlayedStore.bind(to: socketService)
                    socketService.connect()
                    // Kick off Bonjour browsing so the Settings picker has
                    // fresh candidates the moment the user navigates to it.
                    discovery.startDiscovery()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    socketService.reconnectIfNeeded()
                }
        }
    }
}
