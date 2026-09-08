import XCTest
import SwiftUI
import ObjectiveC
@testable import StellarVolumiO

private nonisolated(unsafe) var windowKey: UInt8 = 0

/// Shared hosting + geometry assertions for the layout tests.
///
/// Three things every layout test in this repo needs and none of them can get
/// on their own:
///
/// 1. **A real trait environment.** A bare `UIHostingController` with a
///    manually-set frame still reports the *simulator device's* horizontal size
///    class, so a compact-width assertion silently runs the regular branch (or
///    the reverse) depending on which simulator the suite happens to be on. The
///    only way to drive both from one simulator is a container view controller
///    that overrides its child's trait collection.
/// 2. **A controllable idiom.** `RootLayoutMode` refuses a sidebar to anything
///    that is not an iPad, and `scripts/test.sh` runs an iPhone simulator, so
///    without an injectable idiom the entire iPad branch executes zero times in
///    the default run. `\.stellarIdiom` exists for exactly this.
/// 3. **An assertion that can fail.** `XCTAssertEqual(host.view.frame.width,
///    theWidthWeJustAssigned)` is a tautology — it asserts UIKit stored the
///    value. `assertNothingStrandedHorizontally` walks the rendered hierarchy
///    instead and asserts real geometry.
@MainActor
enum LayoutHosting {

    /// Hosts `view` in a window, at `size`, with the given traits forced onto
    /// it. Returns the hosting controller; the caller must keep it alive.
    ///
    /// The window is real because `NavigationSplitView` and `TabView` only
    /// build their UIKit backing when they are in one.
    static func host<V: View>(_ view: V,
                              size: CGSize,
                              sizeClass: UIUserInterfaceSizeClass = .unspecified) -> UIHostingController<V> {
        let host = UIHostingController(rootView: view)
        let container = UIViewController()

        container.addChild(host)
        container.view.addSubview(host.view)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.didMove(toParent: container)

        if sizeClass != .unspecified {
            container.setOverrideTraitCollection(
                UITraitCollection(horizontalSizeClass: sizeClass), forChild: host)
        }

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = container
        window.isHidden = false
        window.layoutIfNeeded()
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()

        // Under a scene-based lifecycle nothing retains a window we built
        // ourselves, and a deallocated window takes the whole hierarchy with
        // it. Tie its lifetime to the controller the caller is already holding.
        objc_setAssociatedObject(host, &windowKey, window, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        return host
    }

    /// Every rendered leaf must sit inside the pane that owns it, horizontally.
    ///
    /// Horizontal only, deliberately: content taller than the pane is normal —
    /// that is what scrolling is for — but content *wider* than the pane is
    /// stranded or clipped, and it is the failure the iPad port can actually
    /// introduce (a fixed-width hero in a narrow detail column, a reading
    /// column that never got capped).
    ///
    /// "Pane" rather than "canvas" because of what a `NavigationSplitView`
    /// really builds. Its columns are `UISplitViewController` children, and in
    /// portrait the automatic display mode parks the sidebar *off* the canvas
    /// — at 834x1194 the sidebar column sits at x = -100 with every one of its
    /// descendants inherited along with it. That is UIKit's own display-mode
    /// decision, not a layout defect, and measuring it against the window would
    /// fail ~30 times per canvas while saying nothing. So each column is
    /// measured against its own bounds instead, which is the question that
    /// actually matters: does our content fit the column it was given.
    ///
    /// `tolerance` absorbs sub-pixel layout and the deliberate small overhangs
    /// SwiftUI uses for shadows and scroll-bar gutters.
    static func assertNothingStrandedHorizontally(
        in host: UIViewController,
        tolerance: CGFloat = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let panes = contentPanes(of: host)

        XCTAssertFalse(panes.isEmpty,
                       "nothing rendered — the view composed to an empty hierarchy",
                       file: file, line: line)

        for pane in panes {
            XCTAssertFalse(pane.subviews.isEmpty,
                           "\(type(of: pane)) rendered no content",
                           file: file, line: line)
            assertSubtreeFits(pane, tolerance: tolerance, file: file, line: line)
        }
    }

    /// The panes content is laid out inside: a split view's columns when the
    /// root built one, otherwise the whole hosted view.
    private static func contentPanes(of host: UIViewController) -> [UIView] {
        guard let split = firstSplitViewController(in: host) else { return [host.view] }
        let columns = split.children.map(\.view!)
        return columns.isEmpty ? [split.view] : columns
    }

    private static func firstSplitViewController(in controller: UIViewController) -> UISplitViewController? {
        if let split = controller as? UISplitViewController { return split }
        for child in controller.children {
            if let found = firstSplitViewController(in: child) { return found }
        }
        return nil
    }

    /// UIKit's own oversized chrome, excluded from the measurement.
    ///
    /// A compositional list layout paints its inset-grouped section background
    /// with a decoration view deliberately wider than the collection view — in
    /// the sidebar it comes out 560pt wide in a 420pt column, 70pt proud on
    /// each side. It is drawn behind the rows and clipped, and it is not
    /// something the app positions. Everything else in the hierarchy is fair
    /// game.
    private static func isUIKitDecoration(_ view: UIView) -> Bool {
        String(describing: type(of: view)).contains("DecorationView")
    }

    private static func assertSubtreeFits(_ pane: UIView,
                                          tolerance: CGFloat,
                                          file: StaticString,
                                          line: UInt) {
        let bounds = pane.bounds

        func walk(_ view: UIView) {
            for subview in view.subviews {
                guard !subview.isHidden, subview.alpha > 0.01 else { continue }
                guard !isUIKitDecoration(subview) else { continue }
                let frame = subview.convert(subview.bounds, to: pane)
                if frame.width > 0.5 && frame.height > 0.5 {
                    XCTAssertGreaterThanOrEqual(
                        frame.minX, bounds.minX - tolerance,
                        "\(type(of: subview)) starts \(bounds.minX - frame.minX)pt left of its pane",
                        file: file, line: line)
                    XCTAssertLessThanOrEqual(
                        frame.maxX, bounds.maxX + tolerance,
                        "\(type(of: subview)) runs \(frame.maxX - bounds.maxX)pt past its pane",
                        file: file, line: line)
                }
                walk(subview)
            }
        }

        walk(pane)
    }

    /// Is there a controller of this kind anywhere under `controller`?
    ///
    /// Shells are identified by controller, not by view class: SwiftUI backs
    /// `TabView` with a `UITabBarController` and `NavigationSplitView` with a
    /// `UISplitViewController` on every runtime, but the views they build vary
    /// — iPadOS 26 renders a regular-width tab shell as a floating bar rather
    /// than a `UITabBar`, so a view-class check reports the wrong answer on the
    /// iPad simulators.
    static func contains<T: UIViewController>(_ kind: T.Type,
                                              in controller: UIViewController) -> Bool {
        if controller is T { return true }
        return controller.children.contains { contains(kind, in: $0) }
    }

    /// Depth-first search for the first subview satisfying `match`.
    static func firstSubview(in view: UIView,
                             where match: (UIView) -> Bool) -> UIView? {
        for subview in view.subviews {
            if match(subview) { return subview }
            if let found = firstSubview(in: subview, where: match) { return found }
        }
        return nil
    }

    /// A `class-name contains` predicate, which is how the SwiftUI-private
    /// backing types have to be found.
    static func firstSubview(in view: UIView, classNameContains needle: String) -> UIView? {
        firstSubview(in: view) { String(describing: type(of: $0)).contains(needle) }
    }
}

/// The environment graph `StellarApp` injects, built once so the layout tests
/// do not each carry their own copy.
///
/// `socket` comes back with the view because the stores hold it **weakly** — a
/// `SocketService()` passed inline is deallocated immediately and every binding
/// in the tree goes dead before layout runs.
@MainActor
struct StellarTestEnvironment {
    let socket: SocketService
    let backend: BackendConfigStore
    let discovery: BackendDiscoveryService
    let player: PlayerStore
    let airplay: AirplayStore
    let albums: AlbumPickerStore
    let artists: ArtistPickerStore
    let albumTracks: AlbumTracksStore
    let lcd: LcdStore
    let lcdView: LcdViewStore
    let lastPlayed: LastPlayedStore
    let ingest: IngestStore

    init() {
        backend = BackendConfigStore()
        socket = SocketService(config: backend)
        discovery = BackendDiscoveryService()
        player = PlayerStore()
        airplay = AirplayStore()
        albums = AlbumPickerStore()
        artists = ArtistPickerStore()
        albumTracks = AlbumTracksStore()
        lcd = LcdStore()
        lcdView = LcdViewStore()
        lastPlayed = LastPlayedStore()
        ingest = IngestStore()
    }

    /// Injects everything, plus the idiom the layout decision should be made
    /// against. Production never sets the idiom; tests always do, so a run on
    /// an iPhone simulator still exercises the iPad branch.
    func inject<V: View>(into view: V, idiom: UIUserInterfaceIdiom) -> AnyView {
        AnyView(
            view
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
                .environment(\.stellarIdiom, idiom)
        )
    }
}
