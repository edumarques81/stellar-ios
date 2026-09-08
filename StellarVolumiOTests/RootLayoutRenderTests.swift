import XCTest
import SwiftUI
@testable import StellarVolumiO

/// Geometry regression net for the iPad port.
///
/// The port rewrites `ContentView`'s root navigation, and both the iPhone and
/// iPad branches live in that one file. There is no UI test target in this
/// repo, so the only thing standing between a sidebar refactor and a silently
/// broken iPhone build is a render-path test.
///
/// These host the *real* root view — the full environment graph, the same one
/// `StellarApp` injects — at concrete canvas sizes and force a layout pass. A
/// branch that crashes, nil-derefs, or fails to compose fails here.
///
/// Sizes are point sizes in portrait unless stated. Slide Over is the narrowest
/// canvas the app can be handed once `UIRequiresFullScreen` is removed, and is
/// narrower than any iPhone — it is the size most likely to strand content.
@MainActor
final class RootLayoutRenderTests: XCTestCase {

    /// Canvas sizes the port must survive. Named so a failure says which one.
    private static let canvases: [(name: String, size: CGSize)] = [
        ("iPhone 16 Pro portrait",      CGSize(width: 393,  height: 852)),
        ("iPhone 16 Pro landscape",     CGSize(width: 852,  height: 393)),
        ("iPad Slide Over",             CGSize(width: 320,  height: 1024)),
        ("iPad mini portrait",          CGSize(width: 744,  height: 1133)),
        ("iPad Pro 11in portrait",      CGSize(width: 834,  height: 1194)),
        ("iPad Pro 11in landscape",     CGSize(width: 1194, height: 834)),
        ("iPad Pro 13in landscape",     CGSize(width: 1366, height: 1024)),
    ]

    /// Builds the same environment graph `StellarApp` injects into `ContentView`.
    ///
    /// The `SocketService` is deliberately returned alongside the view: stores
    /// hold it weakly, so letting it fall out of scope would leave every
    /// binding dead. Callers must keep the returned tuple alive for the
    /// duration of the test.
    private func makeRoot() -> (view: AnyView, socket: SocketService) {
        let backend = BackendConfigStore()
        let socket = SocketService(config: backend)
        let discovery = BackendDiscoveryService()
        let player = PlayerStore()
        let airplay = AirplayStore()
        let albums = AlbumPickerStore()
        let artists = ArtistPickerStore()
        let albumTracks = AlbumTracksStore()
        let lcd = LcdStore()
        let lcdView = LcdViewStore()
        let lastPlayed = LastPlayedStore()
        let ingest = IngestStore()

        let view = ContentView()
            .environment(socket)
            .environment(backend)
            .environment(discovery)
            .environment(player)
            .environment(airplay)
            .environment(albums)
            .environment(artists)
            .environment(albumTracks)
            .environment(lcd)
            .environment(lcdView)
            .environment(lastPlayed)
            .environment(ingest)

        return (AnyView(view), socket)
    }

    private func renderRoot(at size: CGSize) -> UIHostingController<AnyView> {
        let root = makeRoot()
        let host = UIHostingController(rootView: root.view)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        // Touch the socket so the compiler cannot deem it dead before layout.
        withExtendedLifetime(root.socket) {}
        return host
    }

    /// The root must compose at every canvas the app can be handed — from a
    /// 320 pt Slide Over pane up to a 13" iPad in landscape.
    func testRootComposesAtEveryCanvasSize() {
        for canvas in Self.canvases {
            let host = renderRoot(at: canvas.size)

            XCTAssertNotNil(host.view, "root must compose at \(canvas.name)")
            XCTAssertEqual(host.view.frame.width, canvas.size.width, accuracy: 0.5,
                           "root must fill the canvas width at \(canvas.name)")
            XCTAssertEqual(host.view.frame.height, canvas.size.height, accuracy: 0.5,
                           "root must fill the canvas height at \(canvas.name)")
        }
    }

    /// Rotation is a resize, not a rebuild. Once `UIRequiresFullScreen` is gone
    /// the app is resized live — by rotation, by a Split View divider drag, and
    /// by Stage Manager. Re-laying out the *same* host through a sequence of
    /// sizes catches state that survives a rebuild but not a resize.
    func testRootSurvivesLiveResizeSequence() {
        let root = makeRoot()
        let host = UIHostingController(rootView: root.view)

        for canvas in Self.canvases {
            host.view.frame = CGRect(origin: .zero, size: canvas.size)
            host.view.layoutIfNeeded()

            XCTAssertNotNil(host.view, "root must survive resize to \(canvas.name)")
            XCTAssertGreaterThan(host.view.frame.height, 0,
                                 "root must retain non-zero height at \(canvas.name)")
        }

        withExtendedLifetime(root.socket) {}
    }
}
