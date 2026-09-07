import XCTest
@testable import StellarVolumiO

/// Seek is dead-reckoned between backend broadcasts. These tests drive
/// `tick(now:)` with explicit instants so the projection arithmetic is
/// exercised without sleeping.
@MainActor
final class PlayerStoreSeekTests: XCTestCase {

    private func playingStore(seekMs: Int, durationSeconds: Int = 715) -> PlayerStore {
        let store = PlayerStore()
        var state = PlayerState.empty
        state.status = .play
        state.title = "Symphonic Dances, Op. 45: No. 1"
        state.duration = durationSeconds
        state.seek = seekMs
        store.receiveServerState(state)
        return store
    }

    func testRestartedTrackSnapsBackToServerPosition() {
        // The reported bug: the user restarts the current song. The server now
        // broadcasts the rewound position and the client must adopt it rather
        // than keep counting from where it had reached.
        let store = playingStore(seekMs: 242_000)
        let anchor = store.seekAnchor!

        store.tick(now: anchor.advanced(by: .seconds(10)))
        XCTAssertEqual(store.state.seek, 252_000)

        var restarted = store.state
        restarted.seek = 0
        store.receiveServerState(restarted)
        XCTAssertEqual(store.state.seek, 0)

        let newAnchor = store.seekAnchor!
        store.tick(now: newAnchor.advanced(by: .seconds(3)))
        XCTAssertEqual(store.state.seek, 3_000, "must project from the new anchor")
    }

    func testProjectsRealElapsedTimeNotTickCount() {
        // A `+1s per tick` accumulator reports whatever the timer managed to
        // deliver. Anchoring makes the result independent of tick count.
        let store = playingStore(seekMs: 0)
        let anchor = store.seekAnchor!

        store.tick(now: anchor.advanced(by: .seconds(120)))
        XCTAssertEqual(store.state.seek, 120_000)
    }

    func testDoesNotAdvanceWhilePaused() {
        let store = playingStore(seekMs: 30_000)
        var paused = store.state
        paused.status = .pause
        store.receiveServerState(paused)

        let anchor = store.seekAnchor!
        store.tick(now: anchor.advanced(by: .seconds(60)))
        XCTAssertEqual(store.state.seek, 30_000)
    }

    func testResumesFromServerPositionAfterPause() {
        let store = playingStore(seekMs: 100_000)
        var paused = store.state
        paused.status = .pause
        store.receiveServerState(paused)

        var resumed = store.state
        resumed.status = .play
        resumed.seek = 100_000
        store.receiveServerState(resumed)

        let anchor = store.seekAnchor!
        store.tick(now: anchor.advanced(by: .seconds(5)))
        XCTAssertEqual(store.state.seek, 105_000)
    }

    func testClampsAtTrackDuration() {
        let store = playingStore(seekMs: 710_000, durationSeconds: 715)
        let anchor = store.seekAnchor!

        store.tick(now: anchor.advanced(by: .seconds(60)))
        XCTAssertEqual(store.state.seek, 715_000)
    }

    func testAdvancesWithoutDurationWhenUnknown() {
        // Streams report no duration; projection must still run rather than
        // clamping the position to zero.
        let store = playingStore(seekMs: 5_000, durationSeconds: 0)
        let anchor = store.seekAnchor!

        store.tick(now: anchor.advanced(by: .seconds(30)))
        XCTAssertEqual(store.state.seek, 35_000)
    }

    func testQuantisesToWholeSeconds() {
        // Sub-second ticks must not publish, or @Observable re-renders the
        // SeekBar four times a second for no visible change.
        let store = playingStore(seekMs: 10_000)
        let anchor = store.seekAnchor!

        store.tick(now: anchor.advanced(by: .milliseconds(250)))
        XCTAssertEqual(store.state.seek, 10_000)

        store.tick(now: anchor.advanced(by: .milliseconds(1_100)))
        XCTAssertEqual(store.state.seek, 11_000)
    }
}

/// Coverage for the optimistic scrub path.
///
/// The regression these exist for: releasing the scrubber made the thumb jump
/// back to where the track had been, because `SeekBar` only shows the dragged
/// value while the finger is down and `state.seek` was not updated until the
/// server replied. Combined with the emit bug that dropped the seek entirely,
/// the thumb snapped back and stayed there — "nothing changed on the music".
@MainActor
final class PlayerStoreOptimisticSeekTests: XCTestCase {

    func testScrubMovesThePositionImmediately() {
        let store = PlayerStore()
        store.state.status = .play
        store.state.seek = 41_000

        store.applyOptimisticSeek(150_000)

        XCTAssertEqual(store.state.seek, 150_000,
                       "the scrubbed position must be visible before the server confirms")
        XCTAssertEqual(store.seekAnchorMs, 150_000,
                       "the interpolator must project forward from the new position")
    }

    func testScrubWhilePausedStillMovesThePosition() {
        // tick() returns early unless the server says .play, so anchoring
        // alone would leave a paused scrub with no visible effect at all.
        let store = PlayerStore()
        store.state.status = .pause
        store.state.seek = 41_000

        store.applyOptimisticSeek(10_000)

        XCTAssertEqual(store.state.seek, 10_000)
    }

    func testScrubToStartIsNotTreatedAsNoPosition() {
        let store = PlayerStore()
        store.state.status = .play
        store.state.seek = 41_000

        store.applyOptimisticSeek(0)

        XCTAssertEqual(store.state.seek, 0)
        XCTAssertEqual(store.seekAnchorMs, 0)
    }

    func testNegativePositionIsClampedToZero() {
        let store = PlayerStore()
        store.applyOptimisticSeek(-5_000)

        XCTAssertEqual(store.state.seek, 0)
        XCTAssertEqual(store.seekAnchorMs, 0)
    }

    func testServerStateOverridesAnOptimisticScrub() {
        let store = PlayerStore()
        store.state.status = .play
        store.applyOptimisticSeek(150_000)

        var authoritative = store.state
        authoritative.seek = 3_000
        store.receiveServerState(authoritative)

        XCTAssertEqual(store.state.seek, 3_000,
                       "server truth must win over the optimistic value")
        XCTAssertEqual(store.seekAnchorMs, 3_000)
    }
}
