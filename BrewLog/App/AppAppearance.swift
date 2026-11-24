import SwiftUI
import UIKit

/// The app's accent color (Settings → Appearance). Each has a light and a dark variant; copper is the default.
enum AccentChoice: String, CaseIterable, Identifiable {
    case copper, blue, green, purple, red, graphite

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    /// sRGB hex for light and dark mode.
    var hex: (light: UInt32, dark: UInt32) {
        switch self {
        case .copper: return (0xB86D3C, 0xE29961)
        case .blue: return (0x0A6CFF, 0x5AA2FF)
        case .green: return (0x2E9E5B, 0x4CC17D)
        case .purple: return (0x7B5CE0, 0xA58BFF)
        case .red: return (0xD6403A, 0xFF6B63)
        case .graphite: return (0x5F6368, 0xA8ADB3)
        }
    }

    var color: Color {
        let hex = hex
        return Color(UIColor { $0.userInterfaceStyle == .dark ? Self.ui(hex.dark) : Self.ui(hex.light) })
    }

    private static func ui(_ rgb: UInt32) -> UIColor {
        UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    static var current: AccentChoice {
        AccentChoice(rawValue: UserDefaults.standard.string(forKey: SettingsKey.accentColor) ?? "") ?? .copper
    }
}

/// Light, dark or follow the system (Settings → Appearance).
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
