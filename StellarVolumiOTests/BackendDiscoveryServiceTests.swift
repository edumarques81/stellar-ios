import XCTest
@testable import StellarVolumiO

/// Tests for `BackendDiscoveryService`. We don't spin up a real NWBrowser
/// (no Bonjour service to discover in unit tests) — instead we hit the
/// public state-machine surface and the test-only `_testInsert/_testRemove`
/// shims to verify the @Observable publication path.
@MainActor
final class BackendDiscoveryServiceTests: XCTestCase {

    func testInitialStateIsEmpty() {
        let svc = BackendDiscoveryService()
        XCTAssertTrue(svc.discoveredServers.isEmpty)
        XCTAssertFalse(svc.isBrowsing,
                       "service must not start browsing implicitly — caller drives startDiscovery()")
    }

    func testStartStopIdempotent() {
        let svc = BackendDiscoveryService()

        svc.startDiscovery()
        XCTAssertTrue(svc.isBrowsing, "after startDiscovery the service must report browsing")

        // Calling start again must not toggle state or crash.
        svc.startDiscovery()
        XCTAssertTrue(svc.isBrowsing)

        svc.stopDiscovery()
        XCTAssertFalse(svc.isBrowsing, "after stopDiscovery the service must clear isBrowsing")

        // Stop a stopped service: also a no-op.
        svc.stopDiscovery()
        XCTAssertFalse(svc.isBrowsing)
    }

    func testStopClearsBrowsingFlag() {
        let svc = BackendDiscoveryService()
        svc.startDiscovery()
        svc.stopDiscovery()
        XCTAssertFalse(svc.isBrowsing)
    }

    func testInsertedServersAppearInDiscoveredList() {
        let svc = BackendDiscoveryService()
        let server = DiscoveredServer(
            id: "stellar.local._stellar._tcp",
            name: "stellar",
            host: "192.168.86.221",
            port: 3000,
            txt: ["path": "/socket.io"]
        )
        svc._testInsert(server)
        XCTAssertEqual(svc.discoveredServers.count, 1)
        XCTAssertEqual(svc.discoveredServers.first?.host, "192.168.86.221")
        XCTAssertEqual(svc.discoveredServers.first?.txt["path"], "/socket.io")
    }

    func testInsertingSameIdReplacesEntry() {
        // Bonjour can re-resolve the same instance to a new endpoint (e.g.
        // after the host's IP changes on the LAN). The store must update in
        // place, not double-list.
        let svc = BackendDiscoveryService()
        let v1 = DiscoveredServer(id: "x", name: "x", host: "10.0.0.5",  port: 3000, txt: [:])
        let v2 = DiscoveredServer(id: "x", name: "x", host: "10.0.0.10", port: 3000, txt: [:])
        svc._testInsert(v1)
        svc._testInsert(v2)
        XCTAssertEqual(svc.discoveredServers.count, 1)
        XCTAssertEqual(svc.discoveredServers.first?.host, "10.0.0.10")
    }

    func testRemoveDropsEntry() {
        let svc = BackendDiscoveryService()
        let server = DiscoveredServer(id: "x", name: "x", host: "10.0.0.5", port: 3000, txt: [:])
        svc._testInsert(server)
        XCTAssertEqual(svc.discoveredServers.count, 1)

        svc._testRemove(id: "x")
        XCTAssertTrue(svc.discoveredServers.isEmpty)
    }

    func testRemoveUnknownIdIsNoOp() {
        let svc = BackendDiscoveryService()
        svc._testRemove(id: "does-not-exist")
        XCTAssertTrue(svc.discoveredServers.isEmpty)
    }

    // MARK: - Auto-stop deadline

    func testDeadlineIsNilBeforeStart() {
        let svc = BackendDiscoveryService(autoStopAfter: 0.2)
        XCTAssertNil(svc.discoveryDeadline,
                     "deadline must be nil until startDiscovery() runs")
    }

    func testStartSetsDeadlineInTheFuture() {
        let window: TimeInterval = 0.3
        let svc = BackendDiscoveryService(autoStopAfter: window)
        let before = Date()
        svc.startDiscovery()
        let deadline = svc.discoveryDeadline
        XCTAssertNotNil(deadline, "startDiscovery() must arm the auto-stop deadline")
        // The deadline must sit roughly `window` seconds in the future. We
        // give a generous tolerance to absorb test-runtime scheduling jitter.
        if let deadline {
            let delta = deadline.timeIntervalSince(before)
            XCTAssertGreaterThanOrEqual(delta, window * 0.5)
            XCTAssertLessThanOrEqual(delta, window + 1.0)
        }
        svc.stopDiscovery()
    }

    func testStopClearsDeadline() {
        let svc = BackendDiscoveryService(autoStopAfter: 5)
        svc.startDiscovery()
        XCTAssertNotNil(svc.discoveryDeadline)

        svc.stopDiscovery()
        XCTAssertNil(svc.discoveryDeadline,
                     "stopDiscovery() must clear the auto-stop deadline")
        XCTAssertFalse(svc.isBrowsing)
    }

    func testRestartResetsDeadlineDoesNotStack() async {
        let window: TimeInterval = 0.5
        let svc = BackendDiscoveryService(autoStopAfter: window)

        svc.startDiscovery()
        let firstDeadline = svc.discoveryDeadline
        XCTAssertNotNil(firstDeadline)

        // Wait a non-trivial fraction of the window so a "stacked timer" bug
        // would leave the original deadline visibly earlier than the new one.
        try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2s

        svc.startDiscovery()
        let secondDeadline = svc.discoveryDeadline
        XCTAssertNotNil(secondDeadline)

        // The new deadline must strictly post-date the original — proves we
        // re-armed from "now" rather than reusing or stacking the old timer.
        if let first = firstDeadline, let second = secondDeadline {
            XCTAssertGreaterThan(
                second, first,
                "re-starting discovery must push the deadline forward, not stack timers"
            )
        }
        svc.stopDiscovery()
    }

    func testAutoStopFiresAfterWindow() async {
        // 0.4s window keeps the test fast; we wait ~0.9s for a clean margin
        // over scheduling jitter and the deadline tolerance above.
        let svc = BackendDiscoveryService(autoStopAfter: 0.4)
        svc.startDiscovery()
        XCTAssertTrue(svc.isBrowsing)

        try? await Task.sleep(nanoseconds: 900_000_000)

        XCTAssertFalse(svc.isBrowsing,
                       "auto-stop timer must tear the browser down after the window")
        XCTAssertNil(svc.discoveryDeadline,
                     "auto-stop fire must clear the deadline like manual stop does")
    }

    // MARK: - Default constant

    func testDefaultMaxDiscoveryDurationIsOneMinute() {
        // Pinning the 60-second contract so a casual edit to the constant
        // is caught by CI rather than shipping silently.
        XCTAssertEqual(BackendDiscoveryService.maxDiscoveryDuration, 60)
    }
}
