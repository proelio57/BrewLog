import Foundation

/// The Decent DE1's Bluetooth protocol (from decentespresso/de1app, `de1plus/binary.tcl`): decodes the state and
/// shot sample notifications into `MachineStatus` and encodes the requested-state commands. All values big-endian.
enum DecentProtocol {
    static let service = "0000A000-0000-1000-8000-00805F9B34FB"
    /// Write 1 byte: the state the machine should go to.
    static let requestedState = "0000A002-0000-1000-8000-00805F9B34FB"
    /// Notify: live readings, a few times per second.
    static let shotSample = "0000A00D-0000-1000-8000-00805F9B34FB"
    /// Read + notify: state and substate.
    static let stateInfo = "0000A00E-0000-1000-8000-00805F9B34FB"

    enum State: UInt8 {
        case sleep = 0, goingToSleep, idle, busy, espresso, steam, hotWater, shortCal, selfTest, longCal, descale,
             fatalError, initializing, noRequest, skipToNext, hotWaterRinse, steamRinse, refill, clean, inBootLoader,
             airPurge, schedIdle
    }

    enum Substate: UInt8 {
        case none = 0, heatWaterTank, heatWaterHeater, stabilizeMixTemp, preInfuse, pour, flush, steaming
    }

    struct Sample: Equatable {
        var pressure: Double
        var flow: Double
        var mixTemp: Double
        var headTemp: Double
        var targetMixTemp: Double
        var targetHeadTemp: Double
        var targetPressure: Double
        var targetFlow: Double
        var frame: Int
    }

    /// Decodes a ShotSample (19 bytes). Returns nil for a shorter packet.
    static func sample(_ data: Data) -> Sample? {
        let b = [UInt8](data)
        guard b.count >= 19 else { return nil }
        func u16(_ i: Int) -> Double { Double(UInt16(b[i]) << 8 | UInt16(b[i + 1])) }
        func u24(_ i: Int) -> Double { Double(UInt32(b[i]) << 16 | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2])) }
        return Sample(pressure: u16(2) / 4096,
                      flow: u16(4) / 4096,
                      mixTemp: u16(6) / 256,
                      headTemp: u24(8) / 65536,
                      targetMixTemp: u16(11) / 256,
                      targetHeadTemp: u16(13) / 256,
                      targetPressure: Double(b[15]) / 16,
                      targetFlow: Double(b[16]) / 16,
                      frame: Int(b[17]))
    }

    /// Decodes a StateInfo (2 bytes: state, substate). Returns nil for a shorter packet.
    static func state(_ data: Data) -> (state: UInt8, substate: UInt8)? {
        let b = [UInt8](data)
        guard b.count >= 2 else { return nil }
        return (b[0], b[1])
    }

    static func apply(state rawState: UInt8, substate: UInt8, to status: inout MachineStatus) {
        // An unknown (newer) state changes nothing but the process.
        let state = State(rawValue: rawState) ?? .noRequest
        switch state {
        case .sleep, .goingToSleep, .schedIdle: status.mode = MachineMode.standby.rawValue
        case .steam, .steamRinse: status.mode = MachineMode.steam.rawValue
        case .hotWater, .hotWaterRinse: status.mode = MachineMode.water.rawValue
        case .idle, .espresso, .busy: status.mode = MachineMode.brew.rawValue
        default: break
        }

        if substate >= 200 || state == .fatalError {
            status.systemState = "error"
            status.systemMessage = errorMessage(substate: substate, state: rawState)
            setProcess(nil, label: nil, utility: false, on: &status)
            return
        }
        status.systemState = state == .sleep ? "sleep" : "ready"
        status.systemMessage = nil

        let sub = Substate(rawValue: substate)
        switch state {
        case .espresso where sub == .preInfuse:
            setProcess("infusion", label: "Pre-infusion", utility: false, on: &status)
        case .espresso where sub == .pour:
            setProcess("brew", label: "Extraction", utility: false, on: &status)
        case .hotWaterRinse, .hotWater, .steam, .steamRinse, .clean, .descale:
            // Flush, hot water, steam, cleaning: the pump runs, but it isn't a shot.
            let running = sub == .pour || sub == .flush || sub == .steaming || sub == .preInfuse
            setProcess(running ? "brew" : nil, label: running ? "Flush" : nil, utility: true, on: &status)
        default:
            setProcess(nil, label: nil, utility: false, on: &status)
        }
    }

    static func apply(_ sample: Sample, to status: inout MachineStatus) {
        status.pressure = min(max(sample.pressure, 0), 20)
        status.flow = min(max(sample.flow, 0), 30)
        status.temperature = min(max(sample.headTemp, 0), 200)
        status.targetTemperature = sample.targetHeadTemp > 0 ? min(sample.targetHeadTemp, 200) : nil
        status.targetPressure = sample.targetPressure > 0 ? sample.targetPressure : nil
        status.hasPressure = true
    }

    static func command(for mode: MachineMode) -> Data {
        switch mode {
        case .standby: return Data([State.sleep.rawValue])
        case .brew: return Data([State.idle.rawValue])
        case .steam: return Data([State.steam.rawValue])
        case .water: return Data([State.hotWater.rawValue])
        }
    }

    static let startShot = Data([State.espresso.rawValue])
    static let stopShot = Data([State.idle.rawValue])

    private static func setProcess(_ kind: String?, label: String?, utility: Bool, on status: inout MachineStatus) {
        status.processActive = kind != nil
        status.processKind = kind
        status.processLabel = label
        status.processIsUtility = utility
    }

    private static func errorMessage(substate: UInt8, state: UInt8) -> String {
        switch substate {
        case 204: return "Temperature sensor error"
        case 205: return "Pressure sensor error"
        case 206: return "Water level error"
        default:
            return substate >= 200 ? "Machine error \(substate)" : "Machine error (state \(state))"
        }
    }
}
