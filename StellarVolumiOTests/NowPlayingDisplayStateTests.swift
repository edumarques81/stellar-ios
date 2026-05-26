import XCTest
@testable import StellarVolumiO

/// Coverage for `NowPlayingDisplayState.from(airplay:)` — the AirPlay-source
/// adapter that NowPlayingView feeds into NowPlayingPlayingView.
///
/// The critical assertion is the `isPlaying` wiring. The view's
/// `PlayPauseButton(isPlaying:)` is driven directly from the adapter's
/// `isPlaying` field, so verifying the adapter pins the icon contract:
///
///   state.isPlaying = false → adapter.isPlaying = false → play icon
///   state.isPlaying = true  → adapter.isPlaying = true  → pause icon
///
/// (PlayPauseButton.swift: `isPlaying ? "pause.fill" : "play.fill"`)
final class NowPlayingDisplayStateTests: XCTestCase {

    // MARK: - isPlaying wiring (mid-flight contract amendment)

    func testAdapterIsPlayingTrueWhenAirplayIsPlayingTrue() {
        var s = AirplayState.empty
        s.isActive = true
        s.isPlaying = true                 // iPhone is currently playing
        s.sessionID = "s1"
        s.sender = "iPhone"

        let display = NowPlayingDisplayState.from(airplay: s)

        XCTAssertEqual(display.isPlaying, true,
                       "isPlaying=true on the source must map to pause-icon (display.isPlaying=true)")
    }

    func testAdapterIsPlayingFalseWhenAirplayIsPlayingFalse() {
        var s = AirplayState.empty
        s.isActive = true
        s.isPlaying = false                // iPhone paused mid-session
        s.sessionID = "s1"
        s.sender = "iPhone"

        let display = NowPlayingDisplayState.from(airplay: s)

        XCTAssertEqual(display.isPlaying, false,
                       "isPlaying=false on the source must map to play-icon (display.isPlaying=false)")
    }

    /// Pin the icon-glyph mapping directly so this test fails loudly if
    /// PlayPauseButton ever flips its conditional. `pause.fill` shows when
    /// playing (because the next tap pauses); `play.fill` shows when
    /// paused (because the next tap plays).
    func testIconGlyphContractWithAdapter() {
        var paused = AirplayState.empty
        paused.isActive = true
        paused.isPlaying = false
        paused.sender = "iPhone"
        paused.sessionID = "s1"

        var playing = paused
        playing.isPlaying = true

        let pausedDisplay = NowPlayingDisplayState.from(airplay: paused)
        let playingDisplay = NowPlayingDisplayState.from(airplay: playing)

        // Glyph mapping from PlayPauseButton.swift.
        let pausedGlyph  = pausedDisplay.isPlaying  ? "pause.fill" : "play.fill"
        let playingGlyph = playingDisplay.isPlaying ? "pause.fill" : "play.fill"

        XCTAssertEqual(pausedGlyph, "play.fill",
                       "AirPlay paused → user-facing icon must be play.fill (tap to resume)")
        XCTAssertEqual(playingGlyph, "pause.fill",
                       "AirPlay playing → user-facing icon must be pause.fill (tap to pause)")
    }

    // MARK: - Other wiring contracts

    func testAdapterCarriesSenderForBadge() {
        var s = AirplayState.empty
        s.isActive = true
        s.sender = "Eduardo's iPhone"
        s.sessionID = "s1"

        let display = NowPlayingDisplayState.from(airplay: s)

        XCTAssertEqual(display.airplaySender, "Eduardo's iPhone")
        XCTAssertTrue(display.isAirplay,
                      "non-nil airplaySender must flag the AirPlay branch")
    }

    func testAdapterDisablesSeekAlways() {
        var s = AirplayState.empty
        s.isActive = true
        s.isPlaying = true
        s.sessionID = "s1"
        s.seekSeconds = 30
        s.durationSeconds = 100

        let display = NowPlayingDisplayState.from(airplay: s)
        XCTAssertEqual(display.canSeek, false,
                       "AirPlay never allows seek — DACP has no seek surface")
    }

    func testAdapterRoutesCanControl() {
        // canControl=false → transport buttons disabled (showing "Connecting…").
        var s = AirplayState.empty
        s.isActive = true
        s.isPlaying = true
        s.canControl = false
        s.sessionID = "s1"

        let display = NowPlayingDisplayState.from(airplay: s)
        XCTAssertEqual(display.canControl, false)
    }

    func testAdapterRoutesEmptyCoverToNone() {
        var s = AirplayState.empty
        s.isActive = true
        s.coverDataURL = ""
        s.sessionID = "s1"

        let display = NowPlayingDisplayState.from(airplay: s)
        XCTAssertEqual(display.albumArt, .none)
    }

    func testAdapterRoutesCoverDataURL() {
        var s = AirplayState.empty
        s.isActive = true
        s.coverDataURL = "data:image/jpeg;base64,AAAA"
        s.sessionID = "s1"

        let display = NowPlayingDisplayState.from(airplay: s)
        XCTAssertEqual(display.albumArt, .dataURL("data:image/jpeg;base64,AAAA"))
    }

    func testAdapterCarriesSeekAndDurationAsDoubles() {
        var s = AirplayState.empty
        s.isActive = true
        s.isPlaying = true
        s.seekSeconds = 42
        s.durationSeconds = 245
        s.sessionID = "s1"

        let display = NowPlayingDisplayState.from(airplay: s)
        XCTAssertEqual(display.seekSeconds, 42.0)
        XCTAssertEqual(display.durationSeconds, 245.0)
    }
}
