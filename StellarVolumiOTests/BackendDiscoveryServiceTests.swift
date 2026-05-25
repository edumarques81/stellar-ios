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
}
