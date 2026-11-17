import XCTest
@testable import BrewLog

/// Switching the machine off and on: the plug countdown, auto-off, "ready" and the question after steaming.
final class PowerRulesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let settings = PowerRules.Settings(plugConfigured: true, plugOffInStandby: true, countdown: 30, autoOff: 0)

    private func input(_ mode: Int?, connected: Bool = true, process: Bool = false,
                       temp: Double? = nil, target: Double? = nil) -> PowerRules.Input {
        PowerRules.Input(connected: connected, mode: mode, processActive: process,
                         temperature: temp, targetTemperature: target)
    }

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testStandbyStartsTheCountdownAndThePlugGoesOffWhenItRunsOut() {
        var rules = PowerRules(now: t0)
        XCTAssertEqual(rules.update(input(1), settings: settings, now: at(0)), [])
        XCTAssertEqual(rules.update(input(0), settings: settings, now: at(1)), [])
        XCTAssertEqual(rules.secondsLeft(now: at(1)), 30)
        XCTAssertEqual(rules.update(input(0), settings: settings, now: at(30)), [])
        XCTAssertEqual(rules.update(input(0), settings: settings, now: at(31)), [.plugOff])
        XCTAssertFalse(rules.countdownRunning)
    }

    func testLeavingStandbyCancelsTheCountdown() {
        var rules = PowerRules(now: t0)
        _ = rules.update(input(1), settings: settings, now: at(0))
        _ = rules.update(input(0), settings: settings, now: at(1))
        XCTAssertEqual(rules.update(input(2), settings: settings, now: at(5)), [])
        XCTAssertFalse(rules.countdownRunning)
        XCTAssertEqual(rules.update(input(2), settings: settings, now: at(60)), [])
    }

    func testARunningProcessNeverLetsThePlugGoOff() {
        var rules = PowerRules(now: t0)
        rules.switchOff(settings: settings, now: at(0))
        XCTAssertTrue(rules.countdownRunning)
        XCTAssertEqual(rules.update(input(1, process: true), settings: settings, now: at(10)), [])
        XCTAssertFalse(rules.countdownRunning)
        XCTAssertEqual(rules.update(input(1), settings: settings, now: at(40)), [])
    }

    func testSwitchOffKeepsCountingWhileTheMachineStillReportsBrew() {
        var rules = PowerRules(now: t0)
        _ = rules.update(input(1), settings: settings, now: at(0))
        rules.switchOff(settings: settings, now: at(1))
        XCTAssertEqual(rules.update(input(1), settings: settings, now: at(2)), [])
        XCTAssertEqual(rules.update(input(0), settings: settings, now: at(3)), [])
        XCTAssertEqual(rules.secondsLeft(now: at(3)), 28)
        XCTAssertEqual(rules.update(input(0), settings: settings, now: at(31)), [.plugOff])
    }

    func testNoPlugOrSettingOffMeansNoCountdown() {
        var noPlug = PowerRules(now: t0)
        var s = settings
        s.plugConfigured = false
        _ = noPlug.update(input(1), settings: s, now: at(0))
        _ = noPlug.update(input(0), settings: s, now: at(1))
        XCTAssertFalse(noPlug.countdownRunning)

        var off = PowerRules(now: t0)
        s = settings
        s.plugOffInStandby = false
        _ = off.update(input(1), settings: s, now: at(0))
        _ = off.update(input(0), settings: s, now: at(1))
        XCTAssertFalse(off.countdownRunning)
    }

    func testTheFirstReadingInStandbyDoesNotSwitchThePlugOff() {
        // Opening the app while the machine already idles in standby isn't a change to standby.
        var rules = PowerRules(now: t0)
        XCTAssertEqual(rules.update(input(0), settings: settings, now: at(0)), [])
        XCTAssertFalse(rules.countdownRunning)
    }

    func testCancel() {
        var rules = PowerRules(now: t0)
        rules.switchOff(settings: settings, now: at(0))
        rules.cancelCountdown()
        XCTAssertEqual(rules.update(input(0), settings: settings, now: at(40)), [])
    }

    func testAutoOffAfterIdlingAndRestartedByActivity() {
        var s = settings
        s.autoOff = 15 * 60
        var rules = PowerRules(now: t0)
        _ = rules.update(input(1), settings: s, now: at(0))
        _ = rules.update(input(1, process: true), settings: s, now: at(600))
        XCTAssertEqual(rules.update(input(1), settings: s, now: at(600 + 899)), [])
        XCTAssertEqual(rules.update(input(1), settings: s, now: at(600 + 900)), [.standby])
        XCTAssertEqual(rules.update(input(1), settings: s, now: at(600 + 901)), [])
    }

    func testSwitchOnSetsBrewAndReportsReadyNearTheTarget() {
        var rules = PowerRules(now: t0)
        rules.switchOn(now: at(0))
        XCTAssertEqual(rules.update(input(nil, connected: false), settings: settings, now: at(5)), [])
        XCTAssertEqual(rules.update(input(0, temp: 25, target: 93), settings: settings, now: at(20)), [.setBrew])
        XCTAssertEqual(rules.update(input(0, temp: 26, target: 93), settings: settings, now: at(21)), [])
        XCTAssertEqual(rules.update(input(1, temp: 90, target: 93), settings: settings, now: at(200)), [])
        XCTAssertEqual(rules.update(input(1, temp: 91, target: 93), settings: settings, now: at(260)), [.ready])
        XCTAssertFalse(rules.waitingForReady)
    }

    func testAsksToSwitchOffOnceWhenSteamingIsDone() {
        var rules = PowerRules(now: t0)
        _ = rules.update(input(1), settings: settings, now: at(0))
        rules.steamChosen()
        _ = rules.update(input(2), settings: settings, now: at(1))
        XCTAssertEqual(rules.update(input(1), settings: settings, now: at(120)), [.askSwitchOff])
        _ = rules.update(input(2), settings: settings, now: at(130))
        XCTAssertEqual(rules.update(input(1), settings: settings, now: at(200)), [])
    }
}
