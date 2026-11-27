import SwiftUI

enum DayNoteThemeID: String, CaseIterable, Identifiable, Codable {
    case warmApricot = "warm_apricot"
    case matchaPaper = "matcha_paper"
    case sakuraBlush = "sakura_blush"
    case skyMist = "sky_mist"
    case midnightInk = "midnight_ink"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .warmApricot: return "暖杏手账"
        case .matchaPaper: return "抹茶清纸"
        case .sakuraBlush: return "樱花微醺"
        case .skyMist: return "晴空便笺"
        case .midnightInk: return "静谧夜读"
        }
    }

    var palette: DayNotePalette {
        switch self {
        case .warmApricot:
            return DayNotePalette(
                id: self,
                isDark: false,
                backgroundTop: Color(red: 1.00, green: 0.985, blue: 0.94),
                backgroundBottom: Color(red: 0.99, green: 0.945, blue: 0.885),
                surfaceCard: Color.white.opacity(0.76),
                surfaceCardActive: Color.white.opacity(0.95),
                surfaceElevated: Color.white.opacity(0.62),
                borderSubtle: Color(red: 0.55, green: 0.38, blue: 0.24).opacity(0.10),
                inkPrimary: Color(red: 0.21, green: 0.16, blue: 0.12),
                inkSecondary: Color(red: 0.45, green: 0.38, blue: 0.32),
                accent: Color(red: 0.94, green: 0.42, blue: 0.26),
                accentSoft: Color(red: 0.94, green: 0.42, blue: 0.26).opacity(0.13),
                swatchPreview: Color(red: 0.98, green: 0.91, blue: 0.78)
            )
        case .matchaPaper:
            return DayNotePalette(
                id: self,
                isDark: false,
                backgroundTop: Color(red: 0.96, green: 0.985, blue: 0.955),
                backgroundBottom: Color(red: 0.91, green: 0.96, blue: 0.915),
                surfaceCard: Color.white.opacity(0.78),
                surfaceCardActive: Color.white.opacity(0.96),
                surfaceElevated: Color.white.opacity(0.60),
                borderSubtle: Color(red: 0.20, green: 0.42, blue: 0.28).opacity(0.11),
                inkPrimary: Color(red: 0.13, green: 0.22, blue: 0.16),
                inkSecondary: Color(red: 0.34, green: 0.45, blue: 0.37),
                accent: Color(red: 0.25, green: 0.62, blue: 0.43),
                accentSoft: Color(red: 0.25, green: 0.62, blue: 0.43).opacity(0.13),
                swatchPreview: Color(red: 0.84, green: 0.93, blue: 0.85)
            )
        case .sakuraBlush:
            return DayNotePalette(
                id: self,
                isDark: false,
                backgroundTop: Color(red: 1.00, green: 0.965, blue: 0.975),
                backgroundBottom: Color(red: 0.99, green: 0.925, blue: 0.945),
                surfaceCard: Color.white.opacity(0.78),
                surfaceCardActive: Color.white.opacity(0.96),
                surfaceElevated: Color.white.opacity(0.62),
                borderSubtle: Color(red: 0.58, green: 0.25, blue: 0.36).opacity(0.10),
                inkPrimary: Color(red: 0.24, green: 0.15, blue: 0.19),
                inkSecondary: Color(red: 0.49, green: 0.36, blue: 0.41),
                accent: Color(red: 0.88, green: 0.38, blue: 0.52),
                accentSoft: Color(red: 0.88, green: 0.38, blue: 0.52).opacity(0.13),
                swatchPreview: Color(red: 0.98, green: 0.86, blue: 0.90)
            )
        case .skyMist:
            return DayNotePalette(
                id: self,
                isDark: false,
                backgroundTop: Color(red: 0.955, green: 0.978, blue: 1.00),
                backgroundBottom: Color(red: 0.905, green: 0.948, blue: 0.995),
                surfaceCard: Color.white.opacity(0.80),
                surfaceCardActive: Color.white.opacity(0.96),
                surfaceElevated: Color.white.opacity(0.64),
                borderSubtle: Color(red: 0.18, green: 0.34, blue: 0.58).opacity(0.11),
                inkPrimary: Color(red: 0.12, green: 0.18, blue: 0.27),
                inkSecondary: Color(red: 0.34, green: 0.42, blue: 0.53),
                accent: Color(red: 0.23, green: 0.51, blue: 0.94),
                accentSoft: Color(red: 0.23, green: 0.51, blue: 0.94).opacity(0.13),
                swatchPreview: Color(red: 0.83, green: 0.91, blue: 0.99)
            )
        case .midnightInk:
            return DayNotePalette(
                id: self,
                isDark: true,
                backgroundTop: Color(red: 0.135, green: 0.140, blue: 0.168),
                backgroundBottom: Color(red: 0.098, green: 0.102, blue: 0.125),
                surfaceCard: Color.white.opacity(0.075),
                surfaceCardActive: Color.white.opacity(0.13),
                surfaceElevated: Color.white.opacity(0.055),
                borderSubtle: Color.white.opacity(0.10),
                inkPrimary: Color(red: 0.95, green: 0.94, blue: 0.92),
                inkSecondary: Color(red: 0.67, green: 0.67, blue: 0.72),
                accent: Color(red: 0.98, green: 0.49, blue: 0.34),
                accentSoft: Color(red: 0.98, green: 0.49, blue: 0.34).opacity(0.18),
                swatchPreview: Color(red: 0.17, green: 0.18, blue: 0.22)
            )
        }
    }
}

struct DayNotePalette {
    let id: DayNoteThemeID
    let isDark: Bool
    let backgroundTop: Color
    let backgroundBottom: Color
    let surfaceCard: Color
    let surfaceCardActive: Color
    let surfaceElevated: Color
    let borderSubtle: Color
    let inkPrimary: Color
    let inkSecondary: Color
    let accent: Color
    let accentSoft: Color
    let swatchPreview: Color

    var colorScheme: ColorScheme {
        isDark ? .dark : .light
    }

    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
