import XCTest
@testable import BrewLog

/// Stats, cups left and freshness for the widgets. Foundation only, so these also run on Linux.
final class WidgetStatsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    func testStatsCountDaysStreakAndRatings() {
        let now = date(10, 18)
        let brews: [(date: Date, rating: Int)] = [
            (date(10, 8), 4), (date(10, 15), 0),   // today: 2, one unrated
            (date(9), 5), (date(8), 3),             // streak continues
            (date(6), 2),                           // gap on the 7th ends the streak
            (date(1), 5),                           // older than 7 days
        ]
        let stats = WidgetSnapshot.Stats.compute(brews, now: now, calendar: calendar)
        XCTAssertEqual(stats.brewsToday, 2)
        XCTAssertEqual(stats.perDay, [0, 0, 1, 0, 1, 1, 2], "Nov 4 … Nov 10, today last")
        XCTAssertEqual(stats.weekTotal, 5)
        XCTAssertEqual(stats.streak, 3)
        XCTAssertEqual(stats.averageRating ?? 0, (4 + 5 + 3 + 2) / 4.0, accuracy: 0.001, "unrated brews don't count")
        XCTAssertEqual(stats.lastRating, 0, "the newest brew wasn't rated")
    }

    func testStreakSurvivesUntilTheEndOfToday() {
        let brews: [(date: Date, rating: Int)] = [(date(9), 4), (date(8), 4)]
        XCTAssertEqual(WidgetSnapshot.Stats.compute(brews, now: date(10, 7), calendar: calendar).streak, 2,
                       "no coffee yet today doesn't break the streak")
        XCTAssertEqual(WidgetSnapshot.Stats.compute(brews, now: date(11, 7), calendar: calendar).streak, 0)
        XCTAssertEqual(WidgetSnapshot.Stats.compute([], now: date(10), calendar: calendar).weekTotal, 0)
    }

    func testCupsLeftAndFreshness() {
        var bean = WidgetSnapshot.BeanInfo(name: "Guji", roaster: "", roastDate: date(1), remaining: 160, bagWeight: 250, lastDose: 15)
        XCTAssertEqual(bean.cupsLeft, 10)
        XCTAssertEqual(bean.freshness(now: date(3), calendar: calendar), .resting)
        XCTAssertEqual(bean.freshness(now: date(10), calendar: calendar), .peak)
        XCTAssertEqual(bean.freshness(now: date(1).addingTimeInterval(40 * 86_400), calendar: calendar), .pastPeak)
        bean.lastDose = nil
        XCTAssertNil(bean.cupsLeft, "no brew yet: show grams instead")
        bean.lastDose = 18
        bean.remaining = -5
        XCTAssertEqual(bean.cupsLeft, 0)
    }

    func testOlderSnapshotsStillDecode() throws {
        // A snapshot written before activity/setup/lastDose existed.
        let json = #"{"brewsThisWeek":3,"updated":0,"bean":{"name":"Guji","roaster":"","remaining":100,"bagWeight":250}}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.activity)
        XCTAssertNil(snapshot.stats())
        XCTAssertNil(snapshot.bean?.cupsLeft)
        XCTAssertEqual(AppLink(url: URL(string: "brewlog://start")!), .start)
    }
}
