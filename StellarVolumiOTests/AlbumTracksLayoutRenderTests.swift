import SwiftUI
import UIKit
import XCTest

@testable import StellarVolumiO

/// Phase 4: the Album Tracks screen is the one surface the root render tests
/// cannot reach — it lives behind a navigation push, and the parity sweep that
/// *can* reach it is not in the default scheme.
///
/// Its cover hero was a hard 240×240 and is now a size-class step, so it needs
/// its own net (LAYOUT-01, LAYOUT-04). The size class is overridden and the
/// idiom is injected, so both branches run whichever simulator the suite is on.
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

    private func render(size: CGSize,
                        sizeClass: UIUserInterfaceSizeClass,
                        idiom: UIUserInterfaceIdiom)
    -> (host: UIHostingController<AnyView>, env: StellarTestEnvironment) {
        let env = StellarTestEnvironment()
        let host = LayoutHosting.host(env.inject(into: AlbumTracksView(album: Self.album),
                                                 idiom: idiom),
                                      size: size,
                                      sizeClass: sizeClass)
        return (host, env)
    }

    /// Narrowest canvas the app can be handed (a Slide Over pane) through to a
    /// 13" detail column, at the size class and idiom each would really report.
    func testComposesAcrossTheCanvasRangeWithoutStrandingContent() {
        let cases: [(name: String, sizeClass: UIUserInterfaceSizeClass,
                     idiom: UIUserInterfaceIdiom, size: CGSize)] = [
            ("iPhone SE portrait",  .compact, .phone, CGSize(width: 375,  height: 667)),
            ("iPhone portrait",     .compact, .phone, CGSize(width: 393,  height: 852)),
            ("Slide Over",          .compact, .pad,   CGSize(width: 320,  height: 1024)),
            ("iPad mini detail",    .regular, .pad,   CGSize(width: 500,  height: 1133)),
            ("iPad 11in detail",    .regular, .pad,   CGSize(width: 560,  height: 1194)),
            ("iPad 13in landscape", .regular, .pad,   CGSize(width: 1096, height: 1024)),
        ]

        for c in cases {
            let rendered = render(size: c.size, sizeClass: c.sizeClass, idiom: c.idiom)
            LayoutHosting.assertNothingStrandedHorizontally(in: rendered.host)
            withExtendedLifetime(rendered.env) {}
        }
    }

    /// The case the size-class step gets wrong if the hero keeps a fixed frame.
    ///
    /// Regular width does **not** imply a wide detail column. The iPadOS
    /// compact/regular threshold is around 590 pt of *window*, and the sidebar
    /// takes ~320 pt of that, so a narrow Stage Manager window can hand the
    /// detail column under 280 pt — less than `heroSideRegular` (320). A hero
    /// pinned with `.frame(width:height:)` overflows the pane there and is
    /// clipped; `.frame(maxWidth:maxHeight:)` shrinks instead. This asserts the
    /// rendered result, not the token.
    func testHeroDoesNotOverflowANarrowRegularWidthDetailColumn() {
        let rendered = render(size: CGSize(width: 280, height: 900),
                              sizeClass: .regular,
                              idiom: .pad)
        LayoutHosting.assertNothingStrandedHorizontally(in: rendered.host)
        withExtendedLifetime(rendered.env) {}
    }

    /// The regular-width step is a step *up*, and the compact size is the
    /// phone's historical 240 — REG-01 in token form.
    func testHeroTokensStepUpFromTheUnchangedPhoneSize() {
        XCTAssertEqual(Stellar.Metric.heroSideCompact, 240,
                       "the phone's cover size must be byte-for-byte what it was")
        XCTAssertGreaterThan(Stellar.Metric.heroSideRegular, Stellar.Metric.heroSideCompact,
                             "the point of the regular-width step is that the cover grows")
    }

    /// The content column cap has to be wider than every iPhone, or the port
    /// would have quietly narrowed the phone (REG-01).
    func testContentCapIsWiderThanAnyIPhone() {
        let widestIPhonePortrait: CGFloat = 440   // 16 Pro Max
        XCTAssertGreaterThan(Stellar.Metric.contentMaxWidth, widestIPhonePortrait)
    }
}
