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

/// "Start shot" right after Ready: the tare hasn't reached the scale yet, so it still shows the cup. That weight
/// must not count as the shot (it stopped the machine after a second).
final class ShotBeforeTareTests: XCTestCase {
    private var demoWasOn = false
    private var autoStopWas = true

    override func setUp() {
        super.setUp()
        demoWasOn = UserDefaults.standard.bool(forKey: SettingsKey.demoScale)
        autoStopWas = UserDefaults.standard.bool(forKey: SettingsKey.autoStopShot)
        UserDefaults.standard.set(true, forKey: SettingsKey.autoStopShot)
    }

    override func tearDown() {
        UserDefaults.standard.set(demoWasOn, forKey: SettingsKey.demoScale)
        UserDefaults.standard.set(autoStopWas, forKey: SettingsKey.autoStopShot)
        super.tearDown()
    }

    func testTheCupBeforeTheTareDoesNotStopTheShot() throws {
        let scale = ScaleManager()
        scale.isDemo = true
        let recipe = try XCTUnwrap(RecipeLibrary.presets.first { $0.method.isEspresso })
        let session = BrewSession(recipe: recipe, scale: scale, machine: MachineManager())
        session.activate()
        defer { session.deactivate() }
        session.ready()
        session.startManually()
        XCTAssertEqual(session.phase, .brewing)

        let start = Date()
        func weigh(_ grams: Double, at seconds: TimeInterval) {
            scale.onWeight?(grams, start.addingTimeInterval(seconds))
        }
        // The cup, before the tare lands: no stop.
        weigh(210, at: 0.2)
        weigh(210, at: 0.5)
        XCTAssertFalse(session.stopRequested)
        // Tared: from here the weight is the shot.
        weigh(0, at: 0.9)
        weigh(10, at: 8)
        XCTAssertFalse(session.stopRequested)
        weigh(recipe.water + 1, at: 25)
        XCTAssertTrue(session.stopRequested)
    }
}
