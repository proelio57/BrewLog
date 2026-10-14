import Foundation
import CoreBluetooth

/// BOOKOO Themis Mini BLE protocol.
/// Source: https://github.com/BooKooCode/OpenSource/blob/main/bookoo_mini_scale/protocols.md
/// and Beanconqueror's field-tested implementation (`bokooScale.ts`).
/// Kept free of UI code so it can be ported 1:1 to Kotlin.
enum BookooProtocol {
    static let serviceUUID = CBUUID(string: "0FFE")
    /// Weight notifications (20-byte packets)
    static let weightCharacteristicUUID = CBUUID(string: "FF11")
    /// Commands (6-byte packets)
    static let commandCharacteristicUUID = CBUUID(string: "FF12")
    /// Advertised name prefix, e.g. "BOOKOO_SC xxxx"
    static let namePrefix = "bookoo"

    static let weightPacketLength = 20
    /// Anything longer than this is rejected outright.
    static let maxPacketLength = 64
    /// Themis Mini capacity is 2 kg. Anything far outside is garbage.
    static let plausibleWeightRange: ClosedRange<Double> = -3_000...5_000
    static let plausibleFlowRange: ClosedRange<Double> = -200...200

    /// The only commands BrewLog ever sends (write allowlist).
    enum Command: CaseIterable {
        case tare, startTimer, stopTimer, resetTimer

        /// Fixed, field-tested byte sequences (identical to Beanconqueror's).
        /// Note: the timer checksums don't match a plain XOR, so they're kept verbatim instead of computed.
        var packet: Data {
            switch self {
            case .tare: return Data([0x03, 0x0A, 0x01, 0x00, 0x00, 0x08])
            case .startTimer: return Data([0x03, 0x0A, 0x04, 0x00, 0x00, 0x0A])
            case .stopTimer: return Data([0x03, 0x0A, 0x05, 0x00, 0x00, 0x0D])
            case .resetTimer: return Data([0x03, 0x0A, 0x06, 0x00, 0x00, 0x0C])
            }
        }
    }

    struct Reading: Equatable {
        /// Scale's internal timer in milliseconds
        var milliseconds: Int
        var grams: Double
        var flowRate: Double
        var batteryPercent: Int
        /// Whether byte 20 matched the documented XOR checksum.
        var checksumValid: Bool
    }

    static func checksum<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(0, ^)
    }

    /// Parses a weight notification. Returns nil for anything malformed or implausible.
    static func parse(_ data: Data) -> Reading? {
        guard data.count >= weightPacketLength, data.count <= maxPacketLength else { return nil }
        let b = [UInt8](data.prefix(weightPacketLength))
        guard b[0] == 0x03, b[1] == 0x0B else { return nil }

        let ms = Int(b[2]) << 16 | Int(b[3]) << 8 | Int(b[4])
        var grams = Double(Int(b[7]) << 16 | Int(b[8]) << 8 | Int(b[9])) / 100.0
        if b[6] == 0x2D { grams = -grams } // '-'
        var flow = Double(Int(b[11]) << 8 | Int(b[12])) / 100.0
        if b[10] == 0x2D { flow = -flow }

        guard plausibleWeightRange.contains(grams), plausibleFlowRange.contains(flow) else { return nil }
        let battery = min(Int(b[13]), 100)
        let valid = checksum(b[0..<19]) == b[19]
        return Reading(milliseconds: ms, grams: grams, flowRate: flow, batteryPercent: battery, checksumValid: valid)
    }
}

/// Decides whether to enforce checksums. If the scale's firmware follows the documented XOR checksum,
/// it is enforced after a short learning phase. If not, BrewLog falls back to the plausibility checks only.
struct BookooPacketValidator {
    enum Policy: Equatable { case learning, enforced, ignored }

    private(set) var policy: Policy = .learning
    private(set) var rejected = 0
    private var seen = 0
    private var valid = 0
    private let learningPackets = 10

    mutating func accept(_ data: Data) -> BookooProtocol.Reading? {
        guard let reading = BookooProtocol.parse(data) else {
            rejected += 1
            return nil
        }
        switch policy {
        case .learning:
            seen += 1
            if reading.checksumValid { valid += 1 }
            if seen >= learningPackets {
                policy = valid * 10 >= seen * 9 ? .enforced : .ignored
            }
            return reading
        case .enforced:
            guard reading.checksumValid else {
                rejected += 1
                return nil
            }
            return reading
        case .ignored:
            return reading
        }
    }

    mutating func reset() {
        self = BookooPacketValidator()
    }
}
