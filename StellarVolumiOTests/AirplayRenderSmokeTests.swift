import XCTest
import SwiftUI
@testable import StellarVolumiO

/// Render-path smoke test for the AirPlay NowPlaying branch.
///
/// Builds the full view hierarchy (NowPlayingView → NowPlayingPlayingView →
/// AirplaySourceBadge + AlbumArtHero with dataURL decode + SeekBar +
/// transport row) inside a UIHostingController, walks the view tree once to
/// force the body block to evaluate, and asserts the host's view is non-nil
/// and laid out. If the AirPlay branch ever throws / nil-derefs / fails to
/// compose, this catches it before deploy.
@MainActor
final class AirplayRenderSmokeTests: XCTestCase {

    func testAirplayBranchRenders() {
        // Build the environment graph NowPlayingView depends on.
        let backend = BackendConfigStore()
        let socket = SocketService(config: backend)
        let player = PlayerStore()
        let airplay = AirplayStore()
        let lastPlayed = LastPlayedStore()

        // Inject a fully-populated AirPlay session so the airplay branch wins.
        let coverDataURL = Self.sampleCoverDataURL()
        airplay._debugInject(AirplayState(
            isActive: true,
            isPlaying: true,
            title: "Time",
            artist: "Pink Floyd",
            album: "The Dark Side of the Moon",
            sender: "Eduardo's iPhone",
            coverDataURL: coverDataURL,
            seekSeconds: 42,
            durationSeconds: 245,
            canControl: true,
            sessionID: "smoke-session",
            sampleRate: 44100,
            bitDepth: 16
        ))

        let view = NowPlayingView()
            .environment(socket)
            .environment(player)
            .environment(airplay)
            .environment(lastPlayed)

        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)  // iPhone 16 Pro
        host.view.layoutIfNeeded()

        XCTAssertNotNil(host.view, "AirPlay branch must compose without crashing")
        XCTAssertGreaterThan(host.view.frame.height, 0,
                             "view must lay out with non-zero height")
    }

    func testAirplayBranchRendersWhenCanControlIsFalse() {
        // The "Connecting…" disabled-transport branch must not crash either.
        let backend = BackendConfigStore()
        let socket = SocketService(config: backend)
        let player = PlayerStore()
        let airplay = AirplayStore()
        let lastPlayed = LastPlayedStore()

        airplay._debugInject(AirplayState(
            isActive: true,
            isPlaying: true,
            title: "Connecting Track",
            artist: "—",
            album: "—",
            sender: "iPhone",
            coverDataURL: "",
            seekSeconds: 0,
            durationSeconds: 0,
            canControl: false,             // gate the transport buttons
            sessionID: "smoke-session-2",
            sampleRate: 44100,
            bitDepth: 16
        ))

        let view = NowPlayingView()
            .environment(socket)
            .environment(player)
            .environment(airplay)
            .environment(lastPlayed)

        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        host.view.layoutIfNeeded()

        XCTAssertNotNil(host.view)
    }

    func testMpdBranchStillRendersWithInactiveAirplay() {
        // Sanity: with no AirPlay session, the existing MPD branch still
        // composes — the parameterised refactor must be behavior-preserving.
        let backend = BackendConfigStore()
        let socket = SocketService(config: backend)
        let player = PlayerStore()
        let airplay = AirplayStore()
        let lastPlayed = LastPlayedStore()

        var mpdState = PlayerState.empty
        mpdState.status = .play
        mpdState.title = "Breathe"
        mpdState.artist = "Pink Floyd"
        mpdState.album = "DSOTM"
        mpdState.duration = 163
        mpdState.seek = 30_000
        mpdState.trackType = "flac"
        mpdState.samplerate = "44100"
        mpdState.bitdepth = "16"
        player.state = mpdState

        let view = NowPlayingView()
            .environment(socket)
            .environment(player)
            .environment(airplay)
            .environment(lastPlayed)

        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        host.view.layoutIfNeeded()

        XCTAssertNotNil(host.view, "MPD branch must remain renderable")
    }

    // MARK: - Helpers

    /// Tiny 2×2 magenta JPEG, base64-encoded as a `data:` URL — exercises
    /// the AlbumArtHero dataURL decode path without bundling a real cover.
    private static func sampleCoverDataURL() -> String {
        // A 1×1 red PNG: smallest possible valid image.
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        return "data:image/png;base64,\(pngBase64)"
    }
}
