import SwiftUI

@main
struct StellarApp: App {
    @State private var socketService = SocketService()
    @State private var playerStore = PlayerStore()
    @State private var albumStore = AlbumPickerStore()
    @State private var artistStore = ArtistPickerStore()
    @State private var lcdStore = LcdStore()
    @State private var lastPlayedStore = LastPlayedStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(socketService)
                .environment(playerStore)
                .environment(albumStore)
                .environment(artistStore)
                .environment(lcdStore)
                .environment(lastPlayedStore)
                .preferredColorScheme(.dark)
                .onAppear {
                    playerStore.bind(to: socketService)
                    albumStore.bind(to: socketService)
                    artistStore.bind(to: socketService)
                    lcdStore.bind(to: socketService)
                    lastPlayedStore.bind(to: socketService)
                    socketService.connect()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    socketService.reconnectIfNeeded()
                }
        }
    }
}
