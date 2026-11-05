import Foundation
import CoreBluetooth
import Observation

/// Bluetooth connection to a Decent DE1: subscribes to its state and shot samples and writes requested states.
/// `MachineManager` owns it and turns its updates into the machine status the brew engine reads.
@Observable
final class DecentConnection: NSObject {
    private(set) var state: ScaleConnectionState = .idle
    private(set) var discovered: [DiscoveredScale] = []
    private(set) var connectedName: String?

    /// Every status change; `telemetry` is true for a shot sample (live readings).
    @ObservationIgnored var onStatus: ((MachineStatus, _ telemetry: Bool) -> Void)?
    /// The machine went away without the user disconnecting it.
    @ObservationIgnored var onDisconnect: (() -> Void)?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var requestCharacteristic: CBCharacteristic?
    @ObservationIgnored private var status = MachineStatus()
    @ObservationIgnored private var userInitiatedDisconnect = false
    @ObservationIgnored private var active = false
    /// The DE1's last top-level state (`DecentProtocol.State` raw value).
    @ObservationIgnored private var machineState: UInt8?

    /// The DE1 is in its espresso state (heating up for, or pulling, a shot): it accepted a start.
    var isInEspressoState: Bool { machineState == DecentProtocol.State.espresso.rawValue }

    private static let maxDiscovered = 20
    private static let serviceUUID = CBUUID(string: DecentProtocol.service)
    private static let requestUUID = CBUUID(string: DecentProtocol.requestedState)
    private static let sampleUUID = CBUUID(string: DecentProtocol.shotSample)
    private static let stateUUID = CBUUID(string: DecentProtocol.stateInfo)

    private var savedID: UUID? {
        get { UserDefaults.standard.string(forKey: SettingsKey.machineDecentID).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: SettingsKey.machineDecentID) }
    }

    var hasSavedMachine: Bool { savedID != nil }

    // MARK: Public API

    /// Connects to the remembered machine (asks for Bluetooth the first time).
    func reconnectRemembered() {
        active = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
            return  // continues in centralManagerDidUpdateState
        }
        guard let central, central.state == .poweredOn, let id = savedID, peripheral == nil else { return }
        if let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            peripherals[id] = known
            connect(id)
        } else {
            startScan()  // not known to iOS yet: find it by its advertisement
        }
    }

    func startScan() {
        active = true
        guard let central, central.state == .poweredOn else {
            reconnectRemembered()
            return
        }
        discovered.removeAll()
        if state != .connected { state = .scanning }
        // Unfiltered: not every DE1 firmware advertises its service, so the name ("DE1…") counts too.
        central.scanForPeripherals(withServices: nil, options: nil)
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
        savedID = id
        state = .connecting
        central.connect(target, options: nil)
    }

    /// Stops using the machine (another machine kind was chosen, or "Disconnect & forget").
    func disconnect(forget: Bool) {
        active = false
        central?.stopScan()
        // Only a real cancellation is followed by didDisconnect, which clears the flag again.
        if let peripheral {
            userInitiatedDisconnect = true
            central?.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        requestCharacteristic = nil
        status = MachineStatus()
        machineState = nil
        connectedName = nil
        if forget { savedID = nil }
        state = .idle
    }

    /// Writes a requested state (see `DecentProtocol.command(for:)`, `startShot`, `stopShot`). Returns false if not connected.
    @discardableResult
    func write(_ command: Data) -> Bool {
        guard let peripheral, let requestCharacteristic else { return false }
        peripheral.writeValue(command, for: requestCharacteristic, type: .withResponse)
        return true
    }
}

// MARK: - CoreBluetooth

extension DecentConnection: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            state = .idle
            if active { reconnectRemembered() }
        case .poweredOff:
            state = .bluetoothOff
            dropConnection()
        case .unauthorized:
            state = .unauthorized
            dropConnection()
        case .unsupported: state = .unsupported
        default: break
        }
    }

    /// Bluetooth went off: iOS drops the connection without calling didDisconnect. Tell the manager (ends a
    /// running shot) and forget the peripheral object, so it is reconnected when Bluetooth is back on.
    private func dropConnection() {
        guard peripheral != nil else { return }
        peripheral = nil
        requestCharacteristic = nil
        status = MachineStatus()
        machineState = nil
        if active { onDisconnect?() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard services.contains(Self.serviceUUID) || (name?.hasPrefix("DE1") ?? false) else { return }
        // Advertised names are untrusted input: sanitize and bound them.
        let safeName = (name ?? "DE1").sanitized(maxLength: 40)
        let entry = DiscoveredScale(id: peripheral.identifier, name: safeName.isEmpty ? "DE1" : safeName, rssi: RSSI.intValue)
        if let index = discovered.firstIndex(where: { $0.id == entry.id }) {
            discovered[index] = entry
        } else {
            guard discovered.count < Self.maxDiscovered else { return }
            discovered.append(entry)
        }
        peripherals[peripheral.identifier] = peripheral
        if peripheral.identifier == savedID, state != .connected, state != .connecting {
            connect(peripheral.identifier)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedName = (peripheral.name ?? "DE1").sanitized(maxLength: 40)
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .idle
        onDisconnect?()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // A machine we already switched away from.
        guard peripheral.identifier == self.peripheral?.identifier else {
            userInitiatedDisconnect = false
            return
        }
        requestCharacteristic = nil
        status = MachineStatus()
        machineState = nil
        if userInitiatedDisconnect || !active {
            state = .idle
            userInitiatedDisconnect = false
            return
        }
        // Switched off or out of range: tell the manager (ends a running shot) and keep trying.
        state = .connecting
        onDisconnect?()
        central.connect(peripheral, options: nil)
    }
}

extension DecentConnection: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else { return }
        peripheral.discoverCharacteristics([Self.requestUUID, Self.sampleUUID, Self.stateUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.requestUUID:
                requestCharacteristic = characteristic
            case Self.sampleUUID:
                peripheral.setNotifyValue(true, for: characteristic)
            case Self.stateUUID:
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, data.count <= 64 else { return }
        if characteristic.uuid == Self.stateUUID, let info = DecentProtocol.state(data) {
            machineState = info.state
            DecentProtocol.apply(state: info.state, substate: info.substate, to: &status)
            state = .connected
            onStatus?(status, false)
        } else if characteristic.uuid == Self.sampleUUID, let sample = DecentProtocol.sample(data) {
            DecentProtocol.apply(sample, to: &status)
            onStatus?(status, true)
        }
    }
}
