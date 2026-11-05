import Foundation
import CryptoKit

/// La Marzocco's request signing for their cloud API (see docs/la-marzocco-protocol.md, from pylamarzocco v2.5.6).
/// Each BrewLog install has its own key: a P-256 key pair, a 32-byte secret derived from it and a random id.
enum LaMarzoccoAuth {
    struct InstallationKey: Codable, Equatable {
        let installationID: String
        /// P-256 private key, raw representation (32 bytes).
        let privateKey: Data
        let secret: Data

        var publicKeyDER: Data {
            (try? P256.Signing.PrivateKey(rawRepresentation: privateKey).publicKey.derRepresentation) ?? Data()
        }
    }

    static func makeKey(installationID: String = UUID().uuidString.lowercased()) -> InstallationKey {
        let key = P256.Signing.PrivateKey()
        let id = installationID.lowercased()
        return InstallationKey(installationID: id, privateKey: key.rawRepresentation,
                               secret: secret(installationID: id, publicKeyDER: key.publicKey.derRepresentation))
    }

    /// SHA-256 of "<id>.<base64(public key DER)>.<base64(SHA-256(id))>".
    static func secret(installationID: String, publicKeyDER: Data) -> Data {
        let idHash = Data(SHA256.hash(data: Data(installationID.utf8))).base64EncodedString()
        let triple = "\(installationID).\(publicKeyDER.base64EncodedString()).\(idHash)"
        return Data(SHA256.hash(data: Data(triple.utf8)))
    }

    /// "<id>.<base64(SHA-256(public key DER))>", proven once when registering.
    static func baseString(installationID: String, publicKeyDER: Data) -> String {
        "\(installationID).\(Data(SHA256.hash(data: publicKeyDER)).base64EncodedString())"
    }

    /// La Marzocco's proof: mixes the input into a copy of the secret (XOR + rotate left), then SHA-256, base64.
    static func proof(_ input: String, secret: Data) -> String {
        var work = [UInt8](secret)
        guard work.count == 32 else { return "" }
        for byte in input.utf8 {
            let index = Int(byte) % 32
            let shift = work[(index + 1) % 32] & 7
            let mixed = byte ^ work[index]
            work[index] = shift == 0 ? mixed : (mixed << shift) | (mixed >> (8 - shift))
        }
        return Data(SHA256.hash(data: work)).base64EncodedString()
    }

    /// Headers for every request after registration (sign-in included): id, time, nonce and an ECDSA signature.
    static func signedHeaders(_ key: InstallationKey, nonce: String = UUID().uuidString.lowercased(),
                              now: Date = Date()) -> [String: String] {
        let timestamp = String(Int64((now.timeIntervalSince1970 * 1000).rounded(.down)))
        let input = "\(key.installationID).\(nonce).\(timestamp)"
        let data = Data("\(input).\(proof(input, secret: key.secret))".utf8)
        let signature = (try? P256.Signing.PrivateKey(rawRepresentation: key.privateKey).signature(for: data))?
            .derRepresentation.base64EncodedString() ?? ""
        return [
            "X-App-Installation-Id": key.installationID,
            "X-Timestamp": timestamp,
            "X-Nonce": nonce,
            "X-Request-Signature": signature,
        ]
    }

    /// Headers for registering the key once (`POST /auth/init`, body `{"pk": base64(public key DER)}`).
    static func registrationHeaders(_ key: InstallationKey) -> [String: String] {
        [
            "X-App-Installation-Id": key.installationID,
            "X-Request-Proof": proof(baseString(installationID: key.installationID, publicKeyDER: key.publicKeyDER),
                                     secret: key.secret),
        ]
    }
}
