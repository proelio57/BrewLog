import Foundation

/// Input limits. Everything the user types (or that is decoded from storage) is clamped to sane ranges,
/// so corrupted or hostile data can never produce NaN timers, giant allocations or broken charts.
enum InputLimits {
    static let maxNameLength = 80
    static let maxShortText = 200
    static let maxLongText = 2_000
    static let maxSteps = 30
    static let maxTips = 20
    static let maxBrewSeconds: Double = 1_800
    static let maxDose: Double = 150
    static let maxWater: Double = 3_000
    static let maxBagWeight: Double = 10_000
}

extension String {
    /// Trims whitespace/control characters and limits the length.
    func sanitized(maxLength: Int) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" })
        let cleaned = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count > maxLength ? String(cleaned.prefix(maxLength)) : cleaned
    }
}

extension Double {
    /// Clamps to a range and maps NaN/∞ to the lower bound.
    func clamped(_ lower: Double, _ upper: Double) -> Double {
        guard isFinite else { return lower }
        return Swift.min(Swift.max(self, lower), upper)
    }
}

extension Recipe {
    /// Returns a copy with every field sanitized and clamped to sane ranges.
    func validated() -> Recipe {
        var r = self
        r.id = id.sanitized(maxLength: 120)
        if r.id.isEmpty { r.id = "custom-\(UUID().uuidString)" }
        r.name = name.sanitized(maxLength: InputLimits.maxNameLength)
        if r.name.isEmpty { r.name = "Untitled recipe" }
        r.author = author.sanitized(maxLength: InputLimits.maxNameLength)
        r.summary = summary.sanitized(maxLength: InputLimits.maxLongText)
        r.tasteNotes = tasteNotes.sanitized(maxLength: InputLimits.maxLongText)
        r.grind = grind.sanitized(maxLength: InputLimits.maxShortText)

        r.dose = dose.clamped(1, InputLimits.maxDose)
        r.water = water.clamped(10, InputLimits.maxWater)
        r.temperature = temperature.clamped(0, 100)
        r.flowMin = flowMin.clamped(0.5, 30)
        r.flowMax = flowMax.clamped(r.flowMin + 0.5, 40)
        r.taste = TasteProfile(acidity: min(max(taste.acidity, 1), 5),
                               sweetness: min(max(taste.sweetness, 1), 5),
                               body: min(max(taste.body, 1), 5),
                               clarity: min(max(taste.clarity, 1), 5))

        var cleanSteps = steps.prefix(InputLimits.maxSteps).map { step -> RecipeStep in
            var s = step
            s.time = step.time.clamped(0, InputLimits.maxBrewSeconds)
            if step.kind.isPour {
                s.target = (step.target ?? 0).clamped(0, r.water * 1.5)
            } else {
                s.target = nil
            }
            s.note = step.note.map { $0.sanitized(maxLength: InputLimits.maxShortText) }.flatMap { $0.isEmpty ? nil : $0 }
            return s
        }
        // Stable sort by time, then make cumulative pour targets non-decreasing.
        cleanSteps = cleanSteps.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
        var runningTarget = 0.0
        for index in cleanSteps.indices where cleanSteps[index].kind.isPour {
            let target = Swift.max(cleanSteps[index].target ?? 0, runningTarget)
            cleanSteps[index].target = target
            runningTarget = target
        }
        r.steps = cleanSteps

        let lastStep = cleanSteps.last?.time ?? 0
        r.targetTime = targetTime.clamped(10, InputLimits.maxBrewSeconds)
        if r.targetTime < lastStep { r.targetTime = Swift.min(lastStep + 30, InputLimits.maxBrewSeconds) }

        r.tips = tips.prefix(InputLimits.maxTips)
            .map { $0.sanitized(maxLength: InputLimits.maxShortText) }
            .filter { !$0.isEmpty }
        return r
    }
}
