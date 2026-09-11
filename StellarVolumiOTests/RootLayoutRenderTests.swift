import XCTest
import SwiftUI
@testable import StellarVolumiO

/// Geometry regression net for the iPad port.
///
/// The port rewrites `ContentView`'s root navigation, and both the iPhone and
/// iPad branches live in that one file. There is no UI test target in the
/// default scheme, so the only thing standing between a sidebar refactor and a
/// silently broken iPhone build is a render-path test.
///
/// These host the *real* root view — the full environment graph, the same one
/// `StellarApp` injects — at concrete canvas sizes, in a real window, with the
/// idiom injected so both shells are exercised whichever simulator the suite
/// runs on. The assertion is `assertNothingStrandedHorizontally`, which walks
/// the rendered UIKit hierarchy; a branch that crashes, fails to compose, or
/// pushes content off the side of the canvas fails here.
///
/// Sizes are point sizes in portrait unless stated. Slide Over is the narrowest
/// canvas the app can be handed once `UIRequiresFullScreen` is removed, and is
/// narrower than any iPhone — it is the size most likely to strand content.
@MainActor
final class RootLayoutRenderTests: XCTestCase {

    private static let phoneCanvases: [(name: String, size: CGSize)] = [
        ("iPhone SE portrait",      CGSize(width: 375,  height: 667)),
        ("iPhone 16 Pro portrait",  CGSize(width: 393,  height: 852)),
        ("iPhone 16 Pro Max",       CGSize(width: 440,  height: 956)),
    ]

    private static let padCanvases: [(name: String, size: CGSize)] = [
        ("iPad Slide Over",         CGSize(width: 320,  height: 1024)),
        ("iPad mini portrait",      CGSize(width: 744,  height: 1133)),
        ("iPad Pro 11in portrait",  CGSize(width: 834,  height: 1194)),
        ("iPad Pro 11in landscape", CGSize(width: 1194, height: 834)),
        ("iPad Pro 13in landscape", CGSize(width: 1366, height: 1024)),
    ]

    private func render(size: CGSize,
                        idiom: UIUserInterfaceIdiom,
                        sizeClass: UIUserInterfaceSizeClass)
    -> (host: UIHostingController<AnyView>, env: StellarTestEnvironment) {
        let env = StellarTestEnvironment()
        let host = LayoutHosting.host(env.inject(into: ContentView(), idiom: idiom),
                                      size: size,
                                      sizeClass: sizeClass)
        return (host, env)
    }

    /// The phone shell, at every width the deployment target still ships.
    func testPhoneShellComposesWithoutStrandingContent() {
        for canvas in Self.phoneCanvases {
            let rendered = render(size: canvas.size, idiom: .phone, sizeClass: .compact)
            LayoutHosting.assertNothingStrandedHorizontally(in: rendered.host)
            XCTAssertTrue(LayoutHosting.contains(UITabBarController.self, in: rendered.host),
                          "the phone must still get the tab shell at \(canvas.name)")
            withExtendedLifetime(rendered.env) {}
        }
    }

    /// The iPad shell, from a Slide Over pane to a 13" in landscape.
    func testPadShellComposesWithoutStrandingContent() {
        for canvas in Self.padCanvases {
            // Slide Over is compact even on an iPad — that is the branch that
            // exists because `UIRequiresFullScreen` was dropped.
            let sizeClass: UIUserInterfaceSizeClass = canvas.size.width < 500 ? .compact : .regular
            let rendered = render(size: canvas.size, idiom: .pad, sizeClass: sizeClass)
            LayoutHosting.assertNothingStrandedHorizontally(in: rendered.host)
            withExtendedLifetime(rendered.env) {}
        }
    }

    /// Rotation is a resize, not a rebuild. Once `UIRequiresFullScreen` is gone
    /// the app is resized live — by rotation, by a Split View divider drag, and
    /// by Stage Manager. Re-laying out the *same* host through a sequence of
    /// sizes catches state that survives a rebuild but not a resize.
    func testPadShellSurvivesLiveResizeSequence() {
        let env = StellarTestEnvironment()
        let host = LayoutHosting.host(env.inject(into: ContentView(), idiom: .pad),
                                      size: Self.padCanvases[0].size,
                                      sizeClass: .regular)

        for canvas in Self.padCanvases {
            host.view.frame = CGRect(origin: .zero, size: canvas.size)
            host.view.layoutIfNeeded()
            XCTAssertGreaterThan(host.view.frame.height, 0,
                                 "root must retain non-zero height at \(canvas.name)")
            LayoutHosting.assertNothingStrandedHorizontally(in: host)
        }

        withExtendedLifetime(env) {}
    }
}
