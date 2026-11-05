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
}
