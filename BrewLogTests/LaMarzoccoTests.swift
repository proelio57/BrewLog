import XCTest
import CryptoKit
@testable import BrewLog

/// La Marzocco cloud: request signing and dashboard parsing. Vectors from docs/la-marzocco-protocol.md
/// (computed with pylamarzocco v2.5.6's own functions).
final class LaMarzoccoTests: XCTestCase {

    private let installationID = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"
    private let publicKeyDER = Data((0...90).map { UInt8($0) })

    // MARK: Signing

    func testProofVectors() throws {
        XCTAssertEqual(LaMarzoccoAuth.proof("abc", secret: Data(count: 32)), "P5ynD3LZU7oRYIN0D2ZtOlbpepJdBXQH9vdqJGOfq/o=")
        let secret = try XCTUnwrap(Data(base64Encoded: "EUWj84o7RXt611rkgsprs36qybfa0ZjAUFSQFvJJ2co="))
        XCTAssertEqual(LaMarzoccoAuth.proof("\(installationID).00000000-0000-4000-8000-000000000000.1762358400000", secret: secret),
                       "4rXwI3Qpk0PhDlJu+HH5iSckHEm4F9GknCUIx3iNarg=")
    }

    func testSecretAndBaseString() {
        let secret = LaMarzoccoAuth.secret(installationID: installationID, publicKeyDER: publicKeyDER)
        XCTAssertEqual(secret.base64EncodedString(), "EUWj84o7RXt611rkgsprs36qybfa0ZjAUFSQFvJJ2co=")
        let base = LaMarzoccoAuth.baseString(installationID: installationID, publicKeyDER: publicKeyDER)
        XCTAssertEqual(base, "\(installationID).WNKUWbITCi4VElLUCLlebaxCTFZAYuuRHMdkQMuSbKA=")
        XCTAssertEqual(LaMarzoccoAuth.proof(base, secret: secret), "/gmx2S9P5KtTvJ4RScjIgp96zl4CSPsaVaLcuukpVLs=")
    }

    func testSignedHeadersVerify() throws {
        let key = LaMarzoccoAuth.makeKey(installationID: "abc-id")
        XCTAssertEqual(key.secret.count, 32)
        let headers = LaMarzoccoAuth.signedHeaders(key, nonce: "n-1", now: Date(timeIntervalSince1970: 1_762_358_400))
        XCTAssertEqual(headers["X-App-Installation-Id"], "abc-id")
        XCTAssertEqual(headers["X-Timestamp"], "1762358400000")
        XCTAssertEqual(headers["X-Nonce"], "n-1")
        let signature = try P256.Signing.ECDSASignature(
            derRepresentation: try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(headers["X-Request-Signature"]))))
        let proof = LaMarzoccoAuth.proof("abc-id.n-1.1762358400000", secret: key.secret)
        let publicKey = try P256.Signing.PrivateKey(rawRepresentation: key.privateKey).publicKey
        XCTAssertTrue(publicKey.isValidSignature(signature, for: Data("abc-id.n-1.1762358400000.\(proof)".utf8)))

        let registration = LaMarzoccoAuth.registrationHeaders(key)
        XCTAssertEqual(registration["X-App-Installation-Id"], "abc-id")
        XCTAssertEqual(registration["X-Request-Proof"],
                       LaMarzoccoAuth.proof(LaMarzoccoAuth.baseString(installationID: "abc-id", publicKeyDER: publicKey.derRepresentation),
                                            secret: key.secret))
    }

    func testKeyRoundTripsThroughJSON() throws {
        let key = LaMarzoccoAuth.makeKey()
        let decoded = try JSONDecoder().decode(LaMarzoccoAuth.InstallationKey.self, from: JSONEncoder().encode(key))
        XCTAssertEqual(decoded, key)
        XCTAssertEqual(key.installationID, key.installationID.lowercased())
    }

    // MARK: Dashboard

    private func dashboard(status: String, mode: String, boiler: String = "Ready", target: Double = 94.0,
                           connected: Bool = true, extra: String = "") -> Data {
        Data("""
        { "serialNumber": "MR123456", "type": "CoffeeMachine", "connected": \(connected),
          "widgets": [
            { "code": "CMMachineStatus", "index": 1, "output": { "status": "\(status)",
              "availableModes": ["BrewingMode", "StandBy"], "mode": "\(mode)", "nextStatus": null,
              "brewingStartTime": null } },
            { "code": "CMCoffeeBoiler", "index": 1, "output": { "status": "\(boiler)", "enabled": true,
              "enabledSupported": false, "targetTemperature": \(target), "targetTemperatureMin": 80,
              "targetTemperatureMax": 100, "targetTemperatureStep": 0.1, "readyStartTime": null } }\(extra)
          ],
          "commands": [ { "id": "c-1", "status": "Success", "errorCode": null } ] }
        """.utf8)
    }

    func testDashboardBrewing() {
        var status = MachineStatus()
        let result = LaMarzoccoProtocol.apply(dashboard: dashboard(status: "Brewing", mode: "BrewingMode"), to: &status)
        XCTAssertEqual(result?.connected, true)
        XCTAssertEqual(result?.commandResults["c-1"], "Success")
        XCTAssertTrue(status.isBrewing)
        XCTAssertEqual(status.mode, MachineMode.brew.rawValue)
        XCTAssertEqual(status.targetTemperature ?? 0, 94.0, accuracy: 0.001)
        XCTAssertEqual(status.hasPressure, false, "no pressure sensor: the BOOKOO stays available")
        XCTAssertNil(status.pressure)
    }

    func testDashboardStandby() {
        var status = MachineStatus()
        _ = LaMarzoccoProtocol.apply(dashboard: dashboard(status: "Brewing", mode: "BrewingMode"), to: &status)
        _ = LaMarzoccoProtocol.apply(dashboard: dashboard(status: "StandBy", mode: "StandBy", boiler: "StandBy"), to: &status)
        XCTAssertFalse(status.isBrewing)
        XCTAssertEqual(status.mode, MachineMode.standby.rawValue)
        XCTAssertEqual(status.systemState, "standby")
    }

    func testUnknownWidgetsIgnored() {
        var status = MachineStatus()
        let extra = #", { "code": "CMSomethingNew", "index": 1, "output": { "x": [1, 2] } }, { "code": "CMNoWater" }"#
        let result = LaMarzoccoProtocol.apply(dashboard: dashboard(status: "PoweredOn", mode: "BrewingMode", extra: extra),
                                              to: &status)
        XCTAssertEqual(result?.connected, true)
        XCTAssertFalse(status.isBrewing)
        XCTAssertEqual(status.mode, MachineMode.brew.rawValue)
        // Not JSON at all (garbled or split frame): ignored, nothing changes, and it doesn't count as "online".
        let before = status
        XCTAssertNil(LaMarzoccoProtocol.apply(dashboard: Data("not json".utf8), to: &status))
        XCTAssertNil(LaMarzoccoProtocol.apply(dashboard: Data(#"{"widgets": [ {"#.utf8), to: &status))
        XCTAssertEqual(status, before)
    }

    func testOfflineMachine() {
        var status = MachineStatus()
        let result = LaMarzoccoProtocol.apply(dashboard: dashboard(status: "Brewing", mode: "BrewingMode", connected: false),
                                              to: &status)
        XCTAssertEqual(result?.connected, false)
        XCTAssertFalse(status.isBrewing, "an offline machine never starts a shot")
    }

    func testMissingConnectedIsNoChange() {
        var status = MachineStatus()
        let result = LaMarzoccoProtocol.apply(dashboard: Data(#"{"widgets": [], "commands": []}"#.utf8), to: &status)
        XCTAssertNotNil(result)
        XCTAssertNil(result?.connected, "no 'connected' key: neither online nor offline")
    }

    func testCommandID() {
        XCTAssertEqual(LaMarzoccoProtocol.commandID(Data(#"[{"id":"abc","status":"Pending"}]"#.utf8)), "abc")
        XCTAssertNil(LaMarzoccoProtocol.commandID(Data("[]".utf8)))
        XCTAssertNil(LaMarzoccoProtocol.commandID(Data("{}".utf8)))
    }

    func testBoilerNoWater() {
        var status = MachineStatus()
        _ = LaMarzoccoProtocol.apply(dashboard: dashboard(status: "PoweredOn", mode: "BrewingMode", boiler: "NoWater"), to: &status)
        XCTAssertEqual(status.systemState, "error")
        XCTAssertEqual(status.systemMessage, "No water in the tank")
    }

    func testDecodesStompFrames() throws {
        let connected = try XCTUnwrap(LaMarzoccoProtocol.parseStomp("CONNECTED\nversion:1.2\nheart-beat:0,0\n\n\u{0}"))
        XCTAssertEqual(connected.command, "CONNECTED")
        XCTAssertEqual(connected.headers["version"], "1.2")
        let message = try XCTUnwrap(LaMarzoccoProtocol.parseStomp("MESSAGE\ndestination:/ws/sn/X/dashboard\n\n{\"a\":1}\u{0}"))
        XCTAssertEqual(message.command, "MESSAGE")
        XCTAssertEqual(message.body, "{\"a\":1}")
        let noNul = try XCTUnwrap(LaMarzoccoProtocol.parseStomp("ERROR\nmessage:Bad token\n\nboom"))
        XCTAssertEqual(noNul.command, "ERROR")
        XCTAssertEqual(noNul.headers["message"], "Bad token")
        XCTAssertEqual(noNul.body, "boom")
        XCTAssertNil(LaMarzoccoProtocol.parseStomp(""))
        XCTAssertNil(LaMarzoccoProtocol.parseStomp("\n"), "heart-beat newline is not a frame")

        let frame = LaMarzoccoProtocol.stompFrame("SUBSCRIBE", headers: [("destination", "/ws/sn/X/dashboard"), ("ack", "auto")])
        XCTAssertEqual(frame, "SUBSCRIBE\ndestination:/ws/sn/X/dashboard\nack:auto\n\n\u{0}")
    }

    func testMachinesListFiltersGrinders() {
        let json = Data("""
        [ { "serialNumber": "MR1", "type": "CoffeeMachine", "name": "Micra", "modelName": "LINEA MICRA" },
          { "serialNumber": "G1", "type": "Grinder", "name": "Pico" },
          { "type": "CoffeeMachine", "name": "no serial" } ]
        """.utf8)
        XCTAssertEqual(LaMarzoccoProtocol.machines(json),
                       [LaMarzoccoProtocol.Machine(id: "MR1", name: "Micra", model: "LINEA MICRA")])
        XCTAssertEqual(LaMarzoccoProtocol.machines(Data("{}".utf8)), [])
    }

    func testTokens() {
        let tokens = LaMarzoccoProtocol.tokens(Data(#"{"accessToken":"a","refreshToken":"r","extra":1}"#.utf8))
        XCTAssertEqual(tokens?.access, "a")
        XCTAssertEqual(tokens?.refresh, "r")
        XCTAssertNil(LaMarzoccoProtocol.tokens(Data(#"{"accessToken":"a"}"#.utf8)))
    }

    func testTokenNeedsRefresh() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(LaMarzoccoProtocol.needsRefresh(expiresAt: now.addingTimeInterval(11 * 60), now: now))
        XCTAssertTrue(LaMarzoccoProtocol.needsRefresh(expiresAt: now.addingTimeInterval(9 * 60), now: now))
        XCTAssertTrue(LaMarzoccoProtocol.needsRefresh(expiresAt: now.addingTimeInterval(-60), now: now))
    }
}
