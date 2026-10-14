import XCTest
@testable import BrewLog

final class BookooProtocolTests: XCTestCase {

    /// Builds a weight packet as documented by BOOKOO.
    static func packet(grams: Double, negative: Bool = false, flow: Double = 0, battery: UInt8 = 87,
                       validChecksum: Bool = true, header: UInt8 = 0x0B) -> Data {
        let raw = Int((abs(grams) * 100).rounded())
        let flowRaw = Int((abs(flow) * 100).rounded())
        var b: [UInt8] = [0x03, header,
                          0x00, 0x10, 0x20,                         // ms
                          0x01,                                     // unit
                          negative ? 0x2D : 0x2B,                   // sign
                          UInt8((raw >> 16) & 0xFF), UInt8((raw >> 8) & 0xFF), UInt8(raw & 0xFF),
                          flow < 0 ? 0x2D : 0x2B,
                          UInt8((flowRaw >> 8) & 0xFF), UInt8(flowRaw & 0xFF),
                          battery,
                          0x00, 0x32,                               // standby
                          0x03, 0x01, 0x00]                         // buzzer, smoothing, reserved
        let checksum = b.reduce(0, ^)
        b.append(validChecksum ? checksum : checksum ^ 0xFF)
        return Data(b)
    }

    func testParsesWeightFlowAndBattery() throws {
        let reading = try XCTUnwrap(BookooProtocol.parse(Self.packet(grams: 123.45, flow: 4.5, battery: 87)))
        XCTAssertEqual(reading.grams, 123.45, accuracy: 0.001)
        XCTAssertEqual(reading.flowRate, 4.5, accuracy: 0.001)
        XCTAssertEqual(reading.batteryPercent, 87)
        XCTAssertEqual(reading.milliseconds, 0x001020)
        XCTAssertTrue(reading.checksumValid)
    }

    func testParsesNegativeWeight() throws {
        let reading = try XCTUnwrap(BookooProtocol.parse(Self.packet(grams: 2.3, negative: true)))
        XCTAssertEqual(reading.grams, -2.3, accuracy: 0.001)
    }

    func testRejectsMalformedPackets() {
        XCTAssertNil(BookooProtocol.parse(Data()), "empty")
        XCTAssertNil(BookooProtocol.parse(Data(repeating: 0x03, count: 19)), "too short")
        XCTAssertNil(BookooProtocol.parse(Data(repeating: 0x03, count: 200)), "too long")
        XCTAssertNil(BookooProtocol.parse(Self.packet(grams: 10, header: 0x0A)), "wrong type byte")
        XCTAssertNil(BookooProtocol.parse(Self.packet(grams: 90_000)), "implausible weight")
    }

    func testClampsBattery() throws {
        let reading = try XCTUnwrap(BookooProtocol.parse(Self.packet(grams: 1, battery: 250)))
        XCTAssertEqual(reading.batteryPercent, 100)
    }

    func testDetectsBadChecksum() throws {
        let reading = try XCTUnwrap(BookooProtocol.parse(Self.packet(grams: 5, validChecksum: false)))
        XCTAssertFalse(reading.checksumValid)
    }

    func testCommandAllowlistMatchesKnownGoodPackets() {
        XCTAssertEqual([UInt8](BookooProtocol.Command.tare.packet), [0x03, 0x0A, 0x01, 0x00, 0x00, 0x08])
        XCTAssertEqual([UInt8](BookooProtocol.Command.startTimer.packet), [0x03, 0x0A, 0x04, 0x00, 0x00, 0x0A])
        XCTAssertEqual([UInt8](BookooProtocol.Command.stopTimer.packet), [0x03, 0x0A, 0x05, 0x00, 0x00, 0x0D])
        XCTAssertEqual([UInt8](BookooProtocol.Command.resetTimer.packet), [0x03, 0x0A, 0x06, 0x00, 0x00, 0x0C])
        for command in BookooProtocol.Command.allCases {
            XCTAssertEqual(command.packet.count, 6)
            XCTAssertEqual(command.packet.first, 0x03)
        }
        // Tare checksum is a plain XOR, as documented.
        XCTAssertEqual(BookooProtocol.checksum([0x03, 0x0A, 0x01, 0x00, 0x00]), 0x08)
    }

    func testValidatorEnforcesChecksumWhenFirmwareFollowsSpec() {
        var validator = BookooPacketValidator()
        for _ in 0..<10 { XCTAssertNotNil(validator.accept(Self.packet(grams: 1))) }
        XCTAssertEqual(validator.policy, .enforced)
        XCTAssertNil(validator.accept(Self.packet(grams: 1, validChecksum: false)))
        XCTAssertEqual(validator.rejected, 1)
        XCTAssertNotNil(validator.accept(Self.packet(grams: 2)))
    }

    func testValidatorFallsBackWhenChecksumsNeverMatch() {
        var validator = BookooPacketValidator()
        for _ in 0..<10 { _ = validator.accept(Self.packet(grams: 1, validChecksum: false)) }
        XCTAssertEqual(validator.policy, .ignored)
        XCTAssertNotNil(validator.accept(Self.packet(grams: 3, validChecksum: false)))
        // Plausibility checks still apply.
        XCTAssertNil(validator.accept(Data(repeating: 0, count: 20)))
    }
}
