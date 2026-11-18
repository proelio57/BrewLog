import XCTest
@testable import BrewLog

final class JournalFilterTests: XCTestCase {
    func testAllMatchesEverything() {
        let filter = JournalFilter()
        XCTAssertFalse(filter.isActive)
        XCTAssertTrue(filter.matches(isEspresso: true, isReviewed: true, bean: nil, recipe: "A"))
        XCTAssertTrue(filter.matches(isEspresso: false, isReviewed: false, bean: "B", recipe: "A"))
    }

    func testKind() {
        var filter = JournalFilter(kind: .espresso)
        XCTAssertTrue(filter.matches(isEspresso: true, isReviewed: true, bean: nil, recipe: "A"))
        XCTAssertFalse(filter.matches(isEspresso: false, isReviewed: true, bean: nil, recipe: "A"))
        filter.kind = .filter
        XCTAssertFalse(filter.matches(isEspresso: true, isReviewed: true, bean: nil, recipe: "A"))
        XCTAssertTrue(filter.matches(isEspresso: false, isReviewed: true, bean: nil, recipe: "A"))
    }

    func testToReviewBeanAndRecipeCombine() {
        let filter = JournalFilter(kind: .all, toReview: true, bean: "Booze Cruise · DAK", recipe: "9 Bar Espresso")
        XCTAssertTrue(filter.isActive)
        XCTAssertTrue(filter.matches(isEspresso: true, isReviewed: false, bean: "Booze Cruise · DAK", recipe: "9 Bar Espresso"))
        XCTAssertFalse(filter.matches(isEspresso: true, isReviewed: true, bean: "Booze Cruise · DAK", recipe: "9 Bar Espresso"))
        XCTAssertFalse(filter.matches(isEspresso: true, isReviewed: false, bean: nil, recipe: "9 Bar Espresso"))
        XCTAssertFalse(filter.matches(isEspresso: true, isReviewed: false, bean: "Booze Cruise · DAK", recipe: "Other"))
    }

    func testOptionsMostFrequentFirst() {
        XCTAssertEqual(JournalFilter.options(["B", "A", nil, "", "B", "C", "A", "B"]), ["B", "A", "C"])
    }
}
