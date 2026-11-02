import XCTest
@testable import BrewLog

final class BrewSetupScopeTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    func testScopesDoNotShareKeys() throws {
        let defaults = freshDefaults()
        let espresso = BrewSetup(scope: .espresso, defaults: defaults)
        let shot = try XCTUnwrap(RecipeLibrary.presets.first { $0.method.isEspresso })
        let bean = UUID()
        espresso.select(shot)
        espresso.beanID = bean

        let pourOver = BrewSetup(scope: .pourOver, defaults: defaults)
        XCTAssertNotEqual(pourOver.recipe.id, shot.id)
        XCTAssertNil(pourOver.beanID)

        let espressoAgain = BrewSetup(scope: .espresso, defaults: defaults)
        XCTAssertEqual(espressoAgain.recipe.id, shot.id)
        XCTAssertEqual(espressoAgain.beanID, bean)
    }

    func testPourOverKeepsTodaysKeys() {
        let defaults = freshDefaults()
        defaults.set("rao-v60", forKey: "setup.recipeID")
        let setup = BrewSetup(scope: .pourOver, defaults: defaults)
        XCTAssertEqual(setup.recipe.id, "rao-v60")
    }

    func testDefaultsPerScope() {
        let defaults = freshDefaults()
        XCTAssertTrue(BrewSetup(scope: .espresso, defaults: defaults).recipe.method.isEspresso)
        XCTAssertFalse(BrewSetup(scope: .pourOver, defaults: defaults).recipe.method.isEspresso)
    }

    func testKeyPrefixes() {
        XCTAssertEqual(SetupScope.pourOver.keyPrefix, "setup.")
        XCTAssertEqual(SetupScope.espresso.keyPrefix, "espresso.")
    }
}
