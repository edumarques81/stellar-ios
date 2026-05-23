import SwiftUI

@main
struct StellarApp: App {
    @State private var socketService = SocketService()
    @State private var playerStore = PlayerStore()
    @State private var audioEngineStore = AudioEngineStore()
    @State private var themeStore = ThemeStore()
    @State private var qobuzStore = QobuzStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(socketService)
                .environment(playerStore)
                .environment(audioEngineStore)
                .environment(themeStore)
                .environment(qobuzStore)
                .preferredColorScheme(.dark)
                .onAppear {
                    playerStore.bind(to: socketService)
                    audioEngineStore.bind(to: socketService)
                    qobuzStore.bind(to: socketService)
                    socketService.connect()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    socketService.reconnectIfNeeded()
                }
        }
    }
}
