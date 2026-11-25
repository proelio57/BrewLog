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

    /// The second data color next to the accent (flow rates): teal, except where that would be too close to the accent.
    var flowHex: UInt32 {
        switch self {
        case .blue: return 0x25B7A5
        case .green: return 0x3A86FF
        default: return 0x30B0C7
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

    /// The flow color of the chosen accent (flow lines, flow readouts, the "finish" flash).
    static var flowColor: Color {
        let hex = current.flowHex
        return Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
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
