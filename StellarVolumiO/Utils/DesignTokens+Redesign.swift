import SwiftUI

// MARK: - Redesign palette
//
// Direct port of the Volumio2-UI redesign tokens
// (`Volumio2-UI/src/lib/components/redesign/PlayerLayout.svelte:60-65` and
// `app.css` redesign-tokens). Names are scoped under `Stellar.*` static
// vars so they don't collide with the M3 `md*` tokens that already exist.

enum Stellar {

    enum Color {
        /// Gold accent. Used for the play disc, format badges, the progress
        /// fill, the active tab tint, the Resume CTA.
        static let gold = SwiftUI.Color(red: 0xd4 / 255, green: 0xaf / 255, blue: 0x6a / 255)

        /// Tinted gold fill for badge backgrounds (alpha 0.18).
        static let goldFill = SwiftUI.Color(red: 0xd4 / 255, green: 0xaf / 255, blue: 0x6a / 255, opacity: 0.18)

        /// Deep near-black base, matches PlayerLayout `#050507`.
        static let baseBackground = SwiftUI.Color(red: 0x05 / 255, green: 0x05 / 255, blue: 0x07 / 255)

        /// Surface used for card-like rows in Settings, slightly lifted off base.
        static let surfaceLow = SwiftUI.Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x1a / 255)

        /// Hairline separator.
        static let separator = SwiftUI.Color(red: 0x1f / 255, green: 0x1f / 255, blue: 0x25 / 255)

        /// Status dot colours.
        static let statusGreen = SwiftUI.Color(red: 0x4c / 255, green: 0xaf / 255, blue: 0x50 / 255)
        static let statusAmber = SwiftUI.Color(red: 0xff / 255, green: 0xc1 / 255, blue: 0x07 / 255)
        static let statusRed   = SwiftUI.Color(red: 0xe5 / 255, green: 0x39 / 255, blue: 0x35 / 255)
    }

    enum Metric {
        /// Album-art hero corner radius.
        static let artCornerRadius: CGFloat = 16
        /// Play disc diameter.
        static let playDisc: CGFloat = 72
        /// Optical-centre offset applied to the play.fill triangle inside the disc.
        static let playGlyphOffset: CGFloat = 2
        /// Minimum touch target (Apple HIG).
        static let minTouchTarget: CGFloat = 44
    }

    enum Shadow {
        static let albumArt = (radius: CGFloat(28), y: CGFloat(8), opacity: 0.5)
    }
}

// MARK: - Glassy background modifier
//
// Used as the root background on Now Playing. Two soft radial gradients on top
// of the deep base mimic PlayerLayout.svelte's radial-gradient sheen.

struct StellarGlassyBackground: View {
    var body: some View {
        ZStack {
            Stellar.Color.baseBackground

            RadialGradient(
                colors: [SwiftUI.Color.white.opacity(0.085), .clear],
                center: UnitPoint(x: 0.85, y: 0.15),
                startRadius: 0,
                endRadius: 280
            )

            RadialGradient(
                colors: [SwiftUI.Color(red: 40/255, green: 60/255, blue: 90/255, opacity: 0.15), .clear],
                center: UnitPoint(x: 0.80, y: 0.90),
                startRadius: 0,
                endRadius: 280
            )
        }
        .ignoresSafeArea()
    }
}
