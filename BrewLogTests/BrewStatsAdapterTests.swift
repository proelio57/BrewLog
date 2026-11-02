import XCTest
import SwiftData
@testable import BrewLog

final class BrewStatsAdapterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(for: Bean.self, Equipment.self, Brew.self, SavedRecipe.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    func testEspressoBrewBecomesEntry() throws {
        let shot = try XCTUnwrap(RecipeLibrary.presets.first { $0.method.isEspresso })
        let brew = Brew()
        context.insert(brew)
        brew.recipe = shot
        brew.recipeName = shot.name
        brew.dose = 18
        brew.finalWeight = 36
        brew.totalTime = 28
        brew.rating = 4
        brew.samples = [WeightSample(t: 0, w: 0), WeightSample(t: 6, w: 0.5), WeightSample(t: 7, w: 1.2),
                        WeightSample(t: 28, w: 36)]
        brew.machineSamples = (0..<20).map { i in
            MachineSample(t: Double(i), p: i == 10 ? 9.0 : 8.0, c: 93, f: 2)
        }
        let bean = Bean(name: "Kenya")
        context.insert(bean)
        brew.bean = bean

        let entry = brew.statsEntry
        XCTAssertTrue(entry.espresso)
        XCTAssertEqual(entry.firstDrops, 7)
        XCTAssertEqual(entry.peakPressure, 9.0)
        XCTAssertEqual(entry.yield, 36)
        XCTAssertEqual(entry.time, 28)
        XCTAssertEqual(entry.beanName, "Kenya")
        XCTAssertEqual(entry.beanID, bean.id)
        XCTAssertEqual(entry.targetTime, shot.targetTime)
    }

    func testPourOverBrewWithoutBean() throws {
        let pourOver = try XCTUnwrap(RecipeLibrary.presets.first { !$0.method.isEspresso })
        let brew = Brew()
        context.insert(brew)
        brew.recipe = pourOver
        brew.dose = 15
        brew.finalWeight = 250
        brew.tds = 1.4
        brew.machineSamples = (0..<20).map { MachineSample(t: Double($0), p: 9, c: nil, f: nil) }

        let entry = brew.statsEntry
        XCTAssertFalse(entry.espresso)
        XCTAssertEqual(entry.beanName, "No bean")
        XCTAssertNil(entry.beanID)
        XCTAssertNil(entry.peakPressure)
        XCTAssertNil(entry.firstDrops)
        XCTAssertNotNil(entry.extractionYield)
    }
}
