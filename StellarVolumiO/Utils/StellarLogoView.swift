import SwiftUI

// MARK: - Stellar / Italian Greyhound Logo

/// Placeholder artwork view shown in the player when no track is playing.
/// Features a stylised Italian Greyhound silhouette — a tribute to Talco 🤍
struct StellarLogoView: View {
    var body: some View {
        ZStack {
            // Background — subtle primary tint on surface
            LinearGradient(
                colors: [
                    Color.mdPrimary.opacity(0.08).blended(with: Color.mdSurfaceContainerLow),
                    Color.mdSurfaceContainerLow
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                // Italian Greyhound silhouette
                ItalianGreyhoundShape()
                    .fill(Color.white.opacity(0.82))
                    .shadow(color: Color.mdPrimary.opacity(0.30), radius: 12, y: 4)
                    .frame(width: 200, height: 160)

                // App wordmark
                Text("STELLAR")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(6)
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
    }
}

// MARK: - Italian Greyhound Shape

/// A simplified but recognisable Italian Greyhound silhouette.
/// Standing pose, facing right, showing the breed's hallmark features:
/// long muzzle, arched neck, deep chest and dramatic abdominal tuck.
struct ItalianGreyhoundShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        // Normalised to 220×190 viewBox (matches the SVG)
        let sx = w / 220
        let sy = h / 190

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * sx, y: y * sy)
        }

        var p = Path()

        // ── Main body ────────────────────────────────────────────────────
        // Arched back, deep chest, dramatic abdominal tuck
        p.move(to: pt(136, 62))
        p.addCurve(to: pt(96, 51),
                   control1: pt(128, 58), control2: pt(114, 53))
        p.addCurve(to: pt(50, 54),
                   control1: pt(80, 49), control2: pt(64, 49))
        p.addCurve(to: pt(33, 73),
                   control1: pt(40, 58), control2: pt(34, 65))
        p.addCurve(to: pt(62, 114),
                   control1: pt(32, 81), control2: pt(38, 100))
        p.addCurve(to: pt(93, 87),
                   control1: pt(74, 114), control2: pt(86, 102))
        p.addCurve(to: pt(108, 76),
                   control1: pt(97, 79), control2: pt(100, 74))
        p.addCurve(to: pt(125, 99),
                   control1: pt(115, 78), control2: pt(121, 88))
        p.addCurve(to: pt(129, 120),
                   control1: pt(127, 107), control2: pt(129, 114))
        p.addCurve(to: pt(136, 122),
                   control1: pt(130, 123), control2: pt(133, 124))
        p.addCurve(to: pt(139, 108),
                   control1: pt(139, 120), control2: pt(139, 115))
        p.addCurve(to: pt(136, 62),
                   control1: pt(139, 88), control2: pt(138, 65))
        p.closeSubpath()

        // ── Neck ─────────────────────────────────────────────────────────
        p.move(to: pt(136, 62))
        p.addCurve(to: pt(157, 50),
                   control1: pt(140, 56), control2: pt(148, 51))
        p.addCurve(to: pt(163, 62),
                   control1: pt(162, 50), control2: pt(165, 54))
        p.addCurve(to: pt(150, 76),
                   control1: pt(161, 69), control2: pt(156, 74))
        p.addCurve(to: pt(136, 62),
                   control1: pt(144, 78), control2: pt(139, 76))
        p.closeSubpath()

        // ── Head ─────────────────────────────────────────────────────────
        let headCenter = pt(170, 55)
        let headRx = 21 * sx
        let headRy = 17 * sy
        p.addEllipse(in: CGRect(
            x: headCenter.x - headRx, y: headCenter.y - headRy,
            width: headRx * 2, height: headRy * 2))

        // ── Muzzle (long, tapering) ───────────────────────────────────────
        p.move(to: pt(184, 53))
        p.addCurve(to: pt(208, 74),
                   control1: pt(194, 56), control2: pt(206, 65))
        p.addCurve(to: pt(200, 83),
                   control1: pt(209, 80), control2: pt(205, 84))
        p.addCurve(to: pt(184, 53),
                   control1: pt(195, 82), control2: pt(184, 60))
        p.closeSubpath()

        // ── Rose ear (small, folded) ──────────────────────────────────────
        let earCenter = pt(152, 41)
        let earRx = 11 * sx
        let earRy = 8 * sy
        p.addEllipse(in: CGRect(
            x: earCenter.x - earRx, y: earCenter.y - earRy,
            width: earRx * 2, height: earRy * 2))

        // ── Front legs ───────────────────────────────────────────────────
        p.addRoundedRect(
            in: CGRect(x: 120 * sx, y: 120 * sy, width: 12 * sx, height: 62 * sy),
            cornerRadii: .init(topLeading: 6 * sx, bottomLeading: 6 * sx,
                               bottomTrailing: 6 * sx, topTrailing: 6 * sx))
        p.addRoundedRect(
            in: CGRect(x: 134 * sx, y: 121 * sy, width: 12 * sx, height: 62 * sy),
            cornerRadii: .init(topLeading: 6 * sx, bottomLeading: 6 * sx,
                               bottomTrailing: 6 * sx, topTrailing: 6 * sx))

        // ── Rear legs ─────────────────────────────────────────────────────
        p.move(to: pt(47, 110))
        p.addCurve(to: pt(52, 146), control1: pt(50, 130), control2: pt(52, 138))
        p.addCurve(to: pt(52, 170), control1: pt(54, 158), control2: pt(54, 166))
        p.addCurve(to: pt(44, 170), control1: pt(50, 174), control2: pt(46, 174))
        p.addCurve(to: pt(43, 146), control1: pt(42, 166), control2: pt(42, 158))
        p.addCurve(to: pt(47, 110), control1: pt(44, 130), control2: pt(44, 118))
        p.closeSubpath()

        p.move(to: pt(33, 108))
        p.addCurve(to: pt(36, 144), control1: pt(35, 128), control2: pt(36, 136))
        p.addCurve(to: pt(35, 168), control1: pt(37, 156), control2: pt(37, 164))
        p.addCurve(to: pt(27, 168), control1: pt(33, 172), control2: pt(29, 172))
        p.addCurve(to: pt(27, 144), control1: pt(25, 164), control2: pt(26, 156))
        p.addCurve(to: pt(33, 108), control1: pt(28, 128), control2: pt(30, 118))
        p.closeSubpath()

        // ── Tail (whip, carried low) ──────────────────────────────────────
        p.move(to: pt(33, 78))
        p.addCurve(to: pt(12, 88), control1: pt(26, 80), control2: pt(18, 82))
        p.addCurve(to: pt(13, 100), control1: pt(8, 93), control2: pt(9, 99))
        p.addCurve(to: pt(26, 92), control1: pt(17, 101), control2: pt(22, 97))
        p.addCurve(to: pt(33, 78), control1: pt(30, 87), control2: pt(33, 82))
        p.closeSubpath()

        return p
    }
}

// MARK: - Colour blend helper
private extension Color {
    func blended(with other: Color) -> Color { self } // simplified — just uses self
}

// MARK: - Preview
#Preview {
    StellarLogoView()
        .frame(width: 280, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .padding()
        .background(Color.black)
}
