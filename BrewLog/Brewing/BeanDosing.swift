import Foundation

/// Weighing the beans before a brew: how close the scale reading is to the planned dose.
enum BeanDosing {
    enum Status: Equatable {
        case empty, under, onTarget, over
    }

    /// ±0.2 g counts as on target: the scale shows 0.1 g and a single bean weighs about 0.15 g.
    static let tolerance = 0.2

    static func status(weight: Double, dose: Double) -> Status {
        guard weight.isFinite, weight >= 0.5 else { return .empty }
        if weight < dose - tolerance { return .under }
        if weight > dose + tolerance { return .over }
        return .onTarget
    }

    /// 0…1 for the progress bar.
    static func progress(weight: Double, dose: Double) -> Double {
        guard dose > 0, weight.isFinite else { return 0 }
        return min(max(weight / dose, 0), 1)
    }

    /// The dose to save with the brew: what was weighed (to 0.1 g), or the planned dose when the reading is implausible.
    static func acceptedDose(weight: Double, planned: Double) -> Double {
        guard weight.isFinite, weight >= 0.5, weight <= InputLimits.maxDose else { return planned }
        return (weight * 10).rounded() / 10
    }
}

extension BeanDosing {
    /// Below this difference the recipe stays as planned; from here on it is scaled to the weighed dose.
    static let rescaleThreshold = 0.5

    /// The recipe for the weighed dose: scaled (water and pour targets) when it is at least 0.5 g off the plan.
    static func recipe(_ recipe: Recipe, forDose dose: Double) -> Recipe {
        abs(dose - recipe.dose) >= rescaleThreshold ? recipe.scaled(toDose: dose) : recipe
    }

    /// A settled reading: the readings of the last second (at least 4) lie within ±0.2 g. Lifting the cup off or
    /// still pouring beans in doesn't count, so "Ready" keeps what was actually weighed.
    static func stableWeight(_ readings: [(t: TimeInterval, grams: Double)], now: TimeInterval) -> Double? {
        let window = readings.filter { now - $0.t <= 1.0 }.map(\.grams)
        guard window.count >= 4, let low = window.min(), let high = window.max(), high - low <= 2 * tolerance else { return nil }
        let mean = window.reduce(0, +) / Double(window.count)
        return status(weight: mean, dose: 1) == .empty ? nil : mean
    }
}
