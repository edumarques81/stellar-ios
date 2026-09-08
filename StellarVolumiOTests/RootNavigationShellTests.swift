import SwiftUI
import UIKit
import XCTest

@testable import StellarVolumiO

/// Phase 3: proof that the root actually builds the shell `RootLayoutMode` asks
/// for, not just that it composes without crashing.
///
/// `RootLayoutModeTests` covers the decision; `RootLayoutRenderTests` covers the
/// geometry. Neither can tell a `TabView` from a `NavigationSplitView`, which is
/// exactly the regression the port risks — an iPhone quietly handed a sidebar,
/// or an iPad quietly left on the tab bar.
///
/// The horizontal size class comes from the trait collection, not the frame, so
/// a bare `UIHostingController` always reports whatever the simulator's device
/// is. These tests therefore host the root inside a container that *overrides*
/// the trait, which is the only way to drive both branches from one simulator.
@MainActor
final class RootNavigationShellTests: XCTestCase {

    // MARK: - Hosting

    private struct Hosted {
        let window: UIWindow
        let container: UIViewController
        let host: UIHostingController<AnyView>
        let socket: SocketService
    }

    private func makeRoot() -> (view: AnyView, socket: SocketService) {
        let backend = BackendConfigStore()
        let socket = SocketService(config: backend)
        let view = ContentView()
            .environment(socket)
            .environment(backend)
            .environment(BackendDiscoveryService())
            .environment(PlayerStore())
            .environment(AirplayStore())
            .environment(AlbumPickerStore())
            .environment(ArtistPickerStore())
            .environment(AlbumTracksStore())
            .environment(LcdStore())
            .environment(LcdViewStore())
            .environment(LastPlayedStore())
            .environment(IngestStore())
        return (AnyView(view), socket)
    }

    private func hostRoot(horizontalSizeClass: UIUserInterfaceSizeClass,
                          size: CGSize) -> Hosted {
        let root = makeRoot()
        let host = UIHostingController(rootView: root.view)
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

        return Hosted(window: window, container: container, host: host, socket: root.socket)
    }

    // MARK: - Hierarchy probes

    private func containsTabBar(_ view: UIView) -> Bool {
        if view is UITabBar { return true }
        return view.subviews.contains(where: containsTabBar)
    }

    private func containsSplitViewController(_ controller: UIViewController) -> Bool {
        if controller is UISplitViewController { return true }
        return controller.children.contains(where: containsSplitViewController)
    }

    /// Class names of the hosted hierarchy, for failure messages — a bare
    /// "expected a tab bar" tells you nothing about what SwiftUI built instead.
    private func describe(_ hosted: Hosted) -> String {
        var names: [String] = []
        func walk(_ c: UIViewController, depth: Int) {
            names.append(String(repeating: "  ", count: depth) + String(describing: type(of: c)))
            c.children.forEach { walk($0, depth: depth + 1) }
        }
        walk(hosted.container, depth: 0)
        return names.joined(separator: "\n")
    }

    // MARK: - Tests

    /// A compact width is the phone's shell everywhere, including on an iPad in
    /// Slide Over.
    func testCompactWidthBuildsTheTabBar() {
        let hosted = hostRoot(horizontalSizeClass: .compact,
                              size: CGSize(width: 320, height: 1024))

        XCTAssertTrue(
            containsTabBar(hosted.host.view),
            "compact width must build the TabView shell; got:\n\(describe(hosted))"
        )
        XCTAssertFalse(
            containsSplitViewController(hosted.host),
            "compact width must not build a split view; got:\n\(describe(hosted))"
        )

        withExtendedLifetime(hosted.socket) {}
    }

    /// A regular width is the sidebar — but only on an iPad. On an iPhone
    /// simulator this same call must still produce the tab bar, which is the
    /// REG-01 guard in `RootLayoutMode.resolve` observed end to end.
    func testRegularWidthBuildsTheSidebarOnPadAndTabsElsewhere() {
        let hosted = hostRoot(horizontalSizeClass: .regular,
                              size: CGSize(width: 1194, height: 834))

        let expectSidebar = UIDevice.current.userInterfaceIdiom == .pad

        XCTAssertEqual(
            containsSplitViewController(hosted.host), expectSidebar,
            "regular width on idiom \(UIDevice.current.userInterfaceIdiom.rawValue) "
            + "should\(expectSidebar ? "" : " not") build a split view; got:\n\(describe(hosted))"
        )
        XCTAssertEqual(
            containsTabBar(hosted.host.view), !expectSidebar,
            "regular width on idiom \(UIDevice.current.userInterfaceIdiom.rawValue) "
            + "should\(expectSidebar ? " not" : "") build a tab bar; got:\n\(describe(hosted))"
        )

        withExtendedLifetime(hosted.socket) {}
    }

    /// NAV-07: a Split View drag or a rotation changes the size class under a
    /// live view. The shell must swap without the host tearing itself down.
    func testShellSwapsAcrossASizeClassChange() {
        let hosted = hostRoot(horizontalSizeClass: .regular,
                              size: CGSize(width: 1194, height: 834))
        let isPad = UIDevice.current.userInterfaceIdiom == .pad

        XCTAssertEqual(containsSplitViewController(hosted.host), isPad)

        // Drag the divider in: regular -> compact.
        hosted.container.setOverrideTraitCollection(
            UITraitCollection(horizontalSizeClass: .compact),
            forChild: hosted.host
        )
        hosted.host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 834)
        hosted.window.layoutIfNeeded()

        XCTAssertTrue(
            containsTabBar(hosted.host.view),
            "collapsing to compact must fall back to the tab bar; got:\n\(describe(hosted))"
        )

        // And back out again.
        hosted.container.setOverrideTraitCollection(
            UITraitCollection(horizontalSizeClass: .regular),
            forChild: hosted.host
        )
        hosted.host.view.frame = CGRect(x: 0, y: 0, width: 1194, height: 834)
        hosted.window.layoutIfNeeded()

        XCTAssertEqual(
            containsSplitViewController(hosted.host), isPad,
            "expanding back to regular must restore the sidebar; got:\n\(describe(hosted))"
        )

        withExtendedLifetime(hosted.socket) {}
    }
}
