import XCTest
@testable import BrewLog

/// Grind remembered per grinder and starting values. No SwiftData, so these also run on Linux.
final class GrindMemoryTests: XCTestCase {
    let clicks = GrinderSpec(unit: .clicks, step: 1, adjustStep: 2, rangeNote: "20–30 clicks")
    let dial = GrinderSpec(unit: .dial, step: 0.1, adjustStep: 0.2)

    func testStartingValues() {
        XCTAssertEqual(GrinderSpec(unit: .clicks, defaultGrind: 24).startingValue, 24, "explicit default first")
        XCTAssertEqual(clicks.startingValue, 25, "middle of the typical range")
        XCTAssertEqual(GrinderSpec(unit: .clicks, rangeNote: "about 14–20 clicks").startingValue, 17)
        XCTAssertEqual(GrinderSpec(unit: .dial, step: 0.1, rangeNote: "3-4").startingValue, 3.5, accuracy: 0.0001)
        XCTAssertEqual(GrinderSpec(unit: .clicks, rangeNote: "fine").startingValue, 20)
        XCTAssertEqual(GrinderSpec(unit: .numbers, step: 0.1).startingValue, 6)
        XCTAssertEqual(GrinderSpec(unit: .numbers, step: 1).startingValue, 15)
        XCTAssertEqual(dial.startingValue, 5)
        XCTAssertEqual(GrinderSpec(unit: .microns, step: 10).startingValue, 600)
    }

    func testEachGrinderKeepsItsOwnSetting() {
        let a = UUID(), b = UUID()
        var memory = GrindMemory()
        memory.remember(26, grinder: a)
        memory.remember(7.5, grinder: b)
        XCTAssertEqual(memory.grind(for: a, spec: clicks, recommendation: nil, lastBrew: nil, espresso: false), 26)
        XCTAssertEqual(memory.grind(for: b, spec: dial, recommendation: nil, lastBrew: nil, espresso: false), 7.5)
        XCTAssertEqual(memory.grind(for: UUID(), spec: dial, recommendation: nil, lastBrew: nil, espresso: false), 5,
                       "a new grinder starts at its starting value")
        XCTAssertNil(memory.grind(for: UUID(), spec: dial, recommendation: nil, lastBrew: nil, espresso: true),
                     "no filter starting value for espresso")
    }

    func testHandSetGrindVersusHistory() {
        let grinder = UUID()
        let set = Date(timeIntervalSince1970: 1_000)
        var memory = GrindMemory()
        memory.remember(26, grinder: grinder, at: set)
        XCTAssertEqual(memory.grind(for: grinder, spec: clicks, recommendation: 22, lastBrew: set.addingTimeInterval(-60),
                                    espresso: false), 26, "set by hand after the last brew wins")
        XCTAssertEqual(memory.grind(for: grinder, spec: clicks, recommendation: 22, lastBrew: set.addingTimeInterval(60),
                                    espresso: false), 22, "a newer brew's recommendation wins")
        XCTAssertEqual(memory.grind(for: UUID(), spec: clicks, recommendation: 22, lastBrew: nil, espresso: false), 22)
    }

    func testIgnoresInvalidValuesAndRoundTrips() throws {
        var memory = GrindMemory()
        memory.remember(.nan, grinder: UUID())
        XCTAssertTrue(memory.entries.isEmpty)
        let grinder = UUID()
        memory.remember(3.4, grinder: grinder, at: Date(timeIntervalSince1970: 1_000))
        let copy = try JSONDecoder().decode(GrindMemory.self, from: JSONEncoder().encode(memory))
        XCTAssertEqual(copy, memory)
        XCTAssertEqual(copy.entry(for: grinder)?.value, 3.4)
    }
}
