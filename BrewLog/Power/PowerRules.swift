import Foundation

/// When BrewLog switches the espresso machine and its smart plug: the countdown before the plug goes off,
/// auto-off after idling, switching on and "ready", the follow-up question after steaming.
/// Pure state machine (no timers, no I/O) so it can be tested with a fake clock; `MachinePower` drives it.
struct PowerRules {
    struct Input {
        var connected: Bool
        /// 0 standby, 1 brew, 2 steam, 3 water (`MachineMode`); nil when unknown.
        var mode: Int?
        var processActive: Bool
        var temperature: Double?
        var targetTemperature: Double?
    }

    struct Settings: Equatable {
        /// A smart plug is set up.
        var plugConfigured: Bool
        /// Switch the plug off when the machine is in standby.
        var plugOffInStandby: Bool
        /// Seconds between standby and the plug going off.
        var countdown: TimeInterval
        /// Switch off after this long without a shot or mode change; 0 = never.
        var autoOff: TimeInterval
    }

    enum Action: Equatable {
        /// Switch the plug off (the countdown ran out).
        case plugOff
        /// Put the machine into standby (auto-off).
        case standby
        /// The machine came on after "Switch on" but is in standby: set it to brew so it heats up.
        case setBrew
        /// The machine is within `readyMargin` of its brew temperature after "Switch on".
        case ready
        /// Steaming is done (steam → brew): ask once whether to switch off.
        case askSwitchOff
    }

    /// "Ready" when the boiler is this close below its target.
    static let readyMargin = 2.0

    /// When the plug goes off; nil when no countdown runs.
    private(set) var countdownEnd: Date?
    /// Last shot, mode change or switch-on, for auto-off.
    private(set) var lastActivity: Date
    /// "Switch on" is waiting for the machine to connect and heat up.
    private(set) var waitingForReady = false
    /// The user switched to steam after a shot; ask about switching off when steaming is done.
    private(set) var steamFollowUp = false
    private var lastMode: Int?

    init(now: Date) {
        lastActivity = now
    }

    var countdownRunning: Bool { countdownEnd != nil }

    func secondsLeft(now: Date) -> Int? {
        countdownEnd.map { max(0, Int($0.timeIntervalSince(now).rounded(.up))) }
    }

    /// Feed the current machine state (about once a second). Returns what to do now.
    mutating func update(_ input: Input, settings: Settings, now: Date) -> [Action] {
        var actions: [Action] = []
        let mode = input.connected ? input.mode : nil
        let modeChanged = mode != nil && mode != lastMode
        let standby = MachineMode.standby.rawValue

        if input.processActive || modeChanged { lastActivity = now }

        // Back in use: never cut the power. (Not on "mode isn't standby" alone: after "Switch off" the machine
        // still reports brew for a moment.)
        if input.processActive || (modeChanged && mode != standby) {
            countdownEnd = nil
        }

        // Standby from anywhere (the machine's own timeout, its button, another app).
        if modeChanged, mode == standby, lastMode != nil, !input.processActive {
            startCountdown(settings: settings, now: now)
        }

        if modeChanged, lastMode == MachineMode.steam.rawValue, mode == MachineMode.brew.rawValue, steamFollowUp {
            steamFollowUp = false
            actions.append(.askSwitchOff)
        }
        if modeChanged, mode == standby { steamFollowUp = false }

        if waitingForReady, let mode {
            if mode == standby {
                if modeChanged || lastMode == nil { actions.append(.setBrew) }
            } else if let t = input.temperature, let target = input.targetTemperature, target > 0,
                      t >= target - Self.readyMargin {
                waitingForReady = false
                actions.append(.ready)
            }
        }

        if settings.autoOff > 0, let mode, mode != standby, !input.processActive, !waitingForReady,
           now.timeIntervalSince(lastActivity) >= settings.autoOff {
            lastActivity = now
            actions.append(.standby)
        }

        if let end = countdownEnd, now >= end {
            countdownEnd = nil
            actions.append(.plugOff)
        }

        if mode != nil { lastMode = mode }
        return actions
    }

    /// "Switch off" from BrewLog: standby is sent and the plug countdown starts right away.
    mutating func switchOff(settings: Settings, now: Date) {
        waitingForReady = false
        steamFollowUp = false
        startCountdown(settings: settings, now: now)
    }

    /// "Switch on": the plug goes on; wait for the machine to come up and heat.
    mutating func switchOn(now: Date) {
        countdownEnd = nil
        // The next reading counts as new, so a machine that comes up in standby is set to brew.
        lastMode = nil
        waitingForReady = true
        lastActivity = now
    }

    mutating func cancelCountdown() { countdownEnd = nil }

    /// The user chose steam after a shot.
    mutating func steamChosen() { steamFollowUp = true }

    private mutating func startCountdown(settings: Settings, now: Date) {
        guard settings.plugConfigured, settings.plugOffInStandby, countdownEnd == nil else { return }
        countdownEnd = now.addingTimeInterval(settings.countdown)
    }
}
