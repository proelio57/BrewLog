import Foundation
import CoreBluetooth

/// The scales BrewLog can connect to.
enum ScaleModel: String, CaseIterable {
    case bookoo, timemoreDot

    var defaultName: String {
        switch self {
        case .bookoo: return "BOOKOO scale"
        case .timemoreDot: return "Timemore Dot"
        }
    }

    var serviceUUID: CBUUID {
        switch self {
        case .bookoo: return BookooProtocol.serviceUUID
        case .timemoreDot: return TimemoreDotProtocol.serviceUUID
        }
    }

    var notifyUUID: CBUUID {
        switch self {
        case .bookoo: return BookooProtocol.weightCharacteristicUUID
        case .timemoreDot: return TimemoreDotProtocol.notifyCharacteristicUUID
        }
    }

    var commandUUID: CBUUID {
        switch self {
        case .bookoo: return BookooProtocol.commandCharacteristicUUID
        case .timemoreDot: return TimemoreDotProtocol.commandCharacteristicUUID
        }
    }

    /// Which scale an advertisement belongs to, nil for anything else (the BOOKOO Espresso Monitor is not a scale).
    static func detect(name: String?, services: [CBUUID]) -> ScaleModel? {
        if BookooMonitorProtocol.isMonitor(name: name) { return nil }
        if let name, name.lowercased().contains(BookooProtocol.namePrefix) { return .bookoo }
        if TimemoreDotProtocol.isDot(name: name) { return .timemoreDot }
        if services.contains(BookooProtocol.serviceUUID) { return .bookoo }
        // A nameless FFF0 advertisement: a Dot outside pairing mode. The FFF0 service check on connect rejects others.
        if (name ?? "").isEmpty, services.contains(TimemoreDotProtocol.serviceUUID) { return .timemoreDot }
        return nil
    }
}
