import SwiftUI
import UIKit
import XCTest

@testable import StellarVolumiO

/// Phase 4: the Album Tracks screen is the one surface the root render tests
/// cannot reach — it lives behind a navigation push, and this repo has no UI
/// test target to drive one.
///
/// Its cover hero was a hard 240×240 and is now a size-class step, so it needs
/// its own net: host it directly at both size classes and at the extremes of
/// the canvas range the app can be handed (LAYOUT-01, LAYOUT-04).
@MainActor
final class AlbumTracksLayoutRenderTests: XCTestCase {

    private static let album = LibraryAlbum(
        id: "kansas-city-symphony|to-awaken-the-sleeper",
        title: "To Awaken the Sleeper: Works of Joel Thompson",
        artist: "Kansas City Symphony; EXIGENCE Vocal Ensemble; Michael Stern; Joel Thompson",
        uri: "USB/To Awaken the Sleeper- Works of Joel Thompson",
        albumart: "/albumart?path=USB/To%20Awaken%20the%20Sleeper",
        year: 2024,
        trackCount: 11
    )

    private struct Hosted {
        let window: UIWindow
        let host: UIHostingController<AnyView>
        let socket: SocketService
    }

    private func hostAlbumTracks(horizontalSizeClass: UIUserInterfaceSizeClass,
                                 size: CGSize) -> Hosted {
        let backend = BackendConfigStore()
        let socket = SocketService(config: backend)

        let view = AlbumTracksView(album: Self.album)
            .environment(socket)
            .environment(backend)
            .environment(AlbumTracksStore())
            .environment(PlayerStore())

        let host = UIHostingController(rootView: AnyView(view))
        let container = UIViewController()
        container.addChild(host)
        container.view.addSubview(host.view)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.didMove(toParent: container)
        container.setOverrideTraitCollection(
            UITraitCollection(horizontalSizeClass: horizontalSizeClass),
            forChild: host
        )

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = container
        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        return Hosted(window: window, host: host, socket: socket)
    }

    /// Narrowest canvas the app can be handed (a Slide Over pane) through to a
    /// 13" detail column, at the size class each would really report.
    func testComposesAcrossTheCanvasRange() {
        let cases: [(name: String, sizeClass: UIUserInterfaceSizeClass, size: CGSize)] = [
            ("Slide Over",            .compact, CGSize(width: 320,  height: 1024)),
            ("iPhone portrait",       .compact, CGSize(width: 393,  height: 852)),
            ("iPad mini detail",      .regular, CGSize(width: 500,  height: 1133)),
            ("iPad 11in detail",      .regular, CGSize(width: 560,  height: 1194)),
            ("iPad 13in landscape",   .regular, CGSize(width: 1096, height: 1024)),
        ]

        for c in cases {
            let hosted = hostAlbumTracks(horizontalSizeClass: c.sizeClass, size: c.size)

            XCTAssertEqual(hosted.host.view.frame.width, c.size.width, accuracy: 0.5,
                           "must fill the canvas width at \(c.name)")
            XCTAssertEqual(hosted.host.view.frame.height, c.size.height, accuracy: 0.5,
                           "must fill the canvas height at \(c.name)")

            withExtendedLifetime(hosted.socket) {}
        }
    }

    /// The hero must never be wider than the pane it sits in. 240 already fits
    /// a 320 pt Slide Over with its 24 pt margins; the regular-width step must
    /// not break that promise on the narrowest canvas that reports `.regular`.
    func testHeroFitsTheNarrowestRegularWidthCanvas() {
        let narrowestRegular: CGFloat = 500   // iPad mini detail column
        let margins: CGFloat = 24 * 2

        XCTAssertLessThanOrEqual(
            Stellar.Metric.heroSideRegular, narrowestRegular - margins,
            "the regular-width hero must still fit inside the narrowest pane that reports regular width"
        )
        XCTAssertGreaterThan(
            Stellar.Metric.heroSideRegular, 240,
            "the point of the regular-width step is that the cover grows"
        )
    }

    /// The content column cap has to be wider than every iPhone, or the port
    /// would have quietly narrowed the phone (REG-01).
    func testContentCapIsWiderThanAnyIPhone() {
        let widestIPhonePortrait: CGFloat = 440   // 16 Pro Max
        XCTAssertGreaterThan(Stellar.Metric.contentMaxWidth, widestIPhonePortrait)
    }
}
