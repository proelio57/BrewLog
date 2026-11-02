import XCTest
@testable import BrewLog

final class BrewStatsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    /// Wednesday, 2026-11-04 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_793_793_600)
    private let day: TimeInterval = 86_400

    private func entry(daysAgo: Double, espresso: Bool = false, rating: Int = 0, bean: UUID? = nil,
                       beanName: String = "Bean", recipe: String = "Recipe", dose: Double = 15, yield: Double = 250,
                       time: Double = 180, target: Double = 180, grind: String = "", extraction: Double? = nil,
                       firstDrops: Double? = nil, peak: Double? = nil, drop: Double? = nil) -> BrewStats.Entry {
        BrewStats.Entry(date: now.addingTimeInterval(-daysAgo * day), espresso: espresso, rating: rating, beanID: bean,
                        beanName: beanName, recipeName: recipe, dose: dose, yield: yield, time: time, targetTime: target,
                        grind: grind, extractionYield: extraction, firstDrops: firstDrops, peakPressure: peak,
                        suddenDrop: drop)
    }

    private func summary(_ entries: [BrewStats.Entry], espresso: Bool = false, since: Date? = nil) -> BrewStats.Summary {
        BrewStats.summary(entries, espresso: espresso, since: since, now: now, calendar: calendar)
    }

    private func weeks(_ ratings: [Double?]) -> [BrewStats.Week] {
        ratings.enumerated().map { BrewStats.Week(start: now.addingTimeInterval(Double($0.offset) * 7 * day),
                                                   brews: 1, averageRating: $0.element) }
    }

    func testWeeksCountAndAverage() {
        let s = summary([entry(daysAgo: 0, rating: 4), entry(daysAgo: 1, rating: 5), entry(daysAgo: 2, rating: 0),
                         entry(daysAgo: 7, rating: 3)])
        XCTAssertEqual(s.weeks.count, 12)
        XCTAssertEqual(s.weeks.last?.brews, 3)
        XCTAssertEqual(s.weeks.last?.averageRating, 4.5)
        XCTAssertEqual(s.weeks[10].averageRating, 3.0)
        XCTAssertEqual(s.brews, 4)
        XCTAssertLessThan(s.weeks[0].start, s.weeks[11].start)
    }

    func testTrendVerdicts() {
        XCTAssertEqual(BrewStats.trend(weeks([3.0, 3.5, 4.0, 4.5])), .improving)
        XCTAssertEqual(BrewStats.trend(weeks([4, 4, 4])), .steady)
        XCTAssertEqual(BrewStats.trend(weeks([5, 4, 3])), .declining)
        XCTAssertNil(BrewStats.trend(weeks([3, nil, 5])))
    }

    func testFiltersByKindAndRange() {
        let entries = [entry(daysAgo: 1), entry(daysAgo: 2, espresso: true, dose: 18, yield: 36, time: 28, target: 28),
                       entry(daysAgo: 40)]
        XCTAssertEqual(summary(entries).brews, 2)
        XCTAssertEqual(summary(entries, espresso: true).brews, 1)
        XCTAssertEqual(summary(entries, since: now.addingTimeInterval(-30 * day)).brews, 1)
    }

    func testEspressoAverages() {
        let entries = [
            entry(daysAgo: 1, espresso: true, rating: 4, dose: 18, yield: 36, time: 28, firstDrops: 6, peak: 9, drop: 2.5),
            entry(daysAgo: 2, espresso: true, rating: 3, dose: 18, yield: 39.6, time: 30, firstDrops: 2),
            entry(daysAgo: 3, espresso: true, rating: 5, dose: 18, yield: 37.8, time: 29),
        ]
        let s = summary(entries, espresso: true)
        XCTAssertEqual(s.averageRatio ?? 0, 2.1, accuracy: 0.001)
        XCTAssertEqual(s.averageFirstDrops ?? 0, 4, accuracy: 0.001)
        XCTAssertEqual(s.firstDropsCount, 2)
        XCTAssertEqual(s.averagePeakPressure, 9)
        XCTAssertEqual(s.pressureCount, 1)
        XCTAssertEqual(s.channelingShots, 2)
        XCTAssertEqual(s.points.count, 3)
        XCTAssertEqual(s.averageTime ?? 0, 29, accuracy: 0.001)
    }

    func testPourOverTimeDeltaAndExtraction() {
        let s = summary([entry(daysAgo: 1, time: 192, target: 180, extraction: 20),
                         entry(daysAgo: 2, time: 175, target: 180)])
        XCTAssertEqual(s.averageTimeDelta ?? 0, 3.5, accuracy: 0.001)
        XCTAssertEqual(s.averageExtraction, 20)
        XCTAssertEqual(s.extractionCount, 1)
        XCTAssertTrue(s.points.isEmpty)
    }

    func testBeanGroupBestRecipeAndGrind() throws {
        let bean = UUID()
        let s = summary([entry(daysAgo: 1, rating: 3, bean: bean, beanName: "Kenya", recipe: "A", grind: "20"),
                         entry(daysAgo: 2, rating: 5, bean: bean, beanName: "Kenya", recipe: "B", grind: "22"),
                         entry(daysAgo: 3, rating: 5, bean: bean, beanName: "Kenya", recipe: "C", grind: "24")])
        let group = try XCTUnwrap(s.beans.first)
        XCTAssertEqual(group.name, "Kenya")
        XCTAssertEqual(group.brews, 3)
        XCTAssertEqual(group.averageRating ?? 0, 13.0 / 3, accuracy: 0.001)
        XCTAssertEqual(group.bestRecipe, "B")
        XCTAssertEqual(group.bestGrind, "22")
        XCTAssertEqual(group.lastBrewed, now.addingTimeInterval(-day))
    }

    // MARK: Review focus

    func testEmptyInputGivesEmptyStats() {
        let s = summary([])
        XCTAssertEqual(s.brews, 0)
        XCTAssertEqual(s.weeks.count, 12)
        XCTAssertTrue(s.weeks.allSatisfy { $0.brews == 0 && $0.averageRating == nil })
        XCTAssertNil(s.trend)
        XCTAssertNil(s.averageRatio)
        XCTAssertNil(s.averageTime)
        XCTAssertTrue(s.beans.isEmpty)
        XCTAssertTrue(s.recipes.isEmpty)
        XCTAssertTrue(s.points.isEmpty)
    }

    func testBrewsWithoutBeanAreGrouped() {
        let s = summary([entry(daysAgo: 1, bean: nil, beanName: "No bean"), entry(daysAgo: 2, bean: nil, beanName: "")])
        XCTAssertEqual(s.beans.count, 1)
        XCTAssertEqual(s.beans.first?.name, "No bean")
        XCTAssertEqual(s.beans.first?.brews, 2)
    }

    func testRankingNeedsTwoRatings() {
        var entries = [entry(daysAgo: 1, rating: 5, recipe: "Once")]
        for i in 0..<10 { entries.append(entry(daysAgo: Double(i) + 2, rating: i < 6 ? 5 : 4, recipe: "Often")) }
        entries.append(entry(daysAgo: 1, rating: 0, recipe: "Unrated"))
        entries.append(entry(daysAgo: 2, rating: 0, recipe: "Unrated"))
        let names = summary(entries).recipes.map(\.name)
        XCTAssertEqual(names, ["Often", "Unrated", "Once"])
    }

    func testAveragesSkipMissingValues() {
        let s = summary([entry(daysAgo: 1, espresso: true, dose: 18, yield: 36, time: 28, peak: 9),
                         entry(daysAgo: 2, espresso: true, dose: 18, yield: 36, time: 28),
                         entry(daysAgo: 3, espresso: true, dose: 18, yield: 36, time: 28, peak: 8)], espresso: true)
        XCTAssertEqual(s.averagePeakPressure ?? 0, 8.5, accuracy: 0.001)
        XCTAssertEqual(s.pressureCount, 2)
        XCTAssertNil(s.averageFirstDrops)
        XCTAssertEqual(s.firstDropsCount, 0)
    }

    func testFutureDatesClampToThisWeek() {
        let s = summary([entry(daysAgo: -30, rating: 4)])
        XCTAssertEqual(s.brews, 1)
        XCTAssertEqual(s.weeks.last?.brews, 1)
        XCTAssertEqual(s.weeks.map(\.brews).reduce(0, +), 1)
    }
}
