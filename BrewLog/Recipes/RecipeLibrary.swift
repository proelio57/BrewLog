import Foundation

/// The built-in recipes from the shared `recipes.json` (the same file is used by the Android and web apps),
/// kept up to date by the online recipe list (see `RecipeFeed`).
enum RecipeLibrary {
    static var presets: [Recipe] { RecipeFeed.shared.presets }

    static func preset(id: String) -> Recipe? { presets.first { $0.id == id } }

    /// Starting point for the custom recipe editor.
    static func blankRecipe() -> Recipe {
        Recipe(
            id: "custom-\(UUID().uuidString)",
            name: "My Recipe",
            author: "Me",
            method: .v60,
            summary: "",
            tasteNotes: "",
            taste: TasteProfile(acidity: 3, sweetness: 3, body: 3, clarity: 3),
            dose: 15,
            water: 250,
            temperature: 94,
            grind: "Medium-fine",
            targetTime: 180,
            flowMin: 3,
            flowMax: 8,
            steps: [
                RecipeStep(kind: .bloom, time: 0, target: 45, note: nil),
                RecipeStep(kind: .pour, time: 45, target: 150, note: nil),
                RecipeStep(kind: .pour, time: 75, target: 250, note: nil),
            ],
            tips: [],
            isCustom: true
        )
    }
}

enum PaperShape: String, Hashable {
    case cone, flat, chemex
}

/// Quick-add equipment presets.
struct EquipmentPreset: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let type: EquipmentType
    var method: BrewMethod? = nil
    var flow: FilterFlow? = nil
    var idealRoast: RoastLevel? = nil
    var grinder: GrinderSpec? = nil
    var notes: String = ""
    /// Paper shape a brewer takes / a filter has (used to show compatible papers first).
    var shape: PaperShape? = nil

    func makeEquipment() -> Equipment {
        Equipment(name: name, type: type, method: method, filterFlow: flow, idealRoast: idealRoast,
                  grinder: grinder ?? (type == .grinder ? GrinderSpec() : nil), notes: notes)
    }

    static func grinder(_ name: String, _ unit: GrindUnit, step: Double, adjust: Double,
                        range: String = "", notes: String = "") -> EquipmentPreset {
        EquipmentPreset(name: name, type: .grinder,
                        grinder: GrinderSpec(unit: unit, step: step, adjustStep: adjust, finerIsLower: true, rangeNote: range),
                        notes: notes)
    }

    /// Grinder scales. Ranges are typical starting points only. Every grinder is different, so they're editable.
    static let grinders: [EquipmentPreset] = [
        grinder("Comandante C40", .clicks, step: 1, adjust: 2, range: "20–30 clicks",
                notes: "Clicks counted from fully closed. About 30 µm per click."),
        grinder("1Zpresso K-Ultra", .numbers, step: 0.1, adjust: 0.2,
                notes: "Read the dial as rotation.number, e.g. 7.5."),
        grinder("1Zpresso ZP6 Special", .numbers, step: 0.1, adjust: 0.2,
                notes: "Read the dial as rotation.number, e.g. 4.5."),
        grinder("1Zpresso J-Max", .clicks, step: 1, adjust: 5,
                notes: "Very fine steps, so adjust in bigger jumps for filter."),
        grinder("Timemore C3", .clicks, step: 1, adjust: 1, range: "about 14–20 clicks"),
        grinder("Kingrinder K6", .clicks, step: 1, adjust: 5,
                notes: "Fine steps, so adjust in bigger jumps for filter."),
        grinder("Fellow Ode Gen 2", .dial, step: 1, adjust: 1,
                notes: "Dial 1–11 in steps of 1/3. Track whole numbers or enter thirds as decimals."),
        grinder("Baratza Encore ESP", .numbers, step: 1, adjust: 2),
        grinder("Niche Zero", .dial, step: 1, adjust: 3),
        grinder("Wilfa Uniform", .numbers, step: 1, adjust: 1),
        grinder("Lagom P64", .dial, step: 0.1, adjust: 0.2),
        grinder("Mazzer Philos", .dial, step: 1, adjust: 2),
        grinder("DF64 / DF83", .dial, step: 1, adjust: 3),
    ]

    static let filters: [EquipmentPreset] = [
        // CAFEC roast-specific papers are named after their recommended brew temperature.
        .init(name: "CAFEC T-90 (Medium-Dark Roast)", type: .filter, flow: .medium, idealRoast: .mediumDark,
              notes: "Two-sided crepe, smooth and steady flow, designed for 90 °C. Balanced and repeatable. Also popular for light roasts.", shape: .cone),
        .init(name: "CAFEC T-92 (Light Roast)", type: .filter, flow: .fast, idealRoast: .light,
              notes: "Low density with a deep crepe, designed for 92 °C. Clean cup with strong aroma.", shape: .cone),
        .init(name: "CAFEC T-83 (Dark Roast)", type: .filter, flow: .medium, idealRoast: .dark,
              notes: "0.22 mm, medium density, designed for 83 °C. Fast at first, then slows down. Brings body and sweetness.", shape: .cone),
        .init(name: "CAFEC Abaca+", type: .filter, flow: .fast,
              notes: "Abaca fibre blend. Fast flow, great clarity, an all-rounder.", shape: .cone),
        .init(name: "CAFEC Abaca", type: .filter, flow: .fast,
              notes: "The original abaca paper. Fast and clean.", shape: .cone),
        .init(name: "Hario V60 standard paper", type: .filter, flow: .medium,
              notes: "The standard white V60 paper. Medium flow. Rinse well.", shape: .cone),
        .init(name: "Hario V60 tabbed paper (Japan)", type: .filter, flow: .fast,
              notes: "Japanese-made tabbed paper. Faster than the standard paper.", shape: .cone),
        .init(name: "Hario V60 natural paper (unbleached)", type: .filter, flow: .medium,
              notes: "Unbleached brown paper. Rinse very well to avoid a papery taste.", shape: .cone),
        .init(name: "Sibarist FAST Cone", type: .filter, flow: .fast,
              notes: "Very fast specialty paper. Lets you grind finer without stalling.", shape: .cone),
        .init(name: "Origami cone paper", type: .filter, flow: .fast, shape: .cone),
        .init(name: "Kalita Wave 185 paper", type: .filter, flow: .medium,
              notes: "Flat-bottom wave paper for Kalita, Orea and similar drippers.", shape: .flat),
        .init(name: "Sibarist FAST Flat", type: .filter, flow: .fast,
              notes: "Flat-bottom version for Orea, April and Kalita.", shape: .flat),
        .init(name: "Chemex bonded paper", type: .filter, flow: .slow,
              notes: "Thick paper, very clean cup with lighter body. Slow drawdown, so grind coarser.", shape: .chemex),
    ]

    static let all: [EquipmentPreset] = filters + grinders + [
        // Brewers
        .init(name: "Hario V60 02", type: .brewer, method: .v60, shape: .cone),
        .init(name: "Hario V60 01", type: .brewer, method: .v60, shape: .cone),
        .init(name: "Hario Switch 02", type: .brewer, method: .hybrid, shape: .cone),
        .init(name: "Hario Switch 03", type: .brewer, method: .hybrid, shape: .cone),
        .init(name: "Kalita Wave 185", type: .brewer, method: .kalita, shape: .flat),
        .init(name: "Origami Dripper M", type: .brewer, method: .v60, shape: .cone),
        .init(name: "Orea v4", type: .brewer, method: .kalita, shape: .flat),
        .init(name: "April Brewer", type: .brewer, method: .kalita, shape: .flat),
        .init(name: "Chemex 6-cup", type: .brewer, method: .universal, shape: .chemex),
        .init(name: "Clever Dripper", type: .brewer, method: .hybrid, shape: .cone),
        // Kettles
        .init(name: "Fellow Stagg EKG", type: .kettle),
        .init(name: "Hario Buono", type: .kettle),
        .init(name: "Brewista Artisan", type: .kettle),
        // Scales
        .init(name: "Bookoo Themis Mini", type: .scale),
        // Water
        .init(name: "Third Wave Water (light roast)", type: .water),
        .init(name: "Filtered tap water", type: .water),
    ]
}
