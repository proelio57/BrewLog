import Foundation
import Observation
import UIKit
import UserNotifications

/// Switching the espresso machine off and on: standby on the machine, then its smart plug after a countdown;
/// auto-off after idling; switching on and saying when it's hot. The rules live in `PowerRules`; this class
/// feeds them the machine's state once a second and carries out what they return.
///
/// Only while BrewLog runs: iOS suspends the app in the background, so a machine that goes to standby on its own
/// while the phone is locked keeps its power until BrewLog is opened again.
@Observable
final class MachinePower {
    static let shared = MachinePower()

    /// Seconds until the plug goes off; nil when no countdown runs.
    private(set) var secondsLeft: Int?
    /// "GaggiMate is ready", shown for a moment after switching on.
    private(set) var readyMessage: String?
    /// Steaming after a shot is done: ask once whether to switch off.
    var askSwitchOff = false

    @ObservationIgnored private let machine: MachineManager
    @ObservationIgnored private var rules = PowerRules(now: Date())
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var readyClear: DispatchWorkItem?

    init(machine: MachineManager = .shared) {
        self.machine = machine
    }

    /// Machines BrewLog can put into standby and whose plug it switches.
    var isAvailable: Bool { [.gaggimate, .demo].contains(machine.kind) }

    var plug: SmartPlug? { ShortcutPlug.configured }

    /// The machine is on (connected and not in standby).
    var machineIsOn: Bool {
        machine.isConnected && (machine.status.mode ?? 0) != MachineMode.standby.rawValue
    }

    /// "Switch on" makes sense: the machine is in standby, or unreachable and a plug can switch it on.
    /// Unreachable counts as off: that's how it looks once the plug cut the power.
    var canSwitchOn: Bool { isAvailable && !machineIsOn && (machine.isConnected || plug != nil) }

    var canSwitchOff: Bool { isAvailable && machineIsOn }

    var settings: PowerRules.Settings {
        let d = UserDefaults.standard
        return PowerRules.Settings(plugConfigured: plug != nil,
                                   plugOffInStandby: d.bool(forKey: SettingsKey.powerPlugOffInStandby),
                                   countdown: max(0, d.double(forKey: SettingsKey.powerCountdown)),
                                   autoOff: max(0, d.double(forKey: SettingsKey.powerAutoOff)))
    }

    /// Call once at launch.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    func tick(now: Date = Date()) {
        guard isAvailable else {
            if secondsLeft != nil { rules.cancelCountdown(); secondsLeft = nil }
            return
        }
        // A countdown that ran out long ago (BrewLog was in the background) is dropped: switching the plug off
        // hours later, on opening the app, would be a surprise.
        if let end = rules.countdownEnd, now.timeIntervalSince(end) > 120 { rules.cancelCountdown() }
        let status = machine.status
        let input = PowerRules.Input(connected: machine.isConnected, mode: status.mode,
                                     processActive: status.processActive,
                                     temperature: status.temperature, targetTemperature: status.targetTemperature)
        for action in rules.update(input, settings: settings, now: now) { perform(action) }
        let left = rules.secondsLeft(now: now)
        if left != secondsLeft { secondsLeft = left }
    }

    /// Standby now, the plug after the countdown.
    func switchOff() {
        if machine.isConnected { machine.setMode(.standby) }
        rules.switchOff(settings: settings, now: Date())
        tick()
    }

    /// The plug on (if there is one), then brew mode, then "ready" when it's hot.
    func switchOn() {
        rules.switchOn(now: Date())
        if machine.isConnected, (machine.status.mode ?? 0) == MachineMode.standby.rawValue {
            machine.setMode(.brew)
        } else if !machine.isConnected {
            plug?.turnOn()
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        tick()
    }

    func cancelCountdown() {
        rules.cancelCountdown()
        secondsLeft = nil
    }

    /// The user chose steam after the shot: ask about switching off once steaming is done.
    func steamChosen() { rules.steamChosen() }

    private func perform(_ action: PowerRules.Action) {
        switch action {
        case .plugOff:
            plug?.turnOff()
        case .standby:
            machine.setMode(.standby)
        case .setBrew:
            machine.setMode(.brew)
        case .ready:
            announceReady()
        case .askSwitchOff:
            askSwitchOff = true
        }
    }

    private func announceReady() {
        let message = "\(machine.displayName) is ready"
        readyMessage = message
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        readyClear?.cancel()
        let clear = DispatchWorkItem { [weak self] in self?.readyMessage = nil }
        readyClear = clear
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: clear)
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = message
        content.body = "Heated up to brew temperature."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "machine.ready", content: content,
                                                                     trigger: nil))
    }
}
