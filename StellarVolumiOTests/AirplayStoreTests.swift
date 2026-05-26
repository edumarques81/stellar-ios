import XCTest
@testable import StellarVolumiO

/// Coverage for `AirplayStore` — the sibling of `PlayerStore` that owns the
/// AirPlay-source view of the world. Mirrors the assertions in
/// `PlayerStoreOptimisticTests` where they overlap.
///
/// Contract under test:
///  1. `receiveServerState` replaces state and flips isActive.
///  2. `receiveEnded` with a matching sessionID clears state.
///  3. `receiveEnded` with a mismatched sessionID is a no-op (no stale wipes).
///  4. `receiveEnded` before any state arrives is a no-op (defensive).
///  5. `tick()` advances seekSeconds while active and clamps at duration.
///  6. `tick()` is a no-op while inactive.
///  7. Command emitters call `airplay:command` with the matching `cmd`.
@MainActor
final class AirplayStoreTests: XCTestCase {

    // MARK: - State update + isActive flip

    func testReceiveServerStateReplacesState() {
        let store = AirplayStore()
        XCTAssertFalse(store.state.isActive)

        let s = AirplayState(
            isActive: true,
            title: "Time",
            artist: "Pink Floyd",
            album: "DSOTM",
            sender: "Eduardo's iPhone",
            coverDataURL: "",
            seekSeconds: 10,
            durationSeconds: 100,
            canControl: true,
            sessionID: "s-1",
            sampleRate: 44100,
            bitDepth: 16
        )
        store.receiveServerState(s)

        XCTAssertTrue(store.state.isActive)
        XCTAssertEqual(store.state.title, "Time")
        XCTAssertEqual(store.state.sessionID, "s-1")
    }

    // MARK: - Ended with matching sessionID clears

    func testReceiveEndedClearsWhenSessionIDMatches() {
        let store = AirplayStore()
        var s = AirplayState.empty
        s.isActive = true
        s.sessionID = "session-abc"
        s.title = "Time"
        store.state = s

        store.receiveEnded(AirplayEnded(sessionID: "session-abc"))

        XCTAssertFalse(store.state.isActive,
                       "matching sessionID must clear the active session")
        XCTAssertEqual(store.state.sessionID, "",
                       "cleared session must reset to .empty")
        XCTAssertEqual(store.state.title, "",
                       "cleared session must reset title")
    }

    // MARK: - Stale-ended guard

    /// Critical guard: a delayed `pushAirplayEnded` for an old session must
    /// not wipe out a fresh session that has already started. Without this
    /// check the UI would flicker back to the MPD branch every time a session
    /// turnover happens fast enough for the events to arrive out of order.
    func testReceiveEndedIgnoresMismatchedSessionID() {
        let store = AirplayStore()
        var s = AirplayState.empty
        s.isActive = true
        s.sessionID = "fresh-session"
        s.title = "Time"
        store.state = s

        store.receiveEnded(AirplayEnded(sessionID: "stale-session"))

        XCTAssertTrue(store.state.isActive,
                      "stale ended must not clear a fresh session")
        XCTAssertEqual(store.state.sessionID, "fresh-session",
                       "current sessionID must survive a stale ended")
        XCTAssertEqual(store.state.title, "Time",
                       "current state must survive a stale ended")
    }

    /// Defensive: an `Ended` that arrives before any state push (so the
    /// store still holds `.empty` with sessionID="") must be a no-op rather
    /// than match the empty-string sessionID and "clear" already-empty state.
    func testReceiveEndedBeforeAnyStateIsNoOp() {
        let store = AirplayStore()
        XCTAssertEqual(store.state.sessionID, "")

        store.receiveEnded(AirplayEnded(sessionID: ""))
        XCTAssertFalse(store.state.isActive,
                       "no state means nothing to clear; isActive stays false")

        store.receiveEnded(AirplayEnded(sessionID: "anything"))
        XCTAssertFalse(store.state.isActive)
    }

    // MARK: - Seek ticker

    func testTickAdvancesSeekWhileActive() {
        let store = AirplayStore()
        var s = AirplayState.empty
        s.isActive = true
        s.sessionID = "s-1"
        s.seekSeconds = 5
        s.durationSeconds = 100
        store.state = s

        store.tick()
        XCTAssertEqual(store.state.seekSeconds, 6,
                       "tick must advance seekSeconds by 1 while active")

        store.tick()
        XCTAssertEqual(store.state.seekSeconds, 7)
    }

    func testTickDoesNothingWhileInactive() {
        let store = AirplayStore()
        var s = AirplayState.empty
        s.isActive = false       // not active
        s.seekSeconds = 5
        s.durationSeconds = 100
        store.state = s

        store.tick()
        XCTAssertEqual(store.state.seekSeconds, 5,
                       "tick must not advance seekSeconds while inactive")
    }

    func testTickClampsAtDuration() {
        let store = AirplayStore()
        var s = AirplayState.empty
        s.isActive = true
        s.sessionID = "s-1"
        s.seekSeconds = 99
        s.durationSeconds = 100
        store.state = s

        store.tick()
        XCTAssertEqual(store.state.seekSeconds, 100, "tick clamps at duration")

        store.tick()
        XCTAssertEqual(store.state.seekSeconds, 100, "tick stays clamped at duration")
    }

    func testTickWithZeroDurationStillAdvances() {
        // Some AirPlay sources (e.g. radio streams) don't publish a duration.
        // The seek bar in that mode is purely informational; we still advance
        // seekSeconds so the elapsed counter ticks.
        let store = AirplayStore()
        var s = AirplayState.empty
        s.isActive = true
        s.sessionID = "s-1"
        s.seekSeconds = 30
        s.durationSeconds = 0
        store.state = s

        store.tick()
        XCTAssertEqual(store.state.seekSeconds, 31,
                       "duration=0 must not block the elapsed counter")
    }

    // MARK: - Command emitters route to airplay:command

    func testPlayCommandEmitsAirplayPlay() {
        let socket = SocketService()
        socket.resetEmittedObjectCapture()
        let store = AirplayStore()
        store.bind(to: socket)

        store.play()

        XCTAssertEqual(socket.lastEmittedObjectEvent, "airplay:command",
                       "play() must emit airplay:command, not MPD `play`")
        XCTAssertEqual(socket.lastEmittedObjectPayload?["cmd"] as? String, "play")
    }

    func testPauseCommandEmitsAirplayPause() {
        let socket = SocketService()
        socket.resetEmittedObjectCapture()
        let store = AirplayStore()
        store.bind(to: socket)

        store.pause()

        XCTAssertEqual(socket.lastEmittedObjectEvent, "airplay:command")
        XCTAssertEqual(socket.lastEmittedObjectPayload?["cmd"] as? String, "pause")
    }

    func testPlayPauseCommandEmitsAirplayToggle() {
        let socket = SocketService()
        socket.resetEmittedObjectCapture()
        let store = AirplayStore()
        store.bind(to: socket)

        store.playPause()

        XCTAssertEqual(socket.lastEmittedObjectEvent, "airplay:command")
        XCTAssertEqual(socket.lastEmittedObjectPayload?["cmd"] as? String, "toggle")
    }

    func testNextCommandEmitsAirplayNext() {
        let socket = SocketService()
        socket.resetEmittedObjectCapture()
        let store = AirplayStore()
        store.bind(to: socket)

        store.next()

        XCTAssertEqual(socket.lastEmittedObjectEvent, "airplay:command")
        XCTAssertEqual(socket.lastEmittedObjectPayload?["cmd"] as? String, "next")
    }

    func testPrevCommandEmitsAirplayPrev() {
        let socket = SocketService()
        socket.resetEmittedObjectCapture()
        let store = AirplayStore()
        store.bind(to: socket)

        store.prev()

        XCTAssertEqual(socket.lastEmittedObjectEvent, "airplay:command")
        XCTAssertEqual(socket.lastEmittedObjectPayload?["cmd"] as? String, "prev")
    }

    /// Commands fired before `bind(to:)` must not crash — the store's
    /// `weak var socket` is nil at that point. Mirror of
    /// `LcdStoreTests.testSetOnWithNoSocketBoundIsNoOp`.
    func testCommandsWithNoSocketBoundAreNoOp() {
        let store = AirplayStore()
        store.play()
        store.pause()
        store.playPause()
        store.next()
        store.prev()
        // No crash; nothing to assert beyond reaching this line.
    }
}
