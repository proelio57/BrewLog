import XCTest
@testable import BrewLog

/// Learning when to stop: what still dripped in after the stop, divided by the flow at the stop.
final class StopLagLearnerTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

    func testMeasuredLagIsWhatArrivedAfterTheStopOverTheFlow() throws {
        // Stopped at 33 g with 2 g/s, ended at 36.6 g: 3.6 g came after the stop, 1.8 s worth of flow.
        let lag = try XCTUnwrap(StopLagLearner.measuredLag(weightAtStop: 33, flowAtStop: 2, finalWeight: 36.6))
        XCTAssertEqual(lag, 1.8, accuracy: 0.001)
    }

    func testShotsThatCantTeachAreSkipped() {
        XCTAssertNil(StopLagLearner.measuredLag(weightAtStop: 33, flowAtStop: 0.2, finalWeight: 36))   // too little flow
        XCTAssertNil(StopLagLearner.measuredLag(weightAtStop: 33, flowAtStop: 2, finalWeight: 20))    // cup moved
        XCTAssertNil(StopLagLearner.measuredLag(weightAtStop: 33, flowAtStop: 2, finalWeight: 60))    // implausible jump
    }

    func testTheLagStaysInRange() throws {
        XCTAssertEqual(try XCTUnwrap(StopLagLearner.measuredLag(weightAtStop: 33, flowAtStop: 2, finalWeight: 33)), 0.3)
        XCTAssertEqual(StopLagLearner.updated(current: 2.9, measured: 5), 3.0)
    }

    func testEachShotMovesHalfwayAndCounts() {
        let store = defaults()
        let key = StopLagLearner.key(machine: .gaggimate, scaleOnMachine: false)
        // Started at 1.0 s; the shot wanted 1.8 s → 1.4 s.
        XCTAssertEqual(StopLagLearner.record(key: key, start: 1.0, weightAtStop: 33, flowAtStop: 2, finalWeight: 36.6, store)!,
                       1.4, accuracy: 0.001)
        XCTAssertEqual(StopLagLearner.record(key: key, start: 1.0, weightAtStop: 33, flowAtStop: 2, finalWeight: 36.6, store)!,
                       1.6, accuracy: 0.001)
        XCTAssertEqual(StopLagLearner.learned(for: key, store)?.shots, 2)
        XCTAssertEqual(StopLagLearner.lag(for: key, manual: 1.0, learning: true, store), 1.6, accuracy: 0.001)
        XCTAssertEqual(StopLagLearner.lag(for: key, manual: 1.0, learning: false, store), 1.0)
        // The scale on the machine learns on its own.
        let other = StopLagLearner.key(machine: .gaggimate, scaleOnMachine: true)
        XCTAssertEqual(StopLagLearner.lag(for: other, manual: 1.0, learning: true, store), 1.0)
        StopLagLearner.reset(store)
        XCTAssertNil(StopLagLearner.learned(for: key, store))
    }

    func testTheMonitorRemembersWeightAndFlowAtTheStop() {
        var monitor = ShotMonitor(yield: 36, dose: 18, stopLag: 1.0, autoStop: true)
        XCTAssertEqual(monitor.ingest(grams: 30, flow: 2, at: 20), .none)
        XCTAssertEqual(monitor.ingest(grams: 34.2, flow: 2, at: 22), .stop)
        XCTAssertEqual(monitor.weightAtStop, 34.2)
        XCTAssertEqual(monitor.flowAtStop, 2)
    }
}
