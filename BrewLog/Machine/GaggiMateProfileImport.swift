import Foundation

/// Turns GaggiMate profiles (schema `profile.json` in the GaggiMate repo) into BrewLog espresso recipes.
///
/// Reads a profile exported from GaggiMate's web interface (one object), a list of them, or the machine's
/// `res:profiles:list` answer (`{ "profiles": [...] }`). Pre-infusion phases become the pre-infusion step,
/// the volumetric target the yield, the highest pressure the recipe's pressure. Every phase is listed in the tips,
/// so nothing of the profile is lost even where BrewLog has no field for it.
extension GaggiMateProfile {
    static let recipeIDPrefix = "gaggimate-"

    /// True if the JSON is one GaggiMate profile, a list of them or `{ "profiles": [...] }`.
    static func looksLikeProfiles(_ object: Any) -> Bool {
        if let profile = object as? [String: Any] {
            if let list = profile["profiles"] as? [Any] { return !list.isEmpty && list.allSatisfy(isProfile) }
            return isProfile(profile)
        }
        if let list = object as? [Any] { return !list.isEmpty && list.allSatisfy(isProfile) }
        return false
    }

    private static func isProfile(_ object: Any) -> Bool {
        guard let profile = object as? [String: Any], profile["phases"] is [Any] else { return false }
        // BrewLog recipes have "steps", GaggiMate profiles "label" and "phases".
        return profile["label"] is String && profile["steps"] == nil
    }

    /// All usable profiles in the JSON as recipes. Utility profiles (flush, descale) are left out.
    static func recipes(from object: Any) -> [Recipe] {
        let list: [Any]
        if let wrapper = object as? [String: Any], let profiles = wrapper["profiles"] as? [Any] {
            list = profiles
        } else if let single = object as? [String: Any] {
            list = [single]
        } else {
            list = object as? [Any] ?? []
        }
        return list.prefix(200).compactMap { ($0 as? [String: Any]).flatMap(recipe(from:)) }
    }

    /// One profile as an espresso recipe, or nil if it has no phases or is a utility profile.
    static func recipe(from profile: [String: Any]) -> Recipe? {
        guard (profile["utility"] as? Bool) != true,
              let rawPhases = profile["phases"] as? [Any], !rawPhases.isEmpty,
              var label = (profile["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else { return nil }
        if label.hasPrefix(labelPrefix) { label.removeFirst(labelPrefix.count) }
        let phases = rawPhases.prefix(InputLimits.maxSteps).compactMap { ($0 as? [String: Any]).map(Phase.init) }
        guard !phases.isEmpty else { return nil }

        let dose = number(profile["dose"]).map { $0.clamped(5, 40) } ?? 18
        let yield = phases.compactMap(\.volumetricTarget).last.map { $0.clamped(5, 200) } ?? (dose * 2).rounded()
        let preinfusion = phases.filter(\.isPreinfusion).reduce(0) { $0 + $1.duration }
        let total = phases.reduce(0) { $0 + $1.duration }
        // With a target weight the durations are only safety caps, so the shot usually ends well before their sum.
        let hasWeightTarget = phases.contains { $0.volumetricTarget != nil }
        let time = (hasWeightTarget ? min(total, preinfusion + 25) : total).clamped(15, 120).rounded()
        let pressure = phases.filter { !$0.isPreinfusion }.compactMap(\.pressure).max()
            ?? phases.compactMap(\.pressure).max() ?? 9

        var steps: [RecipeStep] = []
        if preinfusion >= 1 {
            steps.append(RecipeStep(kind: .preinfuse, time: 0, target: nil, valve: nil,
                                    note: phases.filter(\.isPreinfusion).map(\.summary).joined(separator: ", ")))
        }
        steps.append(RecipeStep(kind: .extract, time: preinfusion >= 1 ? preinfusion.rounded() : 0, target: yield, valve: nil,
                                note: phases.filter { !$0.isPreinfusion }.map(\.summary).joined(separator: ", ")))

        let id = (profile["id"] as? String).map { $0.sanitized(maxLength: 60) }.flatMap { $0.isEmpty ? nil : $0 }
            ?? slug(label)
        let description = (profile["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let blank = RecipeLibrary.blankRecipe()
        let recipe = Recipe(
            id: recipeIDPrefix + id,
            name: label,
            author: "GaggiMate",
            method: .espresso,
            summary: description.isEmpty ? "Imported from a GaggiMate profile." : description,
            tasteNotes: "",
            taste: blank.taste,
            dose: dose,
            water: yield,
            temperature: number(profile["temperature"]).map { $0.clamped(80, 100) } ?? 93,
            grind: "",
            targetTime: time,
            flowMin: 1,
            flowMax: 2.5,
            steps: steps,
            tips: phases.enumerated().map { "Phase \($0.offset + 1): \($0.element.summary)" },
            isCustom: true,
            pressure: pressure.clamped(1, 12)
        )
        return recipe.validated()
    }

    /// One phase of a profile, reduced to what BrewLog shows.
    private struct Phase {
        var name: String
        var isPreinfusion: Bool
        var duration: Double
        /// Target or limit pressure in bar.
        var pressure: Double?
        /// Target pump flow in ml/s.
        var flow: Double?
        /// Pump power in percent (simple profiles without pressure control).
        var power: Double?
        var volumetricTarget: Double?

        init(_ raw: [String: Any]) {
            name = ((raw["name"] as? String) ?? "").sanitized(maxLength: 40)
            isPreinfusion = (raw["phase"] as? String) == "preinfusion"
            duration = (GaggiMateProfile.number(raw["duration"]) ?? 0).clamped(0, 300)
            if let pump = raw["pump"] as? [String: Any] {
                let target = pump["target"] as? String
                let pressure = GaggiMateProfile.number(pump["pressure"]).map { $0.clamped(0, 15) }
                let flow = GaggiMateProfile.number(pump["flow"]).map { $0.clamped(0, 15) }
                if target == "flow" {
                    self.flow = flow
                    // In a flow phase the pressure is a limit (0 means none).
                    self.pressure = pressure.flatMap { $0 > 0 ? $0 : nil }
                } else {
                    self.pressure = pressure
                }
            } else if let power = GaggiMateProfile.number(raw["pump"]) {
                self.power = power.clamped(0, 100)
            }
            let targets = raw["targets"] as? [[String: Any]] ?? []
            volumetricTarget = targets.first { ($0["type"] as? String) == "volumetric" }
                .flatMap { GaggiMateProfile.number($0["value"]) }
                .flatMap { $0 > 0 ? $0 : nil }
        }

        /// E.g. "Bloom · 8 s · 3 bar" or "Extraction · 30 s · 2 ml/s, max 9 bar · to 36 g".
        var summary: String {
            var parts = [name.isEmpty ? (isPreinfusion ? "Pre-infusion" : "Brew") : name]
            if duration > 0 { parts.append("\(Self.format(duration)) s") }
            if let flow {
                parts.append("\(Self.format(flow)) ml/s" + (pressure.map { ", max \(Self.format($0)) bar" } ?? ""))
            } else if let pressure {
                parts.append("\(Self.format(pressure)) bar")
            } else if let power {
                parts.append("pump \(Self.format(power)) %")
            }
            if let volumetricTarget { parts.append("to \(Self.format(volumetricTarget)) g") }
            return parts.joined(separator: " · ")
        }

        static func format(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        }
    }

    fileprivate static func number(_ value: Any?) -> Double? {
        let double = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        return double.flatMap { $0.isFinite ? $0 : nil }
    }

    /// A stable id from the name, so importing the same file again updates the recipe instead of adding a copy.
    private static func slug(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let slug = text.lowercased().unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        return slug.isEmpty ? UUID().uuidString : String(slug.prefix(60))
    }
}
