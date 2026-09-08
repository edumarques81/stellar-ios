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

    private static let canvases: [(name: String, sizeClass: UIUserInterfaceSizeClass,
                                   idiom: UIUserInterfaceIdiom, size: CGSize)] = [
        ("iPhone 16 Pro portrait",  .compact, .phone, CGSize(width: 393,  height: 852)),
        ("iPad Slide Over",         .compact, .pad,   CGSize(width: 320,  height: 1024)),
        ("iPad mini portrait",      .regular, .pad,   CGSize(width: 744,  height: 1133)),
        ("iPad Pro 11in landscape", .regular, .pad,   CGSize(width: 1194, height: 834)),
        ("iPad Pro 13in landscape", .regular, .pad,   CGSize(width: 1366, height: 1024)),
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

    private func render(size: CGSize,
                        sizeClass: UIUserInterfaceSizeClass,
                        idiom: UIUserInterfaceIdiom)
    -> (host: UIHostingController<AnyView>, env: StellarTestEnvironment) {
        let env = StellarTestEnvironment()
        env.airplay.receiveServerState(Self.session)
        let host = LayoutHosting.host(env.inject(into: NowPlayingView(), idiom: idiom),
                                      size: size,
                                      sizeClass: sizeClass)
        return (host, env)
    }

    func testAirplayBranchComposesAtEveryCanvasSize() {
        for canvas in Self.canvases {
            let rendered = render(size: canvas.size,
                                  sizeClass: canvas.sizeClass,
                                  idiom: canvas.idiom)
            LayoutHosting.assertNothingStrandedHorizontally(in: rendered.host)
            withExtendedLifetime(rendered.env) {}
        }
    }

    /// A live resize — rotation, a Split View drag, Stage Manager — must not
    /// take the branch down mid-session.
    func testAirplayBranchSurvivesLiveResize() {
        let env = StellarTestEnvironment()
        env.airplay.receiveServerState(Self.session)
        let host = LayoutHosting.host(env.inject(into: NowPlayingView(), idiom: .pad),
                                      size: Self.canvases[0].size,
                                      sizeClass: .regular)

        for canvas in Self.canvases {
            host.view.frame = CGRect(origin: .zero, size: canvas.size)
            host.view.layoutIfNeeded()
            XCTAssertGreaterThan(host.view.frame.height, 0,
                                 "AirPlay branch must retain height at \(canvas.name)")
            LayoutHosting.assertNothingStrandedHorizontally(in: host)
        }

        withExtendedLifetime(env) {}
    }

    /// The suppression contract, asserted through the display-state adapter —
    /// that adapter is what decides whether seek and the format strip are drawn
    /// (`NowPlayingPlayingView` hides both behind `if !state.isAirplay`).
    func testActiveSessionSuppressesSeekAndFormatStrip() {
        let display = NowPlayingDisplayState.from(airplay: Self.session)

        XCTAssertEqual(display.airplaySender, Self.session.sender,
                       "the sender name is what flags the AirPlay branch to the renderer")
        XCTAssertTrue(display.isAirplay)
        XCTAssertFalse(display.canSeek,
                       "AirPlay 1 has no scrub — DACP cannot seek, so the bar must not accept drag")
        XCTAssertEqual(display.samplerate, "",
                       "AirPlay 1 is fixed 44.1/16 — nothing to put in the format strip")
        XCTAssertEqual(display.bitdepth, "")
        XCTAssertEqual(display.trackType, "")
        XCTAssertEqual(display.title, Self.session.title)
        XCTAssertEqual(display.artist, Self.session.artist)

        // The MPD branch is the other side of the switch, and it comes from a
        // different constructor entirely — `airplaySender` is nil there, so
        // `isAirplay` is false and both the seek bar and the format strip draw.
        XCTAssertFalse(NowPlayingDisplayState(
            title: "", artist: "", album: "", trackType: "flac",
            samplerate: "96 kHz", bitdepth: "24 bit",
            seekSeconds: 0, durationSeconds: 0, isPlaying: false,
            canSeek: true, canControl: true,
            airplaySender: nil, albumArt: .none).isAirplay)
    }

    /// Documented latent defect, deliberately asserted as-is rather than fixed.
    ///
    /// `from(airplay:)` maps `airplaySender: s.sender` unconditionally, and
    /// `AirplayState.empty.sender` is `""` — not nil — so an *empty* session
    /// adapts to a state that claims to be the AirPlay branch. It is latent
    /// only: `NowPlayingView` reaches the adapter exclusively when
    /// `airplay.state.isActive`, so an empty state never gets there. Changing
    /// the adapter to map `""` to nil would be correct, but it is an iPhone
    /// behaviour change and out of scope for the iPad port. Pinned here so the
    /// next reader finds it deliberate instead of rediscovering it.
    func testEmptySessionAdaptsToAFalsePositiveAirplayFlag_knownLatentDefect() {
        let adapted = NowPlayingDisplayState.from(airplay: .empty)
        XCTAssertEqual(adapted.airplaySender, "",
                       "empty sender maps through as empty string, not nil")
        XCTAssertTrue(adapted.isAirplay,
                      "known latent defect — unreachable because the caller gates on isActive")
    }
}
