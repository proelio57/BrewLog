import Foundation
import CoreBluetooth
import Observation

/// Connects to a BOOKOO Espresso Monitor (pressure sensor at the group head) or a demo sensor and publishes live
/// pressure. Runs next to the scale connection: BrewLog then records weight and pressure for every shot.
@Observable
final class PressureMonitor: NSObject {
    static let shared = PressureMonitor()

    private(set) var state: ScaleConnectionState = .idle
    private(set) var discovered: [DiscoveredScale] = []
    private(set) var pressure: Double = 0
    private(set) var batteryLevel: Int?
    private(set) var connectedName: String?

    /// Off by default: only espresso users with the sensor need it.
    var isEnabled: Bool = UserDefaults.standard.bool(forKey: SettingsKey.pressureEnabled) {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: SettingsKey.pressureEnabled)
            isEnabled ? start() : shutDown()
        }
    }

    var isDemo: Bool = UserDefaults.standard.bool(forKey: SettingsKey.pressureDemo) {
        didSet {
            UserDefaults.standard.set(isDemo, forKey: SettingsKey.pressureDemo)
            if isEnabled { shutDown(); start() }
        }
    }

    /// Live pressure is available.
    var isReady: Bool { isEnabled && (isDemo || state == .connected) }

    var displayName: String { isDemo ? "Demo sensor" : (connectedName ?? "Pressure sensor") }

    /// Every reading (bar). Used by the brew engine.
    @ObservationIgnored var onPressure: ((Double, Date) -> Void)?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var commandCharacteristic: CBCharacteristic?
    @ObservationIgnored private var userInitiatedDisconnect = false
    @ObservationIgnored private let demo = DemoPressureSensor()

    private static let maxDiscovered = 20
    private static let savedPeripheralKey = "pressure.lastPeripheralID"
    private static let serviceUUID = CBUUID(string: BookooMonitorProtocol.serviceID)
    private static let dataUUID = CBUUID(string: BookooMonitorProtocol.dataCharacteristicID)
    private static let commandUUID = CBUUID(string: BookooMonitorProtocol.commandCharacteristicID)

    private var savedPeripheralID: UUID? {
        get { UserDefaults.standard.string(forKey: Self.savedPeripheralKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Self.savedPeripheralKey) }
    }

    override init() {
        super.init()
        demo.onPressure = { [weak self] bar in self?.handle(bar: bar, battery: 100) }
    }

    // MARK: Public API

    /// Call once at launch (does nothing while the sensor is turned off).
    func start() {
        guard isEnabled else { return }
        if isDemo {
            demo.start()
            state = .connected
            return
        }
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
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
        peripheral = target
        target.delegate = self
        savedPeripheralID = id
        state = .connecting
        central.connect(target, options: nil)
    }

    func disconnect(forget: Bool) {
        userInitiatedDisconnect = true
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        if forget { savedPeripheralID = nil }
        state = .idle
    }

    /// Demo: simulate the pressure of a shot for this recipe, starting 2.5 s from now (like the demo scale).
    func prepareForShot(recipe: Recipe) {
        if isEnabled && isDemo { demo.simulateShot(recipe: recipe) }
    }

    func shotFinished() {
        demo.stopShot()
    }

    // MARK: Private

    private func shutDown() {
        demo.stop()
        central?.stopScan()
        if let peripheral {
            userInitiatedDisconnect = true
            central?.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        commandCharacteristic = nil
        pressure = 0
        state = .idle
    }

    private func reconnectSaved() {
        guard isEnabled, !isDemo, let central, central.state == .poweredOn, let id = savedPeripheralID else { return }
        if let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            peripherals[id] = known
            peripheral = known
            known.delegate = self
            state = .connecting
            central.connect(known, options: nil)
        }
    }

    private func handle(bar: Double, battery: Int?) {
        guard bar.isFinite else { return }
        pressure = bar
        if let battery { batteryLevel = min(max(battery, 0), 100) }
        onPressure?(bar, Date())
    }

    private func send(_ bytes: [UInt8]) {
        guard let peripheral, let commandCharacteristic else { return }
        let type: CBCharacteristicWriteType = commandCharacteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(Data(bytes), for: commandCharacteristic, type: type)
    }
}

// MARK: - CoreBluetooth

extension PressureMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !isDemo else { return }
        switch central.state {
        case .poweredOn:
            state = .idle
            reconnectSaved()
        case .poweredOff: state = .bluetoothOff
        case .unauthorized: state = .unauthorized
        case .unsupported: state = .unsupported
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard BookooMonitorProtocol.isMonitor(name: name) || services.contains(Self.serviceUUID) else { return }
        // Advertised names are untrusted input: sanitize and bound them.
        let safeName = (name ?? "Espresso Monitor").sanitized(maxLength: 40)
        let entry = DiscoveredScale(id: peripheral.identifier, name: safeName.isEmpty ? "Espresso Monitor" : safeName,
                                    rssi: RSSI.intValue)
        if let index = discovered.firstIndex(where: { $0.id == entry.id }) {
            discovered[index] = entry
        } else {
            guard discovered.count < Self.maxDiscovered else { return }
            discovered.append(entry)
        }
        peripherals[peripheral.identifier] = peripheral
        if peripheral.identifier == savedPeripheralID, state != .connected, state != .connecting {
            connect(peripheral.identifier)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedName = (peripheral.name ?? "Espresso Monitor").sanitized(maxLength: 40)
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .idle
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        commandCharacteristic = nil
        guard !isDemo, isEnabled else { return }
        if userInitiatedDisconnect {
            state = .idle
            userInitiatedDisconnect = false
        } else {
            // Switched off or out of range: keep trying in the background.
            state = .connecting
            central.connect(peripheral, options: nil)
        }
    }
}

extension PressureMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else { return }
        peripheral.discoverCharacteristics([Self.dataUUID, Self.commandUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.dataUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == Self.commandUUID {
                commandCharacteristic = characteristic
            }
        }
        // The sensor only streams after the start command.
        send(BookooMonitorProtocol.startCommand)
        state = .connected
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == Self.dataUUID, let data = characteristic.value,
              let reading = BookooMonitorProtocol.parse([UInt8](data)) else { return }
        if state != .connected { state = .connected }
        handle(bar: reading.bar, battery: reading.batteryPercent)
    }
}

// MARK: - Demo sensor

/// Idles at 0 bar and follows a realistic shot profile when a shot is simulated.
private final class DemoPressureSensor {
    var onPressure: ((Double) -> Void)?

    private var timer: Timer?
    private var shotStart: Date?
    private var preinfusion: Double = 6
    private var peak: Double = 9
    private var duration: Double = 28

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        shotStart = nil
    }

    func simulateShot(recipe: Recipe) {
        if let shotStart, Date() >= shotStart { return }
        let extract = recipe.steps.first { $0.kind == .extract }?.time ?? 6
        preinfusion = max(extract - 1, 2)
        peak = recipe.pressure ?? 9
        duration = recipe.targetTime + Double.random(in: -1.5...2)
        shotStart = Date().addingTimeInterval(2.5)
    }

    func stopShot() {
        shotStart = nil
    }

    private func tick() {
        var bar = 0.0
        if let shotStart, Date() >= shotStart {
            let t = Date().timeIntervalSince(shotStart)
            if t >= duration {
                self.shotStart = nil
            } else if t < preinfusion {
                bar = min(t / 1.5, 1) * 3
            } else if t < preinfusion + 2.5 {
                bar = 3 + (peak - 3) * (t - preinfusion) / 2.5
            } else {
                let progress = (t - preinfusion - 2.5) / max(duration - preinfusion - 2.5, 1)
                bar = peak * (1 - 0.18 * progress)
            }
            bar = max(bar + Double.random(in: -0.1...0.1), 0)
        }
        onPressure?((bar * 100).rounded() / 100)
    }
}
