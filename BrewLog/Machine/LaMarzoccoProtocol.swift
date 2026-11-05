import Foundation

/// La Marzocco's cloud messages (see docs/la-marzocco-protocol.md): the machine list, the dashboard
/// (widgets → `MachineStatus`), tokens and the STOMP frames the dashboard WebSocket speaks. Pure Foundation.
enum LaMarzoccoProtocol {
    static let host = "lion.lamarzocco.io"
    static let apiBase = "https://lion.lamarzocco.io/api/customer-app"
    static let socketURL = "wss://lion.lamarzocco.io/ws/connect"
    /// Refresh the access token this long before it expires (it lasts about an hour).
    static let refreshMargin: TimeInterval = 10 * 60
    static let tokenLifetime: TimeInterval = 60 * 60

    struct Machine: Equatable, Identifiable, Codable {
        /// Serial number.
        let id: String
        let name: String
        let model: String
    }

    // MARK: REST

    /// Coffee machines from `GET /things` (grinders and entries without a serial are left out).
    static func machines(_ json: Data) -> [Machine] {
        guard json.count <= 1_000_000,
              let list = (try? JSONSerialization.jsonObject(with: json)) as? [[String: Any]] else { return [] }
        return list.prefix(20).compactMap { thing in
            guard (thing["type"] as? String ?? "CoffeeMachine") == "CoffeeMachine",
                  let serial = (thing["serialNumber"] as? String)?.sanitized(maxLength: 40), !serial.isEmpty else { return nil }
            let name = (thing["name"] as? String)?.sanitized(maxLength: 60) ?? ""
            let model = (thing["modelName"] as? String)?.sanitized(maxLength: 60) ?? ""
            return Machine(id: serial, name: name.isEmpty ? (model.isEmpty ? serial : model) : name, model: model)
        }
    }

    /// Access and refresh token from `/auth/signin` or `/auth/refreshtoken`.
    static func tokens(_ json: Data) -> (access: String, refresh: String)? {
        guard json.count <= 100_000,
              let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let access = object["accessToken"] as? String, !access.isEmpty,
              let refresh = object["refreshToken"] as? String, !refresh.isEmpty else { return nil }
        return (access, refresh)
    }

    /// The id of a command just sent (`POST …/command/…` answers `[{"id", "status"}]`); its result comes later
    /// in the dashboard's `commands`.
    static func commandID(_ json: Data) -> String? {
        guard json.count <= 100_000,
              let list = (try? JSONSerialization.jsonObject(with: json)) as? [[String: Any]] else { return nil }
        return list.first?["id"] as? String
    }

    static func needsRefresh(expiresAt: Date, now: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(now) < refreshMargin
    }

    // MARK: Dashboard

    /// Applies a dashboard (REST or WebSocket message) to the status. Returns whether the machine is online (nil when
    /// the message doesn't say) and the results of commands it mentions (command id → "Success", "Error", "Failed" or
    /// "Timeout"). Returns nil, changing nothing, for a message that isn't a dashboard (garbled or split frame).
    @discardableResult
    static func apply(dashboard json: Data, to status: inout MachineStatus) -> (connected: Bool?, commandResults: [String: String])? {
        guard json.count <= 1_000_000,
              let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else {
            return nil
        }
        let connected = object["connected"] as? Bool
        var results: [String: String] = [:]
        for command in (object["commands"] as? [[String: Any]] ?? []).prefix(50) {
            if let id = command["id"] as? String, let result = command["status"] as? String { results[id] = result }
        }
        // The machine has no pressure sensor or live temperature in the cloud data.
        status.hasPressure = false
        status.pressure = nil
        status.flow = nil

        for widget in (object["widgets"] as? [[String: Any]] ?? []).prefix(100) {
            guard let output = widget["output"] as? [String: Any] else { continue }
            switch widget["code"] as? String ?? "" {
            case "CMMachineStatus":
                applyMachineStatus(output, connected: connected != false, to: &status)
            case "CMCoffeeBoiler":
                applyBoiler(output, to: &status)
            default:
                break  // unknown or not needed
            }
        }
        if connected == false { setBrewing(false, on: &status) }
        return (connected, results)
    }

    private static func applyMachineStatus(_ output: [String: Any], connected: Bool, to status: inout MachineStatus) {
        let state = output["status"] as? String
        switch output["mode"] as? String ?? "" {
        case "StandBy": status.mode = MachineMode.standby.rawValue
        case "BrewingMode", "EcoMode": status.mode = MachineMode.brew.rawValue
        default: break
        }
        if state == "StandBy" || state == "Off" {
            status.mode = MachineMode.standby.rawValue
            status.systemState = "standby"
            status.systemMessage = nil
        } else if status.systemState == "standby" {
            status.systemState = "ready"
        }
        setBrewing(connected && state == "Brewing", on: &status)
    }

    private static func applyBoiler(_ output: [String: Any], to status: inout MachineStatus) {
        if let target = (output["targetTemperature"] as? NSNumber)?.doubleValue, target.isFinite, (50...130).contains(target) {
            status.targetTemperature = target
        }
        switch output["status"] as? String ?? "" {
        case "NoWater":
            status.systemState = "error"
            status.systemMessage = "No water in the tank"
        case "HeatingUp":
            status.systemState = "heating"
            status.systemMessage = nil
        case "Ready":
            status.systemState = "ready"
            status.systemMessage = nil
        default:
            break
        }
    }

    private static func setBrewing(_ brewing: Bool, on status: inout MachineStatus) {
        status.processActive = brewing
        status.processKind = brewing ? "brew" : nil
        status.processLabel = brewing ? "Brewing" : nil
        status.processIsUtility = false
    }

    // MARK: STOMP

    /// One STOMP frame: command, `key:value` headers, blank line, body, NUL.
    static func stompFrame(_ command: String, headers: [(String, String)], body: String = "") -> String {
        var lines = [command]
        lines += headers.map { "\($0.0):\($0.1)" }
        return lines.joined(separator: "\n") + "\n\n" + body + "\u{0}"
    }

    /// Splits a STOMP frame. Nil for empty text or a bare heart-beat newline.
    static func parseStomp(_ text: String) -> (command: String, headers: [String: String], body: String)? {
        var frame = text
        if frame.hasSuffix("\u{0}") { frame.removeLast() }
        let trimmedStart = frame.drop { $0 == "\n" || $0 == "\r" }
        guard !trimmedStart.isEmpty else { return nil }
        let parts = trimmedStart.components(separatedBy: "\n\n")
        let head = parts[0].components(separatedBy: "\n")
        guard let command = head.first?.trimmingCharacters(in: .whitespaces), !command.isEmpty else { return nil }
        var headers: [String: String] = [:]
        for line in head.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon])] = String(line[line.index(after: colon)...])
        }
        let body = parts.count > 1 ? parts.dropFirst().joined(separator: "\n\n") : ""
        return (command, headers, body)
    }
}
