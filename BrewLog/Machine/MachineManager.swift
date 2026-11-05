import Foundation
import Observation

enum MachineKind: String, CaseIterable, Identifiable {
    case none, gaggimate, decent, demo
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .gaggimate: return "GaggiMate"
        case .decent: return "Decent DE1"
        case .demo: return "Demo machine"
        }
    }
}

/// What BrewLog can do with a kind of machine beyond reading its state.
struct MachineCapabilities: OptionSet {
    let rawValue: Int
    /// Profiles stored on the machine: send a recipe as one, list and select them.
    static let profiles = MachineCapabilities(rawValue: 1 << 0)
    /// Raise or lower the brew temperature by 1 °C.
    static let temperatureNudge = MachineCapabilities(rawValue: 1 << 1)
    /// A scale connected to the machine (weight read and tared through it).
    static let machineScale = MachineCapabilities(rawValue: 1 << 2)
    /// Start and stop shots, switch modes.
    static let startStop = MachineCapabilities(rawValue: 1 << 3)
}

extension MachineKind {
    var capabilities: MachineCapabilities {
        switch self {
        case .none: return []
        case .gaggimate, .demo: return [.profiles, .temperatureNudge, .machineScale, .startStop]
        // Profile upload to the DE1 isn't built yet; it has no scale of its own.
        case .decent: return [.startStop]
        }
    }
}

/// Connection to the espresso machine: live pressure, temperature and flow, and shot start/stop.
///
/// GaggiMate is reached over its local WebSocket (`ws://gaggimate.local/ws`): BrewLog reads the telemetry, and on request
/// switches the mode, starts or stops a shot, nudges the temperature and saves a recipe as a profile.
/// The demo machine simulates a shot for trying things without hardware.
@Observable
final class MachineManager {
    static let shared = MachineManager()

    enum ConnectionState: Equatable {
        case off, connecting, connected, unreachable
    }

    private(set) var state: ConnectionState = .off
    private(set) var status = MachineStatus()
    /// Short feedback for the last command, e.g. "Profile sent" or an error from the machine.
    private(set) var notice: String?
    /// The machine refused to start because of a warning (e.g. low water) and waits for a decision.
    private(set) var startBlockedBy: [String] = []
    /// The profiles stored on the machine, for the profile picker (see `refreshProfiles()`).
    private(set) var profiles: [MachineProfileSummary] = []
    private(set) var profilesLoading = false

    var kind: MachineKind = MachineKind(rawValue: UserDefaults.standard.string(forKey: SettingsKey.machineKind) ?? "") ?? .none {
        didSet {
            guard kind != oldValue else { return }
            UserDefaults.standard.set(kind.rawValue, forKey: SettingsKey.machineKind)
            restart()
        }
    }

    var host: String = UserDefaults.standard.string(forKey: SettingsKey.machineHost) ?? "gaggimate.local" {
        didSet {
            guard host != oldValue else { return }
            UserDefaults.standard.set(host, forKey: SettingsKey.machineHost)
            if kind == .gaggimate { restart() }
        }
    }

    var isConnected: Bool { state == .connected }

    /// The machine measures the pressure itself (GaggiMate with its pressure sensor, the demo machine), so BrewLog
    /// reads it from there and a separate pressure sensor isn't needed. That one is only for machines BrewLog
    /// can't connect to, or a GaggiMate without a pressure sensor.
    var readsPressure: Bool { kind != .none && status.hasPressure != false }

    var displayName: String {
        switch kind {
        case .none: return "No machine"
        case .gaggimate: return "GaggiMate"
        case .decent: return decent.connectedName ?? "Decent DE1"
        case .demo: return "Demo machine"
        }
    }

    /// Bluetooth connection to a Decent DE1 (used when `kind == .decent`; Settings pairs it).
    let decent = DecentConnection()

    /// Every telemetry frame (about twice a second). Used by the brew engine to record the shot.
    @ObservationIgnored var onReading: ((MachineStatus, Date) -> Void)?
    /// The machine started (true) or stopped (false) a shot.
    @ObservationIgnored var onShot: ((Bool, Date) -> Void)?

    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var lastMessage = Date.distantPast
    @ObservationIgnored private var watchdog: Timer?
    @ObservationIgnored private var retry: DispatchWorkItem?
    @ObservationIgnored private let demo = DemoMachine()
    @ObservationIgnored private var pending: [String: ([String: Any]?) -> Void] = [:]
    @ObservationIgnored private var nextRequest = 0

    init() {
        demo.onStatus = { [weak self] status, frameIsTelemetry in
            self?.apply(status: status, telemetry: frameIsTelemetry)
        }
        decent.onStatus = { [weak self] status, telemetry in
            guard let self, self.kind == .decent else { return }
            self.apply(status: status, telemetry: telemetry)
        }
        decent.onDisconnect = { [weak self] in
            guard let self, self.kind == .decent else { return }
            self.decentLost()
        }
    }

    // MARK: Public API

    /// Call once at launch.
    func start() {
        restart()
    }

    /// Demo machine: simulate a shot for this recipe (a real machine is started by hand).
    func prepareForShot(recipe: Recipe) {
        if kind == .demo { demo.simulateShot(recipe: recipe) }
    }

    func cancelShot() {
        if kind == .demo { demo.stopShot() }
    }

    // MARK: Control (GaggiMate)

    var canControl: Bool { kind != .none && isConnected }

    /// The machine keeps profiles that can be listed and selected from BrewLog.
    var canChooseProfile: Bool { kind.capabilities.contains(.profiles) && isConnected }

    func setMode(_ mode: MachineMode) {
        if kind == .demo { demo.setMode(mode); return }
        if kind == .decent { writeToDecent(DecentProtocol.command(for: mode)); return }
        send(["tp": "req:change-mode", "mode": mode.rawValue])
    }

    /// Starts the shot with the selected profile (switches to brew mode first if needed).
    func startShot(ignoreWarnings: Bool = false) {
        startBlockedBy = []
        if kind == .demo { demo.startShotNow(); return }
        if kind == .decent {
            guard writeToDecent(DecentProtocol.startShot) else { return }
            // A DE1 with a group head controller only starts shots from the machine.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                // Accepted: the DE1 is in its espresso state (it may still be heating before the pump runs).
                guard let self, self.kind == .decent, self.isConnected, !self.decent.isInEspressoState else { return }
                self.notice = "Start the shot on the machine."
            }
            return
        }
        if status.mode != MachineMode.brew.rawValue { send(["tp": "req:change-mode", "mode": MachineMode.brew.rawValue]) }
        send(["tp": "req:process:activate", "ignoreWarnings": ignoreWarnings])
    }

    func stopShot() {
        if kind == .demo { demo.stopShot(); return }
        if kind == .decent { writeToDecent(DecentProtocol.stopShot); return }
        send(["tp": "req:process:deactivate"])
    }

    /// Tares the scale connected to the machine.
    func tareScale() {
        guard kind.capabilities.contains(.machineScale), kind != .demo else { return }
        send(["tp": "req:scale:tare"])
    }

    func dismissStartWarning() {
        startBlockedBy = []
        send(["tp": "req:brew:confirm:cancel"])
    }

    /// Changes the brew temperature by 1 °C.
    func nudgeTemperature(up: Bool) {
        if kind == .demo { demo.nudgeTemperature(up: up); return }
        guard kind.capabilities.contains(.temperatureNudge) else { return }
        send(["tp": up ? "req:raise-temp" : "req:lower-temp"])
    }

    /// Saves the recipe as a GaggiMate profile (updating the one sent before) and selects it.
    func sendProfile(recipe: Recipe, dose: Double, temperature: Double) {
        if kind == .demo {
            demo.setTargetTemperature(temperature)
            notice = "Demo machine: \(recipe.name) selected"
            return
        }
        var profile = GaggiMateProfile.make(recipe: recipe, dose: dose, temperature: temperature,
                                            hasPressure: status.hasPressure ?? true, hasScale: status.scaleConnected)
        let key = "machine.profile." + recipe.id
        if let id = UserDefaults.standard.string(forKey: key) { profile["id"] = id }
        notice = "Sending \(recipe.name)…"
        send(["tp": "req:profiles:save", "profile": profile]) { [weak self] response in
            guard let self else { return }
            guard let response, response["error"] == nil,
                  let saved = response["profile"] as? [String: Any], let id = saved["id"] as? String else {
                if profile["id"] != nil {
                    // The profile was deleted on the machine: save it as a new one.
                    UserDefaults.standard.removeObject(forKey: key)
                    self.sendProfile(recipe: recipe, dose: dose, temperature: temperature)
                } else {
                    self.notice = "The machine didn't accept the profile" + ((response?["error"] as? String).map { ": \($0)" } ?? ".")
                }
                return
            }
            UserDefaults.standard.set(id, forKey: key)
            self.send(["tp": "req:profiles:select", "id": id]) { [weak self] _ in
                self?.notice = "\(recipe.name) is selected on the machine"
            }
        }
    }

    /// Reads the profiles saved on the machine as espresso recipes. Profiles BrewLog sent itself are left out,
    /// they already are recipes here. `completion` gets nil if the machine didn't answer.
    func fetchProfiles(completion: @escaping ([Recipe]?) -> Void) {
        guard kind == .gaggimate else { completion(nil); return }
        requestProfiles { summaries in
            completion(summaries.map { $0.filter { !$0.isBrewLogs }.compactMap(\.recipe) })
        }
    }

    /// Loads the machine's profile list into `profiles` (selected first, then favorites).
    func refreshProfiles() {
        if kind == .demo {
            profiles = demo.profiles
            return
        }
        guard kind == .gaggimate, isConnected, !profilesLoading else { return }
        profilesLoading = true
        requestProfiles { [weak self] summaries in
            guard let self else { return }
            self.profilesLoading = false
            if let summaries {
                self.profiles = summaries
            } else {
                self.notice = "Couldn't read the profiles from the machine."
            }
        }
    }

    /// Selects a profile on the machine; `completion` gets whether the machine accepted it.
    func selectProfile(_ id: String, completion: @escaping (Bool) -> Void) {
        if kind == .demo {
            demo.selectProfile(id)
            profiles = demo.profiles
            completion(true)
            return
        }
        send(["tp": "req:profiles:select", "id": id]) { [weak self] response in
            guard let self else { return }
            let accepted = response != nil && response?["error"] == nil
            if accepted {
                self.notice = nil
                self.refreshProfiles()
            } else {
                self.notice = "The machine didn't select the profile" + ((response?["error"] as? String).map { ": \($0)" } ?? ".")
            }
            completion(accepted)
        }
    }

    /// The BrewLog recipe a profile was sent from (`sendProfile` remembers the profile id per recipe).
    func recipeID(forProfile id: String) -> String? {
        let prefix = "machine.profile."
        return UserDefaults.standard.dictionaryRepresentation()
            .first { $0.key.hasPrefix(prefix) && ($0.value as? String) == id }
            .map { String($0.key.dropFirst(prefix.count)) }
    }

    private func requestProfiles(completion: @escaping ([MachineProfileSummary]?) -> Void) {
        send(["tp": "req:profiles:list"]) { response in
            guard let response, response["error"] == nil, response["profiles"] is [Any] else {
                completion(nil)
                return
            }
            completion(GaggiMateProfile.summaries(fromListResponse: response))
        }
    }

    /// Sends a request; `completion` gets the matching `res:` message, or nil after a timeout.
    private func send(_ payload: [String: Any], completion: (([String: Any]?) -> Void)? = nil) {
        guard let socket, state == .connected else {
            notice = "The machine isn't connected."
            completion?(nil)
            return
        }
        var message = payload
        if let completion {
            nextRequest += 1
            let rid = "bl\(nextRequest)"
            message["rid"] = rid
            pending[rid] = completion
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.pending.removeValue(forKey: rid)?(nil)
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { [weak self] error in
            guard error != nil else { return }
            DispatchQueue.main.async { self?.notice = "Sending to the machine failed." }
        }
    }

    private func handle(other message: [String: Any]) {
        guard let type = message["tp"] as? String else { return }
        if type == "evt:brew:confirm" {
            startBlockedBy = (message["warn"] as? [[String: Any]] ?? []).compactMap { $0["k"] as? String }
        } else if type == "evt:brew:confirm:cancel" {
            startBlockedBy = []
        } else if type.hasPrefix("res:"), let rid = message["rid"] as? String, let completion = pending.removeValue(forKey: rid) {
            completion(message)
        }
    }

    // MARK: Connection

    private func restart() {
        disconnect()
        demo.stop()
        if kind != .decent { decent.disconnect(forget: false) }
        status = MachineStatus()
        profiles = []
        profilesLoading = false
        switch kind {
        case .none:
            state = .off
        case .demo:
            state = .connected
            demo.start()
        case .gaggimate:
            connect()
        case .decent:
            notice = nil
            state = decent.hasSavedMachine ? .connecting : .unreachable
            decent.reconnectRemembered()
        }
    }

    /// "Disconnect & forget" in Settings: unpairs the DE1 and shows it as gone right away.
    func forgetDecent() {
        decent.disconnect(forget: true)
        guard kind == .decent else { return }
        decentLost()
        notice = nil
    }

    /// Pairs the DE1 chosen in Settings and starts using it.
    func connectDecent(_ id: UUID) {
        decent.connect(id)
        if kind == .decent { state = .connecting }
    }

    @discardableResult
    private func writeToDecent(_ command: Data) -> Bool {
        guard decent.write(command) else {
            notice = "The machine isn't connected."
            return false
        }
        notice = nil
        return true
    }

    /// The DE1 went away: end a running shot once; the connection keeps trying in the background.
    private func decentLost() {
        let wasBrewing = status.isBrewing
        state = .unreachable
        status = MachineStatus()
        if wasBrewing { onShot?(false, Date()) }
    }

    private func connect() {
        retry?.cancel()
        guard kind == .gaggimate, let url = gaggiMateURL(host: host) else {
            state = .unreachable
            return
        }
        state = .connecting
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        let socket = session.webSocketTask(with: url)
        socket.maximumMessageSize = 256 * 1024
        self.session = session
        self.socket = socket
        lastMessage = Date()
        socket.resume()
        receive(on: socket)
        startWatchdog()
    }

    private func disconnect() {
        for completion in pending.values { completion(nil) }
        pending.removeAll()
        watchdog?.invalidate()
        watchdog = nil
        retry?.cancel()
        retry = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func receive(on socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.socket === socket else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message {
                        if let frame = MachineStatus.statusFrame(text) {
                            var status = self.status
                            status.merge(frame)
                            self.apply(status: status, telemetry: MachineStatus.isTelemetry(frame))
                        } else if text.utf8.count <= 256 * 1024,
                                  let other = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
                            self.lastMessage = Date()
                            self.handle(other: other)
                        }
                    }
                    self.receive(on: socket)
                case .failure:
                    self.connectionLost()
                }
            }
        }
    }

    /// GaggiMate sends telemetry every 500 ms, so a few silent seconds mean the connection is gone.
    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.socket != nil else { return }
            if Date().timeIntervalSince(self.lastMessage) > 6 { self.connectionLost() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func connectionLost() {
        let wasBrewing = status.isBrewing
        disconnect()
        profilesLoading = false
        state = .unreachable
        if wasBrewing { onShot?(false, Date()) }
        status = MachineStatus()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.kind == .gaggimate else { return }
            self.connect()
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func apply(status newStatus: MachineStatus, telemetry: Bool) {
        let wasBrewing = status.isBrewing
        lastMessage = Date()
        state = .connected
        status = newStatus
        if telemetry { onReading?(newStatus, Date()) }
        if newStatus.isBrewing != wasBrewing { onShot?(newStatus.isBrewing, Date()) }
    }
}

/// Simulated machine: idles at brew temperature and runs a realistic pressure profile when a shot is simulated.
private final class DemoMachine {
    var onStatus: ((MachineStatus, Bool) -> Void)?

    private var timer: Timer?
    private var status = MachineStatus()
    private var shotStart: Date?
    private var preinfusion: Double = 7
    private var peak: Double = 9
    private var duration: Double = 28

    func start() {
        status = MachineStatus()
        status.mode = 1
        status.profile = "Demo"
        status.hasPressure = true
        status.targetTemperature = 93
        status.temperature = 93
        status.pressure = 0
        status.flow = 0
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        onStatus?(status, false)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        shotStart = nil
    }

    /// Starts a simulated shot 2.5 s from now (the same delay the demo scale uses before the first drops).
    func simulateShot(recipe: Recipe) {
        if let shotStart, Date() >= shotStart { return }  // a shot is already running
        let extract = recipe.steps.first { $0.kind == .extract }?.time ?? 6
        preinfusion = max(extract - 1, 2)
        peak = recipe.pressure ?? 9
        duration = recipe.targetTime + Double.random(in: -1.5...2)
        shotStart = Date().addingTimeInterval(2.5)
    }

    func stopShot() {
        shotStart = nil
        status.processActive = false
        status.pressure = 0
        status.flow = 0
    }

    func startShotNow() {
        if shotStart == nil { shotStart = Date() }
    }

    func setMode(_ mode: MachineMode) {
        status.mode = mode.rawValue
        onStatus?(status, false)
    }

    /// Two espresso presets stand in for the profiles on a real machine.
    private var selectedProfile: String?

    var profiles: [MachineProfileSummary] {
        let recipes = RecipeLibrary.presets.filter(\.method.isEspresso).prefix(2)
        let selected = selectedProfile ?? recipes.first?.id
        return recipes.map {
            MachineProfileSummary(id: $0.id, label: $0.name, isSelected: $0.id == selected, isFavorite: false,
                                  isBrewLogs: false, recipe: $0)
        }
        .sorted { $0.isSelected && !$1.isSelected }
    }

    func selectProfile(_ id: String) {
        selectedProfile = id
        status.profile = profiles.first { $0.id == id }?.label
        onStatus?(status, false)
    }

    func nudgeTemperature(up: Bool) {
        setTargetTemperature((status.targetTemperature ?? 93) + (up ? 1 : -1))
    }

    func setTargetTemperature(_ value: Double) {
        status.targetTemperature = value
        onStatus?(status, false)
    }

    private func tick() {
        let target = status.targetTemperature ?? 93
        if let shotStart, Date() >= shotStart {
            let t = Date().timeIntervalSince(shotStart)
            if t >= duration {
                stopShot()
                status.processLabel = "Finished"
            } else {
                status.processActive = true
                status.processKind = t < preinfusion ? "infusion" : "brew"
                status.processLabel = t < preinfusion ? "Pre-infusion" : "Extraction"
                let pressure: Double
                if t < preinfusion {
                    pressure = min(t / 1.5, 1) * 3
                } else if t < preinfusion + 2.5 {
                    pressure = 3 + (peak - 3) * (t - preinfusion) / 2.5
                } else {
                    // The puck erodes, so the pressure eases off towards the end.
                    let progress = (t - preinfusion - 2.5) / max(duration - preinfusion - 2.5, 1)
                    pressure = peak * (1 - 0.18 * progress)
                }
                status.pressure = max(pressure + Double.random(in: -0.15...0.15), 0)
                status.flow = t < preinfusion ? 3.5 - t / preinfusion * 1.5 : 1.8 + Double.random(in: -0.2...0.2)
                status.temperature = target - 0.8 * sin(min(t / duration, 1) * .pi) + Double.random(in: -0.1...0.1)
            }
        } else {
            status.temperature = target + Double.random(in: -0.1...0.1)
        }
        onStatus?(status, true)
    }
}
