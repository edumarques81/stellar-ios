import SwiftUI
import UIKit

/// The idiom the layout decision should be made against.
///
/// `UIDevice.current.userInterfaceIdiom` is the real answer and is the default,
/// but reading it directly from a view makes the iPad branch unreachable
/// anywhere except an iPad. `scripts/test.sh` runs the unit suite on an iPhone
/// simulator, so every sidebar-side code path — `regularSidebar`,
/// `detailColumn`, the roomy-canvas layout steps — would execute zero times in
/// the default run no matter how many size classes a test overrides.
///
/// Putting it in the environment costs one line at the call site and makes the
/// whole branch testable from any simulator. Production never sets it.
private struct StellarIdiomKey: EnvironmentKey {
    static let defaultValue: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom
}

extension EnvironmentValues {
    var stellarIdiom: UIUserInterfaceIdiom {
        get { self[StellarIdiomKey.self] }
        set { self[StellarIdiomKey.self] = newValue }
    }
}
