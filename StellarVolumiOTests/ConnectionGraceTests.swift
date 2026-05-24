import XCTest
@testable import StellarVolumiO

@MainActor
final class ConnectionGraceTests: XCTestCase {

    func testReportedStateRespectsGrace() async {
        let svc = SocketService()
        // Simulate connect.
        svc.connectionState = .connected
        XCTAssertEqual(svc.reportedConnectionState, .connected)

        // Internal: disconnect arrives — reported state still shows .connecting
        // during grace period (UI-friendly: spinner, not red).
        svc.markDisconnectedInternal()
        XCTAssertEqual(svc.reportedConnectionState, .connecting,
                       "during grace period UI shows 'Connecting…' not 'Disconnected'")

        // Wait 5.5 s for grace to expire.
        try? await Task.sleep(nanoseconds: 5_500_000_000)
        XCTAssertEqual(svc.reportedConnectionState, .disconnected,
                       "after 5s grace, UI shows 'Disconnected'")
    }

    func testReconnectDuringGraceClearsTimer() async {
        let svc = SocketService()
        svc.connectionState = .connected
        svc.markDisconnectedInternal()
        XCTAssertEqual(svc.reportedConnectionState, .connecting)

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        svc.connectionState = .connected
        XCTAssertEqual(svc.reportedConnectionState, .connected)

        // Wait past the original 5s window — must NOT flip to disconnected.
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        XCTAssertEqual(svc.reportedConnectionState, .connected)
    }
}
