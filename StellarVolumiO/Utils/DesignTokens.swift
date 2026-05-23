import SwiftUI

// MARK: - MD3-inspired Design Tokens for Stellar VolumiO
// Full tonal palette per theme — every surface, container, and text token changes.

// MARK: - Per-theme palette lookup
private struct Palette {
    let primary:                String
    let onPrimary:              String
    let primaryContainer:       String
    let onPrimaryContainer:     String
    let secondary:              String
    let onSecondary:            String
    let secondaryContainer:     String
    let onSecondaryContainer:   String
    let background:             String
    let onBackground:           String
    let surface:                String
    let onSurface:              String
    let surfaceVariant:         String
    let onSurfaceVariant:       String
    let surfaceContainerLowest: String
    let surfaceContainerLow:    String
    let surfaceContainer:       String
    let surfaceContainerHigh:   String
    let surfaceContainerHighest:String
    let outline:                String
    let outlineVariant:         String
}

private let palettes: [String: Palette] = [
    // ── Rose Crimson ─────────────────────────────────────────
    "rose": Palette(
        primary:                 "#B5264C",
        onPrimary:               "#FFFFFF",
        primaryContainer:        "#FFD9DE",
        onPrimaryContainer:      "#3F0019",
        secondary:               "#75565B",
        onSecondary:             "#FFFFFF",
        secondaryContainer:      "#FFD9DE",
        onSecondaryContainer:    "#2C1519",
        background:              "#1C1112",
        onBackground:            "#EFE0E1",
        surface:                 "#1C1112",
        onSurface:               "#EFE0E1",
        surfaceVariant:          "#524344",
        onSurfaceVariant:        "#D7C1C3",
        surfaceContainerLowest:  "#160C0D",
        surfaceContainerLow:     "#241A1B",
        surfaceContainer:        "#281E1F",
        surfaceContainerHigh:    "#332829",
        surfaceContainerHighest: "#3E3233",
        outline:                 "#A08C8E",
        outlineVariant:          "#524344"
    ),
    // ── Dark Forest ──────────────────────────────────────────
    "darkForest": Palette(
        primary:                 "#4DBB7A",
        onPrimary:               "#00391C",
        primaryContainer:        "#005229",
        onPrimaryContainer:      "#72E5A0",
        secondary:               "#87BF9A",
        onSecondary:             "#0B3320",
        secondaryContainer:      "#234A31",
        onSecondaryContainer:    "#A3D9B5",
        background:              "#0B1610",
        onBackground:            "#D8E8DA",
        surface:                 "#0B1610",
        onSurface:               "#D8E8DA",
        surfaceVariant:          "#3A4B3D",
        onSurfaceVariant:        "#B8CCB9",
        surfaceContainerLowest:  "#071009",
        surfaceContainerLow:     "#131E15",
        surfaceContainer:        "#17231A",
        surfaceContainerHigh:    "#212E23",
        surfaceContainerHighest: "#2C392E",
        outline:                 "#85988A",
        outlineVariant:          "#3A4B3D"
    ),
    // ── Violet Expressive ────────────────────────────────────
    "violetExpressive": Palette(
        primary:                 "#C084FC",
        onPrimary:               "#3B006E",
        primaryContainer:        "#55008A",
        onPrimaryContainer:      "#E9BBFF",
        secondary:               "#8B9AEA",
        onSecondary:             "#1A1F65",
        secondaryContainer:      "#313690",
        onSecondaryContainer:    "#DDE0FF",
        background:              "#120D1E",
        onBackground:            "#EAE0FF",
        surface:                 "#120D1E",
        onSurface:               "#EAE0FF",
        surfaceVariant:          "#4A3568",
        onSurfaceVariant:        "#CAB9E8",
        surfaceContainerLowest:  "#0D0817",
        surfaceContainerLow:     "#1A1228",
        surfaceContainer:        "#1F162F",
        surfaceContainerHigh:    "#2A1F3D",
        surfaceContainerHighest: "#36294C",
        outline:                 "#9880B8",
        outlineVariant:          "#4A3568"
    ),
    // ── Sage Green ───────────────────────────────────────────
    "sageGreen": Palette(
        primary:                 "#78BE8E",
        onPrimary:               "#003918",
        primaryContainer:        "#005225",
        onPrimaryContainer:      "#94EBAC",
        secondary:               "#91BAA0",
        onSecondary:             "#1C3827",
        secondaryContainer:      "#344E3C",
        onSecondaryContainer:    "#ACD5BC",
        background:              "#101510",
        onBackground:            "#DEE4DB",
        surface:                 "#101510",
        onSurface:               "#DEE4DB",
        surfaceVariant:          "#3C4A3D",
        onSurfaceVariant:        "#BBCABC",
        surfaceContainerLowest:  "#0B100B",
        surfaceContainerLow:     "#181D18",
        surfaceContainer:        "#1C221C",
        surfaceContainerHigh:    "#272C27",
        surfaceContainerHighest: "#323832",
        outline:                 "#889A89",
        outlineVariant:          "#3C4A3D"
    ),
    // ── Lime ─────────────────────────────────────────────────
    // Electric lime (#BFEF3C) IS the background — Lavender concept in green.
    "lime": Palette(
        primary:                 "#174400",
        onPrimary:               "#DEFF8A",
        primaryContainer:        "#255D00",
        onPrimaryContainer:      "#EEFFA8",
        secondary:               "#204800",
        onSecondary:             "#E8FF90",
        secondaryContainer:      "#2E6000",
        onSecondaryContainer:    "#F0FFC0",
        background:              "#BFEF3C",
        onBackground:            "#0A1800",
        surface:                 "#BFEF3C",
        onSurface:               "#0A1800",
        surfaceVariant:          "#CAEF50",
        onSurfaceVariant:        "#182500",
        surfaceContainerLowest:  "#CBF248",
        surfaceContainerLow:     "#C2EA3C",
        surfaceContainer:        "#B5DE2E",
        surfaceContainerHigh:    "#A6CE20",
        surfaceContainerHighest: "#96BC14",
        outline:                 "#2A5200",
        outlineVariant:          "#6A9800"
    ),
    // ── Lavender ─────────────────────────────────────────────
    // Background IS the vivid lavender (#BF80FF) — bold inversion.
    // Deep aubergine accents + dark text on bright surface.
    "lavender": Palette(
        primary:                 "#3A0078",
        onPrimary:               "#F0D0FF",
        primaryContainer:        "#520095",
        onPrimaryContainer:      "#EBBEFF",
        secondary:               "#4A0085",
        onSecondary:             "#EDD5FF",
        secondaryContainer:      "#620099",
        onSecondaryContainer:    "#F2D0FF",
        background:              "#BF80FF",
        onBackground:            "#15003A",
        surface:                 "#BF80FF",
        onSurface:               "#15003A",
        surfaceVariant:          "#CA90FF",
        onSurfaceVariant:        "#2D005A",
        surfaceContainerLowest:  "#CB92FF",
        surfaceContainerLow:     "#C488FF",
        surfaceContainer:        "#B878F8",
        surfaceContainerHigh:    "#AC68EE",
        surfaceContainerHighest: "#9E58DE",
        outline:                 "#5500AA",
        outlineVariant:          "#9055D0"
    ),
    // ── Amethyst ─────────────────────────────────────────────
    // Seed: #9B30D9  Hue ~285° (red-violet) — vivid amethyst crystal
    // Inspired by the "Elena" poster (~#A855F7 lavender-violet)
    "amethyst": Palette(
        primary:                 "#D080FF",
        onPrimary:               "#45007E",
        primaryContainer:        "#5F009E",
        onPrimaryContainer:      "#EDCCFF",
        secondary:               "#D09CF5",
        onSecondary:             "#400070",
        secondaryContainer:      "#5C008E",
        onSecondaryContainer:    "#F0CCFF",
        background:              "#130720",
        onBackground:            "#F0E5FF",
        surface:                 "#130720",
        onSurface:               "#F0E5FF",
        surfaceVariant:          "#4E2E6A",
        onSurfaceVariant:        "#D4B8F0",
        surfaceContainerLowest:  "#0C0518",
        surfaceContainerLow:     "#1C0E30",
        surfaceContainer:        "#211338",
        surfaceContainerHigh:    "#2C1B46",
        surfaceContainerHighest: "#382555",
        outline:                 "#A080C5",
        outlineVariant:          "#4E2E6A"
    ),
]

private func activePalette() -> Palette {
    let id = UserDefaults.standard.string(forKey: "colorTheme") ?? "rose"
    return palettes[id] ?? palettes["rose"]!
}

// MARK: - Color Extensions

extension Color {

    // MARK: Primary
    static var mdPrimary:              Color { Color(hex: activePalette().primary) }
    static var mdOnPrimary:            Color { Color(hex: activePalette().onPrimary) }
    static var mdPrimaryContainer:     Color { Color(hex: activePalette().primaryContainer) }
    static var mdOnPrimaryContainer:   Color { Color(hex: activePalette().onPrimaryContainer) }

    // MARK: Secondary
    static var mdSecondary:            Color { Color(hex: activePalette().secondary) }
    static var mdOnSecondary:          Color { Color(hex: activePalette().onSecondary) }
    static var mdSecondaryContainer:   Color { Color(hex: activePalette().secondaryContainer) }
    static var mdOnSecondaryContainer: Color { Color(hex: activePalette().onSecondaryContainer) }

    // MARK: Tertiary (audio format badges — fixed across themes)
    static let mdTertiary            = Color(hex: "#7C5635")
    static let mdTertiaryContainer   = Color(hex: "#FFD9BC")
    static let mdOnTertiaryContainer = Color(hex: "#2E1500")

    // MARK: Background / Surface
    static var mdBackground:               Color { Color(hex: activePalette().background) }
    static var mdOnBackground:             Color { Color(hex: activePalette().onBackground) }
    static var mdSurface:                  Color { Color(hex: activePalette().surface) }
    static var mdOnSurface:                Color { Color(hex: activePalette().onSurface) }
    static var mdSurfaceVariant:           Color { Color(hex: activePalette().surfaceVariant) }
    static var mdOnSurfaceVariant:         Color { Color(hex: activePalette().onSurfaceVariant) }
    static var mdSurfaceContainerLowest:   Color { Color(hex: activePalette().surfaceContainerLowest) }
    static var mdSurfaceContainerLow:      Color { Color(hex: activePalette().surfaceContainerLow) }
    static var mdSurfaceContainer:         Color { Color(hex: activePalette().surfaceContainer) }
    static var mdSurfaceContainerHigh:     Color { Color(hex: activePalette().surfaceContainerHigh) }
    static var mdSurfaceContainerHighest:  Color { Color(hex: activePalette().surfaceContainerHighest) }

    // MARK: Outline
    static var mdOutline:        Color { Color(hex: activePalette().outline) }
    static var mdOutlineVariant: Color { Color(hex: activePalette().outlineVariant) }

    // MARK: Semantic (fixed)
    static let mdError           = Color(hex: "#FFB4AB")
    static let mdSuccess         = Color(hex: "#34C759")
    static let audirvanaAccent   = Color(hex: "#6B4EA0")
}

// MARK: - Shape Tokens
extension CGFloat {
    static let mdShapeNone: CGFloat = 0
    static let mdShapeExtraSmall: CGFloat = 4
    static let mdShapeSmall: CGFloat = 8
    static let mdShapeMedium: CGFloat = 12
    static let mdShapeLarge: CGFloat = 16
    static let mdShapeExtraLarge: CGFloat = 28
    static let mdShapeFull: CGFloat = 999
}

// MARK: - Typography Tokens
struct StellarFont {
    static let displayLarge   = Font.system(size: 57, weight: .regular)
    static let displayMedium  = Font.system(size: 45, weight: .regular)
    static let displaySmall   = Font.system(size: 36, weight: .regular)
    static let headlineLarge  = Font.system(size: 32, weight: .semibold)
    static let headlineMedium = Font.system(size: 28, weight: .semibold)
    static let headlineSmall  = Font.system(size: 24, weight: .semibold)
    static let titleLarge     = Font.system(size: 22, weight: .medium)
    static let titleMedium    = Font.system(size: 16, weight: .medium)
    static let titleSmall     = Font.system(size: 14, weight: .medium)
    static let bodyLarge      = Font.system(size: 16, weight: .regular)
    static let bodyMedium     = Font.system(size: 14, weight: .regular)
    static let bodySmall      = Font.system(size: 12, weight: .regular)
    static let labelLarge     = Font.system(size: 14, weight: .medium)
    static let labelMedium    = Font.system(size: 12, weight: .medium)
    static let labelSmall     = Font.system(size: 11, weight: .medium)
}

// MARK: - Hex Color Init
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int & 0xFF0000) >> 16) / 255
        let g = Double((int & 0x00FF00) >> 8) / 255
        let b = Double(int & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Button Press Styles

struct StellarIconPressStyle: ButtonStyle {
    var scale: CGFloat = 0.88
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(duration: 0.18, bounce: 0.4), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

struct StellarPlayPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(duration: 0.2, bounce: 0.35), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .medium), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

struct StellarTilePressStyle: ButtonStyle {
    var cornerRadius: CGFloat = .mdShapeLarge
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0))
                    .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(duration: 0.2, bounce: 0.25), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .medium), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}
