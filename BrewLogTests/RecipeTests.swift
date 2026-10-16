import XCTest
@testable import BrewLog

final class RecipeTests: XCTestCase {

    func testPresetsLoadAndAreConsistent() {
        let presets = RecipeLibrary.presets
        XCTAssertGreaterThanOrEqual(presets.count, 9)
        XCTAssertGreaterThanOrEqual(presets.filter(\.method.isEspresso).count, 3, "espresso recipes")
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count, "ids must be unique")

        for recipe in presets {
            XCTAssertFalse(recipe.tasteNotes.isEmpty, "\(recipe.id) needs taste notes")
            XCTAssertFalse(recipe.steps.isEmpty, "\(recipe.id) needs steps")
            XCTAssertEqual(recipe.steps.first?.time, 0, "\(recipe.id) must start at 0:00")
            XCTAssertEqual(recipe.steps.map(\.time), recipe.steps.map(\.time).sorted(), "\(recipe.id) steps sorted")
            let targets = recipe.pourSteps.compactMap(\.target)
            XCTAssertEqual(targets, targets.sorted(), "\(recipe.id) targets cumulative")
            XCTAssertEqual(targets.last ?? 0, recipe.water, accuracy: 0.5, "\(recipe.id) last pour reaches total water")
            XCTAssertGreaterThanOrEqual(recipe.targetTime, recipe.steps.last?.time ?? 0)
            let ratios: ClosedRange<Double> = recipe.method.isEspresso ? 1.2...5 : 12...18
            XCTAssertTrue(ratios.contains(recipe.ratio), "\(recipe.id) ratio \(recipe.ratio)")
            XCTAssertLessThan(recipe.flowMin, recipe.flowMax)
        }
    }

    func testBundledJSONIsAlreadyValid() throws {
        // Decode the raw file (presets are validated on load, so check the source itself).
        let url = try XCTUnwrap(Bundle.main.url(forResource: "recipes", withExtension: "json"))
        let raw = try JSONDecoder().decode([Recipe].self, from: Data(contentsOf: url))
        XCTAssertEqual(raw.count, RecipeLibrary.presets.count)
        for recipe in raw {
            XCTAssertEqual(recipe.validated(), recipe, "\(recipe.id) should already be valid")
        }
    }

    func testScalingKeepsTimesAndScalesWeights() throws {
        let recipe = try XCTUnwrap(RecipeLibrary.preset(id: "kasuya-46"))
        let scaled = recipe.scaled(toDose: 30)
        XCTAssertEqual(scaled.dose, 30)
        XCTAssertEqual(scaled.water, 450)
        XCTAssertEqual(scaled.steps.map(\.time), recipe.steps.map(\.time))
        XCTAssertEqual(scaled.pourSteps.compactMap(\.target), [90, 180, 270, 360, 450])
        XCTAssertEqual(scaled.ratio, recipe.ratio, accuracy: 0.01)
    }

    func testTargetCurveEndsAtTotalWater() throws {
        let recipe = try XCTUnwrap(RecipeLibrary.preset(id: "hoffmann-ultimate-v60"))
        let curve = recipe.targetCurve()
        XCTAssertEqual(curve.first?.weight, 0)
        XCTAssertEqual(curve.last?.weight, recipe.water)
        XCTAssertEqual(curve.last?.time, recipe.targetTime)
        XCTAssertEqual(curve.map(\.time), curve.map(\.time).sorted())
    }

    func testValidationClampsHostileValues() {
        var recipe = RecipeLibrary.blankRecipe()
        recipe.name = "  \u{0000}Evil\u{0007} name " + String(repeating: "x", count: 500)
        recipe.dose = .nan
        recipe.water = -50
        recipe.temperature = 1_000
        recipe.targetTime = .infinity
        recipe.flowMin = 10
        recipe.flowMax = 2
        recipe.taste = TasteProfile(acidity: 99, sweetness: -3, body: 3, clarity: 0)
        recipe.steps = [
            RecipeStep(kind: .pour, time: 60, target: 50, note: nil),
            RecipeStep(kind: .bloom, time: -5, target: 1_000_000, note: nil),
            RecipeStep(kind: .swirl, time: 9_999, target: 42, note: String(repeating: "n", count: 999)),
        ] + Array(repeating: RecipeStep(kind: .pour, time: 10, target: 1, note: nil), count: 100)

        let clean = recipe.validated()

        XCTAssertTrue(clean.name.hasPrefix("Evil name"))
        XCTAssertLessThanOrEqual(clean.name.count, InputLimits.maxNameLength)
        XCTAssertFalse(clean.name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) })
        XCTAssertEqual(clean.dose, 1)
        XCTAssertEqual(clean.water, 10)
        XCTAssertEqual(clean.temperature, 100)
        XCTAssertTrue(clean.targetTime.isFinite)
        XCTAssertGreaterThan(clean.flowMax, clean.flowMin)
        XCTAssertEqual(clean.taste, TasteProfile(acidity: 5, sweetness: 1, body: 3, clarity: 1))
        XCTAssertLessThanOrEqual(clean.steps.count, InputLimits.maxSteps)
        XCTAssertEqual(clean.steps.map(\.time), clean.steps.map(\.time).sorted())
        XCTAssertTrue(clean.steps.allSatisfy { (0...InputLimits.maxBrewSeconds).contains($0.time) })
        XCTAssertNil(clean.steps.first(where: { $0.kind == .swirl })?.target, "non-pour steps have no target")
        let targets = clean.pourSteps.compactMap(\.target)
        XCTAssertEqual(targets, targets.sorted(), "targets made cumulative")
        XCTAssertTrue(targets.allSatisfy { $0 <= clean.water * 1.5 })
        XCTAssertGreaterThanOrEqual(clean.targetTime, clean.steps.last?.time ?? 0)
    }

    func testSanitizedStringStripsControlCharactersAndLimitsLength() {
        XCTAssertEqual("  hello\u{0000}\u{001B}world  ".sanitized(maxLength: 50), "helloworld")
        XCTAssertEqual("abcdef".sanitized(maxLength: 3), "abc")
        XCTAssertEqual("line1\nline2".sanitized(maxLength: 50), "line1\nline2")
    }

    func testDoubleClampedHandlesNonFinite() {
        XCTAssertEqual(Double.nan.clamped(1, 5), 1)
        XCTAssertEqual(Double.infinity.clamped(1, 5), 1)
        XCTAssertEqual(7.0.clamped(1, 5), 5)
        XCTAssertEqual(0.0.clamped(1, 5), 1)
    }

    func testMmssFormatting() {
        XCTAssertEqual(TimeInterval(0).mmss, "0:00")
        XCTAssertEqual(TimeInterval(65.9).mmss, "1:05")
        XCTAssertEqual(TimeInterval(210).mmss, "3:30")
    }
}
