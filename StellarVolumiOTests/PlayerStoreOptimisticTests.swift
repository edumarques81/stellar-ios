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

    /// External-play repro: user paused on iOS, then an LCD/web client presses
    /// play. Backend `pushState` arrives with status=.play but every other
    /// field identical (same track, same album art). The previous bind-block
    /// comparison checked status alongside other fields — verify that a
    /// status-only flip still routes through `receiveServerState` so the
    /// button + seek bar follow the external transport.
    func testReceiveServerStatePlayAfterPauseFlipsIsPlaying() {
        let store = PlayerStore()
        var paused = PlayerState.empty
        paused.status   = .pause
        paused.title    = "Time"
        paused.artist   = "Pink Floyd"
        paused.album    = "The Dark Side of the Moon"
        paused.albumart = "/albumart?path=NAS/Pink%20Floyd/Dark%20Side"
        paused.duration = 413
        paused.seek     = 134_000
        paused.volume   = 55
        store.state = paused
        XCTAssertFalse(store.isPlaying, "baseline: pause means not playing")

        // Same track, status flipped to play — this is what the backend
        // emits when an external client (LCD / web) resumes playback.
        var playing = paused
        playing.status = .play
        store.receiveServerState(playing)

        XCTAssertTrue(store.isPlaying,
                      "status=.play from server must flip isPlaying true")
        XCTAssertNil(store.optimisticStatus,
                     "receiveServerState must clear optimistic")
    }

    /// Album-art-only changes used to slip through the bind-block comparison
    /// because `albumart` wasn't in the diff list. Verify the store now
    /// updates art when only the albumart field differs.
    func testReceiveServerStateUpdatesAlbumArt() {
        let store = PlayerStore()
        var initial = PlayerState.empty
        initial.status   = .play
        initial.title    = "Time"
        initial.artist   = "Pink Floyd"
        initial.album    = "The Dark Side of the Moon"
        initial.albumart = "/albumart?path=old"
        store.state = initial

        var updated = initial
        updated.albumart = "/albumart?path=new"
        store.receiveServerState(updated)

        XCTAssertEqual(store.state.albumart, "/albumart?path=new")
    }

    /// SeekBar fix: while playing, calling `tick()` once per second must
    /// advance `state.seek` by 1000 ms so the bar moves between backend
    /// broadcasts (which are gated on status/title changes, not seek).
    func testTickAdvancesSeekWhilePlaying() {
        let store = PlayerStore()
        var s = PlayerState.empty
        s.status   = .play
        s.title    = "Time"
        s.seek     = 5_000      // 5 s in ms
        s.duration = 100        // 100 s
        store.state = s

        store.tick()
        XCTAssertEqual(store.state.seek, 6_000, "tick must advance seek by 1 s while playing")

        store.tick()
        XCTAssertEqual(store.state.seek, 7_000, "tick is idempotent at the per-second cadence")
    }

    /// `tick()` should be a no-op when paused / stopped (and when optimistic
    /// status is the source of "playing", tick should still gate on the
    /// server state — we never advance seek while the server says paused).
    func testTickDoesNothingWhilePaused() {
        let store = PlayerStore()
        var s = PlayerState.empty
        s.status   = .pause
        s.title    = "Time"
        s.seek     = 5_000
        s.duration = 100
        store.state = s

        store.tick()
        XCTAssertEqual(store.state.seek, 5_000, "tick must not advance seek while paused")
    }

    /// `tick()` must not run past the end of the track.
    func testTickClampsAtDuration() {
        let store = PlayerStore()
        var s = PlayerState.empty
        s.status   = .play
        s.title    = "Time"
        s.seek     = 99_500     // 99.5 s
        s.duration = 100        // 100 s
        store.state = s

        store.tick()
        XCTAssertEqual(store.state.seek, 100_000, "tick clamps to duration")

        store.tick()
        XCTAssertEqual(store.state.seek, 100_000, "tick stays clamped at duration")
    }
}
