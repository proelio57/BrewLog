import Foundation
import UIKit

/// How BrewLog reaches the espresso machine's smart plug (Settings → Espresso machine → Smart plug).
enum PlugKind: String, CaseIterable, Identifiable {
    case none
    /// Two shortcuts in the Shortcuts app that switch the plug (works with HomeKit, Home Assistant, any plug app).
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .shortcuts: return "Shortcuts"
        }
    }

    static var current: PlugKind {
        PlugKind(rawValue: UserDefaults.standard.string(forKey: SettingsKey.powerPlug) ?? "") ?? .none
    }
}

/// The machine's smart plug.
protocol SmartPlug {
    func turnOn()
    func turnOff()
}

/// Runs the user's shortcuts "Machine on" / "Machine off" (names in Settings). HomeKit itself isn't available to
/// a SideStore install, so the Shortcuts app does the switching: it comes to the front for a moment and returns
/// to BrewLog (x-success).
struct ShortcutPlug: SmartPlug {
    var onName: String
    var offName: String

    static var configured: ShortcutPlug? {
        guard PlugKind.current == .shortcuts else { return nil }
        let d = UserDefaults.standard
        let on = (d.string(forKey: SettingsKey.powerShortcutOn) ?? "").trimmingCharacters(in: .whitespaces)
        let off = (d.string(forKey: SettingsKey.powerShortcutOff) ?? "").trimmingCharacters(in: .whitespaces)
        guard !on.isEmpty, !off.isEmpty else { return nil }
        return ShortcutPlug(onName: on, offName: off)
    }

    func turnOn() { run(onName) }
    func turnOff() { run(offName) }

    /// `shortcuts://x-callback-url/run-shortcut?name=…&x-success=brewlog://resume&x-error=brewlog://resume?failed=…`
    /// On an error (e.g. no shortcut with that name) Shortcuts returns to BrewLog with `errorMessage` added.
    static func url(name: String) -> URL? {
        var error = URLComponents(url: AppLink.resume.url, resolvingAgainstBaseURL: false)
        error?.queryItems = [URLQueryItem(name: failedKey, value: name)]
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "x-success", value: AppLink.resume.url.absoluteString),
            URLQueryItem(name: "x-error", value: error?.url?.absoluteString ?? AppLink.resume.url.absoluteString),
        ]
        return components.url
    }

    static let failedKey = "failed"

    /// The failed shortcut's name and Shortcuts' message, from the x-error callback; nil for any other link.
    static func failure(in url: URL) -> (name: String, message: String?)? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let name = items.first(where: { $0.name == failedKey })?.value, !name.isEmpty else { return nil }
        let message = items.first(where: { $0.name == "errorMessage" })?.value
        return (String(name.prefix(80)), message.map { String($0.prefix(200)) })
    }

    /// Settings → Test: runs one of the shortcuts.
    static func test(name: String) {
        guard let url = url(name: name) else { return }
        UIApplication.shared.open(url)
    }

    private func run(_ name: String) {
        guard let url = Self.url(name: name) else { return }
        DispatchQueue.main.async { UIApplication.shared.open(url) }
    }
}
