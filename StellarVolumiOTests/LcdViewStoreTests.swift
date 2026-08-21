import XCTest
@testable import StellarVolumiO

/// Contract for the tab bar's VU item.
///
/// The store's whole job is "flip the Pi's LCD kiosk to the VU meter, and back
/// to whatever it was showing" — with the *back* half supplied by the backend's
/// `previousView` rather than any history kept here.
///
/// Note every test binds a **named** `SocketService` local: the store holds it
/// weakly, so `bind(to: SocketService())` would pass a temporary that dies
/// immediately and turn every action into a silent no-op.
@MainActor
final class LcdViewStoreTests: XCTestCase {

    // MARK: - Toggling

    func testToggleFromPlayerGoesToVuMeter() {
        let store = LcdViewStore()
        let socket = SocketService()
        store.bind(to: socket)

        store.toggleVuMeter()

        XCTAssertEqual(store.view, .vuMeter,
                       "toggling off the player view must optimistically move to the VU meter")
        XCTAssertEqual(socket.lastEmittedObjectEvent, "lcdSetView")
        XCTAssertEqual(socket.lastEmittedObjectPayload?["view"] as? String, "vu-meter")
    }

    func testToggleBackReturnsToTheRememberedView() {
        let store = LcdViewStore()
        let socket = SocketService()
        store.bind(to: socket)
        store.applyForTesting(view: .vuMeter, previousView: .library)

        store.toggleVuMeter()

        XCTAssertEqual(store.view, .library,
                       "leaving the VU meter must return to the view the backend remembered")
        XCTAssertEqual(socket.lastEmittedObjectPayload?["view"] as? String, "library")
    }

    /// The user tapped VU to *see* something. A view change on a dark panel is
    /// not that, so the command carries wake.
    func testToggleAlwaysRequestsWake() {
        let store = LcdViewStore()
        let socket = SocketService()
        store.bind(to: socket)

        store.toggleVuMeter()
        XCTAssertEqual(socket.lastEmittedObjectPayload?["wake"] as? Bool, true)

        store.toggleVuMeter()
        XCTAssertEqual(socket.lastEmittedObjectPayload?["wake"] as? Bool, true,
                       "the return leg must wake too — it is just as invisible on a dark panel")
    }

    func testToggleWithNoSocketBoundIsNoOp() {
        // Defensive: a tap that lands before .onAppear has run must not crash
        // and must not desync local state from a backend that heard nothing.
        let store = LcdViewStore()
        store.toggleVuMeter()

        XCTAssertEqual(store.view, .player,
                       "without a bound socket the toggle must early-return and leave view untouched")
    }

    // MARK: - Degenerate "previous" values

    /// If previousView were echoed as the VU meter itself, "back" would be a
    /// no-op and the user would be stuck on the meter with a dead button.
    func testToggleBackFromSelfReferentialPreviousFallsBackToPlayer() {
        let store = LcdViewStore()
        let socket = SocketService()
        store.bind(to: socket)
        store.applyForTesting(view: .vuMeter, previousView: .vuMeter)

        store.toggleVuMeter()

        XCTAssertEqual(store.view, .player)
        XCTAssertEqual(socket.lastEmittedObjectPayload?["view"] as? String, "player")
    }

    func testToggleBackFromUnknownPreviousFallsBackToPlayer() {
        let store = LcdViewStore()
        let socket = SocketService()
        store.bind(to: socket)
        store.applyForTesting(view: .vuMeter, previousView: .unknown)

        store.toggleVuMeter()

        XCTAssertEqual(store.view, .player)
    }

    // MARK: - isShowingVuMeter

    func testIsShowingVuMeterReflectsView() {
        let store = LcdViewStore()
        XCTAssertFalse(store.isShowingVuMeter, "defaults to the player view the kiosk boots into")

        store.applyForTesting(view: .vuMeter, previousView: .player)
        XCTAssertTrue(store.isShowingVuMeter)

        store.applyForTesting(view: .queue, previousView: .vuMeter)
        XCTAssertFalse(store.isShowingVuMeter)
    }

    // MARK: - Wire decoding

    func testDecodesCanonicalPayload() throws {
        let dict: [String: Any] = ["view": "vu-meter", "previousView": "library"]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let status = try JSONDecoder().decode(LcdViewStatus.self, from: data)

        XCTAssertEqual(status.view, .vuMeter)
        XCTAssertEqual(status.previousView, .library)
    }

    /// A backend that grows a new screen must not take the whole frame down.
    func testUnknownViewNameDecodesRatherThanThrowing() throws {
        let dict: [String: Any] = ["view": "spectrum", "previousView": "player"]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let status = try JSONDecoder().decode(LcdViewStatus.self, from: data)

        XCTAssertEqual(status.view, .unknown)
        XCTAssertEqual(status.previousView, .player)
    }

    func testMissingFieldsDecodeAsUnknown() throws {
        let data = try JSONSerialization.data(withJSONObject: [String: Any]())
        let status = try JSONDecoder().decode(LcdViewStatus.self, from: data)

        XCTAssertEqual(status.view, .unknown)
        XCTAssertEqual(status.previousView, .unknown)
    }

    func testAllKnownViewNamesRoundTrip() throws {
        let cases: [(String, LcdView)] = [
            ("player", .player),
            ("library", .library),
            ("queue", .queue),
            ("settings", .settings),
            ("vu-meter", .vuMeter)
        ]
        for (wire, expected) in cases {
            let data = try JSONSerialization.data(withJSONObject: ["view": wire, "previousView": wire])
            let status = try JSONDecoder().decode(LcdViewStatus.self, from: data)
            XCTAssertEqual(status.view, expected, "wire name \(wire) must decode to \(expected)")
        }
    }
}
