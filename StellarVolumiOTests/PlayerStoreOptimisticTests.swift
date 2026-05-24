import XCTest
@testable import StellarVolumiO

@MainActor
final class PlayerStoreOptimisticTests: XCTestCase {

    func testOptimisticPlayMakesIsPlayingTrue() {
        let store = PlayerStore()
        store.state = PlayerState.empty
        XCTAssertFalse(store.isPlaying)
        store.applyOptimistic(.play)
        XCTAssertTrue(store.isPlaying)
    }

    func testServerStateClearsOptimistic() {
        let store = PlayerStore()
        store.applyOptimistic(.play)
        XCTAssertTrue(store.isPlaying)

        // Server confirms pause (matches no optimistic value).
        var newState = PlayerState.empty
        newState.status = .pause
        store.receiveServerState(newState)

        XCTAssertNil(store.optimisticStatus, "server state must clear optimistic")
        XCTAssertFalse(store.isPlaying)
    }

    func testIsPlayingPrefersOptimistic() {
        let store = PlayerStore()
        var s = PlayerState.empty
        s.status = .pause
        store.state = s
        XCTAssertFalse(store.isPlaying)

        store.applyOptimistic(.play)
        XCTAssertTrue(store.isPlaying, "optimistic must override server state until reconciled")
    }
}
