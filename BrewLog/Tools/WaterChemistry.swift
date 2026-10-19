import Foundation

/// Brewing water made from distilled / reverse-osmosis water and minerals.
///
/// Hardness (GH) and alkalinity (KH) are in mg/L (ppm) as CaCO3, the unit most water recipes use.
/// The minerals: Epsom salt (MgSO4·7H2O) and calcium chloride (CaCl2·2H2O) for hardness, baking soda (NaHCO3) for
/// the buffer. The concentrates follow Barista Hustle: 1000 ppm each, so 1 g of concentrate per litre adds 1 ppm.
enum WaterChemistry {
    /// Milligrams of mineral per litre for 1 mg/L as CaCO3 (molar mass ratios; bicarbonate counts half).
    static let epsomPerPPM = 246.47 / 100.09
    static let calciumChloridePerPPM = 147.01 / 100.09
    static let bakingSodaPerPPM = 2 * 84.007 / 100.09

    /// Grams of mineral in one litre of 1000 ppm concentrate.
    static let epsomConcentrate = epsomPerPPM
    static let calciumChlorideConcentrate = calciumChloridePerPPM
    static let bakingSodaConcentrate = bakingSodaPerPPM

    enum Limits {
        static let maxPPM = 500.0
        static let maxLitres = 50.0
    }

    struct Profile: Identifiable, Equatable, Hashable {
        var id: String { name }
        var name: String
        var hardness: Double
        var alkalinity: Double
        var note: String = ""
    }

    /// Well-known recipes (Barista Hustle concentrate amounts, rounded).
    static let presets: [Profile] = [
        Profile(name: "SCA standard", hardness: 68, alkalinity: 40,
                note: "The SCA target for brewing water: 68 ppm hardness, 40 ppm alkalinity."),
        Profile(name: "Rao", hardness: 76, alkalinity: 50,
                note: "Close to Scott Rao's recommendation. A bit more buffer, rounder and less bright."),
        Profile(name: "Barista Hustle", hardness: 81, alkalinity: 40,
                note: "Barista Hustle's original recipe. Lots of hardness for sweetness and body."),
        Profile(name: "Hendon", hardness: 100, alkalinity: 31,
                note: "Centre of Hendon's and Colonna-Dashwood's ideal zone. High hardness, low buffer, very bright."),
        Profile(name: "World of Coffee Budapest", hardness: 51, alkalinity: 40,
                note: "Competition water. Balanced and clean."),
        Profile(name: "Melbourne", hardness: 24, alkalinity: 12,
                note: "Very soft, like Melbourne tap water. Clear and delicate, great for light roasts."),
    ]

    /// How much of the hardness comes from magnesium (Epsom salt) vs calcium (calcium chloride).
    /// Magnesium tends to taste brighter, calcium rounder. Calcium also scales machines faster.
    struct Recipe: Equatable {
        var hardness: Double
        var alkalinity: Double
        var litres: Double
        /// 0 = only calcium chloride, 1 = only Epsom salt.
        var magnesiumShare: Double = 1

        private var h: Double { hardness.clamped(0, Limits.maxPPM) }
        private var a: Double { alkalinity.clamped(0, Limits.maxPPM) }
        private var l: Double { litres.clamped(0, Limits.maxLitres) }
        private var mg: Double { magnesiumShare.clamped(0, 1) }

        /// Grams of dry mineral to dissolve directly in `litres` of water.
        var epsomGrams: Double { h * mg * epsomPerPPM * l / 1000 }
        var calciumChlorideGrams: Double { h * (1 - mg) * calciumChloridePerPPM * l / 1000 }
        var bakingSodaGrams: Double { a * bakingSodaPerPPM * l / 1000 }

        /// Grams of each 1000 ppm concentrate, topped up with distilled water to `litres`.
        var hardnessConcentrateGrams: Double { h * mg * l }
        var calciumConcentrateGrams: Double { h * (1 - mg) * l }
        var bufferConcentrateGrams: Double { a * l }

        /// Distilled water to add to the concentrates (1 g ≈ 1 ml).
        var distilledGrams: Double {
            max(l * 1000 - hardnessConcentrateGrams - calciumConcentrateGrams - bufferConcentrateGrams, 0)
        }
    }

    /// One-line summary, e.g. "GH 68 · KH 40 ppm".
    static func summary(hardness: Double, alkalinity: Double) -> String {
        "GH \(Int(hardness.rounded())) · KH \(Int(alkalinity.rounded())) ppm"
    }

    /// What the water does to the cup, from the hardness and the buffer.
    static func character(hardness: Double, alkalinity: Double) -> String {
        if hardness <= 0 && alkalinity <= 0 { return "Pure water: flat, sour coffee. Add minerals." }
        var parts: [String] = []
        if alkalinity < 20 { parts.append("Low buffer: bright, more acidity.") }
        else if alkalinity > 60 { parts.append("High buffer: mutes acidity, can taste chalky.") }
        else { parts.append("Moderate buffer: balanced acidity.") }
        if hardness < 30 { parts.append("Soft: clean but less sweetness and body.") }
        else if hardness > 120 { parts.append("Very hard: heavy, can over-extract and scales machines.") }
        else { parts.append("Hardness extracts sweetness well.") }
        return parts.joined(separator: " ")
    }
}
