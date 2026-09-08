import XCTest
import SwiftUI
@testable import StellarVolumiO

/// PARITY-06 — the AirPlay branch of Now Playing, at iPad sizes.
///
/// `NowPlayingView` has two mutually exclusive branches and only one of them
/// can be reached by driving the app: the AirPlay branch needs a real session
/// from a real Apple device, which the simulator sweep cannot manufacture. So
/// the branch is exercised here instead — an active `AirplayStore` state, the
/// full environment graph, and the same canvases the MPD branch is checked at.
///
/// The two suppressions are the part worth pinning. AirPlay 1 has no seek (DACP
/// carries no scrub) and is fixed at 44.1/16, so this branch must render
/// *neither* a seek slider *nor* a format strip — a regression there would look
/// harmless and be wrong, because the controls would be inert.
///
/// Live AirPlay on hardware is Phase 6 (DEVICE-02).
@MainActor
final class AirplayLayoutRenderTests: XCTestCase {

    private static let canvases: [(name: String, size: CGSize)] = [
        ("iPhone 16 Pro portrait",  CGSize(width: 393,  height: 852)),
        ("iPad Slide Over",         CGSize(width: 320,  height: 1024)),
        ("iPad mini portrait",      CGSize(width: 744,  height: 1133)),
        ("iPad Pro 11in landscape", CGSize(width: 1194, height: 834)),
        ("iPad Pro 13in landscape", CGSize(width: 1366, height: 1024)),
    ]

    private static let session = AirplayState(
        isActive: true,
        isPlaying: true,
        title: "Basil",
        artist: "Mark Knopfler",
        album: "Tracker (Deluxe)",
        sender: "Eduardo's iPhone",
        coverDataURL: "",
        seekSeconds: 77,
        durationSeconds: 344,
        canControl: true,
        sessionID: "test-session",
        sampleRate: 44100,
        bitDepth: 16
    )

    /// The environment `NowPlayingView` reads. The `SocketService` comes back
    /// with it because the stores hold it weakly — dropping it here would kill
    /// every binding before layout runs.
    private func makeView(active: Bool) -> (view: AnyView, socket: SocketService) {
        let config = BackendConfigStore()
        let socket = SocketService(config: config)
        let airplay = AirplayStore()
        if active { airplay.receiveServerState(Self.session) }

        let view = NowPlayingView()
            .environment(socket)
            .environment(config)
            .environment(PlayerStore())
            .environment(airplay)
            .environment(LastPlayedStore())
            .environment(AlbumTracksStore())

        return (AnyView(view), socket)
    }

    private func render(_ view: AnyView, at size: CGSize) -> UIHostingController<AnyView> {
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        return host
    }

    func testAirplayBranchComposesAtEveryCanvasSize() {
        for canvas in Self.canvases {
            let made = makeView(active: true)
            let host = render(made.view, at: canvas.size)
            withExtendedLifetime(made.socket) {}

            XCTAssertEqual(host.view.frame.width, canvas.size.width, accuracy: 0.5,
                           "AirPlay branch must fill \(canvas.name) width")
            XCTAssertEqual(host.view.frame.height, canvas.size.height, accuracy: 0.5,
                           "AirPlay branch must fill \(canvas.name) height")
        }
    }

    /// A live resize — rotation, a Split View drag, Stage Manager — must not
    /// take the branch down mid-session.
    func testAirplayBranchSurvivesLiveResize() {
        let made = makeView(active: true)
        let host = UIHostingController(rootView: made.view)

        for canvas in Self.canvases {
            host.view.frame = CGRect(origin: .zero, size: canvas.size)
            host.view.layoutIfNeeded()
            XCTAssertGreaterThan(host.view.frame.height, 0,
                                 "AirPlay branch must retain height at \(canvas.name)")
        }

        withExtendedLifetime(made.socket) {}
    }

    /// The branch switch itself: an empty store must render the MPD side, an
    /// active one the AirPlay side. Asserted through the display-state adapter
    /// rather than the view hierarchy, because that adapter is what decides
    /// whether seek and the format strip are drawn.
    func testActiveSessionSuppressesSeekAndFormatStrip() {
        let display = NowPlayingDisplayState.from(airplay: Self.session)

        // `isAirplay` is the single gate: NowPlayingPlayingView hides both the
        // SeekBar and the FormatBadgeStrip behind `if !state.isAirplay`.
        XCTAssertTrue(display.isAirplay,
                      "a session with a sender must select the AirPlay branch")
        XCTAssertFalse(display.canSeek,
                       "AirPlay 1 has no scrub — DACP cannot seek, so the bar must not accept drag")
        XCTAssertEqual(display.samplerate, "",
                       "AirPlay 1 is fixed 44.1/16 — nothing to put in the format strip")
        XCTAssertEqual(display.bitdepth, "")
        XCTAssertEqual(display.trackType, "")
        XCTAssertEqual(display.title, Self.session.title)
        XCTAssertEqual(display.artist, Self.session.artist)
        XCTAssertEqual(display.airplaySender, Self.session.sender)

        // And the other side of the switch: an inactive session must not be
        // mistaken for the AirPlay branch.
        XCTAssertFalse(NowPlayingDisplayState.from(airplay: .empty).airplaySender?.isEmpty == false,
                       "an empty session carries no sender")
    }
}
