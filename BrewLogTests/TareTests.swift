import XCTest
@testable import BrewLog

/// Where the live brew screen offers Tare: whenever the scale shows a weight before the pour.
final class TareTests: XCTestCase {
    private var demoWasOn = false

    override func setUp() {
        super.setUp()
        demoWasOn = UserDefaults.standard.bool(forKey: SettingsKey.demoScale)
    }

    override func tearDown() {
        UserDefaults.standard.set(demoWasOn, forKey: SettingsKey.demoScale)
        super.tearDown()
    }

    private func session(demoScale: Bool) -> BrewSession {
        let scale = ScaleManager()
        scale.isDemo = demoScale
        return BrewSession(recipe: RecipeLibrary.blankRecipe(), scale: scale)
    }

    func testTareIsOfferedWithAScaleBeforeTheBrew() {
        let withScale = session(demoScale: true)
        XCTAssertEqual(withScale.phase, .preparing)
        XCTAssertTrue(withScale.canTare)
    }

    func testNoTareWithoutAScale() {
        XCTAssertFalse(session(demoScale: false).canTare)
    }

    func testTareDoesNothingWithoutAScale() {
        let noScale = session(demoScale: false)
        noScale.tare()
        XCTAssertEqual(noScale.phase, .preparing)
    }
}
