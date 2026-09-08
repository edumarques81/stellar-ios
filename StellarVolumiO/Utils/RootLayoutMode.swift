import SwiftUI
import UIKit

/// Which navigation shell the app's root should build.
///
/// The iPad port needs the root to be a `NavigationSplitView` on a roomy canvas
/// and the phone's `TabView` on a narrow one. Rather than let that condition
/// spread through the view tree as repeated `horizontalSizeClass` checks
/// (NAV-06), the whole decision lives here: one enum, one pure function, every
/// input a parameter. `ContentView` reads the environment once and asks.
///
/// The rules, in the order they are applied:
///
/// 1. **Only an iPad can get a sidebar.** This is the REG-01 guard — "the
///    iPhone is unchanged" — stated in code rather than left to depend on the
///    Info.plist happening to lock the phone to portrait. If landscape is ever
///    unlocked on the phone, it still keeps the tab bar it shipped with.
/// 2. **A compact width means tabs, even on an iPad.** Slide Over hands the app
///    a canvas around 320pt wide; a sidebar does not belong there. This branch
///    only exists because Phase 1 dropped `UIRequiresFullScreen`.
/// 3. **An unknown (`nil`) size class defers to the idiom.** SwiftUI reports
///    `nil` before an environment is resolved — previews, a detached hosting
///    controller, the first pass of a resize. Defaulting to `.tabs` there would
///    flash a tab bar onto an iPad, so a pad assumes `.sidebar` and everything
///    else assumes `.tabs`.
enum RootLayoutMode: Equatable, CaseIterable, Sendable {
    /// The `TabView` the iPhone has always used.
    case tabs
    /// A `NavigationSplitView` with a persistent sidebar.
    case sidebar

    static func resolve(horizontalSizeClass: UserInterfaceSizeClass?,
                        idiom: UIUserInterfaceIdiom) -> RootLayoutMode {
        guard idiom == .pad else { return .tabs }
        return horizontalSizeClass == .compact ? .tabs : .sidebar
    }
}
