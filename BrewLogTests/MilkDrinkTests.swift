import XCTest
@testable import BrewLog

/// Milk drinks: milk in the recipe, what happens after the shot, the milk step.
final class MilkDrinkTests: XCTestCase {
    func testMilkDrinkSteamsWhateverTheEspressoSetting() {
        for setting in SteamAfterShot.allCases {
            XCTAssertEqual(AfterShot.action(milkDrink: true, canSteam: true, canSwitchOff: true, setting: setting),
                           .steamAndMilk)
        }
        XCTAssertEqual(AfterShot.action(milkDrink: true, canSteam: false, canSwitchOff: false, setting: .ask), .milk)
    }

    func testMilkWeighedBeforeTheShotOnlySteamsAfterIt() {
        XCTAssertEqual(AfterShot.action(milkDrink: true, canSteam: true, canSwitchOff: true, setting: .ask, milkTiming: .before), .steam)
        XCTAssertEqual(AfterShot.action(milkDrink: true, canSteam: false, canSwitchOff: true, setting: .ask, milkTiming: .before), .nothing)
        XCTAssertEqual(AfterShot.action(milkDrink: false, canSteam: true, canSwitchOff: true, setting: .ask, milkTiming: .before), .askSwitchOff)
    }

    func testMilkTimingDefaultsToAfterTheShot() {
        XCTAssertEqual(MilkTiming(rawValue: "after"), .after)
        XCTAssertEqual(MilkTiming.allCases.count, 2)
    }

    func testEspressoFollowsTheSettingAndNeverSteams() {
        XCTAssertEqual(AfterShot.action(milkDrink: false, canSteam: true, canSwitchOff: true, setting: .ask), .askSwitchOff)
        XCTAssertEqual(AfterShot.action(milkDrink: false, canSteam: true, canSwitchOff: true, setting: .switchOff), .switchOff)
        XCTAssertEqual(AfterShot.action(milkDrink: false, canSteam: true, canSwitchOff: true, setting: .off), .nothing)
        XCTAssertEqual(AfterShot.action(milkDrink: false, canSteam: false, canSwitchOff: false, setting: .ask), .nothing)
    }

    func testTheOldSteamSettingReadsAsAsk() {
        XCTAssertNil(SteamAfterShot(rawValue: "steam"))
    }

    func testRecipeMilkDecodesAndValidates() throws {
        let json = #"{"name":"Flat White","method":"espresso","dose":18,"water":36,"milk":120,"steps":[]}"#
        let recipe = try JSONDecoder().decode(Recipe.self, from: Data(json.utf8))
        XCTAssertEqual(recipe.milk, 120)
        XCTAssertTrue(recipe.isMilkDrink)

        let plain = #"{"name":"Espresso","method":"espresso","dose":18,"water":36,"steps":[]}"#
        XCTAssertFalse(try JSONDecoder().decode(Recipe.self, from: Data(plain.utf8)).isMilkDrink)

        var zero = recipe
        zero.milk = 0
        XCTAssertNil(zero.validated().milk)
    }

    func testScaledRecipeCarriesTheSetupMilk() throws {
        let setup = BrewSetup(scope: .espresso, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        var recipe = try XCTUnwrap(RecipeLibrary.presets.first { $0.method.isEspresso })
        recipe.milk = 120
        setup.select(recipe)
        XCTAssertEqual(setup.scaledRecipe.milk, 120)
        setup.milk = 0
        XCTAssertNil(setup.scaledRecipe.milk)
    }

    func testMilkStepValues() {
        XCTAssertEqual(MilkStep.progress(weight: 60, target: 120), 0.5)
        XCTAssertEqual(MilkStep.progress(weight: 200, target: 120), 1)
        XCTAssertEqual(MilkStep.progress(weight: -3, target: 120), 0)
        XCTAssertEqual(MilkStep.recorded(118.26), 118.3)
        XCTAssertNil(MilkStep.recorded(0.4))
    }
}
