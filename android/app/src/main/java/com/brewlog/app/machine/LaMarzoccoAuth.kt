package com.brewlog.app.machine

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.PublicKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import java.util.UUID

/**
 * La Marzocco's request signing for their cloud API (see docs/la-marzocco-protocol.md, from pylamarzocco v2.5.6).
 * Each BrewLog install has its own key: a P-256 key pair, a 32-byte secret derived from it and a random id.
 */
object LaMarzoccoAuth {

    data class InstallationKey(
        val installationId: String,
        val privateKeyPkcs8: ByteArray,
        val secret: ByteArray,
        val publicKeyDer: ByteArray,
    ) {
        val privateKey: PrivateKey by lazy {
            KeyFactory.getInstance("EC").generatePrivate(PKCS8EncodedKeySpec(privateKeyPkcs8))
        }

        val publicKey: PublicKey by lazy {
            KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(publicKeyDer))
        }

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is InstallationKey) return false
            return installationId == other.installationId &&
                privateKeyPkcs8.contentEquals(other.privateKeyPkcs8) &&
                secret.contentEquals(other.secret) &&
                publicKeyDer.contentEquals(other.publicKeyDer)
        }

        override fun hashCode(): Int {
            var result = installationId.hashCode()
            result = 31 * result + privateKeyPkcs8.contentHashCode()
            result = 31 * result + secret.contentHashCode()
            result = 31 * result + publicKeyDer.contentHashCode()
            return result
        }

        fun toJson(): String {
            return buildJsonObject {
                put("installationId", installationId)
                put("privateKeyPkcs8", Base64.getEncoder().encodeToString(privateKeyPkcs8))
                put("secret", Base64.getEncoder().encodeToString(secret))
                put("publicKeyDer", Base64.getEncoder().encodeToString(publicKeyDer))
            }.toString()
        }

        companion object {
            fun fromJson(json: String): InstallationKey? = runCatching {
                val obj = Json.parseToJsonElement(json).jsonObject
                val id = (obj["installationId"] ?: obj["installationID"])?.jsonPrimitive?.content ?: return null
                InstallationKey(
                    installationId = id.lowercase(),
                    privateKeyPkcs8 = Base64.getDecoder().decode(obj["privateKeyPkcs8"]?.jsonPrimitive?.content ?: ""),
                    secret = Base64.getDecoder().decode(obj["secret"]?.jsonPrimitive?.content ?: ""),
                    publicKeyDer = Base64.getDecoder().decode(obj["publicKeyDer"]?.jsonPrimitive?.content ?: ""),
                )
            }.getOrNull()
        }
    }

    fun makeKey(installationId: String = UUID.randomUUID().toString().lowercase()): InstallationKey {
        val generator = KeyPairGenerator.getInstance("EC")
        generator.initialize(ECGenParameterSpec("secp256r1"))
        val pair = generator.generateKeyPair()
        val pubDer = pair.public.encoded
        val privPkcs8 = pair.private.encoded
        val id = installationId.lowercase()
        val sec = secret(id, pubDer)
        return InstallationKey(
            installationId = id,
            privateKeyPkcs8 = privPkcs8,
            secret = sec,
            publicKeyDer = pubDer,
        )
    }

    /** SHA-256 of "<id>.<base64(public key DER)>.<base64(SHA-256(id))>". */
    fun secret(installationId: String, publicKeyDer: ByteArray): ByteArray {
        val md = MessageDigest.getInstance("SHA-256")
        val idHash = Base64.getEncoder().encodeToString(md.digest(installationId.toByteArray(Charsets.UTF_8)))
        val pubB64 = Base64.getEncoder().encodeToString(publicKeyDer)
        val triple = "$installationId.$pubB64.$idHash"
        return md.digest(triple.toByteArray(Charsets.UTF_8))
    }

    /** "<id>.<base64(SHA-256(public key DER))>", proven once when registering. */
    fun baseString(installationId: String, publicKeyDer: ByteArray): String {
        val md = MessageDigest.getInstance("SHA-256")
        val pubHash = Base64.getEncoder().encodeToString(md.digest(publicKeyDer))
        return "$installationId.$pubHash"
    }

    /** La Marzocco's proof: mixes the input into a copy of the secret (XOR + rotate left), then SHA-256, base64. */
    fun proof(input: String, secret: ByteArray): String {
        if (secret.size != 32) return ""
        val work = secret.copyOf()
        val inputBytes = input.toByteArray(Charsets.UTF_8)
        for (b in inputBytes) {
            val byteVal = b.toInt() and 0xFF
            val index = byteVal % 32
            val shift = (work[(index + 1) % 32].toInt() and 0xFF) and 7
            val mixed = (byteVal xor (work[index].toInt() and 0xFF)) and 0xFF
            val rotated = if (shift == 0) {
                mixed
            } else {
                ((mixed shl shift) or (mixed ushr (8 - shift))) and 0xFF
            }
            work[index] = rotated.toByte()
        }
        val md = MessageDigest.getInstance("SHA-256")
        val hash = md.digest(work)
        return Base64.getEncoder().encodeToString(hash)
    }

    /** Headers for every request after registration (sign-in included): id, time, nonce and an ECDSA signature. */
    fun signedHeaders(
        key: InstallationKey,
        nonce: String = UUID.randomUUID().toString().lowercase(),
        nowMs: Long = System.currentTimeMillis(),
    ): Map<String, String> {
        val timestamp = nowMs.toString()
        val input = "${key.installationId}.$nonce.$timestamp"
        val data = "$input.${proof(input, key.secret)}".toByteArray(Charsets.UTF_8)
        val signer = Signature.getInstance("SHA256withECDSA")
        signer.initSign(key.privateKey)
        signer.update(data)
        val signature = Base64.getEncoder().encodeToString(signer.sign())
        return mapOf(
            "X-App-Installation-Id" to key.installationId,
            "X-Timestamp" to timestamp,
            "X-Nonce" to nonce,
            "X-Request-Signature" to signature,
        )
    }

    /** Headers for registering the key once (`POST /auth/init`, body `{"pk": base64(public key DER)}`). */
    fun registrationHeaders(key: InstallationKey): Map<String, String> {
        return mapOf(
            "X-App-Installation-Id" to key.installationId,
            "X-Request-Proof" to proof(baseString(key.installationId, key.publicKeyDer), key.secret),
        )
    }
}
