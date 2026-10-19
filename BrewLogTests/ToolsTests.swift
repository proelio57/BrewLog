import XCTest
@testable import BrewLog

/// Extraction, water, grind conversion, label scan and voice prompt texts. No UIKit, so these also run on Linux.
final class ToolsTests: XCTestCase {
    // MARK: Extraction

    func testExtractionYield() throws {
        // 15 g coffee, 220 g in the cup at 1.35 % TDS → 19.8 %
        XCTAssertEqual(try XCTUnwrap(Extraction.yield(tds: 1.35, beverage: 220, dose: 15)), 19.8, accuracy: 0.001)
        XCTAssertNil(Extraction.yield(tds: 0, beverage: 220, dose: 15))
        XCTAssertNil(Extraction.yield(tds: 1.3, beverage: 220, dose: 0))
    }

    func testEstimatedBeverage() {
        // Filter: the grounds keep about twice their weight
        XCTAssertEqual(Extraction.estimatedBeverage(finalWeight: 250, dose: 15, espresso: false), 220)
        XCTAssertEqual(Extraction.estimatedBeverage(finalWeight: 36, dose: 18, espresso: true), 36)
        XCTAssertEqual(Extraction.estimatedBeverage(finalWeight: 10, dose: 15, espresso: false), 0)
    }

    func testExtractionVerdicts() throws {
        let ideal = try XCTUnwrap(Extraction.evaluate(tds: 1.35, beverage: 220, dose: 15, espresso: false))
        XCTAssertEqual(ideal.verdict, .ideal)
        XCTAssertEqual(ideal.strength, .ideal)

        let under = try XCTUnwrap(Extraction.evaluate(tds: 1.1, beverage: 220, dose: 15, espresso: false))
        XCTAssertEqual(under.verdict, .under) // 16.1 %
        XCTAssertEqual(under.strength, .weak)
        XCTAssertTrue(under.advice.contains("grind finer"))

        let espresso = try XCTUnwrap(Extraction.evaluate(tds: 10, beverage: 36, dose: 18, espresso: true))
        XCTAssertEqual(espresso.yield, 20, accuracy: 0.001)
        XCTAssertEqual(espresso.verdict, .ideal)
        XCTAssertEqual(espresso.strength, .ideal)

        let over = try XCTUnwrap(Extraction.evaluate(tds: 12.5, beverage: 36, dose: 18, espresso: true))
        XCTAssertEqual(over.verdict, .over)
        XCTAssertEqual(over.strength, .strong)
    }

    // MARK: Water

    func testWaterMineralsMatchBaristaHustleConcentrates() {
        // Barista Hustle: 2.45 g Epsom salt or 1.68 g baking soda in 1 L make 1000 ppm
        XCTAssertEqual(WaterChemistry.epsomConcentrate, 2.45, accuracy: 0.02)
        XCTAssertEqual(WaterChemistry.bakingSodaConcentrate, 1.68, accuracy: 0.01)
        XCTAssertEqual(WaterChemistry.calciumChlorideConcentrate, 1.47, accuracy: 0.01)
    }

    func testWaterRecipe() {
        let sca = WaterChemistry.Recipe(hardness: 68, alkalinity: 40, litres: 4)
        XCTAssertEqual(sca.epsomGrams, 68 * 2.4625 * 4 / 1000, accuracy: 0.001) // ≈ 0.670 g
        XCTAssertEqual(sca.calciumChlorideGrams, 0)
        XCTAssertEqual(sca.bakingSodaGrams, 40 * 1.6786 * 4 / 1000, accuracy: 0.001) // ≈ 0.269 g
        XCTAssertEqual(sca.hardnessConcentrateGrams, 272)
        XCTAssertEqual(sca.bufferConcentrateGrams, 160)
        XCTAssertEqual(sca.distilledGrams, 4000 - 272 - 160)

        let mixed = WaterChemistry.Recipe(hardness: 100, alkalinity: 0, litres: 1, magnesiumShare: 0.5)
        XCTAssertEqual(mixed.epsomGrams, 50 * WaterChemistry.epsomPerPPM / 1000, accuracy: 0.0001)
        XCTAssertEqual(mixed.calciumChlorideGrams, 50 * WaterChemistry.calciumChloridePerPPM / 1000, accuracy: 0.0001)
        XCTAssertEqual(mixed.hardnessConcentrateGrams + mixed.calciumConcentrateGrams, 100)
    }

    func testWaterInputsAreClamped() {
        let silly = WaterChemistry.Recipe(hardness: 99_999, alkalinity: -5, litres: 1_000, magnesiumShare: 3)
        XCTAssertEqual(silly.hardnessConcentrateGrams, WaterChemistry.Limits.maxPPM * WaterChemistry.Limits.maxLitres)
        XCTAssertEqual(silly.bakingSodaGrams, 0)
        XCTAssertEqual(silly.calciumChlorideGrams, 0)
        XCTAssertGreaterThanOrEqual(silly.distilledGrams, 0)
    }

    func testWaterPresetsAndCharacter() {
        XCTAssertEqual(Set(WaterChemistry.presets.map(\.name)).count, WaterChemistry.presets.count)
        XCTAssertEqual(WaterChemistry.summary(hardness: 68, alkalinity: 40), "GH 68 · KH 40 ppm")
        XCTAssertTrue(WaterChemistry.character(hardness: 0, alkalinity: 0).contains("Add minerals"))
        XCTAssertTrue(WaterChemistry.character(hardness: 100, alkalinity: 10).contains("bright"))
    }

    // MARK: Grind conversion

    private var comandante: GrinderSpec {
        GrinderSpec(unit: .clicks, step: 1, adjustStep: 2, defaultGrind: 24, micronsPerStep: 30)
    }
    private var kUltra: GrinderSpec {
        GrinderSpec(unit: .numbers, step: 0.1, adjustStep: 0.2, defaultGrind: 7.5, micronsPerStep: 20)
    }

    func testConvertsBetweenGrinders() throws {
        // Starting points match each other
        XCTAssertEqual(try XCTUnwrap(GrindConverter.convert(24, from: comandante, to: kUltra)), 7.5, accuracy: 0.0001)
        // 2 clicks finer = 60 µm = 3 steps of 0.1 on the K-Ultra
        XCTAssertEqual(try XCTUnwrap(GrindConverter.convert(22, from: comandante, to: kUltra)), 7.2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(GrindConverter.convert(7.8, from: kUltra, to: comandante)), 26, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(GrindConverter.microns(for: 24, spec: comandante)), 720)
    }

    func testConversionNeedsCalibration() {
        let unknown = GrinderSpec(unit: .dial, step: 1, adjustStep: 1, defaultGrind: 5)
        XCTAssertFalse(GrindConverter.canConvert(unknown))
        XCTAssertNil(GrindConverter.convert(5, from: unknown, to: comandante))
        // Presets are calibrated by name, a grinder's own value wins
        XCTAssertEqual(GrindConverter.calibrated(GrinderSpec(defaultGrind: 24), name: "Comandante C40").micronsPerStep, 30)
        XCTAssertEqual(GrindConverter.calibrated(GrinderSpec(micronsPerStep: 25), name: "Comandante C40").micronsPerStep, 25)
        XCTAssertEqual(GrindConverter.calibrated(GrinderSpec(unit: .microns, step: 10), name: "Lab grinder").micronsPerStep, 10)
        XCTAssertTrue(EquipmentPreset.grinders.contains { $0.grinder.map(GrindConverter.canConvert) == true })
    }

    func testCoarserWhenLowerGrinder() throws {
        var reversed = comandante
        reversed.finerIsLower = false
        XCTAssertEqual(try XCTUnwrap(GrindConverter.convert(22, from: comandante, to: reversed)), 26, accuracy: 0.0001)
    }

    func testRecipeGrindHint() throws {
        XCTAssertEqual(GrindConverter.micronRange(in: "Medium-fine (roughly 600–750 µm, e.g. Comandante 22–25 clicks)"), 600...750)
        XCTAssertEqual(GrindConverter.micronRange(in: "Medium (approx. 750 µm)"), 750...750)
        XCTAssertNil(GrindConverter.micronRange(in: "Fine (espresso). Adjust so the shot takes 25–30 s."))
        XCTAssertEqual(GrindConverter.hint(recipeGrind: "about 600–750 µm", spec: comandante), "≈ 20–25 clicks")
        XCTAssertEqual(GrindConverter.hint(recipeGrind: "approx. 720 µm", spec: kUltra), "≈ 7.5")
        XCTAssertNil(GrindConverter.hint(recipeGrind: "about 600–750 µm", spec: GrinderSpec()))
        // Every built-in pour-over recipe gives a size the hint can use
        let recipes = try JSONDecoder().decode([Recipe].self, from: ToolsTests.recipesJSON())
        for recipe in recipes where !recipe.method.isEspresso && !recipe.id.hasPrefix("template") {
            XCTAssertNotNil(GrindConverter.micronRange(in: recipe.grind), recipe.id)
        }
    }

    /// The shared recipe list from the repository (tests run from the source tree).
    static func recipesJSON() throws -> Data {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent("Shared/recipes.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                let data = try Data(contentsOf: candidate)
                // The file is either a list or {"recipes": [...]}
                if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let list = object["recipes"] {
                    return try JSONSerialization.data(withJSONObject: list)
                }
                return data
            }
        }
        throw XCTSkip("Shared/recipes.json not found")
    }

    // MARK: Label scan

    private let now: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 19; components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private func day(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func testParsesEnglishLabel() {
        let lines: [LabelParser.Line] = [
            .init(text: "Northbound Coffee Roasters", height: 0.04, top: 0.05),
            .init(text: "Gesha Village", height: 0.09, top: 0.2),
            .init(text: "Bench Maji, Ethiopia", height: 0.03, top: 0.32),
            .init(text: "Variety: Gesha 1931", height: 0.02, top: 0.4),
            .init(text: "Process: Natural", height: 0.02, top: 0.44),
            .init(text: "Tasting notes: jasmine, peach, bergamot", height: 0.02, top: 0.5),
            .init(text: "Light roast", height: 0.02, top: 0.55),
            .init(text: "Roasted on 02.10.2026", height: 0.02, top: 0.6),
            .init(text: "Best before 02.10.2027", height: 0.02, top: 0.62),
            .init(text: "Net 250g", height: 0.02, top: 0.7),
        ]
        let result = LabelParser.parse(lines, now: now)
        XCTAssertEqual(result.name, "Gesha Village")
        XCTAssertEqual(result.roaster, "Northbound Coffee Roasters")
        XCTAssertEqual(result.origin, "Bench Maji, Ethiopia")
        XCTAssertEqual(result.varietal, "Geisha")
        XCTAssertEqual(result.process, .natural)
        XCTAssertEqual(result.roastLevel, .light)
        XCTAssertEqual(day(result.roastDate), "2026-10-02")
        XCTAssertEqual(result.bagWeight, 250)
        XCTAssertEqual(result.tastingNotes, "jasmine, peach, bergamot")
        XCTAssertTrue(result.foundFields.contains("roast date"))
    }

    func testParsesGermanLabel() {
        let lines: [LabelParser.Line] = [
            .init(text: "KAFFEERÖSTEREI MÜLLER", height: 0.05, top: 0.02),
            .init(text: "Finca El Paraíso", height: 0.08, top: 0.15),
            .init(text: "Kolumbien · Cauca", height: 0.03, top: 0.3),
            .init(text: "Aufbereitung: anaerob", height: 0.02, top: 0.4),
            .init(text: "Sorte: Castillo, Caturra", height: 0.02, top: 0.45),
            .init(text: "Röstdatum", height: 0.02, top: 0.5),
            .init(text: "14. Oktober 2026", height: 0.02, top: 0.53),
            .init(text: "Filterröstung · 1 kg", height: 0.02, top: 0.6),
            .init(text: "Aromen: Erdbeere, Rum, Kakao", height: 0.02, top: 0.65),
        ]
        let result = LabelParser.parse(lines, now: now)
        XCTAssertEqual(result.name, "Finca El Paraíso")
        XCTAssertEqual(result.roaster, "KAFFEERÖSTEREI MÜLLER")
        XCTAssertEqual(result.origin, "Kolumbien · Cauca")
        XCTAssertEqual(result.process, .anaerobic)
        XCTAssertEqual(result.varietal, "Castillo, Caturra")
        XCTAssertEqual(day(result.roastDate), "2026-10-14")
        XCTAssertEqual(result.roastLevel, .light)
        XCTAssertEqual(result.bagWeight, 1000)
        XCTAssertEqual(result.tastingNotes, "Erdbeere, Rum, Kakao")
    }

    func testIgnoresImplausibleDates() {
        XCTAssertNil(LabelParser.date(in: "12.10.2030", now: now, calendar: Calendar(identifier: .gregorian)))
        XCTAssertNil(LabelParser.date(in: "31.02.2026", now: now, calendar: Calendar(identifier: .gregorian)))
        XCTAssertNil(LabelParser.date(in: "01.01.2020", now: now, calendar: Calendar(identifier: .gregorian)))
        XCTAssertEqual(day(LabelParser.date(in: "2026-09-30", now: now, calendar: Calendar(identifier: .gregorian))), "2026-09-30")
        XCTAssertEqual(day(LabelParser.date(in: "Oct 5, 2026", now: now, calendar: Calendar(identifier: .gregorian))), "2026-10-05")
        // Only a best-before date: no roast date
        XCTAssertNil(LabelParser.parse([.init(text: "MHD 01.10.2026")], now: now).roastDate)
    }

    func testEmptyOrJunkLabel() {
        XCTAssertTrue(LabelParser.parse([], now: now).isEmpty)
        let junk = LabelParser.parse([.init(text: "12345"), .init(text: "  "), .init(text: "www.example.com")], now: now)
        XCTAssertNil(junk.name)
        XCTAssertNil(LabelParser.bagWeight(in: "Altitude 1900 m"))
        XCTAssertNil(LabelParser.bagWeight(in: "20 g per cup... 12000 g"))
        XCTAssertEqual(LabelParser.bagWeight(in: "0,5 kg"), 500)
        // "Colombia" is a varietal only after a varietal label
        XCTAssertNil(LabelParser.varietals(in: "Huila, Colombia"))
        XCTAssertEqual(LabelParser.varietals(in: "Varietal: Colombia"), "Colombia")
        XCTAssertEqual(LabelParser.varietals(in: "Pink Bourbon"), "Pink Bourbon")
    }

    // MARK: Voice prompts

    func testStepAnnouncements() {
        XCTAssertEqual(StepAnnouncement.text(for: RecipeStep(kind: .bloom, time: 0, target: 45, note: nil)), "Bloom to 45 grams.")
        XCTAssertEqual(StepAnnouncement.text(for: RecipeStep(kind: .pour, time: 45, target: 150.4, note: "Slow spiral")),
                       "Pour to 150 grams. Slow spiral.")
        XCTAssertEqual(StepAnnouncement.text(for: RecipeStep(kind: .swirl, time: 90, target: nil, note: nil)), "Swirl gently.")
        XCTAssertEqual(StepAnnouncement.text(for: RecipeStep(kind: .openValve, time: 120, target: nil, note: nil)), "Open the valve.")
        XCTAssertEqual(StepAnnouncement.preview(for: RecipeStep(kind: .pour, time: 75, target: 250, note: "Long note is not read ahead")),
                       "Next, pour to 250 grams.")
        let long = String(repeating: "word ", count: 30)
        XCTAssertEqual(StepAnnouncement.text(for: RecipeStep(kind: .stir, time: 10, target: nil, note: long)), "Stir.")
        XCTAssertEqual(StepAnnouncement.grams(1), "1 gram")
    }

    // MARK: Recipe filter and valve countdown

    private func recipe(_ id: String, _ method: BrewMethod, steps: [RecipeStep] = []) -> Recipe {
        var recipe = RecipeLibrary.blankRecipe()
        recipe.id = id
        recipe.method = method
        if !steps.isEmpty { recipe.steps = steps }
        return recipe
    }

    func testRecipeFilterByBrewer() {
        let v60 = recipe("a", .v60), any = recipe("b", .universal), shot = recipe("c", .espresso), sw = recipe("d", .hybrid)
        XCTAssertTrue(RecipeFilter.matches(v60, method: nil))
        XCTAssertTrue(RecipeFilter.matches(any, method: .v60), "any pour-over fits a V60")
        XCTAssertFalse(RecipeFilter.matches(any, method: .espresso))
        XCTAssertFalse(RecipeFilter.matches(sw, method: .v60))

        let sections = RecipeFilter.sections(custom: [recipe("mine", .hybrid)], presets: [v60, any, shot, sw], method: .hybrid)
        XCTAssertEqual(sections.map(\.title), ["My recipes", "Hario Switch", "Any pour-over"])
        XCTAssertEqual(RecipeFilter.sections(custom: [], presets: [v60, any, shot, sw], method: nil).count, 4)
        XCTAssertEqual(RecipeFilter.methods(in: [v60, any, shot]), [.v60, .espresso])
    }

    func testValveChanges() {
        let switchRecipe = recipe("s", .hybrid, steps: [
            RecipeStep(kind: .bloom, time: 0, target: 60, valve: .open, note: nil),
            RecipeStep(kind: .pour, time: 30, target: 120, valve: .open, note: nil),
            RecipeStep(kind: .pour, time: 75, target: 280, valve: .closed, note: nil),
            RecipeStep(kind: .swirl, time: 90, target: nil, valve: nil, note: nil),
            RecipeStep(kind: .openValve, time: 105, target: nil, valve: nil, note: nil),
        ])
        XCTAssertNil(switchRecipe.valveChange(at: 0), "the starting position isn't a change")
        XCTAssertNil(switchRecipe.valveChange(at: 1))
        XCTAssertEqual(switchRecipe.valveChange(at: 2), .closed)
        XCTAssertNil(switchRecipe.valveChange(at: 3))
        XCTAssertEqual(switchRecipe.valveChange(at: 4), .open)
        XCTAssertNil(switchRecipe.valveChange(at: 9))
        XCTAssertNil(recipe("v", .v60).valveChange(at: 1))
        // Every built-in Switch recipe has at least one valve change to count down to.
        for preset in RecipeLibrary.presets where preset.method == .hybrid {
            XCTAssertTrue(preset.steps.indices.contains { preset.valveChange(at: $0) != nil }, preset.id)
        }
    }

    // MARK: Backup with the new fields

    func testBackupRoundTripsNewFields() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5, 6])
        var backup = BrewLogBackup()
        backup.beans = [.init(id: BackupTests.beanID, name: "Gesha")]
        backup.equipment = [.init(id: "id-water-1", name: "SCA water", type: .water, waterHardness: 68, waterAlkalinity: 40),
                            .init(id: BackupTests.grinderID, name: "C40", type: .grinder,
                                  grinder: GrinderSpec(defaultGrind: 24, micronsPerStep: 30))]
        backup.brews = [.init(id: "brew-1", dose: 15, finalWeight: 250, beanId: BackupTests.beanID,
                              tds: 1.38, beverageWeight: 218, waterId: "id-water-1", waterName: "SCA water")]
        backup.photos = [BackupTests.beanID: jpeg]
        let decoded = try BrewLogBackup.decode(backup.encoded())
        XCTAssertEqual(decoded.photos[BackupTests.beanID], jpeg)
        XCTAssertEqual(decoded.equipment.first?.waterHardness, 68)
        XCTAssertEqual(decoded.equipment.first?.waterAlkalinity, 40)
        XCTAssertEqual(decoded.equipment.last?.grinder.micronsPerStep, 30)
        XCTAssertEqual(decoded.brews.first?.tds, 1.38)
        XCTAssertEqual(decoded.brews.first?.beverageWeight, 218)
        XCTAssertEqual(decoded.brews.first?.waterId, "id-water-1")
        XCTAssertEqual(decoded.brews.first?.waterName, "SCA water")
    }

    func testBackupDropsBadPhotosAndValues() throws {
        let json = """
        {"app": "BrewLog", "format": 1, "data": {"version": 1,
          "beans": [{"id": "b1", "name": "A"}],
          "equipment": [{"id": "w1", "name": "W", "type": "water", "waterHardness": 99999, "waterAlkalinity": "x"}],
          "brews": [{"id": "r1", "tds": -3, "beverageWeight": 0}, {"id": "r2", "tds": 400}]},
         "photos": {"b1": "PHNjcmlwdD4=", "b2": 12, "b3": "/9j/4AAQSkZJRg=="}}
        """
        let backup = try BrewLogBackup.decode(Data(json.utf8))
        XCTAssertNil(backup.photos["b1"]) // not an image
        XCTAssertNil(backup.photos["b2"])
        XCTAssertNotNil(backup.photos["b3"]) // JPEG header
        XCTAssertEqual(backup.equipment.first?.waterHardness, WaterChemistry.Limits.maxPPM)
        XCTAssertNil(backup.equipment.first?.waterAlkalinity)
        XCTAssertNil(backup.brews.first?.tds)
        XCTAssertNil(backup.brews.first?.beverageWeight)
        XCTAssertEqual(backup.brews.last?.tds, Extraction.Limits.maxTDS)
    }

    func testOlderBackupsStillRead() throws {
        let backup = try BrewLogBackup.decode(Data(BackupTests.webBackupJSON.utf8))
        XCTAssertTrue(backup.photos.isEmpty)
        XCTAssertNil(backup.brews.first?.tds)
        XCTAssertEqual(backup.brews.first?.waterName, "")
    }
}
