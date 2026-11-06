import XCTest
@testable import BrewLog

/// Settings → Pressure view: when the shot screen shows the big pressure number and graph, and its colours.
final class PressureFocusTests: XCTestCase {

    func testAutomaticFollowsTheSensor() {
        XCTAssertTrue(PressureFocus.isActive(mode: .automatic, sensorIsSource: true, hasPressure: true))
        XCTAssertFalse(PressureFocus.isActive(mode: .automatic, sensorIsSource: false, hasPressure: true))
    }

    func testAlwaysNeedsAPressureSource() {
        XCTAssertTrue(PressureFocus.isActive(mode: .always, sensorIsSource: false, hasPressure: true))
        XCTAssertFalse(PressureFocus.isActive(mode: .always, sensorIsSource: false, hasPressure: false))
    }

    func testOffNeverFocuses() {
        XCTAssertFalse(PressureFocus.isActive(mode: .off, sensorIsSource: true, hasPressure: true))
    }

    func testZones() {
        XCTAssertEqual(PressureFocus.zone(pressure: 7.9, target: 9), .low)
        XCTAssertEqual(PressureFocus.zone(pressure: 9.2, target: 9), .onTarget)
        XCTAssertEqual(PressureFocus.zone(pressure: 10.1, target: 9), .high)
    }

    func testZoneBoundariesAreOnTarget() {
        XCTAssertEqual(PressureFocus.zone(pressure: 8.5, target: 9), .onTarget)
        XCTAssertEqual(PressureFocus.zone(pressure: 9.5, target: 9), .onTarget)
        XCTAssertEqual(PressureFocus.zone(pressure: 5.6, target: 6.1), .onTarget)
    }

    func testZoneWithoutTarget() {
        XCTAssertEqual(PressureFocus.zone(pressure: 9, target: nil), .noTarget)
        XCTAssertEqual(PressureFocus.zone(pressure: nil, target: 9), .noTarget)
        XCTAssertEqual(PressureFocus.zone(pressure: .nan, target: 9), .noTarget)
    }

    func testUnknownStoredModeFallsBackToAutomatic() {
        XCTAssertEqual(PressureFocusMode(rawValue: "bogus") ?? .automatic, .automatic)
        XCTAssertEqual(PressureFocusMode(rawValue: "always"), .always)
    }

    func testFocusIsLatchedForTheShot() {
        var latch = PressureFocusLatch()
        // Before the shot it follows the sensor.
        XCTAssertTrue(latch.value(live: true))
        XCTAssertFalse(latch.value(live: false))
        // The shot starts with the sensor connected; it drops out mid-shot: the layout stays.
        latch.latch(true)
        XCTAssertTrue(latch.value(live: false))
        // The next shot starts without the sensor.
        latch.latch(false)
        XCTAssertFalse(latch.value(live: true))
    }
}
