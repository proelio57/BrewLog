import XCTest
import SwiftData
@testable import BrewLog

final class GrinderSpecTests: XCTestCase {
    let comandante = GrinderSpec(unit: .clicks, step: 1, adjustStep: 2, finerIsLower: true)

    func testAdjustFinerAndCoarser() {
        XCTAssertEqual(comandante.adjusted(24, coarser: false), 22)
        XCTAssertEqual(comandante.adjusted(24, coarser: true), 26)
        XCTAssertEqual(comandante.adjusted(24, coarser: false, multiplier: 2), 20)
    }

    func testAdjustRespectsReversedScale() {
        let reversed = GrinderSpec(unit: .numbers, step: 1, adjustStep: 1, finerIsLower: false)
        XCTAssertEqual(reversed.adjusted(10, coarser: false), 11)
        XCTAssertEqual(reversed.adjusted(10, coarser: true), 9)
    }

    func testAdjustSnapsToStepAndNeverGoesNegative() {
        let dial = GrinderSpec(unit: .dial, step: 0.1, adjustStep: 0.2, finerIsLower: true)
        XCTAssertEqual(dial.adjusted(7.5, coarser: false), 7.3, accuracy: 0.0001)
        XCTAssertEqual(comandante.adjusted(1, coarser: false), 0)
    }

    func testFormatting() {
        XCTAssertEqual(comandante.format(24), "24 clicks")
        XCTAssertEqual(comandante.formatDelta(1), "1 click")
        XCTAssertEqual(comandante.formatDelta(-2), "2 clicks")
        let dial = GrinderSpec(unit: .dial, step: 0.1, adjustStep: 0.2)
        XCTAssertEqual(dial.format(7.5), "7.5")
    }
}

final class GrindRecommenderTests: XCTestCase {
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

    private func makeGrinder() -> Equipment {
        let grinder = Equipment(name: "Comandante C40", type: .grinder,
                                grinder: GrinderSpec(unit: .clicks, step: 1, adjustStep: 2))
        context.insert(grinder)
        return grinder
    }

    private func makeBrew(bean: Bean?, grinder: Equipment, grind: Double, recipeID: String = "kasuya-46",
                          daysAgo: Double, feedback: Set<TasteFeedback> = [], rating: Int = 0,
                          suggested: Double? = nil) -> Brew {
        let brew = Brew()
        context.insert(brew)
        brew.date = Date().addingTimeInterval(-daysAgo * 86_400)
        brew.recipeID = recipeID
        brew.setGrinder(grinder)
        brew.grindValue = grind
        brew.feedback = feedback
        brew.rating = rating
        brew.suggestedGrind = suggested
        brew.bean = bean
        return brew
    }

    func testNoHistoryMeansNoRecommendation() {
        let grinder = makeGrinder()
        XCTAssertNil(GrindRecommender.recommend(beanID: nil, grinder: grinder, recipeID: "kasuya-46", brews: []))
        XCTAssertNil(GrindRecommender.recommend(beanID: nil, grinder: nil, recipeID: "kasuya-46", brews: []))
    }

    func testUsesSuggestionFromLastReview() throws {
        let grinder = makeGrinder()
        let bean = Bean(name: "Guji")
        context.insert(bean)
        let brews = [
            makeBrew(bean: bean, grinder: grinder, grind: 24, daysAgo: 1, feedback: [.sour], rating: 2, suggested: 22),
            makeBrew(bean: bean, grinder: grinder, grind: 26, daysAgo: 3, feedback: [.sour], rating: 1),
        ]
        let recommendation = try XCTUnwrap(GrindRecommender.recommend(beanID: bean.id, grinder: grinder,
                                                                     recipeID: "kasuya-46", brews: brews))
        XCTAssertEqual(recommendation.value, 22)
        XCTAssertTrue(recommendation.reason.contains("Suggested"))
        XCTAssertGreaterThan(grinder.grinderSpec.adjustStep, 0)
    }

    func testPerfectBrewBecomesReference() throws {
        let grinder = makeGrinder()
        let bean = Bean(name: "Kenya")
        context.insert(bean)
        let brews = [makeBrew(bean: bean, grinder: grinder, grind: 23, daysAgo: 1, feedback: [.perfect], rating: 5)]
        let recommendation = try XCTUnwrap(GrindRecommender.recommend(beanID: bean.id, grinder: grinder,
                                                                     recipeID: "kasuya-46", brews: brews))
        XCTAssertEqual(recommendation.value, 23)
        XCTAssertTrue(recommendation.reason.contains("reference"))
    }

    func testFallsBackToLastBrewOfRecipe() throws {
        let grinder = makeGrinder()
        let brews = [
            makeBrew(bean: nil, grinder: grinder, grind: 18, recipeID: "rao-v60", daysAgo: 1),
            makeBrew(bean: nil, grinder: grinder, grind: 27, recipeID: "kasuya-46", daysAgo: 2),
        ]
        let recommendation = try XCTUnwrap(GrindRecommender.recommend(beanID: UUID(), grinder: grinder,
                                                                     recipeID: "kasuya-46", brews: brews))
        XCTAssertEqual(recommendation.value, 27)
    }

    func testUsesSuggestionForRecipeWhenNoBeanWasLogged() throws {
        let grinder = makeGrinder()
        let brews = [makeBrew(bean: nil, grinder: grinder, grind: 24, daysAgo: 1, feedback: [.sour], rating: 2, suggested: 20)]
        let recommendation = try XCTUnwrap(GrindRecommender.recommend(beanID: nil, grinder: grinder,
                                                                     recipeID: "kasuya-46", brews: brews))
        XCTAssertEqual(recommendation.value, 20)
        XCTAssertTrue(recommendation.reason.contains("of this recipe"))
    }

    func testExplicitGrindIsPinnedUntilBeanOrGrinderChanges() {
        let setup = BrewSetup()
        setup.beanID = UUID()
        setup.grinderID = UUID()
        setup.pinGrind(24)
        XCTAssertEqual(setup.grindValue, 24)
        XCTAssertTrue(setup.isGrindPinned, "recommendations must not overwrite an explicitly set grind")
        setup.beanID = UUID()
        XCTAssertFalse(setup.isGrindPinned, "a different bean gets its own recommendation again")
    }

    func testBrewGrindDisplayUsesSnapshotSpec() {
        let grinder = makeGrinder()
        let brew = makeBrew(bean: nil, grinder: grinder, grind: 24, daysAgo: 0)
        XCTAssertEqual(brew.grindDisplay, "24 clicks")
        brew.setGrinder(nil)
        brew.grindValue = nil
        brew.grindSetting = "medium-fine"
        XCTAssertEqual(brew.grindDisplay, "medium-fine")
    }
}
