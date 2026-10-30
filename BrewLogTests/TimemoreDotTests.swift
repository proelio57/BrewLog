import XCTest
@testable import BrewLog

/// Timemore Black Mirror Dot protocol. The command bytes are the frames verified against a physical Dot in
/// decentespresso/decaid #739 (timemore_dot_protocol_test.dart). No CoreBluetooth calls, so these also run on Linux.
final class TimemoreDotTests: XCTestCase {
    private func bytes(_ command: TimemoreDotProtocol.Command) -> [UInt8] { [UInt8](command.packet) }

    func testCommandFramesMatchTheVerifiedBytes() {
        XCTAssertEqual(bytes(.tare), [0xA5, 0x5A, 0x03, 0x0D, 0x00, 0x00, 0x64, 0xD1])
        XCTAssertEqual(bytes(.startTimer), [0xA5, 0x5A, 0x03, 0x02, 0x00, 0x01, 0x01, 0x18, 0x67])
        XCTAssertEqual(bytes(.stopTimer), [0xA5, 0x5A, 0x03, 0x02, 0x00, 0x01, 0x02, 0x19, 0x27])
        XCTAssertEqual(bytes(.resetTimer), [0xA5, 0x5A, 0x03, 0x02, 0x00, 0x01, 0x03, 0xD9, 0xE6])
        XCTAssertEqual(bytes(.setUnitGrams), [0xA5, 0x5A, 0x03, 0x06, 0x00, 0x01, 0x00, 0xE8, 0xA7])
        XCTAssertEqual(bytes(.setStandardMode), [0xA5, 0x5A, 0x03, 0x08, 0x00, 0x02, 0x01, 0x00, 0xEB, 0x31])
        XCTAssertEqual(bytes(.requestBattery), [0xA5, 0x5A, 0x02, 0x05, 0x00, 0x00, 0x5A, 0x51])
        XCTAssertEqual(TimemoreDotProtocol.crc16([0xA5, 0x5A, 0x03, 0x0D, 0x00, 0x00]), 0x64D1)
    }

    /// A weight notification as the Dot sends it: zero tail instead of a CRC.
    private func weightFrame(_ grams: Double, timer: Int = 0, opcode: UInt8 = 0x01) -> [UInt8] {
        let raw = UInt32(bitPattern: Int32((grams * 10).rounded()))
        let payload: [UInt8] = [UInt8(raw >> 24 & 0xFF), UInt8(raw >> 16 & 0xFF), UInt8(raw >> 8 & 0xFF), UInt8(raw & 0xFF),
                                0, 0, UInt8(timer >> 8), UInt8(timer & 0xFF), 0]
        return [0xA5, 0x5A, opcode, 0x01, 0x00, UInt8(payload.count)] + payload + [0x00, 0x00]
    }

    func testDecodesWeightTimerAndBattery() {
        var parser = TimemoreDotProtocol.Parser()
        XCTAssertEqual(parser.feed(Data(weightFrame(1234.5, timer: 42))), [.weight(grams: 1234.5, timerSeconds: 42)])
        XCTAssertEqual(parser.feed(Data(weightFrame(-12.3))), [.weight(grams: -12.3, timerSeconds: 0)])
        XCTAssertEqual(parser.feed(Data(weightFrame(1.1, opcode: 0x02))), [.weight(grams: 1.1, timerSeconds: 0)])
        XCTAssertEqual(parser.feed(Data([0xA5, 0x5A, 0x01, 0x05, 0x00, 0x02, 0x00, 0x48, 0, 0])), [.battery(72)])
        XCTAssertEqual(parser.feed(Data([0xA5, 0x5A, 0x01, 0x05, 0x00, 0x01, 80, 0, 0])), [.battery(80)])
        XCTAssertEqual(parser.feed(Data([0xA5, 0x5A, 0x01, 0x05, 0x00, 0x02, 0x00, 0x65, 0, 0])), [], "implausible battery")
        // Command acks (opcode 0x03) are ignored.
        XCTAssertEqual(parser.feed(TimemoreDotProtocol.Command.tare.packet), [])
    }

    func testReassemblesSplitPackedAndGarbledNotifications() {
        var parser = TimemoreDotProtocol.Parser()
        let frame = weightFrame(250)
        XCTAssertEqual(parser.feed(Data(frame.prefix(5))), [])
        XCTAssertEqual(parser.feed(Data(frame.dropFirst(5))), [.weight(grams: 250, timerSeconds: 0)])
        XCTAssertEqual(parser.feed(Data(weightFrame(1) + weightFrame(2))), [.weight(grams: 1, timerSeconds: 0), .weight(grams: 2, timerSeconds: 0)])
        XCTAssertEqual(parser.feed(Data([0x00, 0xFF, 0x12] + weightFrame(3))), [.weight(grams: 3, timerSeconds: 0)])
        // A length field over 64 resyncs instead of waiting forever.
        XCTAssertEqual(parser.feed(Data([0xA5, 0x5A, 0x01, 0x01, 0xFF, 0xFF] + weightFrame(4))), [.weight(grams: 4, timerSeconds: 0)])
        // Implausible weight is dropped.
        XCTAssertEqual(parser.feed(Data(weightFrame(99_999))), [])
    }

    func testRecognizesTheDot() {
        XCTAssertTrue(TimemoreDotProtocol.isDot(name: "TIMEMORE Dot"))
        XCTAssertTrue(TimemoreDotProtocol.isDot(name: "TES017-1A2B"))
        XCTAssertFalse(TimemoreDotProtocol.isDot(name: "BOOKOO_SC"))
        XCTAssertFalse(TimemoreDotProtocol.isDot(name: nil))
    }
}
