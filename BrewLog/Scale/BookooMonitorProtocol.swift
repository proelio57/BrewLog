import Foundation

/// BOOKOO Espresso Monitor (pressure sensor) BLE protocol, from BOOKOO's published spec
/// (github.com/BooKooCode/OpenSource, `espresso_monitor/protocols.md`), as also used by Beanconqueror.
///
/// - Service `0x0FFF`, commands on `0xFF01`, extraction data notifications on `0xFF02`.
/// - Data packet (10 bytes): `02 1B 00 00 <pressure×100 hi> <lo> <battery %> 00 00 00`.
/// - Commands (7 bytes, last byte = XOR of the others): start `02 0C 01 00 00 00 0F`, stop `02 0C 00 00 00 00 0E`.
enum BookooMonitorProtocol {
    static let serviceID = "0FFF"
    static let commandCharacteristicID = "FF01"
    static let dataCharacteristicID = "FF02"
    /// Advertised name, e.g. "BOOKOO_EM 1234". The scale advertises "BOOKOO_SC…", so match the full prefix.
    static let namePrefix = "bookoo_em"

    static let startCommand: [UInt8] = [0x02, 0x0C, 0x01, 0x00, 0x00, 0x00, 0x0F]
    static let stopCommand: [UInt8] = [0x02, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x0E]

    struct Reading: Equatable {
        /// Pressure in bar (0.01 resolution).
        var bar: Double
        var batteryPercent: Int
    }

    static let plausibleBar: ClosedRange<Double> = 0...20

    /// Parses an extraction data notification. Returns nil for anything that isn't a plausible pressure packet.
    static func parse(_ bytes: [UInt8]) -> Reading? {
        guard bytes.count >= 7, bytes.count <= 20, bytes[0] == 0x02, bytes[1] == 0x1B else { return nil }
        let bar = Double(UInt16(bytes[4]) << 8 | UInt16(bytes[5])) / 100
        guard plausibleBar.contains(bar) else { return nil }
        return Reading(bar: bar, batteryPercent: min(Int(bytes[6]), 100))
    }

    /// XOR of all bytes but the last, which is how BOOKOO checksums its commands.
    static func checksum(_ bytes: [UInt8]) -> UInt8 {
        bytes.dropLast().reduce(0, ^)
    }

    static func isMonitor(name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        return name.hasPrefix(namePrefix) || name.contains("espresso monitor")
    }
}
