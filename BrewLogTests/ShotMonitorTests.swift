import XCTest
@testable import BrewLog

/// Stopping and finishing an espresso shot, live numbers and GaggiMate's settings. Foundation only, so these also
/// run on Linux (scripts/test-pure-swift.sh).
final class ShotMonitorTests: XCTestCase {
    func testStopsAheadOfTheYield() {
        XCTAssertTrue(ShotMonitor.shouldStop(weight: 34.2, flow: 2.0, yield: 36, lag: 1.0))   // 36.2 ≥ 36
        XCTAssertFalse(ShotMonitor.shouldStop(weight: 33.5, flow: 2.0, yield: 36, lag: 1.0))  // 35.5
    }

    func testStopsOnceAndIgnoresNegativeFlow() {
        var m = ShotMonitor(yield: 36, dose: 18, stopLag: 1.0, autoStop: true)
        XCTAssertEqual(m.ingest(grams: 35.9, flow: -5, at: 20), .none)   // bump: negative flow counts as 0
        XCTAssertEqual(m.ingest(grams: 36.0, flow: 1.5, at: 20.1), .stop)
        XCTAssertEqual(m.ingest(grams: 37.0, flow: 1.5, at: 20.2), .none)  // only once
    }

    func testFinishesWhenSettledAfterNinetyPercent() {
        var m = ShotMonitor(yield: 36, dose: 18, stopLag: 1.0, autoStop: false)
        var actions: [ShotMonitor.Action] = []
        for i in 0..<8 { actions.append(m.ingest(grams: 33.0 + (i.isMultiple(of: 2) ? 0.1 : 0), flow: 0, at: 30 + Double(i) * 0.2)) }
        // 33 g ≥ 32.4 (90 %), settled within ±0.3 g after 4 readings — and only once.
        XCTAssertEqual(actions.filter { $0 == .finish }.count, 1)
        XCTAssertEqual(actions.firstIndex(of: .finish), 3)
    }

    func testNotFinishedBelowNinetyPercent() {
        var m = ShotMonitor(yield: 36, dose: 18, stopLag: 1.0, autoStop: false)
        for i in 0..<10 { XCTAssertEqual(m.ingest(grams: 20, flow: 0, at: Double(i) * 0.2), .none) }
    }

    func testFirstDropsAndLiveRatio() {
        var m = ShotMonitor(yield: 36, dose: 18, stopLag: 1.0, autoStop: true)
        _ = m.ingest(grams: 0.4, flow: 0.2, at: 5)
        _ = m.ingest(grams: 1.2, flow: 0.8, at: 6.5)
        XCTAssertEqual(m.firstDropsTime, 6.5)
        XCTAssertEqual(m.liveRatio ?? 0, 1.2 / 18, accuracy: 0.0001)
    }

    func testNoYieldNoStop() {
        var m = ShotMonitor(yield: 0, dose: 0, stopLag: 1.0, autoStop: true)
        XCTAssertEqual(m.ingest(grams: 50, flow: 3, at: 10), .none)
        XCTAssertNil(m.liveRatio)
    }

    func testGaggiMateWins() {
        XCTAssertEqual(ShotMonitor.shotTemperature(recipe: 93, machineTarget: 91, measuredAverage: 90.4), 91)
        XCTAssertEqual(ShotMonitor.shotTemperature(recipe: 93, machineTarget: nil, measuredAverage: 90.4), 90.4)
        XCTAssertEqual(ShotMonitor.shotTemperature(recipe: 93, machineTarget: 0, measuredAverage: nil), 93) // implausible
        XCTAssertEqual(ShotMonitor.targetPressure(recipe: 9, machineTarget: 6), 6)
        XCTAssertEqual(ShotMonitor.targetPressure(recipe: 9, machineTarget: nil), 9)
    }

    func testNoReadingsNoDecision() {
        XCTAssertFalse(ShotMonitor.isSettled([], now: 10))
        XCTAssertFalse(ShotMonitor.isSettled([(t: 9.9, grams: 30), (t: 10, grams: 30)], now: 10)) // < 4 readings
    }
}
