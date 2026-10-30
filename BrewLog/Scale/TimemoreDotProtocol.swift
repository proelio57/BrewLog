import Foundation
import CoreBluetooth

/// Timemore Black Mirror Dot (TES017) over Bluetooth LE. Community-documented protocol (decentespresso/decaid #739,
/// Sofronio/dot-scale-mate), not an official Timemore spec.
///
/// Frames: `A5 5A | opcode | cmd | length (2, big-endian) | payload | 2-byte tail`. Commands carry a CRC-16/MODBUS
/// tail (init 0xFFFF, reflected poly 0xA001, big-endian). The Dot's notifications leave the tail at `00 00`, so
/// incoming frames are checked for shape and plausibility, not CRC.
enum TimemoreDotProtocol {
    static let serviceUUID = CBUUID(string: "FFF0")
    /// Weight, timer and battery notifications (also command acks).
    static let notifyCharacteristicUUID = CBUUID(string: "FFF1")
    static let commandCharacteristicUUID = CBUUID(string: "FFF2")

    static let headerSize = 6
    static let tailSize = 2
    static let maxPayload = 64
    static let plausibleWeightRange: ClosedRange<Double> = -3_000...5_000

    /// The Dot advertises "...Dot..." or its model number; outside pairing mode it can advertise FFF0 without a name.
    static func isDot(name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        return name.contains("dot") || name.contains("tes017")
    }

    static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
        }
        return crc
    }

    static func frame(opcode: UInt8, cmd: UInt8, payload: [UInt8] = []) -> Data {
        precondition(payload.count <= maxPayload)
        let body: [UInt8] = [0xA5, 0x5A, opcode, cmd, UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)] + payload
        let crc = crc16(body)
        return Data(body + [UInt8(crc >> 8), UInt8(crc & 0xFF)])
    }

    enum Command: CaseIterable {
        case tare, startTimer, stopTimer, resetTimer, setUnitGrams, setStandardMode, requestBattery

        var packet: Data {
            switch self {
            case .tare: return frame(opcode: 0x03, cmd: 0x0D)
            case .startTimer: return frame(opcode: 0x03, cmd: 0x02, payload: [0x01])
            case .stopTimer: return frame(opcode: 0x03, cmd: 0x02, payload: [0x02])
            case .resetTimer: return frame(opcode: 0x03, cmd: 0x02, payload: [0x03])
            case .setUnitGrams: return frame(opcode: 0x03, cmd: 0x06, payload: [0x00])
            case .setStandardMode: return frame(opcode: 0x03, cmd: 0x08, payload: [0x01, 0x00])
            case .requestBattery: return frame(opcode: 0x02, cmd: 0x05)
            }
        }
    }

    /// The Dot only sends weight after unit and mode are set: (command, delay before it in seconds).
    static let initSequence: [(Command, TimeInterval)] = [(.setUnitGrams, 0.5), (.setStandardMode, 0.2), (.requestBattery, 0.1)]

    enum Event: Equatable {
        case weight(grams: Double, timerSeconds: Int)
        case battery(Int)
    }

    /// Reassembles frames that are split across or packed into notifications, and resyncs on garbage.
    struct Parser {
        private var buffer: [UInt8] = []
        private static let maxBuffer = 256

        mutating func feed(_ data: Data) -> [Event] {
            buffer.append(contentsOf: data)
            if buffer.count > Self.maxBuffer { buffer.removeFirst(buffer.count - Self.maxBuffer) }
            var events: [Event] = []
            while buffer.count >= headerSize {
                guard buffer[0] == 0xA5, buffer[1] == 0x5A else { buffer.removeFirst(); continue }
                let length = Int(buffer[4]) << 8 | Int(buffer[5])
                guard length <= maxPayload else { buffer.removeFirst(); continue }
                let total = headerSize + length + tailSize
                guard buffer.count >= total else { break }
                let opcode = buffer[2], cmd = buffer[3]
                let payload = Array(buffer[headerSize..<(headerSize + length)])
                buffer.removeFirst(total)
                if let event = Self.event(opcode: opcode, cmd: cmd, payload: payload) { events.append(event) }
            }
            return events
        }

        mutating func reset() { buffer.removeAll() }

        static func event(opcode: UInt8, cmd: UInt8, payload: [UInt8]) -> Event? {
            guard opcode != 0x03 else { return nil } // command ack
            switch cmd {
            case 0x01:
                guard payload.count >= 8 else { return nil }
                let raw = Int32(bitPattern: UInt32(payload[0]) << 24 | UInt32(payload[1]) << 16 | UInt32(payload[2]) << 8 | UInt32(payload[3]))
                let grams = Double(raw) / 10
                guard plausibleWeightRange.contains(grams) else { return nil }
                return .weight(grams: grams, timerSeconds: Int(payload[6]) << 8 | Int(payload[7]))
            case 0x05:
                guard let raw = payload.count >= 2 ? payload[1] : payload.first, raw <= 100 else { return nil }
                return .battery(Int(raw))
            default:
                return nil
            }
        }
    }
}
