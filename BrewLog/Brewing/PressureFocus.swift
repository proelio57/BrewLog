import Foundation

/// Settings → Pressure view: when the live shot screen is about the pressure (big number, big graph).
enum PressureFocusMode: String, CaseIterable, Identifiable {
    /// While a pressure sensor (BOOKOO Espresso Monitor) gives the pressure: for setting it by hand.
    case automatic
    /// Also with the machine's own pressure (GaggiMate, DE1).
    case always
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .always: return "Always"
        case .off: return "Off"
        }
    }

    static var current: PressureFocusMode {
        UserDefaults.standard.string(forKey: SettingsKey.pressureFocus).flatMap(PressureFocusMode.init) ?? .automatic
    }
}

/// Where the live pressure is relative to the recipe's target.
enum PressureZone: Equatable {
    case low, onTarget, high, noTarget
}

enum PressureFocus {
    /// ± bar around the target that count as on target.
    static let tolerance = 0.5

    static func isActive(mode: PressureFocusMode, sensorIsSource: Bool, hasPressure: Bool) -> Bool {
        switch mode {
        case .automatic: return sensorIsSource
        case .always: return hasPressure
        case .off: return false
        }
    }

    static func zone(pressure: Double?, target: Double?) -> PressureZone {
        guard let pressure, let target, pressure.isFinite, target > 0 else { return .noTarget }
        // A little slack for floating point, so 8.5 and 9.5 around 9 bar count as on target.
        let delta = pressure - target
        if abs(delta) <= tolerance + 1e-9 { return .onTarget }
        return delta < 0 ? .low : .high
    }
}

/// Keeps the layout of a running shot: decided live until the shot starts, then fixed for that shot,
/// so a sensor dropping out mid-shot doesn't flip the screen.
struct PressureFocusLatch: Equatable {
    private var latched: Bool?

    func value(live: Bool) -> Bool { latched ?? live }

    /// At the start of a shot: keep the current decision until the next shot.
    mutating func latch(_ live: Bool) { latched = live }
}
