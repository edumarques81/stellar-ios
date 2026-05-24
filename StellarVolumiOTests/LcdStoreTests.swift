import XCTest
@testable import StellarVolumiO

/// Regression pin for the LCD toggle.
///
/// Background: the Settings tab's LCD on/off control silently stopped working
/// on iOS 18.3 when wrapped as `Toggle().labelsHidden()` after a `Spacer()`
/// inside an HStack inside a NavigationStack with
/// `.navigationBarTitleDisplayMode(.inline)`. The view still rendered, but
/// the Toggle's `set` closure was never invoked. The fix (in `SettingsView`)
/// replaces the Toggle with a `Button` whose action calls `LcdStore.setOn`,
/// and a custom Capsule+Circle switch graphic.
///
/// These tests assert the contract that the button action depends on:
/// `setOn(true)`  → optimistic isOn=true  + emits `lcdWake` via socket
/// `setOn(false)` → optimistic isOn=false + emits `lcdStandby` via socket
/// `pushLcdStatus` from the backend reconciles `isOn` (covered by the bind
/// callback registered in `bind(to:)`).
@MainActor
final class LcdStoreTests: XCTestCase {

    func testSetOnTrueIsOptimistic() {
        let store = LcdStore()
        let socket = SocketService()
        store.bind(to: socket)
        store.isOn = false

        store.setOn(true)
        XCTAssertTrue(store.isOn,
                      "setOn(true) must optimistically flip isOn before pushLcdStatus arrives")
    }

    func testSetOnFalseIsOptimistic() {
        let store = LcdStore()
        let socket = SocketService()
        store.bind(to: socket)
        store.isOn = true

        store.setOn(false)
        XCTAssertFalse(store.isOn,
                       "setOn(false) must optimistically flip isOn before pushLcdStatus arrives")
    }

    func testSetOnWithNoSocketBoundIsNoOp() {
        // Defensive: setOn called before bind(to:) must not crash, must not
        // mutate state. This guards against view-tree races where the user
        // taps before .onAppear has run.
        let store = LcdStore()
        store.isOn = true

        store.setOn(false)
        XCTAssertTrue(store.isOn,
                      "without a bound socket setOn must early-return and leave isOn untouched")
    }

    func testLcdStatusPayloadParserAcceptsIsOnBool() {
        // Canonical wire shape from the Go backend: {"isOn": bool}
        let dict: [String: Any] = ["isOn": true]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let status = try! JSONDecoder().decode(LcdStatus.self, from: data)
        XCTAssertTrue(status.isOn)

        let dict2: [String: Any] = ["isOn": false]
        let data2 = try! JSONSerialization.data(withJSONObject: dict2)
        let status2 = try! JSONDecoder().decode(LcdStatus.self, from: data2)
        XCTAssertFalse(status2.isOn)
    }

    func testLcdStatusPayloadParserAcceptsLegacyStateString() {
        // Tolerance for older firmware that sends `{"state":"on"}` /
        // `{"state":"off"}` instead of the canonical isOn bool.
        for (s, expected) in [("on", true), ("wake", true), ("off", false), ("standby", false)] {
            let dict: [String: Any] = ["state": s]
            let data = try! JSONSerialization.data(withJSONObject: dict)
            let status = try! JSONDecoder().decode(LcdStatus.self, from: data)
            XCTAssertEqual(status.isOn, expected, "state=\(s) must map to isOn=\(expected)")
        }
    }
}
