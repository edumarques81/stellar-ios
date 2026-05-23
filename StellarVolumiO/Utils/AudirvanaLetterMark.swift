import SwiftUI

/// Stylised "A" letterform used as the Audirvana branded artwork placeholder.
/// Matches the aesthetic of the web/Pi SVG logo — two angled legs, horizontal crossbar, accent dot.
struct AudirvanaLetterMark: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        // Proportions (normalised to a 200×200 viewBox, scaled to rect)
        let sx = w / 200
        let sy = h / 200

        var p = Path()

        // Left leg: top-centre → bottom-left
        p.move(to:    CGPoint(x: 85 * sx, y: 45 * sy))
        p.addLine(to: CGPoint(x: 100 * sx, y: 45 * sy))
        p.addLine(to: CGPoint(x: 63 * sx,  y: 155 * sy))
        p.addLine(to: CGPoint(x: 48 * sx,  y: 155 * sy))
        p.closeSubpath()

        // Right leg: top-centre → bottom-right
        p.move(to:    CGPoint(x: 100 * sx, y: 45 * sy))
        p.addLine(to: CGPoint(x: 115 * sx, y: 45 * sy))
        p.addLine(to: CGPoint(x: 152 * sx, y: 155 * sy))
        p.addLine(to: CGPoint(x: 137 * sx, y: 155 * sy))
        p.closeSubpath()

        // Crossbar (pill shape via rounded rect)
        let crossbar = CGRect(x: 68 * sx, y: 104 * sy, width: 64 * sx, height: 14 * sy)
        p.addRoundedRect(in: crossbar, cornerRadii: .init(topLeading: 7 * sx, bottomLeading: 7 * sx, bottomTrailing: 7 * sx, topTrailing: 7 * sx))

        // Accent dot below A
        let dotR: CGFloat = 7 * sx
        let dotC = CGPoint(x: 100 * sx, y: 170 * sy)
        p.addEllipse(in: CGRect(x: dotC.x - dotR, y: dotC.y - dotR, width: dotR * 2, height: dotR * 2))

        return p
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [Color(red: 0.42, green: 0.31, blue: 0.63), Color(red: 0.24, green: 0.16, blue: 0.44)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        AudirvanaLetterMark()
            .foregroundStyle(.white)
            .frame(width: 160, height: 160)
    }
    .frame(width: 280, height: 280)
    .clipShape(RoundedRectangle(cornerRadius: 32))
}
