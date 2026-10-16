import Foundation

/// One reading from the espresso machine during a shot, stored with the brew.
struct MachineSample: Codable, Hashable {
    /// Seconds since the shot started.
    var t: Double
    /// Pressure in bar.
    var p: Double
    /// Brew temperature in °C.
    var c: Double?
    /// Pump flow in ml/s.
    var f: Double?
}

/// Live state of a GaggiMate controller, built from its WebSocket `evt:status` frames
/// (see GaggiMate's `docs/websocket-api.yaml`).
///
/// Frames are partial: fast telemetry (temperature, pressure, flow, process) every 500 ms and the slow state
/// (mode, profile) when it changes. A key that is missing keeps its value, a key sent as null clears it.
struct GaggiMateStatus: Equatable {
    var temperature: Double?
    var targetTemperature: Double?
    var pressure: Double?
    var targetPressure: Double?
    var flow: Double?
    /// 0 standby, 1 brew, 2 steam, 3 water, 4 grind.
    var mode: Int?
    var profile: String?
    /// Whether the machine has a pressure sensor.
    var hasPressure: Bool?
    var processActive = false
    /// "brew", "infusion" or "grind".
    var processKind: String?
    var processLabel: String?
    /// Flush, backflush or descaling, which isn't a shot.
    var processIsUtility = false
    /// Weight from the scale connected to GaggiMate (if any), in grams.
    var weight: Double?
    /// A Bluetooth scale is connected to GaggiMate.
    var scaleConnected = false
    /// "ready", "starting", "waiting", "error" …
    var systemState: String?
    var systemMessage: String?

    /// Weight can be read from the machine (its own scale connection).
    var hasWeight: Bool { scaleConnected && weight != nil }

    /// A shot is running (pre-infusion or extraction), not a flush or grind.
    var isBrewing: Bool {
        processActive && !processIsUtility && (processKind == "brew" || processKind == "infusion")
    }

    /// Parses a WebSocket text message. Returns the frame if it's an `evt:status`.
    static func statusFrame(_ text: String) -> [String: Any]? {
        guard text.utf8.count <= 64 * 1024,
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              object["tp"] as? String == "evt:status" else { return nil }
        return object
    }

    /// True if the frame carries live readings (as opposed to the slow state).
    static func isTelemetry(_ frame: [String: Any]) -> Bool { frame["pr"] != nil || frame["ct"] != nil }

    mutating func merge(_ frame: [String: Any]) {
        func number(_ key: String, _ value: inout Double?, range: ClosedRange<Double>) {
            guard frame.keys.contains(key) else { return }
            if let n = (frame[key] as? NSNumber)?.doubleValue, n.isFinite {
                value = min(max(n, range.lowerBound), range.upperBound)
            } else {
                value = nil
            }
        }
        number("ct", &temperature, range: 0...200)
        number("tt", &targetTemperature, range: 0...200)
        number("pr", &pressure, range: 0...20)
        number("pt", &targetPressure, range: 0...20)
        number("fl", &flow, range: 0...30)
        number("cw", &weight, range: -100...5000)
        if frame.keys.contains("bc") { scaleConnected = (frame["bc"] as? NSNumber)?.boolValue ?? false }
        if let sys = frame["sys"] as? [String: Any] {
            systemState = (sys["s"] as? String).map { String($0.prefix(20)) }
            systemMessage = (sys["m"] as? String).map { String($0.prefix(200)) }
        }
        if frame.keys.contains("m") { mode = (frame["m"] as? NSNumber)?.intValue }
        if frame.keys.contains("p") { profile = (frame["p"] as? String).map { String($0.prefix(80)) } }
        if frame.keys.contains("cp") { hasPressure = (frame["cp"] as? NSNumber)?.boolValue }
        if frame.keys.contains("process") {
            if let process = frame["process"] as? [String: Any] {
                processActive = (process["a"] as? NSNumber)?.intValue == 1
                processKind = process["s"] as? String
                processLabel = (process["l"] as? String).map { String($0.prefix(80)) }
                processIsUtility = (process["u"] as? NSNumber)?.intValue == 1
            } else {
                processActive = false
                processKind = nil
                processLabel = nil
                processIsUtility = false
            }
        }
    }
}

enum MachineMode: Int, CaseIterable, Identifiable {
    case standby = 0, brew = 1, steam = 2, water = 3
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .standby: return "Standby"
        case .brew: return "Brew"
        case .steam: return "Steam"
        case .water: return "Water"
        }
    }
}

/// Builds a GaggiMate profile (schema `profile.json` in the GaggiMate repo) from an espresso recipe.
enum GaggiMateProfile {
    static let labelPrefix = "BrewLog · "

    /// - Parameters:
    ///   - hasPressure: the machine has a pressure sensor, so pressure-controlled phases are possible.
    ///   - hasScale: a scale is connected to GaggiMate, so the shot can stop at the target weight.
    static func make(recipe: Recipe, dose: Double, temperature: Double, hasPressure: Bool, hasScale: Bool) -> [String: Any] {
        let scaled = recipe.scaled(toDose: dose)
        let yield = scaled.water.rounded()
        let extractStart = recipe.steps.first { $0.kind == .extract }?.time ?? 0
        let preinfusion = hasPressure ? max(extractStart - 2, 0).rounded() : 0
        let pressure = min(max(recipe.pressure ?? 9, 1), 12)

        var phases: [[String: Any]] = []
        if preinfusion >= 1 {
            phases.append([
                "name": "Pre-infusion",
                "phase": "preinfusion",
                "valve": 1,
                "duration": preinfusion,
                "pump": ["target": "pressure", "pressure": 3, "flow": 4] as [String: Any],
            ])
        }
        var brew: [String: Any] = [
            "name": "Extraction",
            "phase": "brew",
            "valve": 1,
            // With a scale the weight ends the shot and the duration is only a safety cap.
            "duration": hasScale ? (recipe.targetTime + 20).rounded() : max(recipe.targetTime - preinfusion, 5).rounded(),
            "pump": hasPressure ? ["target": "pressure", "pressure": pressure, "flow": 0] as [String: Any] : 100,
        ]
        if hasPressure {
            brew["transition"] = ["type": "linear", "duration": 2, "adaptive": true] as [String: Any]
        }
        if hasScale {
            brew["targets"] = [["type": "volumetric", "operator": "gte", "value": yield] as [String: Any]]
        }
        phases.append(brew)

        return [
            "label": String((labelPrefix + recipe.name).prefix(60)),
            "type": "pro",
            "description": String(format: "From BrewLog: %.1f g in, %.0f g out, about %.0f s.", dose, yield, recipe.targetTime),
            "temperature": min(max(temperature.rounded(), 80), 100),
            "dose": min(max(dose, 1), 100),
            "phases": phases,
        ]
    }
}

/// Normalizes what the user typed as the machine address: "gaggimate.local", "192.168.1.20",
/// "http://gaggimate.local/" → WebSocket URL. Returns nil for anything that isn't a plain host name or IP.
func gaggiMateURL(host input: String) -> URL? {
    var host = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    for prefix in ["http://", "https://", "ws://", "wss://"] where host.hasPrefix(prefix) {
        host.removeFirst(prefix.count)
    }
    while host.hasSuffix("/") { host.removeLast() }
    if host.hasSuffix("/ws") { host.removeLast(3) }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-:")
    guard !host.isEmpty, host.count <= 253, host.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
    return URL(string: "ws://\(host)/ws")
}
