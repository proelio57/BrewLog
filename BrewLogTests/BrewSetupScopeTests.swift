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

final class BrewSetupMigrationTests: XCTestCase {
    func testEspressoRecipeInPourOverSetupMovesOver() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let shot = try XCTUnwrap(RecipeLibrary.presets.first { $0.method.isEspresso })
        let grinder = UUID()
        // Before the switch existed, an espresso recipe lived in the one (pour-over) setup.
        defaults.set(shot.id, forKey: "setup.recipeID")
        defaults.set(grinder.uuidString, forKey: "setup.grinderID")
        let pourOver = BrewSetup(scope: .pourOver, defaults: defaults)
        let espresso = BrewSetup(scope: .espresso, defaults: defaults)

        XCTAssertTrue(BrewSetup.moveEspressoRecipe(from: pourOver, to: espresso))
        XCTAssertEqual(espresso.recipe.id, shot.id)
        XCTAssertEqual(espresso.grinderID, grinder)
        XCTAssertFalse(pourOver.recipe.method.isEspresso)
        XCTAssertFalse(BrewSetup.moveEspressoRecipe(from: pourOver, to: espresso))
    }
}
