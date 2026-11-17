import Foundation
import HomeKit

/// Smart plugs (and other on/off accessories) in the user's Apple Home, for switching the espresso machine's power.
/// `HMHomeManager` is only created by `start()`: creating it asks for HomeKit access, so it waits until the user
/// opens a screen that needs it.
final class HomeKitPlugs: NSObject, ObservableObject, HMHomeManagerDelegate {
    /// One switchable power state: an outlet of a plug, or a switch.
    struct Plug: Identifiable {
        /// The power state characteristic.
        let id: UUID
        let home: String
        let room: String
        let name: String
        var isOn: Bool?
        var reachable: Bool
        var error: String?
    }

    @Published private(set) var plugs: [Plug] = []
    @Published private(set) var status = "Not started"
    @Published private(set) var busy: Set<UUID> = []

    private var manager: HMHomeManager?
    private var characteristics: [UUID: HMCharacteristic] = [:]

    func start() {
        guard manager == nil else { return }
        status = "Asking for HomeKit access…"
        let manager = HMHomeManager()
        manager.delegate = self
        self.manager = manager
    }

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        DispatchQueue.main.async { self.reload() }
    }

    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        DispatchQueue.main.async { self.reload() }
    }

    private func reload() {
        guard let manager else { return }
        let auth = manager.authorizationStatus
        if !auth.contains(.determined) {
            status = "Waiting for HomeKit access"
        } else if auth.contains(.restricted) {
            status = "HomeKit is restricted on this device"
        } else if !auth.contains(.authorized) {
            status = "No HomeKit access. Allow it in Settings → Privacy & Security → HomeKit."
        } else if manager.homes.isEmpty {
            status = "HomeKit works, but no home is set up"
        } else {
            status = "HomeKit works"
        }

        var found: [Plug] = []
        characteristics = [:]
        for home in manager.homes {
            for accessory in home.accessories {
                for service in accessory.services where service.isUserInteractive {
                    for characteristic in service.characteristics
                    where characteristic.characteristicType == HMCharacteristicTypePowerState {
                        characteristics[characteristic.uniqueIdentifier] = characteristic
                        let name = service.name == accessory.name ? accessory.name : "\(accessory.name) – \(service.name)"
                        found.append(Plug(id: characteristic.uniqueIdentifier, home: home.name,
                                          room: accessory.room?.name ?? "", name: name,
                                          isOn: characteristic.value as? Bool, reachable: accessory.isReachable))
                    }
                }
            }
        }
        plugs = found
        if auth.contains(.authorized), !manager.homes.isEmpty, found.isEmpty {
            status = "HomeKit works, but no plug or switch was found"
        }
        for plug in found { read(plug.id) }
    }

    private func read(_ id: UUID) {
        guard let characteristic = characteristics[id] else { return }
        characteristic.readValue { [weak self] error in
            DispatchQueue.main.async {
                self?.update(id) {
                    $0.isOn = characteristic.value as? Bool
                    $0.error = error?.localizedDescription
                }
            }
        }
    }

    /// Switches the plug to the opposite of its known state. A second tap while a write runs is ignored.
    func toggle(_ id: UUID) {
        guard let characteristic = characteristics[id], !busy.contains(id),
              let plug = plugs.first(where: { $0.id == id }) else { return }
        let target = !(plug.isOn ?? false)
        busy.insert(id)
        characteristic.writeValue(target) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy.remove(id)
                self.update(id) {
                    if error == nil { $0.isOn = target }
                    $0.error = error?.localizedDescription
                }
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout Plug) -> Void) {
        guard let index = plugs.firstIndex(where: { $0.id == id }) else { return }
        change(&plugs[index])
    }
}
