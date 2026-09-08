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
/// and force a layout pass. A sheet that cannot compose, or that refuses to
/// take the width it is given, fails here.
@MainActor
final class SheetLayoutRenderTests: XCTestCase {

    /// Canvases a sheet is handed. The phone gets the whole screen; the iPad
    /// gets a form sheet, and a Slide Over pane shrinks that further.
    private static let canvases: [(name: String, size: CGSize)] = [
        ("iPhone full screen",     CGSize(width: 393, height: 852)),
        ("iPad form sheet",        CGSize(width: 540, height: 620)),
        ("iPad form sheet, wide",  CGSize(width: 704, height: 820)),
        ("Slide Over sheet",       CGSize(width: 320, height: 700)),
    ]

    /// The environment graph both sheets read from. The `SocketService` is
    /// returned alongside because the stores hold it weakly — dropping it would
    /// leave every binding dead before layout runs.
    private func makeEnvironment() -> (config: BackendConfigStore,
                                       socket: SocketService,
                                       discovery: BackendDiscoveryService,
                                       ingest: IngestStore) {
        let config = BackendConfigStore()
        return (config,
                SocketService(config: config),
                BackendDiscoveryService(),
                IngestStore())
    }

    private func render(_ view: some View, at size: CGSize) -> UIHostingController<AnyView> {
        let host = UIHostingController(rootView: AnyView(view))
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        return host
    }

    func testBackendDiscoverySheetComposesAtEveryPresentationSize() {
        for canvas in Self.canvases {
            let env = makeEnvironment()
            let sheet = BackendDiscoverySheet(onSelected: {})
                .environment(env.discovery)
                .environment(env.config)

            let host = render(sheet, at: canvas.size)
            withExtendedLifetime(env.socket) {}

            XCTAssertEqual(host.view.frame.width, canvas.size.width, accuracy: 0.5,
                           "discovery sheet must take the full \(canvas.name) width")
            XCTAssertEqual(host.view.frame.height, canvas.size.height, accuracy: 0.5,
                           "discovery sheet must take the full \(canvas.name) height")
        }
    }

    func testIngestSheetComposesAtEveryPresentationSize() {
        for canvas in Self.canvases {
            let env = makeEnvironment()
            let sheet = IngestSheet().environment(env.ingest)

            let host = render(sheet, at: canvas.size)
            withExtendedLifetime(env.socket) {}

            XCTAssertEqual(host.view.frame.width, canvas.size.width, accuracy: 0.5,
                           "ingest sheet must take the full \(canvas.name) width")
            XCTAssertEqual(host.view.frame.height, canvas.size.height, accuracy: 0.5,
                           "ingest sheet must take the full \(canvas.name) height")
        }
    }
}
