import XCTest
@testable import BrewLog

final class WhatsNewTests: XCTestCase {
    private let notes = WhatsNew(version: "2.14.0", ios: ["Compact brew tab"])

    func testShownOnceAfterAnUpdate() {
        XCTAssertEqual(WhatsNew.pending(notes, installedVersion: "2.14.0", lastSeen: "2.13.0", onboardingDone: true), notes)
        XCTAssertNil(WhatsNew.pending(notes, installedVersion: "2.14.0", lastSeen: "2.14.0", onboardingDone: true))
    }

    func testAnExistingInstallThatNeverSawItGetsIt() {
        XCTAssertEqual(WhatsNew.pending(notes, installedVersion: "2.14.0", lastSeen: nil, onboardingDone: true), notes)
    }

    func testNothingOnAFreshInstall() {
        XCTAssertNil(WhatsNew.pending(notes, installedVersion: "2.14.0", lastSeen: nil, onboardingDone: false))
    }

    func testNothingWhenTheReleaseDidNotChangeIOS() {
        let none = WhatsNew(version: "2.14.0", ios: [])
        XCTAssertNil(WhatsNew.pending(none, installedVersion: "2.14.0", lastSeen: "2.13.0", onboardingDone: true))
    }

    func testNothingForNotesOfAnotherVersion() {
        XCTAssertNil(WhatsNew.pending(notes, installedVersion: "0.1", lastSeen: nil, onboardingDone: true))
        XCTAssertNil(WhatsNew.pending(nil, installedVersion: "2.14.0", lastSeen: nil, onboardingDone: true))
    }

    func testDecodesTheGeneratedFile() throws {
        let json = #"{"version":"2.14.0","ios":["A"],"android":[],"web":[]}"#
        XCTAssertEqual(try JSONDecoder().decode(WhatsNew.self, from: Data(json.utf8)).ios, ["A"])
    }
}

final class AccentChoiceTests: XCTestCase {
    func testEveryChoiceHasDistinctColors() {
        let lights = Set(AccentChoice.allCases.map { $0.hex.light })
        XCTAssertEqual(lights.count, AccentChoice.allCases.count)
        XCTAssertEqual(AccentChoice.allCases.first, .copper)
    }

    func testAppearanceModes() {
        XCTAssertNil(AppearanceMode.system.colorScheme)
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
        XCTAssertEqual(AppearanceMode(rawValue: "light"), .light)
    }
}
