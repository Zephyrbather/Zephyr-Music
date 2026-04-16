import SwiftUI

struct PlayerTheme {
    let backgroundTop: Color
    let backgroundBottom: Color
    let panel: Color
    let panelSecondary: Color
    let accent: Color
    let accentSoft: Color
    let border: Color
    let lyricGlow: Color
    let primaryText: Color
    let secondaryText: Color
    let primaryShadow: Color

    static func forSelection(_ selection: PlayerViewModel.AppTheme, colorScheme: ColorScheme) -> PlayerTheme {
        switch selection {
        case .system:
            return forColorScheme(colorScheme)
        case .pureBlack:
            return PlayerTheme(
                backgroundTop: .black,
                backgroundBottom: Color(red: 0.04, green: 0.04, blue: 0.04),
                panel: Color.white.opacity(0.08),
                panelSecondary: Color.white.opacity(0.05),
                accent: Color(red: 0.42, green: 0.86, blue: 0.81),
                accentSoft: Color(red: 0.16, green: 0.26, blue: 0.25),
                border: Color.white.opacity(0.10),
                lyricGlow: Color(red: 0.42, green: 0.86, blue: 0.81).opacity(0.26),
                primaryText: Color.white.opacity(0.97),
                secondaryText: Color.white.opacity(0.72),
                primaryShadow: Color.black.opacity(0.34)
            )
        case .pureWhite:
            return PlayerTheme(
                backgroundTop: .white,
                backgroundBottom: Color(red: 0.95, green: 0.95, blue: 0.95),
                panel: Color.white.opacity(0.92),
                panelSecondary: Color.white.opacity(0.76),
                accent: Color(red: 0.16, green: 0.42, blue: 0.68),
                accentSoft: Color(red: 0.84, green: 0.91, blue: 0.97),
                border: Color.black.opacity(0.08),
                lyricGlow: Color(red: 0.16, green: 0.42, blue: 0.68).opacity(0.12),
                primaryText: Color.black.opacity(0.92),
                secondaryText: Color.black.opacity(0.58),
                primaryShadow: Color.clear
            )
        case .pastelBlue:
            return PlayerTheme(
                backgroundTop: Color(red: 0.91, green: 0.96, blue: 1.0),
                backgroundBottom: Color(red: 0.82, green: 0.90, blue: 0.99),
                panel: Color.white.opacity(0.82),
                panelSecondary: Color.white.opacity(0.62),
                accent: Color(red: 0.22, green: 0.55, blue: 0.82),
                accentSoft: Color(red: 0.74, green: 0.86, blue: 0.98),
                border: Color.black.opacity(0.08),
                lyricGlow: Color(red: 0.22, green: 0.55, blue: 0.82).opacity(0.14),
                primaryText: Color.black.opacity(0.90),
                secondaryText: Color.black.opacity(0.58),
                primaryShadow: Color.clear
            )
        case .pastelPurple:
            return PlayerTheme(
                backgroundTop: Color(red: 0.97, green: 0.92, blue: 1.0),
                backgroundBottom: Color(red: 0.90, green: 0.84, blue: 0.97),
                panel: Color.white.opacity(0.82),
                panelSecondary: Color.white.opacity(0.62),
                accent: Color(red: 0.52, green: 0.37, blue: 0.76),
                accentSoft: Color(red: 0.88, green: 0.81, blue: 0.96),
                border: Color.black.opacity(0.08),
                lyricGlow: Color(red: 0.52, green: 0.37, blue: 0.76).opacity(0.14),
                primaryText: Color.black.opacity(0.90),
                secondaryText: Color.black.opacity(0.58),
                primaryShadow: Color.clear
            )
        case .pastelGreen:
            return PlayerTheme(
                backgroundTop: Color(red: 0.92, green: 0.99, blue: 0.94),
                backgroundBottom: Color(red: 0.84, green: 0.95, blue: 0.87),
                panel: Color.white.opacity(0.82),
                panelSecondary: Color.white.opacity(0.62),
                accent: Color(red: 0.22, green: 0.58, blue: 0.40),
                accentSoft: Color(red: 0.78, green: 0.93, blue: 0.83),
                border: Color.black.opacity(0.08),
                lyricGlow: Color(red: 0.22, green: 0.58, blue: 0.40).opacity(0.14),
                primaryText: Color.black.opacity(0.90),
                secondaryText: Color.black.opacity(0.58),
                primaryShadow: Color.clear
            )
        case .customImage:
            return PlayerTheme(
                backgroundTop: Color.black.opacity(0.72),
                backgroundBottom: Color.black.opacity(0.88),
                panel: Color.white.opacity(0.16),
                panelSecondary: Color.white.opacity(0.10),
                accent: Color(red: 0.45, green: 0.83, blue: 0.92),
                accentSoft: Color.white.opacity(0.16),
                border: Color.white.opacity(0.12),
                lyricGlow: Color(red: 0.45, green: 0.83, blue: 0.92).opacity(0.18),
                primaryText: Color.white.opacity(0.98),
                secondaryText: Color.white.opacity(0.76),
                primaryShadow: Color.black.opacity(0.42)
            )
        }
    }

    static func forColorScheme(_ colorScheme: ColorScheme) -> PlayerTheme {
        if colorScheme == .dark {
            return PlayerTheme(
                backgroundTop: Color(red: 0.08, green: 0.10, blue: 0.16),
                backgroundBottom: Color(red: 0.03, green: 0.04, blue: 0.08),
                panel: Color.white.opacity(0.08),
                panelSecondary: Color.white.opacity(0.05),
                accent: Color(red: 0.35, green: 0.82, blue: 0.77),
                accentSoft: Color(red: 0.18, green: 0.42, blue: 0.40),
                border: Color.white.opacity(0.10),
                lyricGlow: Color(red: 0.35, green: 0.82, blue: 0.77).opacity(0.30),
                primaryText: Color.white.opacity(0.97),
                secondaryText: Color.white.opacity(0.72),
                primaryShadow: Color.black.opacity(0.24)
            )
        }

        return PlayerTheme(
            backgroundTop: Color(red: 0.93, green: 0.97, blue: 0.99),
            backgroundBottom: Color(red: 0.89, green: 0.94, blue: 0.97),
            panel: Color.white.opacity(0.84),
            panelSecondary: Color.white.opacity(0.60),
            accent: Color(red: 0.06, green: 0.52, blue: 0.68),
            accentSoft: Color(red: 0.77, green: 0.90, blue: 0.93),
            border: Color.black.opacity(0.08),
            lyricGlow: Color(red: 0.06, green: 0.52, blue: 0.68).opacity(0.14),
            primaryText: Color.black.opacity(0.92),
            secondaryText: Color.black.opacity(0.58),
            primaryShadow: Color.clear
        )
    }
}
