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
/// Both inputs to the decision are forced: the horizontal size class comes from
/// an overridden trait collection (a bare `UIHostingController` always reports
/// the simulator device's), and the idiom comes from `\.stellarIdiom`. Without
/// the second, every sidebar assertion below would be skipped on the iPhone
/// simulator `scripts/test.sh` runs — which is to say, always.
@MainActor
final class RootNavigationShellTests: XCTestCase {

    // MARK: - Hosting

    private struct Hosted {
        let host: UIHostingController<AnyView>
        let env: StellarTestEnvironment

        var container: UIViewController { host.parent! }
    }

    private func hostRoot(horizontalSizeClass: UIUserInterfaceSizeClass,
                          idiom: UIUserInterfaceIdiom,
                          size: CGSize) -> Hosted {
        let env = StellarTestEnvironment()
        let host = LayoutHosting.host(env.inject(into: ContentView(), idiom: idiom),
                                      size: size,
                                      sizeClass: horizontalSizeClass)
        return Hosted(host: host, env: env)
    }

    // MARK: - Hierarchy probes

    /// Detected by controller, not by `UITabBar`. SwiftUI backs `TabView` with
    /// a `UITabBarController` on every runtime, but the *view* it builds is not
    /// always a `UITabBar` — on iPadOS 26 a regular-width tab shell renders the
    /// floating bar instead, so a class check on the view fails on the iPad
    /// simulators while the shell is perfectly correct.
    private func containsTabBarController(_ controller: UIViewController) -> Bool {
        if controller is UITabBarController { return true }
        return controller.children.contains(where: containsTabBarController)
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
        for idiom in [UIUserInterfaceIdiom.phone, .pad] {
            let hosted = hostRoot(horizontalSizeClass: .compact,
                                  idiom: idiom,
                                  size: CGSize(width: 320, height: 1024))

            XCTAssertTrue(
                containsTabBarController(hosted.host),
                "compact width must build the TabView shell on \(idiom); got:\n\(describe(hosted))"
            )
            XCTAssertFalse(
                containsSplitViewController(hosted.host),
                "compact width must not build a split view on \(idiom); got:\n\(describe(hosted))"
            )

            withExtendedLifetime(hosted.env) {}
        }
    }

    /// Regular width on an iPad is the sidebar.
    func testRegularWidthOnPadBuildsTheSidebar() {
        let hosted = hostRoot(horizontalSizeClass: .regular,
                              idiom: .pad,
                              size: CGSize(width: 1194, height: 834))

        XCTAssertTrue(
            containsSplitViewController(hosted.host),
            "regular width on an iPad must build a split view; got:\n\(describe(hosted))"
        )
        XCTAssertFalse(
            containsTabBarController(hosted.host),
            "the sidebar shell must not also carry a tab bar; got:\n\(describe(hosted))"
        )

        withExtendedLifetime(hosted.env) {}
    }

    /// REG-01 observed end to end: an iPhone Max in landscape reports *regular*
    /// width, and must still get the tab bar. Size class alone is not the guard
    /// — only the idiom check in `RootLayoutMode.resolve` is.
    func testRegularWidthOnPhoneStillBuildsTheTabBar() {
        let hosted = hostRoot(horizontalSizeClass: .regular,
                              idiom: .phone,
                              size: CGSize(width: 956, height: 440))

        XCTAssertTrue(
            containsTabBarController(hosted.host),
            "a regular-width iPhone must keep the tab bar; got:\n\(describe(hosted))"
        )
        XCTAssertFalse(
            containsSplitViewController(hosted.host),
            "an iPhone must never build a split view; got:\n\(describe(hosted))"
        )

        withExtendedLifetime(hosted.env) {}
    }

    /// NAV-07: a Split View drag or a rotation changes the size class under a
    /// live view. The shell must swap without the host tearing itself down.
    func testShellSwapsAcrossASizeClassChange() {
        let hosted = hostRoot(horizontalSizeClass: .regular,
                              idiom: .pad,
                              size: CGSize(width: 1194, height: 834))

        XCTAssertTrue(containsSplitViewController(hosted.host))

        // Drag the divider in: regular -> compact.
        hosted.container.setOverrideTraitCollection(
            UITraitCollection(horizontalSizeClass: .compact),
            forChild: hosted.host
        )
        hosted.host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 834)
        hosted.container.view.layoutIfNeeded()
        hosted.host.view.layoutIfNeeded()

        XCTAssertTrue(
            containsTabBarController(hosted.host),
            "collapsing to compact must fall back to the tab bar; got:\n\(describe(hosted))"
        )

        // And back out again.
        hosted.container.setOverrideTraitCollection(
            UITraitCollection(horizontalSizeClass: .regular),
            forChild: hosted.host
        )
        hosted.host.view.frame = CGRect(x: 0, y: 0, width: 1194, height: 834)
        hosted.container.view.layoutIfNeeded()
        hosted.host.view.layoutIfNeeded()

        XCTAssertTrue(
            containsSplitViewController(hosted.host),
            "expanding back to regular must restore the sidebar; got:\n\(describe(hosted))"
        )

        withExtendedLifetime(hosted.env) {}
    }

    // MARK: - Reconnect wiring

    /// The root is where the reconnect hook lives, so it is the only place the
    /// wiring can be proved. `IngestStore.socketDidConnect()` is what unsticks a
    /// commit whose `pushIngestResult` was lost to a locked screen — the store
    /// test covers the transition, this covers the fact that anything calls it.
    ///
    /// Both shells, because the hook sits on the outer `Group`: a version that
    /// hung it off `compactTabs` would leave every iPad stuck instead.
    func testReconnectUnsticksAStrandedCommitInBothShells() {
        for (name, sizeClass, idiom, size) in [
            ("tab bar", UIUserInterfaceSizeClass.compact, UIUserInterfaceIdiom.phone,
             CGSize(width: 393, height: 852)),
            ("sidebar", .regular, .pad, CGSize(width: 1194, height: 834)),
        ] {
            let hosted = hostRoot(horizontalSizeClass: sizeClass, idiom: idiom, size: size)

            // Strand a commit: the plan is spent, the phase latched, and the
            // result broadcast never arrives.
            hosted.env.ingest.bind(to: hosted.env.socket)
            hosted.env.ingest.apply(preview: IngestReport(
                items: [IngestItem(name: "Nojima Plays Liszt", status: "would-ingest", audioFiles: 5)],
                summary: IngestSummary(total: 1, wouldIngest: 1),
                token: "plan-token"
            ))
            hosted.env.ingest.commit()
            XCTAssertEqual(hosted.env.ingest.phase, .committing, "\(name): setup")

            hosted.env.socket.connectionState = .connected
            settle(hosted)

            XCTAssertEqual(hosted.env.ingest.phase, .idle,
                           "\(name): a reconnect must clear a phase whose reply can never arrive")

            withExtendedLifetime(hosted.env) {}
        }
    }

    /// SwiftUI applies an `onChange` on its own update cycle, not on the
    /// assignment, so the observation has to be given a turn of the run loop
    /// before it can be asserted on.
    private func settle(_ hosted: Hosted) {
        for _ in 0..<20 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            hosted.container.view.layoutIfNeeded()
            hosted.host.view.layoutIfNeeded()
            if hosted.env.ingest.phase == .idle { return }
        }
    }
}
