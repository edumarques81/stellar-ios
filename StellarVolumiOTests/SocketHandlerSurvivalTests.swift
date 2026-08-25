import XCTest
@testable import StellarVolumiO

/// Regression coverage for handler loss across a backend-endpoint change.
///
/// `SocketService.ensureInitialised()` tears down the SocketManager whenever the
/// resolved endpoint differs from the one it built against, and clears
/// `eventHandlers` while doing so. The doc-comment there claims "re-bind callers
/// will re-register their `on(...)` handlers via ensureInitialised() the next
/// time they emit" — nothing in the codebase does that. `emit()` rebuilds the
/// socket but never re-runs any store's `bind(to:)`, and `onRawDict` (which is
/// how `pushState` is subscribed) never records into `eventHandlers` at all, so
/// there is nothing to replay even in principle.
///
/// Consequence in the field: after Settings → Save, or after picking a server in
/// the discovery sheet, the app reconnects and reports itself connected while
/// receiving nothing. Within a single track the only field that visibly changes
/// is `seek`, so the user-visible symptom is precisely "the progress bar is not
/// moving, the time is not progressing".
final class SocketHandlerSurvivalTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SocketHandlerSurvivalTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// A store binds, then the user changes the backend host. The subscription
    /// registered before the change must still be live afterwards.
    func testEventHandlersSurviveAnEndpointChange() {
        let config = BackendConfigStore(defaults: defaults)
        try? config.setCustom(host: "host-a.local", port: 3000, scheme: nil)

        let socket = SocketService(config: config)
        let player = PlayerStore()
        player.bind(to: socket)

        // Force the socket to be built against host-a.
        socket.connect()
        XCTAssertEqual(socket.serverHost, "host-a.local")

        // The user picks a different backend in Settings.
        try? config.setCustom(host: "host-b.local", port: 3000, scheme: nil)
        socket.reconnectWithCurrentConfig()
        XCTAssertEqual(socket.serverHost, "host-b.local")

        // The pushState subscription PlayerStore registered in bind(to:) is
        // expected to still be attached to the rebuilt socket.
        XCTAssertTrue(
            socket.hasSubscription(for: "pushState"),
            "pushState handler was dropped by the endpoint change and never re-registered — "
          + "the app is now permanently deaf to state updates until relaunch."
        )
    }

    /// Boundary check: an ordinary same-endpoint reconnect keeps the socket
    /// object, so handlers must survive that too.
    func testEventHandlersSurviveASameEndpointReconnect() {
        let config = BackendConfigStore(defaults: defaults)
        try? config.setCustom(host: "host-a.local", port: 3000, scheme: nil)

        let socket = SocketService(config: config)
        let player = PlayerStore()
        player.bind(to: socket)
        socket.connect()

        socket.disconnect()
        socket.reconnectIfNeeded()

        XCTAssertTrue(socket.hasSubscription(for: "pushState"))
    }

    /// Every event a store subscribes to in `bind(to:)` must come back after a
    /// rebuild — not just `pushState`.
    func testAllStoreSubscriptionsAreReplayed() {
        let config = BackendConfigStore(defaults: defaults)
        try? config.setCustom(host: "host-a.local", port: 3000, scheme: nil)

        let socket = SocketService(config: config)
        let player = PlayerStore()
        let lcd = LcdStore()
        player.bind(to: socket)
        lcd.bind(to: socket)
        socket.connect()

        let before = Set(socket.subscribedEvents)
        XCTAssertFalse(before.isEmpty)

        try? config.setCustom(host: "host-b.local", port: 3000, scheme: nil)
        socket.reconnectWithCurrentConfig()

        XCTAssertEqual(Set(socket.subscribedEvents), before,
                       "subscription set changed across the endpoint rebuild")
    }
}
