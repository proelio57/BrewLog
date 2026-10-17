import Foundation
import SwiftData

// MARK: - Beans

enum RoastLevel: String, Codable, CaseIterable, Identifiable {
    case light, mediumLight, medium, mediumDark, dark
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .mediumLight: return "Medium-light"
        case .medium: return "Medium"
        case .mediumDark: return "Medium-dark"
        case .dark: return "Dark"
        }
    }
    /// 0 = lightest, 4 = darkest
    var index: Int { RoastLevel.allCases.firstIndex(of: self) ?? 0 }
}

enum ProcessMethod: String, Codable, CaseIterable, Identifiable {
    case washed, natural, honey, anaerobic, other
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

@Model
final class Bean {
    var id: UUID = UUID()
    var name: String = ""
    var roaster: String = ""
    var origin: String = ""
    var varietal: String = ""
    var processRaw: String = ProcessMethod.washed.rawValue
    var roastLevelRaw: String = RoastLevel.light.rawValue
    var roastDate: Date?
    var tastingNotes: String = ""
    var notes: String = ""
    var bagWeight: Double = 250
    var remaining: Double = 250
    var isArchived: Bool = false
    var createdAt: Date = Date()
    /// Where an imported bean came from, e.g. "beanconqueror:<uuid>". Prevents duplicates on re-import.
    var externalID: String?

    @Relationship(deleteRule: .nullify, inverse: \Brew.bean)
    var brews: [Brew]? = []

    init(name: String = "", roaster: String = "") {
        self.name = name
        self.roaster = roaster
    }

    var process: ProcessMethod {
        get { ProcessMethod(rawValue: processRaw) ?? .other }
        set { processRaw = newValue.rawValue }
    }

    var roastLevel: RoastLevel {
        get { RoastLevel(rawValue: roastLevelRaw) ?? .light }
        set { roastLevelRaw = newValue.rawValue }
    }

    var daysOffRoast: Int? {
        guard let roastDate else { return nil }
        return Calendar.current.dateComponents([.day], from: roastDate, to: Date()).day
    }

    var displayName: String { roaster.isEmpty ? name : "\(name) · \(roaster)" }
}

// MARK: - Equipment

enum EquipmentType: String, Codable, CaseIterable, Identifiable {
    case brewer, grinder, kettle, filter, scale, water
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .brewer: return "Brewers"
        case .grinder: return "Grinders"
        case .kettle: return "Kettles"
        case .filter: return "Filters"
        case .scale: return "Scales"
        case .water: return "Water"
        }
    }
    var symbol: String {
        switch self {
        case .brewer: return "cup.and.saucer.fill"
        case .grinder: return "gearshape.2.fill"
        case .kettle: return "flame.fill"
        case .filter: return "doc.fill"
        case .scale: return "scalemass.fill"
        case .water: return "drop.triangle.fill"
        }
    }
}

/// How fast water passes through a filter paper. This has a big effect on drawdown time.
enum FilterFlow: String, Codable, CaseIterable, Identifiable {
    case fast, medium, slow
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

/// How a grinder's setting is expressed.
enum GrindUnit: String, Codable, CaseIterable, Identifiable {
    case clicks, numbers, dial, microns
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .clicks: return "Clicks"
        case .numbers: return "Numbers"
        case .dial: return "Dial"
        case .microns: return "Microns"
        }
    }
    /// Suffix shown after the value, e.g. "24 clicks"
    var suffix: String {
        switch self {
        case .clicks: return "clicks"
        case .numbers, .dial: return ""
        case .microns: return "µm"
        }
    }
}

/// Description of a grinder's adjustment scale, so suggestions can be concrete ("try 22 clicks").
struct GrinderSpec: Hashable, Codable {
    var unit: GrindUnit = .clicks
    /// Smallest increment, e.g. 1 click or 0.1 on a dial.
    var step: Double = 1
    /// What a sensible small adjustment is for this grinder.
    var adjustStep: Double = 2
    /// Most grinders get finer as the number goes down.
    var finerIsLower: Bool = true
    /// Typical pour-over range, e.g. "20–30 clicks" (informational).
    var rangeNote: String = ""
    /// Sensible starting grind for filter coffee (presets), see `startingValue`.
    var defaultGrind: Double? = nil

    func format(_ value: Double) -> String {
        let decimals = step < 1 ? (step < 0.1 ? 2 : 1) : 0
        let number = String(format: "%.\(decimals)f", value)
        return unit.suffix.isEmpty ? number : "\(number) \(unit.suffix)"
    }

    func formatDelta(_ delta: Double) -> String {
        let decimals = step < 1 ? (step < 0.1 ? 2 : 1) : 0
        let number = String(format: "%.\(decimals)f", abs(delta))
        switch unit {
        case .clicks: return "\(number) click\(abs(delta) == 1 ? "" : "s")"
        case .microns: return "\(number) µm"
        case .numbers, .dial: return number
        }
    }

    /// Moves `value` by `steps` adjustment-steps in the finer (negative) or coarser (positive) direction.
    func adjusted(_ value: Double, coarser: Bool, multiplier: Double = 1) -> Double {
        let delta = adjustStep * multiplier
        let signed = (coarser == finerIsLower) ? delta : -delta
        let raw = value + signed
        let snapped = (raw / step).rounded() * step
        return max(0, snapped)
    }
}

@Model
final class Equipment {
    var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = EquipmentType.brewer.rawValue
    var notes: String = ""
    var methodRaw: String?
    /// Filters only: flow speed of the paper.
    var filterFlowRaw: String?
    /// Filters only: roast level the paper is designed for (e.g. CAFEC roast-specific papers).
    var idealRoastRaw: String?
    /// Grinders only: adjustment scale.
    var grindUnitRaw: String = GrindUnit.clicks.rawValue
    var grindStep: Double = 1
    var grindAdjustStep: Double = 2
    var finerIsLower: Bool = true
    var grindRangeNote: String = ""
    var grindDefault: Double?
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    /// Where imported gear came from, e.g. "beanconqueror:<uuid>".
    var externalID: String?

    init(name: String, type: EquipmentType, method: BrewMethod? = nil,
         filterFlow: FilterFlow? = nil, idealRoast: RoastLevel? = nil,
         grinder: GrinderSpec? = nil, notes: String = "") {
        self.name = name
        self.typeRaw = type.rawValue
        self.methodRaw = method?.rawValue
        self.filterFlowRaw = filterFlow?.rawValue
        self.idealRoastRaw = idealRoast?.rawValue
        self.notes = notes
        if let grinder { self.grinderSpec = grinder }
    }

    var grinderSpec: GrinderSpec {
        get {
            GrinderSpec(unit: GrindUnit(rawValue: grindUnitRaw) ?? .clicks,
                        step: grindStep > 0 ? grindStep : 1,
                        adjustStep: grindAdjustStep > 0 ? grindAdjustStep : 1,
                        finerIsLower: finerIsLower,
                        rangeNote: grindRangeNote,
                        defaultGrind: grindDefault)
        }
        set {
            grindUnitRaw = newValue.unit.rawValue
            grindStep = newValue.step
            grindAdjustStep = newValue.adjustStep
            finerIsLower = newValue.finerIsLower
            grindRangeNote = newValue.rangeNote
            grindDefault = newValue.defaultGrind
        }
    }

    var type: EquipmentType {
        get { EquipmentType(rawValue: typeRaw) ?? .brewer }
        set { typeRaw = newValue.rawValue }
    }

    var method: BrewMethod? {
        get { methodRaw.flatMap(BrewMethod.init(rawValue:)) }
        set { methodRaw = newValue?.rawValue }
    }

    var filterFlow: FilterFlow? {
        get { filterFlowRaw.flatMap(FilterFlow.init(rawValue:)) }
        set { filterFlowRaw = newValue?.rawValue }
    }

    var idealRoast: RoastLevel? {
        get { idealRoastRaw.flatMap(RoastLevel.init(rawValue:)) }
        set { idealRoastRaw = newValue?.rawValue }
    }

    var subtitle: String {
        switch type {
        case .filter:
            var parts: [String] = []
            if let filterFlow { parts.append("\(filterFlow.displayName) flow") }
            if let idealRoast { parts.append("for \(idealRoast.displayName.lowercased()) roasts") }
            return parts.joined(separator: " · ")
        case .grinder:
            let spec = grinderSpec
            var text = "Adjust in steps of \(spec.formatDelta(spec.adjustStep))"
            if !spec.rangeNote.isEmpty { text += " · pour-over \(spec.rangeNote)" }
            return text
        case .brewer:
            return method?.displayName ?? ""
        default:
            return notes
        }
    }
}

// MARK: - Brews

struct WeightSample: Codable, Hashable {
    /// Seconds since brew start.
    var t: Double
    /// Grams on the scale.
    var w: Double
}

enum TasteFeedback: String, Codable, CaseIterable, Identifiable {
    case perfect, sour, bitter, weak, strong, astringent, flat
    var id: String { rawValue }

    var title: String {
        switch self {
        case .perfect: return "Perfect"
        case .sour: return "Too sour"
        case .bitter: return "Too bitter"
        case .weak: return "Too weak"
        case .strong: return "Too strong"
        case .astringent: return "Dry / astringent"
        case .flat: return "Flat / dull"
        }
    }

    var subtitle: String {
        switch self {
        case .perfect: return "Sweet, balanced, would brew again"
        case .sour: return "Sharp, salty, thin, short finish"
        case .bitter: return "Harsh, burnt, lingering bitterness"
        case .weak: return "Watery, lacking flavour"
        case .strong: return "Heavy, intense, muddy"
        case .astringent: return "Drying, rough, mouth-puckering"
        case .flat: return "Lifeless, hollow, no sparkle"
        }
    }

    var emoji: String {
        switch self {
        case .perfect: return "checkmark.seal.fill"
        case .sour: return "drop.triangle"
        case .bitter: return "flame"
        case .weak: return "drop"
        case .strong: return "bolt.fill"
        case .astringent: return "leaf"
        case .flat: return "minus.circle"
        }
    }
}

@Model
final class Brew {
    var id: UUID = UUID()
    var date: Date = Date()
    var recipeID: String = ""
    var recipeName: String = ""
    var recipeData: Data?
    var dose: Double = 0
    var targetWater: Double = 0
    var finalWeight: Double = 0
    var totalTime: Double = 0
    var waterTemp: Double = 0
    /// Free-text grind (used when no grinder is selected).
    var grindSetting: String = ""
    /// Numeric grind setting on the selected grinder's scale.
    var grindValue: Double?
    /// Grind suggested by the analysis after reviewing this brew. Pre-filled next time for the same bean and grinder.
    var suggestedGrind: Double?
    var brewerID: UUID?
    var brewerName: String = ""
    var grinderID: UUID?
    var grinderName: String = ""
    /// Snapshot of the grinder scale, so formatting and analysis survive deleting the grinder.
    var grinderSpecData: Data?
    var filterID: UUID?
    var filterName: String = ""
    /// Snapshot of the filter's properties so the analysis still works if the filter gets deleted.
    var filterFlowRaw: String?
    var filterIdealRoastRaw: String?
    var bean: Bean?
    var samplesData: Data?
    /// Espresso: pressure/temperature/flow from the machine, `[MachineSample]` as JSON.
    var machineSamplesData: Data?
    var usedScale: Bool = false
    var rating: Int = 0
    var feedbackRaw: String = ""
    var notes: String = ""
    /// Where an imported brew came from, e.g. "beanconqueror:<uuid>". Prevents duplicates on re-import.
    var externalID: String?

    init() {}

    var recipe: Recipe? {
        get { recipeData.flatMap { try? JSONDecoder().decode(Recipe.self, from: $0) } }
        set { recipeData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var samples: [WeightSample] {
        get { samplesData.flatMap { try? JSONDecoder().decode([WeightSample].self, from: $0) } ?? [] }
        set { samplesData = try? JSONEncoder().encode(newValue) }
    }

    var machineSamples: [MachineSample] {
        get { machineSamplesData.flatMap { try? JSONDecoder().decode([MachineSample].self, from: $0) } ?? [] }
        set { machineSamplesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var feedback: Set<TasteFeedback> {
        get { Set(feedbackRaw.split(separator: ",").compactMap { TasteFeedback(rawValue: String($0)) }) }
        set { feedbackRaw = newValue.map(\.rawValue).sorted().joined(separator: ",") }
    }

    var filterFlow: FilterFlow? { filterFlowRaw.flatMap(FilterFlow.init(rawValue:)) }
    var filterIdealRoast: RoastLevel? { filterIdealRoastRaw.flatMap(RoastLevel.init(rawValue:)) }

    func setFilter(_ filter: Equipment?) {
        filterID = filter?.id
        filterName = filter?.name ?? ""
        filterFlowRaw = filter?.filterFlowRaw
        filterIdealRoastRaw = filter?.idealRoastRaw
    }

    func setGrinder(_ grinder: Equipment?) {
        grinderID = grinder?.id
        grinderName = grinder?.name ?? ""
        grinderSpec = grinder?.grinderSpec
    }

    var grinderSpec: GrinderSpec? {
        get { grinderSpecData.flatMap { try? JSONDecoder().decode(GrinderSpec.self, from: $0) } }
        set { grinderSpecData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Human readable grind, e.g. "24 clicks" or the free text.
    var grindDisplay: String {
        if let grindValue {
            return (grinderSpec ?? GrinderSpec()).format(grindValue)
        }
        return grindSetting
    }

    var ratio: Double { dose > 0 ? finalWeight / dose : 0 }
    var isReviewed: Bool { rating > 0 || !feedbackRaw.isEmpty }
}

// MARK: - Custom recipes

@Model
final class SavedRecipe {
    var id: String = UUID().uuidString
    var data: Data = Data()
    var createdAt: Date = Date()

    init(recipe: Recipe) {
        self.id = recipe.id
        self.data = (try? JSONEncoder().encode(recipe)) ?? Data()
    }

    /// Decoded defensively: stored data is always re-validated before use.
    var recipe: Recipe? {
        get { (try? JSONDecoder().decode(Recipe.self, from: data))?.validated() }
        set { if let newValue, let d = try? JSONEncoder().encode(newValue.validated()) { data = d } }
    }
}
