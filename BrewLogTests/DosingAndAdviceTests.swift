import XCTest
@testable import BrewLog

final class DosingAndAdviceTests: XCTestCase {

    // MARK: Weighing the beans

    func testDoseStatus() {
        XCTAssertEqual(BeanDosing.status(weight: 0.2, dose: 15), .empty)
        XCTAssertEqual(BeanDosing.status(weight: 12, dose: 15), .under)
        XCTAssertEqual(BeanDosing.status(weight: 14.8, dose: 15), .onTarget)
        XCTAssertEqual(BeanDosing.status(weight: 15.2, dose: 15), .onTarget)
        XCTAssertEqual(BeanDosing.status(weight: 15.5, dose: 15), .over)
        XCTAssertEqual(BeanDosing.status(weight: .nan, dose: 15), .empty)
    }

    func testDoseProgressIsClamped() {
        XCTAssertEqual(BeanDosing.progress(weight: 7.5, dose: 15), 0.5, accuracy: 0.001)
        XCTAssertEqual(BeanDosing.progress(weight: 20, dose: 15), 1)
        XCTAssertEqual(BeanDosing.progress(weight: -2, dose: 15), 0)
        XCTAssertEqual(BeanDosing.progress(weight: 5, dose: 0), 0)
    }

    func testAcceptedDoseUsesTheReadingOrFallsBack() {
        XCTAssertEqual(BeanDosing.acceptedDose(weight: 15.26, planned: 15), 15.3)
        XCTAssertEqual(BeanDosing.acceptedDose(weight: 0.1, planned: 15), 15)
        XCTAssertEqual(BeanDosing.acceptedDose(weight: 900, planned: 15), 15)
        XCTAssertEqual(BeanDosing.acceptedDose(weight: .infinity, planned: 15), 15)
    }

    // MARK: Recipe advice

    private func preset(_ id: String) throws -> Recipe { try XCTUnwrap(RecipeLibrary.preset(id: id)) }

    func testClearerAlternativeIsNeverTheBrewedRecipe() throws {
        for recipe in RecipeLibrary.presets where !recipe.method.isEspresso {
            let alternative = RecipeFilter.clearerAlternative(to: recipe, among: RecipeLibrary.presets)
            XCTAssertNotEqual(alternative?.id, recipe.id, recipe.id)
            XCTAssertNotEqual(alternative?.name, recipe.name, recipe.id)
            XCTAssertFalse(alternative?.id.hasPrefix("template-") ?? false)
            if let alternative {
                XCTAssertTrue(RecipeFilter.matches(alternative, method: recipe.method == .universal ? nil : recipe.method))
                XCTAssertFalse(alternative.method.isEspresso)
            }
        }
    }

    func testRaoV60PointsToAnotherClearV60Recipe() throws {
        let rao = try preset("rao-v60")
        let alternative = try XCTUnwrap(RecipeFilter.clearerAlternative(to: rao, among: RecipeLibrary.presets))
        XCTAssertNotEqual(alternative.id, rao.id)
        XCTAssertGreaterThanOrEqual(alternative.taste.clarity, rao.taste.clarity)
    }

    func testSwitchStaysOnTheSwitch() throws {
        let immersion = try preset("switch-immersion")
        let alternative = try XCTUnwrap(RecipeFilter.clearerAlternative(to: immersion, among: RecipeLibrary.presets))
        XCTAssertTrue(RecipeFilter.matches(alternative, method: .hybrid))
        XCTAssertGreaterThan(alternative.taste.clarity, immersion.taste.clarity)
    }

    func testCopyOfTheSameRecipeIsNotSuggested() throws {
        var rao = try preset("rao-v60")
        rao.id = "custom-rao"
        let candidates = [try preset("rao-v60")]
        XCTAssertNil(RecipeFilter.clearerAlternative(to: rao, among: candidates))
    }

    func testEspressoGetsNoPourOverRecipe() throws {
        XCTAssertNil(RecipeFilter.clearerAlternative(to: try preset("espresso-classic"), among: RecipeLibrary.presets))
    }

    func testFlatCupAdviceDoesNotNameTheBrewedRecipe() throws {
        let rao = try preset("rao-v60")
        let input = AnalysisInput(recipe: rao, samples: [], usedScale: false, totalTime: rao.targetTime,
                                  finalWeight: rao.water, dose: rao.dose, waterTemp: rao.temperature,
                                  roastLevel: .light, daysOffRoast: 14, filterName: "Paper", filterFlow: .fast,
                                  filterIdealRoast: nil, grinder: nil, feedback: [.flat], history: [],
                                  alternatives: RecipeLibrary.presets)
        let clarity = try XCTUnwrap(BrewAnalyzer.analyze(input).suggestions.first { $0.key == "clarity" })
        XCTAssertFalse(clarity.title.contains(rao.name))
        XCTAssertTrue(clarity.detail.hasSuffix("than \(rao.name)."), clarity.detail)
        // Already on a fast paper: no paper advice.
        XCTAssertFalse(clarity.detail.contains("CAFEC"))
    }

    func testFlatCupWithoutAlternativesOnlySuggestsPaper() throws {
        let advice = BrewAnalyzer.clarityAdvice(recipe: try preset("rao-v60"), input: AnalysisInput(
            recipe: try preset("rao-v60"), samples: [], usedScale: false, totalTime: 0, finalWeight: 0, dose: 15,
            waterTemp: 0, roastLevel: nil, daysOffRoast: nil, filterName: "", filterFlow: .slow, filterIdealRoast: nil,
            grinder: nil, feedback: [.flat], history: []))
        XCTAssertEqual(advice?.title, "Try a faster paper")
    }
}
