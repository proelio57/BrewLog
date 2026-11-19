import Foundation

/// Learns how long coffee keeps arriving after BrewLog stops a shot, so the next stop lands on the yield.
///
/// When the app stops the machine it remembers the weight and the flow at that moment. Once the cup has settled,
/// what arrived after the stop divided by that flow is the lead that would have been right. The stored lead moves
/// halfway towards it, so one odd shot doesn't throw it off. Kept per machine and scale (the phone's scale reacts
/// differently from one connected to GaggiMate).
enum StopLagLearner {
    static let range = 0.3...3.0
    /// Below this flow the measurement is mostly scale noise.
    static let minFlow = 0.5
    static let learningRate = 0.5

    /// The lead that would have hit the yield in this shot, or nil when the shot can't teach anything:
    /// too little flow, the cup moved (the weight fell), or an implausible jump after the stop.
    static func measuredLag(weightAtStop: Double, flowAtStop: Double, finalWeight: Double) -> Double? {
        guard weightAtStop.isFinite, flowAtStop.isFinite, finalWeight.isFinite, flowAtStop >= minFlow else { return nil }
        let after = finalWeight - weightAtStop
        guard after >= -0.5, after <= flowAtStop * 5 else { return nil }
        return min(max(max(after, 0) / flowAtStop, range.lowerBound), range.upperBound)
    }

    static func updated(current: Double, measured: Double) -> Double {
        let next = current + learningRate * (measured - current)
        return min(max(next, range.lowerBound), range.upperBound)
    }

    /// "gaggimate-phone" or "gaggimate-machine": where the weight comes from changes the delay.
    static func key(machine: MachineKind, scaleOnMachine: Bool) -> String {
        "\(machine.rawValue)-\(scaleOnMachine ? "machine" : "phone")"
    }

    struct Learned: Codable, Equatable {
        var lag: Double
        var shots: Int
    }

    private static let storeKey = "shotStopLag.learned"

    static func all(_ defaults: UserDefaults = .standard) -> [String: Learned] {
        guard let data = defaults.data(forKey: storeKey),
              let stored = try? JSONDecoder().decode([String: Learned].self, from: data) else { return [:] }
        return stored
    }

    static func learned(for key: String, _ defaults: UserDefaults = .standard) -> Learned? { all(defaults)[key] }

    /// The lead to use now: learned for this machine and scale, otherwise the manual setting.
    static func lag(for key: String, manual: Double, learning: Bool, _ defaults: UserDefaults = .standard) -> Double {
        guard learning, let learned = learned(for: key, defaults) else { return manual }
        return learned.lag
    }

    /// Adds one shot. Returns the new lead, or nil when the shot didn't count.
    @discardableResult
    static func record(key: String, start: Double, weightAtStop: Double, flowAtStop: Double, finalWeight: Double,
                       _ defaults: UserDefaults = .standard) -> Double? {
        guard let measured = measuredLag(weightAtStop: weightAtStop, flowAtStop: flowAtStop, finalWeight: finalWeight)
        else { return nil }
        var stored = all(defaults)
        let previous = stored[key]
        let lag = updated(current: previous?.lag ?? start, measured: measured)
        stored[key] = Learned(lag: lag, shots: (previous?.shots ?? 0) + 1)
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: storeKey) }
        return lag
    }

    static func reset(_ defaults: UserDefaults = .standard) { defaults.removeObject(forKey: storeKey) }
}
