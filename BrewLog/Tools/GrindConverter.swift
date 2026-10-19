import Foundation

/// Rough translation of grind settings between grinders.
///
/// Every calibrated grinder has a medium-fine filter setting (`GrinderSpec.defaultGrind`) and how many µm one step
/// moves the burrs (`GrinderSpec.micronsPerStep`). The filter setting is pinned to the same point on a shared scale
/// (`referenceMicrons`, Comandante 24 clicks ≈ 720 µm), and steps move along it. Recipes give grind sizes in µm on
/// that scale. Burrs and zero points differ, so the result is a starting point to taste from, not an exact match.
enum GrindConverter {
    /// The shared scale's point for a medium-fine filter grind.
    static let referenceMicrons = 720.0

    /// Calibration of the grinder presets by name: µm per smallest step.
    static let knownMicronsPerStep: [String: Double] = [
        "Comandante C40": 30,
        "1Zpresso K-Ultra": 20,
        "1Zpresso ZP6 Special": 16,
        "Kingrinder K6": 16,
    ]

    /// The spec with the preset calibration filled in when the grinder has none of its own.
    static func calibrated(_ spec: GrinderSpec, name: String) -> GrinderSpec {
        var spec = spec
        if spec.micronsPerStep == nil {
            spec.micronsPerStep = spec.unit == .microns ? spec.step : knownMicronsPerStep[name]
        }
        return spec
    }

    static func canConvert(_ spec: GrinderSpec) -> Bool {
        spec.defaultGrind != nil && (spec.micronsPerStep ?? 0) > 0 && spec.step > 0
    }

    /// The setting's position on the shared µm scale.
    static func microns(for value: Double, spec: GrinderSpec) -> Double? {
        guard canConvert(spec), let start = spec.defaultGrind, let perStep = spec.micronsPerStep else { return nil }
        let steps = (value - start) / spec.step
        // Most grinders get finer as the number goes down; for the others the scale runs the other way.
        return referenceMicrons + (spec.finerIsLower ? steps : -steps) * perStep
    }

    /// The setting on this grinder for a size on the shared scale, snapped to the grinder's steps.
    static func value(for microns: Double, spec: GrinderSpec) -> Double? {
        guard canConvert(spec), let start = spec.defaultGrind, let perStep = spec.micronsPerStep else { return nil }
        let steps = (microns - referenceMicrons) / perStep
        let raw = start + (spec.finerIsLower ? steps : -steps) * spec.step
        return max(0, (raw / spec.step).rounded() * spec.step)
    }

    static func convert(_ value: Double, from: GrinderSpec, to: GrinderSpec) -> Double? {
        microns(for: value, spec: from).flatMap { Self.value(for: $0, spec: to) }
    }

    /// The grind size range in a recipe's grind text, e.g. "Medium-fine (about 600–750 µm)" → 600...750.
    static func micronRange(in text: String) -> ClosedRange<Double>? {
        let pattern = #"(\d{3,4})\s*(?:[–—-]|to)\s*(\d{3,4})\s*(?:µm|μm|um|microns)|(\d{3,4})\s*(?:µm|μm|um|microns)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ index: Int) -> Double? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Double(text[range])
        }
        if let low = group(1), let high = group(2) { return min(low, high)...max(low, high) }
        if let single = group(3) { return single...single }
        return nil
    }

    /// The recipe's grind size on this grinder, e.g. "≈ 22–25 clicks". Nil when the grinder isn't calibrated.
    static func hint(recipeGrind: String, spec: GrinderSpec) -> String? {
        guard let range = micronRange(in: recipeGrind),
              let a = value(for: range.lowerBound, spec: spec),
              let b = value(for: range.upperBound, spec: spec) else { return nil }
        let low = min(a, b), high = max(a, b)
        if low == high { return "≈ " + spec.format(low) }
        let number = spec.format(high)
        let lowText = spec.format(low).replacingOccurrences(of: " " + spec.unit.suffix, with: "")
        return "≈ \(lowText)–\(number)"
    }
}
