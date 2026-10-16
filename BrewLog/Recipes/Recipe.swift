import Foundation

/// Brewing method a recipe was designed for.
enum BrewMethod: String, Codable, CaseIterable, Identifiable {
    case v60
    case hybrid = "switch"
    case kalita
    case universal
    case espresso

    var id: String { rawValue }

    var isEspresso: Bool { self == .espresso }

    var displayName: String {
        switch self {
        case .v60: return "V60"
        case .hybrid: return "Hario Switch"
        case .kalita: return "Flat bottom"
        case .universal: return "Any pour-over"
        case .espresso: return "Espresso"
        }
    }

    var symbol: String {
        switch self {
        case .v60: return "cone"
        case .hybrid: return "switch.2"
        case .kalita: return "cylinder"
        case .universal: return "drop"
        case .espresso: return "cup.and.saucer.fill"
        }
    }
}

/// The kind of action a recipe step asks for.
enum StepKind: String, Codable, CaseIterable, Identifiable {
    case bloom
    case pour
    case swirl
    case stir
    case closeValve
    case openValve
    case remove
    /// Espresso: pump on at low pressure until the first drops.
    case preinfuse
    /// Espresso: full extraction up to the target yield in the cup.
    case extract

    var id: String { rawValue }

    /// Steps with a cumulative weight target on the scale.
    var isPour: Bool { self == .bloom || self == .pour || self == .extract }

    var title: String {
        switch self {
        case .bloom: return "Bloom"
        case .pour: return "Pour"
        case .swirl: return "Swirl"
        case .stir: return "Stir"
        case .closeValve: return "Close valve"
        case .openValve: return "Open valve"
        case .remove: return "Remove dripper"
        case .preinfuse: return "Pre-infusion"
        case .extract: return "Extract"
        }
    }

    var symbol: String {
        switch self {
        case .bloom: return "sparkles"
        case .pour: return "drop.fill"
        case .swirl: return "arrow.triangle.2.circlepath"
        case .stir: return "arrow.clockwise"
        case .closeValve: return "lock.fill"
        case .openValve: return "lock.open.fill"
        case .remove: return "arrow.up.circle"
        case .preinfuse: return "drop.halffull"
        case .extract: return "cup.and.saucer.fill"
        }
    }
}

enum ValveState: String, Codable {
    case open
    case closed
}

struct RecipeStep: Codable, Hashable {
    var kind: StepKind
    /// Start time in seconds from brew start.
    var time: Double
    /// Cumulative target weight in grams (pours/blooms only).
    var target: Double?
    /// Optional valve state for immersion/hybrid brewers like the Hario Switch.
    var valve: ValveState?
    var note: String?

    var headline: String {
        if kind.isPour, let target {
            let verb = kind == .bloom ? "Bloom to" : (kind == .extract ? "Extract to" : "Pour to")
            return "\(verb) \(Int(target.rounded())) g"
        }
        return kind.title
    }
}

struct TasteProfile: Codable, Hashable {
    var acidity: Int
    var sweetness: Int
    var body: Int
    var clarity: Int
}

struct Recipe: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var author: String
    var method: BrewMethod
    var summary: String
    /// Plain-language description of how the cup should taste.
    var tasteNotes: String
    var taste: TasteProfile
    var dose: Double
    var water: Double
    var temperature: Double
    var grind: String
    /// Expected total brew time (incl. drawdown) in seconds.
    var targetTime: Double
    /// Healthy average pour rate range in g/s.
    var flowMin: Double
    var flowMax: Double
    var steps: [RecipeStep]
    var tips: [String]
    var isCustom: Bool?
    /// Espresso: peak brew pressure in bar the recipe is designed for (e.g. 9, or 6 for turbo shots).
    var pressure: Double?

    var ratio: Double { dose > 0 ? water / dose : 0 }

    var ratioText: String { String(format: "1:%.1f", ratio) }

    var pourSteps: [RecipeStep] { steps.filter { $0.kind.isPour && $0.target != nil } }

    /// Returns a copy scaled to a new dose. Times stay the same; weights scale with the dose.
    func scaled(toDose newDose: Double) -> Recipe {
        guard dose > 0, newDose > 0, abs(newDose - dose) > 0.01 else { return self }
        let factor = newDose / dose
        var copy = self
        copy.dose = newDose
        copy.water = (water * factor).rounded()
        copy.steps = steps.map { step in
            var s = step
            if let t = step.target { s.target = (t * factor).rounded() }
            return s
        }
        return copy
    }

    /// Expected cumulative weight over time, used to draw the "ideal" line on charts.
    func targetCurve() -> [(time: Double, weight: Double)] {
        var points: [(Double, Double)] = [(0, 0)]
        var previous: Double = 0
        let idealFlow = max((flowMin + flowMax) / 2, 1)
        let pours = steps.enumerated().filter { $0.element.kind.isPour && $0.element.target != nil }
        for (offset, entry) in pours.enumerated() {
            let step = entry.element
            guard let target = step.target else { continue }
            let nextStart = offset + 1 < pours.count ? pours[offset + 1].element.time : targetTime
            var duration = (target - previous) / idealFlow
            duration = min(duration, max(nextStart - step.time - 1, 1))
            points.append((step.time, previous))
            points.append((step.time + duration, target))
            previous = target
        }
        points.append((targetTime, previous))
        return points
    }
}

extension Recipe {
    /// Lenient decoding, so hand-written or shared recipe files only need a name and steps.
    /// Everything else falls back to the defaults of a new recipe. `validated()` cleans up the values afterwards.
    /// (Lives in this file because it needs the synthesized `CodingKeys`.)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let blank = RecipeLibrary.blankRecipe()
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? blank.id
        name = try c.decode(String.self, forKey: .name)
        steps = try c.decode([RecipeStep].self, forKey: .steps)
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        method = (try? c.decodeIfPresent(BrewMethod.self, forKey: .method)) ?? .universal
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        tasteNotes = try c.decodeIfPresent(String.self, forKey: .tasteNotes) ?? ""
        taste = try c.decodeIfPresent(TasteProfile.self, forKey: .taste) ?? blank.taste
        dose = try c.decodeIfPresent(Double.self, forKey: .dose) ?? blank.dose
        water = try c.decodeIfPresent(Double.self, forKey: .water)
            ?? steps.compactMap(\.target).max() ?? blank.water
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? blank.temperature
        grind = try c.decodeIfPresent(String.self, forKey: .grind) ?? ""
        targetTime = try c.decodeIfPresent(Double.self, forKey: .targetTime)
            ?? (steps.map(\.time).max() ?? 0) + 60
        flowMin = try c.decodeIfPresent(Double.self, forKey: .flowMin) ?? blank.flowMin
        flowMax = try c.decodeIfPresent(Double.self, forKey: .flowMax) ?? blank.flowMax
        tips = try c.decodeIfPresent([String].self, forKey: .tips) ?? []
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom)
        pressure = try c.decodeIfPresent(Double.self, forKey: .pressure)
    }
}

extension TimeInterval {
    /// Formats seconds as m:ss.
    var mmss: String {
        let total = Int(self.rounded(.down))
        let sign = total < 0 ? "-" : ""
        let value = abs(total)
        return String(format: "%@%d:%02d", sign, value / 60, value % 60)
    }
}
