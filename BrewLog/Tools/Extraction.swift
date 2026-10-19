import Foundation

/// Extraction yield from a refractometer reading (TDS).
///
///     EY % = beverage (g) × TDS % / dose (g)
///
/// The beverage is what ends up in the cup, not the water poured: the grounds hold back about twice their dry weight.
enum Extraction {
    /// Water the spent grounds hold back, in grams per gram of coffee (pour-over).
    static let retentionRatio = 2.0

    enum Limits {
        static let maxTDS = 25.0
    }

    /// Extraction yield in percent, nil when an input is missing.
    static func yield(tds: Double, beverage: Double, dose: Double) -> Double? {
        guard tds > 0, beverage > 0, dose > 0 else { return nil }
        return beverage * tds / dose
    }

    /// Estimated drink weight when it wasn't weighed: the yield for espresso (weighed in the cup),
    /// the poured water minus what the grounds absorb for filter coffee.
    static func estimatedBeverage(finalWeight: Double, dose: Double, espresso: Bool) -> Double {
        guard finalWeight > 0 else { return 0 }
        if espresso { return finalWeight }
        return max(finalWeight - dose * retentionRatio, 0)
    }

    /// The classic brewing control chart zones (SCA / Gold Cup for filter, common espresso targets).
    struct Zone: Equatable {
        var tds: ClosedRange<Double>
        var yield: ClosedRange<Double>

        static let filter = Zone(tds: 1.15...1.45, yield: 18...22)
        static let espresso = Zone(tds: 8...12, yield: 18...22)

        static func forMethod(espresso: Bool) -> Zone { espresso ? .espresso : .filter }
    }

    enum Verdict: Equatable {
        case under, ideal, over
        var title: String {
            switch self {
            case .under: return "Under-extracted"
            case .ideal: return "In the ideal range"
            case .over: return "Over-extracted"
            }
        }
    }

    enum Strength: Equatable {
        case weak, ideal, strong
        var title: String {
            switch self {
            case .weak: return "weak"
            case .ideal: return "ideal strength"
            case .strong: return "strong"
            }
        }
    }

    struct Reading: Equatable {
        var tds: Double
        var yield: Double
        var verdict: Verdict
        var strength: Strength

        /// Plain-language advice for the next brew.
        var advice: String {
            var parts: [String] = []
            switch verdict {
            case .under: parts.append("Extract more: grind finer, use hotter water or brew longer.")
            case .over: parts.append("Extract less: grind coarser, use cooler water or brew shorter.")
            case .ideal: break
            }
            switch strength {
            case .weak: parts.append("For a stronger cup use more coffee for the same water (lower ratio).")
            case .strong: parts.append("For a lighter cup use more water for the same coffee (higher ratio).")
            case .ideal: break
            }
            return parts.isEmpty ? "Balanced on both strength and extraction." : parts.joined(separator: " ")
        }
    }

    static func evaluate(tds: Double, beverage: Double, dose: Double, espresso: Bool) -> Reading? {
        guard let yield = yield(tds: tds, beverage: beverage, dose: dose) else { return nil }
        let zone = Zone.forMethod(espresso: espresso)
        let verdict: Verdict = yield < zone.yield.lowerBound ? .under : (yield > zone.yield.upperBound ? .over : .ideal)
        let strength: Strength = tds < zone.tds.lowerBound ? .weak : (tds > zone.tds.upperBound ? .strong : .ideal)
        return Reading(tds: tds, yield: yield, verdict: verdict, strength: strength)
    }
}
