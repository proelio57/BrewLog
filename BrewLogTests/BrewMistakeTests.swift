import XCTest
@testable import BrewLog

final class BrewMistakeTests: XCTestCase {
    func testAnEmptyShotIsAMistake() {
        XCTAssertEqual(BrewMistake.check(isEspresso: true, usedScale: true, totalTime: 0, finalWeight: 0, targetWater: 36), .tooShort)
    }

    func testAVeryShortShotIsAMistake() {
        XCTAssertEqual(BrewMistake.check(isEspresso: true, usedScale: false, totalTime: 5, finalWeight: 0, targetWater: 36), .tooShort)
    }

    func testHardlyAnyWeightIsAMistake() {
        XCTAssertEqual(BrewMistake.check(isEspresso: true, usedScale: true, totalTime: 25, finalWeight: 3, targetWater: 36), .tooLittle)
    }

    func testARealShotIsFine() {
        XCTAssertNil(BrewMistake.check(isEspresso: true, usedScale: true, totalTime: 28, finalWeight: 36, targetWater: 36))
    }

    func testWithoutAScaleTheWeightDoesNotCount() {
        XCTAssertNil(BrewMistake.check(isEspresso: true, usedScale: false, totalTime: 28, finalWeight: 0, targetWater: 36))
    }

    func testPourOversNeedMoreTime() {
        XCTAssertEqual(BrewMistake.check(isEspresso: false, usedScale: true, totalTime: 20, finalWeight: 240, targetWater: 240), .tooShort)
        XCTAssertNil(BrewMistake.check(isEspresso: false, usedScale: true, totalTime: 180, finalWeight: 240, targetWater: 240))
    }
}
