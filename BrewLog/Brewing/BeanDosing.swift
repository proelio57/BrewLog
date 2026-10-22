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
