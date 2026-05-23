import SwiftUI

// MARK: - Stellar Colour Themes

enum StellarTheme: String, CaseIterable, Identifiable {
    case rose              = "rose"
    case darkForest        = "darkForest"
    case sageGreen         = "sageGreen"
    case violetExpressive  = "violetExpressive"
    case amethyst          = "amethyst"
    case lavender          = "lavender"
    case lime              = "lime"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rose:             return "Rose Crimson"
        case .darkForest:       return "Dark Forest"
        case .sageGreen:        return "Sage Green"
        case .violetExpressive: return "Violet Expressive"
        case .amethyst:         return "Amethyst"
        case .lavender:         return "Lavender"
        case .lime:             return "Lime"
        }
    }

    var emoji: String {
        switch self {
        case .rose:             return "🌹"
        case .darkForest:       return "🌿"
        case .sageGreen:        return "✨"
        case .violetExpressive: return "💜"
        case .amethyst:         return "💎"
        case .lavender:         return "🪻"
        case .lime:             return "🍋‍🟩"
        }
    }

    var accentColor: Color {
        switch self {
        case .rose:             return Color(hex: "#B5264C")
        case .darkForest:       return Color(hex: "#4DBB7A")
        case .sageGreen:        return Color(hex: "#78BE8E")
        case .violetExpressive: return Color(hex: "#C084FC")
        case .amethyst:         return Color(hex: "#D080FF")
        case .lavender:         return Color(hex: "#3A0078")
        case .lime:             return Color(hex: "#174400")
        }
    }

    var backgroundColor: Color {
        switch self {
        case .rose:             return Color(hex: "#1C1112")
        case .darkForest:       return Color(hex: "#0B1610")
        case .sageGreen:        return Color(hex: "#101510")
        case .violetExpressive: return Color(hex: "#120D1E")
        case .amethyst:         return Color(hex: "#130720")
        case .lavender:         return Color(hex: "#BF80FF")
        case .lime:             return Color(hex: "#BFEF3C")
        }
    }

    var icon: String {
        switch self {
        case .rose:             return "heart.fill"
        case .darkForest:       return "leaf.fill"
        case .sageGreen:        return "sparkles"
        case .violetExpressive: return "wand.and.stars"
        case .amethyst:         return "diamond.fill"
        case .lavender:         return "cloud.fill"
        case .lime:             return "leaf.circle.fill"
        }
    }

    /// Custom font name for this theme (nil = system default DM Sans)
    var customFontName: String? {
        switch self {
        case .violetExpressive: return "PlusJakartaSans"
        case .amethyst:         return "CormorantGaramond"
        case .lavender:         return "SpaceGrotesk"
        case .lime:             return "SpaceGrotesk"
        default:                return nil
        }
    }
}

// MARK: - Theme Store

@Observable
final class ThemeStore {
    private static let key = "colorTheme"

    var theme: StellarTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.key) }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.key) ?? ""
        theme = StellarTheme(rawValue: stored) ?? .rose
    }
}
