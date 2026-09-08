import SwiftUI
import UIKit
import XCTest

@testable import StellarVolumiO

/// Phase 2 of the iPad port: the navigation decision, isolated.
///
/// NAV-06 asks for one pure, unit-testable type instead of `if
/// horizontalSizeClass == .regular` scattered through the views. Everything the
/// decision depends on is a parameter, so the whole truth table can be asserted
/// here without a simulator, a window, or a rotation.
///
/// The load-bearing case is not the iPad one — it is REG-01, "the iPhone is
/// unchanged". A phone must land on `.tabs` for *every* input, including a
/// regular width class it should never report, so that a later orientation
/// change cannot quietly hand the phone a sidebar.
final class RootLayoutModeTests: XCTestCase {

    // MARK: - iPad

    func testPadRegularWidthGetsTheSidebar() {
        XCTAssertEqual(
            RootLayoutMode.resolve(horizontalSizeClass: .regular, idiom: .pad),
            .sidebar
        )
    }

    /// Slide Over hands the app a ~320pt compact-width canvas. A sidebar does
    /// not fit there, so the iPad falls back to the phone's tab bar — this is
    /// the case that only exists because Phase 1 dropped `UIRequiresFullScreen`.
    func testPadCompactWidthFallsBackToTabs() {
        XCTAssertEqual(
            RootLayoutMode.resolve(horizontalSizeClass: .compact, idiom: .pad),
            .tabs
        )
    }

    /// The size class is `nil` before SwiftUI has resolved an environment —
    /// previews, a detached host, the first pass of a resize. Guessing `.tabs`
    /// there would flash a tab bar onto an iPad, so the idiom decides instead.
    func testPadWithUnknownSizeClassAssumesSidebar() {
        XCTAssertEqual(
            RootLayoutMode.resolve(horizontalSizeClass: nil, idiom: .pad),
            .sidebar
        )
    }

    // MARK: - iPhone (REG-01)

    func testPhoneCompactWidthKeepsTabs() {
        XCTAssertEqual(
            RootLayoutMode.resolve(horizontalSizeClass: .compact, idiom: .phone),
            .tabs
        )
    }

    /// Today the phone is portrait-locked and can never report a regular width.
    /// This asserts the guard rather than the current plist: if someone unlocks
    /// landscape later, the phone still keeps the layout it shipped with.
    func testPhoneNeverGetsASidebarEvenAtRegularWidth() {
        XCTAssertEqual(
            RootLayoutMode.resolve(horizontalSizeClass: .regular, idiom: .phone),
            .tabs
        )
    }

    func testPhoneWithUnknownSizeClassKeepsTabs() {
        XCTAssertEqual(
            RootLayoutMode.resolve(horizontalSizeClass: nil, idiom: .phone),
            .tabs
        )
    }

    // MARK: - Everything else

    /// Mac Catalyst, visionOS compatibility, CarPlay, `.unspecified`. None are
    /// shipping targets; none should be handed an untested sidebar.
    func testNonPadIdiomsKeepTabs() {
        let others: [UIUserInterfaceIdiom] = [.unspecified, .phone, .tv, .carPlay, .mac, .vision]
        for idiom in others {
            for sizeClass: UserInterfaceSizeClass? in [.compact, .regular, nil] {
                XCTAssertEqual(
                    RootLayoutMode.resolve(horizontalSizeClass: sizeClass, idiom: idiom),
                    .tabs,
                    "idiom \(idiom.rawValue) with size class \(String(describing: sizeClass))"
                )
            }
        }
    }

    // MARK: - The whole truth table

    /// One assertion over every input combination, so a future change to the
    /// rules has to be made here deliberately rather than drifting in.
    func testSidebarIsReachableOnlyFromAPad() {
        let idioms: [UIUserInterfaceIdiom] = [.unspecified, .phone, .pad, .tv, .carPlay, .mac, .vision]
        for idiom in idioms {
            for sizeClass: UserInterfaceSizeClass? in [.compact, .regular, nil] {
                let mode = RootLayoutMode.resolve(horizontalSizeClass: sizeClass, idiom: idiom)
                let expectSidebar = (idiom == .pad && sizeClass != .compact)
                XCTAssertEqual(
                    mode,
                    expectSidebar ? .sidebar : .tabs,
                    "idiom \(idiom.rawValue) with size class \(String(describing: sizeClass))"
                )
            }
        }
    }

    func testTheDecisionIsTotal() {
        XCTAssertEqual(Set(RootLayoutMode.allCases), [.tabs, .sidebar])
    }

    // MARK: - isRoomy

    /// `isRoomy` is what every *layout* step asks (gradient radius, cover size,
    /// vertical centring). It must agree with the shell decision on every
    /// input — if the two ever disagree, the app would grow a sidebar while
    /// laying out for a phone, or the reverse.
    func testIsRoomyAgreesWithResolveOnEveryInput() {
        let idioms: [UIUserInterfaceIdiom] = [.unspecified, .phone, .pad, .tv, .carPlay, .mac, .vision]
        for idiom in idioms {
            for sizeClass: UserInterfaceSizeClass? in [.compact, .regular, nil] {
                XCTAssertEqual(
                    RootLayoutMode.isRoomy(horizontalSizeClass: sizeClass, idiom: idiom),
                    RootLayoutMode.resolve(horizontalSizeClass: sizeClass, idiom: idiom) == .sidebar,
                    "idiom \(idiom.rawValue) with size class \(String(describing: sizeClass))"
                )
            }
        }
    }

    /// The specific case that makes `isRoomy` worth having: an iPhone Max in
    /// landscape reports *regular* width. A layout step keyed off the size
    /// class alone would silently restyle the phone (REG-01).
    func testRegularWidthIPhoneIsNotRoomy() {
        XCTAssertFalse(RootLayoutMode.isRoomy(horizontalSizeClass: .regular, idiom: .phone))
        XCTAssertTrue(RootLayoutMode.isRoomy(horizontalSizeClass: .regular, idiom: .pad))
        XCTAssertFalse(RootLayoutMode.isRoomy(horizontalSizeClass: .compact, idiom: .pad),
                       "a Slide Over pane is an iPad, but it is not roomy")
    }
}
