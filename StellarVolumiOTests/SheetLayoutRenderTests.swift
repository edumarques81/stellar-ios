import XCTest
import SwiftUI
@testable import StellarVolumiO

/// LAYOUT-07 — the two sheets on a large canvas.
///
/// On iPad a `.sheet` is a form sheet: a fixed-ish card floated over the app,
/// roughly 540×620 in portrait, *not* the full screen the phone gives it. Both
/// sheets are a `NavigationStack` over scrolling content sized `maxWidth:
/// .infinity`, so they should simply fill whatever card they are handed — but
/// "should" is the part worth pinning, because a hardcoded width added later
/// would strand content inside the card with no visible failure on the phone.
///
/// These host each sheet's *content* at the canvases the system actually uses
/// and assert on the rendered hierarchy: nothing may sit outside the card.
@MainActor
final class SheetLayoutRenderTests: XCTestCase {

    /// Canvases a sheet is handed. The phone gets the whole screen; the iPad
    /// gets a form sheet, and a Slide Over pane shrinks that further.
    private static let canvases: [(name: String, sizeClass: UIUserInterfaceSizeClass,
                                   idiom: UIUserInterfaceIdiom, size: CGSize)] = [
        ("iPhone full screen",    .compact, .phone, CGSize(width: 393, height: 852)),
        ("iPad form sheet",       .regular, .pad,   CGSize(width: 540, height: 620)),
        ("iPad form sheet, wide", .regular, .pad,   CGSize(width: 704, height: 820)),
        ("Slide Over sheet",      .compact, .pad,   CGSize(width: 320, height: 700)),
    ]

    func testBackendDiscoverySheetComposesAtEveryPresentationSize() {
        for canvas in Self.canvases {
            let env = StellarTestEnvironment()
            let host = LayoutHosting.host(
                env.inject(into: BackendDiscoverySheet(onSelected: {}), idiom: canvas.idiom),
                size: canvas.size,
                sizeClass: canvas.sizeClass)

            LayoutHosting.assertNothingStrandedHorizontally(in: host)
            withExtendedLifetime(env) {}
        }
    }

    func testIngestSheetComposesAtEveryPresentationSize() {
        for canvas in Self.canvases {
            let env = StellarTestEnvironment()
            let host = LayoutHosting.host(
                env.inject(into: IngestSheet(), idiom: canvas.idiom),
                size: canvas.size,
                sizeClass: canvas.sizeClass)

            LayoutHosting.assertNothingStrandedHorizontally(in: host)
            withExtendedLifetime(env) {}
        }
    }
}
