import Foundation
import CoreBluetooth
import Observation

struct DiscoveredScale: Identifiable, Equatable {
    let id: UUID
    let name: String
    var rssi: Int
    var model: ScaleModel = .bookoo
}

/// What BrewLog asks a scale to do. Each model translates it into its own packet.
enum ScaleCommand: CaseIterable {
    case tare, startTimer, stopTimer, resetTimer

    func packet(for model: ScaleModel) -> Data {
        switch (model, self) {
        case (.bookoo, .tare): return BookooProtocol.Command.tare.packet
        case (.bookoo, .startTimer): return BookooProtocol.Command.startTimer.packet
        case (.bookoo, .stopTimer): return BookooProtocol.Command.stopTimer.packet
        case (.bookoo, .resetTimer): return BookooProtocol.Command.resetTimer.packet
        case (.timemoreDot, .tare): return TimemoreDotProtocol.Command.tare.packet
        case (.timemoreDot, .startTimer): return TimemoreDotProtocol.Command.startTimer.packet
        case (.timemoreDot, .stopTimer): return TimemoreDotProtocol.Command.stopTimer.packet
        case (.timemoreDot, .resetTimer): return TimemoreDotProtocol.Command.resetTimer.packet
        }
    }
}

enum ScaleConnectionState: Equatable {
    case unknown, bluetoothOff, unauthorized, unsupported, idle, scanning, connecting, connected

    var label: String {
        switch self {
        case .unknown: return "Starting Bluetooth…"
        case .bluetoothOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth permission needed"
        case .unsupported: return "Bluetooth not supported"
        case .idle: return "Not connected"
        case .scanning: return "Searching…"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        }
    }
}

/// Connects to a BOOKOO Themis Mini or a Timemore Black Mirror Dot (or a built-in demo scale) and publishes live weight readings.
@Observable
final class ScaleManager: NSObject {
    static let shared = ScaleManager()

    private(set) var state: ScaleConnectionState = .unknown
    private(set) var discovered: [DiscoveredScale] = []
    private(set) var weight: Double = 0
    private(set) var batteryLevel: Int?
    private(set) var connectedName: String?
    /// The kind of scale that is (or was last) connected.
    private(set) var model: ScaleModel = ScaleModel(rawValue: UserDefaults.standard.string(forKey: "scale.lastModel") ?? "") ?? .bookoo

    var isDemo: Bool = UserDefaults.standard.bool(forKey: SettingsKey.demoScale) {
        didSet {
            UserDefaults.standard.set(isDemo, forKey: SettingsKey.demoScale)
            applyDemoMode()
        }
    }

    /// True when live weight is available.
    var isReady: Bool { isDemo || state == .connected }

    var displayName: String {
        if isDemo { return "Demo scale" }
        return connectedName ?? "Scale"
    }

    /// Receives every weight reading (grams). Used by the brew engine.
    @ObservationIgnored var onWeight: ((Double, Date) -> Void)?

    /// Packets dropped by validation (shown in the scale sheet for diagnostics).
    private(set) var rejectedPackets = 0

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var commandCharacteristic: CBCharacteristic?
    @ObservationIgnored private var userInitiatedDisconnect = false
    @ObservationIgnored private var validator = BookooPacketValidator()
    @ObservationIgnored private var dotParser = TimemoreDotProtocol.Parser()
    @ObservationIgnored private var models: [UUID: ScaleModel] = [:]
    @ObservationIgnored private let demo = DemoScale()
    /// Upper bound on remembered nearby devices (scan results are attacker-controllable).
    private static let maxDiscovered = 20

    private static let savedPeripheralKey = "scale.lastPeripheralID"
    private static let savedModelKey = "scale.lastModel"

    private var savedPeripheralID: UUID? {
        get { UserDefaults.standard.string(forKey: Self.savedPeripheralKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Self.savedPeripheralKey) }
    }

    var hasSavedScale: Bool { savedPeripheralID != nil }

    override init() {
        super.init()
        demo.onWeight = { [weak self] grams in
            self?.handle(grams: grams, battery: 100)
        }
    }

    // MARK: Public API

    /// Call once at launch: starts Bluetooth and reconnects to the last scale.
    func start() {
        applyDemoMode()
        guard !isDemo else { return }
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: true])
        } else {
            reconnectSaved()
        }
    }

    func startScan() {
        guard let central, central.state == .poweredOn else {
            start()
            return
        }
        discovered.removeAll()
        if state != .connected { state = .scanning }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central?.stopScan()
        if state == .scanning { state = .idle }
    }

    func connect(_ id: UUID) {
        guard let central, let target = peripherals[id] else { return }
        central.stopScan()
        if let peripheral, peripheral.identifier != id {
            userInitiatedDisconnect = true
            central.cancelPeripheralConnection(peripheral)
        }
        userInitiatedDisconnect = false
        peripheral = target
        target.delegate = self
        state = .connecting
        savedPeripheralID = id
        setModel(models[id] ?? .bookoo)
        central.connect(target, options: nil)
    }

    func disconnect(forget: Bool) {
        userInitiatedDisconnect = true
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        if forget { savedPeripheralID = nil }
        peripheral = nil
        commandCharacteristic = nil
        connectedName = nil
        state = .idle
    }

    func tare() {
        if isDemo {
            demo.tare()
            return
        }
        send(.tare)
    }

    /// Writes one of the allowlisted commands. No other bytes can be sent to the scale.
    func send(_ command: ScaleCommand) {
        write(command.packet(for: model))
    }

    private func write(_ packet: Data) {
        guard !isDemo, let peripheral, peripheral.state == .connected, let characteristic = commandCharacteristic else { return }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(packet, for: characteristic, type: type)
    }

    private func setModel(_ newModel: ScaleModel) {
        model = newModel
        UserDefaults.standard.set(newModel.rawValue, forKey: Self.savedModelKey)
    }

    /// The Dot only reports weight once unit and mode are set.
    private func initializeDot() {
        var delay: TimeInterval = 0
        for (command, wait) in TimemoreDotProtocol.initSequence {
            delay += wait
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.model == .timemoreDot else { return }
                self.write(command.packet)
            }
        }
    }

    /// Tares and resets the scale timer. In demo mode it also schedules a simulated pour that follows the recipe.
    func prepareForBrew(recipe: Recipe) {
        if isDemo {
            demo.simulate(recipe: recipe)
        } else {
            send(.tare)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.send(.resetTimer) }
        }
    }

    /// Tares for weighing the beans. In demo mode it also simulates beans being added to the cup.
    func prepareForDosing(dose: Double) {
        if isDemo {
            demo.simulateDose(dose)
        } else {
            send(.tare)
        }
    }

    func dosingFinished() {
        if isDemo { demo.stopSimulation() }
    }

    func brewStarted() { send(.startTimer) }

    func brewFinished() {
        send(.stopTimer)
        if isDemo { demo.stopSimulation() }
    }

    // MARK: Private

    private func applyDemoMode() {
        if isDemo {
            if let peripheral { central?.cancelPeripheralConnection(peripheral) }
            demo.start()
            state = .connected
            batteryLevel = 100
        } else {
            demo.stop()
            if state == .connected && peripheral == nil { state = .idle }
            if central != nil { reconnectSaved() }
        }
    }

    private func reconnectSaved() {
        guard !isDemo, let central, central.state == .poweredOn, let id = savedPeripheralID else {
            if central?.state == .poweredOn && state != .connected { state = .idle }
            return
        }
        if let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            peripherals[id] = known
            peripheral = known
            known.delegate = self
            state = .connecting
            // A pending connect never times out, so the scale reconnects as soon as it is switched on.
            central.connect(known, options: nil)
        } else {
            state = .idle
        }
    }

    private func handle(grams: Double, battery: Int?) {
        guard grams.isFinite else { return }
        weight = grams
        if let battery { batteryLevel = min(max(battery, 0), 100) }
        onWeight?(grams, Date())
    }

    private func scaleModel(name: String?, advertisement: [String: Any]) -> ScaleModel? {
        ScaleModel.detect(name: name, services: advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
    }
}

// MARK: - CBCentralManagerDelegate

extension ScaleManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if !isDemo {
                state = .idle
                reconnectSaved()
            }
        case .poweredOff:
            if !isDemo { state = .bluetoothOff }
        case .unauthorized:
            if !isDemo { state = .unauthorized }
        case .unsupported:
            if !isDemo { state = .unsupported }
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let found = scaleModel(name: name, advertisement: advertisementData) else { return }
        // Advertised names are untrusted input: sanitize and bound them.
        let safeName = (name ?? found.defaultName).sanitized(maxLength: 40)
        let entry = DiscoveredScale(id: peripheral.identifier, name: safeName.isEmpty ? found.defaultName : safeName,
                                    rssi: RSSI.intValue, model: found)
        models[peripheral.identifier] = found
        if let index = discovered.firstIndex(where: { $0.id == entry.id }) {
            discovered[index] = entry
        } else {
            guard discovered.count < Self.maxDiscovered else { return }
            discovered.append(entry)
        }
        peripherals[peripheral.identifier] = peripheral
        // Auto-connect when the saved scale shows up while scanning
        if peripheral.identifier == savedPeripheralID, state != .connected, state != .connecting {
            connect(peripheral.identifier)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedName = (peripheral.name ?? model.defaultName).sanitized(maxLength: 40)
        validator.reset()
        dotParser.reset()
        peripheral.delegate = self
        peripheral.discoverServices([model.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .idle
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        commandCharacteristic = nil
        guard !isDemo else { return }
        if userInitiatedDisconnect {
            state = .idle
            userInitiatedDisconnect = false
        } else {
            // Unexpected disconnect (scale switched off or out of range): keep trying in the background.
            state = .connecting
            central.connect(peripheral, options: nil)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension ScaleManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == model.serviceUUID }) else {
            // Not the scale it advertised to be (e.g. another device with "dot" in its name): let it go.
            if error == nil {
                userInitiatedDisconnect = true
                central?.cancelPeripheralConnection(peripheral)
            }
            return
        }
        peripheral.discoverCharacteristics([model.notifyUUID, model.commandUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == model.notifyUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == model.commandUUID {
                commandCharacteristic = characteristic
            }
        }
        if model == .timemoreDot { initializeDot() }
        if !isDemo { state = .connected }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == model.notifyUUID, let data = characteristic.value else { return }
        if model == .timemoreDot {
            for event in dotParser.feed(data) {
                switch event {
                case .weight(let grams, _):
                    if state != .connected && !isDemo { state = .connected }
                    handle(grams: grams, battery: nil)
                case .battery(let percent):
                    batteryLevel = percent
                }
            }
            return
        }
        guard let reading = validator.accept(data) else {
            rejectedPackets = validator.rejected
            return
        }
        if state != .connected && !isDemo { state = .connected }
        handle(grams: reading.grams, battery: reading.batteryPercent)
    }
}

// MARK: - Demo scale

/// Simulates a scale that pours according to the recipe. Handy for trying the app without hardware or in the Simulator.
final class DemoScale {
    var onWeight: ((Double) -> Void)?

    private struct PlannedPour {
        let start: Double
        let goal: Double
        let rate: Double
    }

    private var timer: Timer?
    private var weight: Double = 0
    private var plan: [PlannedPour] = []
    private var pourStart: Date?
    private var endTime: Double = 0

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        stopSimulation()
    }

    func tare() {
        weight = 0
    }

    func simulate(recipe: Recipe, delay: Double = 2.5) {
        weight = 0
        let espresso = recipe.method.isEspresso
        let low = espresso ? max(recipe.flowMin, 1) : max(recipe.flowMin, 2)
        let high = max(recipe.flowMax, low + 0.5)
        plan = recipe.pourSteps.enumerated().map { index, step in
            // Pour-over: the first pour starts right away. Espresso: the first drops come after the pre-infusion.
            PlannedPour(start: index == 0 && !espresso ? 0 : step.time + Double.random(in: -1...2.5),
                        goal: (step.target ?? 0) + Double.random(in: -1.5...2.5),
                        rate: Double.random(in: low...high))
        }
        endTime = recipe.targetTime + 20
        pourStart = Date().addingTimeInterval(delay)
    }

    /// Beans trickling into a cup, ending a little off the dose like a real hand would.
    func simulateDose(_ dose: Double, delay: Double = 1.5) {
        weight = 0
        plan = [PlannedPour(start: 0, goal: max(dose + Double.random(in: -0.3...0.4), 0), rate: Double.random(in: 1.5...2.5))]
        endTime = 60
        pourStart = Date().addingTimeInterval(delay)
    }

    func stopSimulation() {
        plan = []
        pourStart = nil
    }

    private func tick() {
        if let pourStart, Date() >= pourStart {
            let t = Date().timeIntervalSince(pourStart)
            if let active = plan.last(where: { $0.start <= t }), weight < active.goal {
                let increment = active.rate * 0.1 * Double.random(in: 0.75...1.25)
                weight = min(active.goal, weight + increment)
            }
            if t > endTime { stopSimulation() }
        }
        let noise = Double.random(in: -0.03...0.03)
        onWeight?(((weight + noise) * 10).rounded() / 10)
    }
}
