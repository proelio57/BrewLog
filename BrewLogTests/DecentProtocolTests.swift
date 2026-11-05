import XCTest
@testable import BrewLog

/// Decent DE1 Bluetooth packets. Foundation only, so these also run on Linux (scripts/test-pure-swift.sh).
final class DecentProtocolTests: XCTestCase {

    private func bytes(_ values: [UInt8]) -> Data { Data(values) }

    func testDecodesShotSample() throws {
        let data = bytes([0x00, 0x64,          // SampleTime
                          0x90, 0x00,          // GroupPressure 9.0
                          0x20, 0x00,          // GroupFlow 2.0
                          0x5D, 0x00,          // MixTemp 93.0
                          0x5D, 0x80, 0x00,    // HeadTemp 93.5
                          0x5D, 0x00,          // SetMixTemp 93.0
                          0x5D, 0x80,          // SetHeadTemp 93.5
                          0x90,                // SetGroupPressure 9.0
                          0x00,                // SetGroupFlow 0
                          0x03,                // FrameNumber
                          0x82])               // SteamTemp
        let sample = try XCTUnwrap(DecentProtocol.sample(data))
        XCTAssertEqual(sample.pressure, 9.0, accuracy: 0.001)
        XCTAssertEqual(sample.flow, 2.0, accuracy: 0.001)
        XCTAssertEqual(sample.mixTemp, 93.0, accuracy: 0.001)
        XCTAssertEqual(sample.headTemp, 93.5, accuracy: 0.001)
        XCTAssertEqual(sample.targetMixTemp, 93.0, accuracy: 0.001)
        XCTAssertEqual(sample.targetHeadTemp, 93.5, accuracy: 0.001)
        XCTAssertEqual(sample.targetPressure, 9.0, accuracy: 0.001)
        XCTAssertEqual(sample.targetFlow, 0)
        XCTAssertEqual(sample.frame, 3)

        var status = MachineStatus()
        DecentProtocol.apply(sample, to: &status)
        XCTAssertEqual(status.pressure ?? 0, 9.0, accuracy: 0.001)
        XCTAssertEqual(status.temperature ?? 0, 93.5, accuracy: 0.001)
        XCTAssertEqual(status.targetTemperature ?? 0, 93.5, accuracy: 0.001)
        XCTAssertEqual(status.targetPressure ?? 0, 9.0, accuracy: 0.001)
        XCTAssertEqual(status.hasPressure, true)
    }

    func testStatesMapToShot() {
        var status = MachineStatus()
        DecentProtocol.apply(state: 4, substate: 4, to: &status)
        XCTAssertTrue(status.isBrewing)
        XCTAssertEqual(status.processKind, "infusion")
        DecentProtocol.apply(state: 4, substate: 5, to: &status)
        XCTAssertTrue(status.isBrewing)
        XCTAssertEqual(status.processKind, "brew")
        DecentProtocol.apply(state: 2, substate: 0, to: &status)
        XCTAssertFalse(status.isBrewing)
        XCTAssertEqual(status.mode, MachineMode.brew.rawValue)
        DecentProtocol.apply(state: 0, substate: 0, to: &status)
        XCTAssertEqual(status.mode, MachineMode.standby.rawValue)
    }

    func testFlushIsNotAShot() {
        var status = MachineStatus()
        DecentProtocol.apply(state: 15, substate: 6, to: &status)
        XCTAssertFalse(status.isBrewing)
        DecentProtocol.apply(state: 6, substate: 0, to: &status)
        XCTAssertFalse(status.isBrewing)
        XCTAssertEqual(status.mode, MachineMode.water.rawValue)
        DecentProtocol.apply(state: 5, substate: 7, to: &status)
        XCTAssertFalse(status.isBrewing)
        XCTAssertEqual(status.mode, MachineMode.steam.rawValue)
    }

    func testErrorStateEndsShot() {
        var status = MachineStatus()
        DecentProtocol.apply(state: 4, substate: 5, to: &status)
        DecentProtocol.apply(state: 11, substate: 0, to: &status)
        XCTAssertFalse(status.isBrewing)
        XCTAssertEqual(status.systemState, "error")
        DecentProtocol.apply(state: 4, substate: 205, to: &status)
        XCTAssertFalse(status.isBrewing)
        XCTAssertTrue(status.systemMessage?.lowercased().contains("pressure sensor") == true, status.systemMessage ?? "")
        DecentProtocol.apply(state: 2, substate: 0, to: &status)
        XCTAssertNil(status.systemMessage, "the error clears once the machine is fine again")
    }

    func testShortPacketsAreIgnored() {
        XCTAssertNil(DecentProtocol.sample(Data(repeating: 0, count: 18)))
        XCTAssertNil(DecentProtocol.state(Data([4])))
        XCTAssertEqual(DecentProtocol.state(Data([4, 5]))?.state, 4)
        XCTAssertEqual(DecentProtocol.state(Data([4, 5]))?.substate, 5)
    }

    func testCommands() {
        XCTAssertEqual(DecentProtocol.command(for: .standby), Data([0]))
        XCTAssertEqual(DecentProtocol.command(for: .brew), Data([2]))
        XCTAssertEqual(DecentProtocol.command(for: .steam), Data([5]))
        XCTAssertEqual(DecentProtocol.command(for: .water), Data([6]))
        XCTAssertEqual(DecentProtocol.startShot, Data([4]))
        XCTAssertEqual(DecentProtocol.stopShot, Data([2]))
    }
}
