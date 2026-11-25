import XCTest
@testable import BrewLog

final class StopConfirmationTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testTheFirstTapOnlyArms() {
        var stop = StopConfirmation()
        XCTAssertEqual(stop.tap(now: t0), .arm)
        XCTAssertTrue(stop.isArmed(now: t0.addingTimeInterval(1)))
    }

    func testADoubleTapDoesNotStop() {
        var stop = StopConfirmation()
        _ = stop.tap(now: t0)
        XCTAssertEqual(stop.tap(now: t0.addingTimeInterval(0.2)), .ignore)
        XCTAssertTrue(stop.isArmed(now: t0.addingTimeInterval(0.3)))
    }

    func testASecondDeliberateTapStops() {
        var stop = StopConfirmation()
        _ = stop.tap(now: t0)
        XCTAssertEqual(stop.tap(now: t0.addingTimeInterval(1.5)), .stop)
        XCTAssertFalse(stop.isArmed(now: t0.addingTimeInterval(1.6)))
    }

    func testTheArmedStateRunsOut() {
        var stop = StopConfirmation()
        _ = stop.tap(now: t0)
        XCTAssertFalse(stop.isArmed(now: t0.addingTimeInterval(StopConfirmation.timeout + 0.1)))
        XCTAssertEqual(stop.tap(now: t0.addingTimeInterval(StopConfirmation.timeout + 0.1)), .arm)
    }
}
