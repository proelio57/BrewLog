package com.brewlog.app

import com.brewlog.app.machine.LaMarzoccoAuth
import com.brewlog.app.machine.LaMarzoccoProtocol
import com.brewlog.app.machine.MachineMode
import com.brewlog.app.machine.MachineStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.Signature
import java.util.Base64

class LaMarzoccoTest {

    private val installationID = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"
    private val publicKeyDER = ByteArray(91) { it.toByte() }

    // MARK: Signing

    @Test
    fun testProofVectors() {
        assertEquals("P5ynD3LZU7oRYIN0D2ZtOlbpepJdBXQH9vdqJGOfq/o=", LaMarzoccoAuth.proof("abc", ByteArray(32)))
        val secret = Base64.getDecoder().decode("EUWj84o7RXt611rkgsprs36qybfa0ZjAUFSQFvJJ2co=")
        assertEquals(
            "4rXwI3Qpk0PhDlJu+HH5iSckHEm4F9GknCUIx3iNarg=",
            LaMarzoccoAuth.proof("$installationID.00000000-0000-4000-8000-000000000000.1762358400000", secret),
        )
    }

    @Test
    fun testSecretAndBaseString() {
        val secret = LaMarzoccoAuth.secret(installationID, publicKeyDER)
        assertEquals("EUWj84o7RXt611rkgsprs36qybfa0ZjAUFSQFvJJ2co=", Base64.getEncoder().encodeToString(secret))
        val base = LaMarzoccoAuth.baseString(installationID, publicKeyDER)
        assertEquals("$installationID.WNKUWbITCi4VElLUCLlebaxCTFZAYuuRHMdkQMuSbKA=", base)
        assertEquals("/gmx2S9P5KtTvJ4RScjIgp96zl4CSPsaVaLcuukpVLs=", LaMarzoccoAuth.proof(base, secret))
    }

    @Test
    fun testSignedHeadersVerify() {
        val key = LaMarzoccoAuth.makeKey(installationId = "abc-id")
        assertEquals(32, key.secret.size)
        val headers = LaMarzoccoAuth.signedHeaders(key, nonce = "n-1", nowMs = 1762358400000L)
        assertEquals("abc-id", headers["X-App-Installation-Id"])
        assertEquals("1762358400000", headers["X-Timestamp"])
        assertEquals("n-1", headers["X-Nonce"])

        val verifier = Signature.getInstance("SHA256withECDSA")
        verifier.initVerify(key.publicKey)
        val proof = LaMarzoccoAuth.proof("abc-id.n-1.1762358400000", key.secret)
        verifier.update("abc-id.n-1.1762358400000.$proof".toByteArray(Charsets.UTF_8))
        val sigBytes = Base64.getDecoder().decode(headers["X-Request-Signature"]!!)
        assertTrue(verifier.verify(sigBytes))

        val registration = LaMarzoccoAuth.registrationHeaders(key)
        assertEquals("abc-id", registration["X-App-Installation-Id"])
        assertEquals(
            LaMarzoccoAuth.proof(LaMarzoccoAuth.baseString("abc-id", key.publicKeyDer), key.secret),
            registration["X-Request-Proof"],
        )
    }

    @Test
    fun testKeyRoundTripsThroughJSON() {
        val key = LaMarzoccoAuth.makeKey()
        val json = key.toJson()
        val decoded = LaMarzoccoAuth.InstallationKey.fromJson(json)
        assertEquals(key, decoded)
        assertEquals(key.installationId, key.installationId.lowercase())
    }

    // MARK: Dashboard

    private fun dashboard(
        status: String,
        mode: String,
        boiler: String = "Ready",
        target: Double = 94.0,
        connected: Boolean = true,
        extra: String = "",
    ): ByteArray {
        return """
        { "serialNumber": "MR123456", "type": "CoffeeMachine", "connected": $connected,
          "widgets": [
            { "code": "CMMachineStatus", "index": 1, "output": { "status": "$status",
              "availableModes": ["BrewingMode", "StandBy"], "mode": "$mode", "nextStatus": null,
              "brewingStartTime": null } },
            { "code": "CMCoffeeBoiler", "index": 1, "output": { "status": "$boiler", "enabled": true,
              "enabledSupported": false, "targetTemperature": $target, "targetTemperatureMin": 80,
              "targetTemperatureMax": 100, "targetTemperatureStep": 0.1, "readyStartTime": null } }$extra
          ],
          "commands": [ { "id": "c-1", "status": "Success", "errorCode": null } ] }
        """.trimIndent().toByteArray(Charsets.UTF_8)
    }

    @Test
    fun testDashboardBrewing() {
        var status = MachineStatus()
        val result = LaMarzoccoProtocol.apply(dashboard(status = "Brewing", mode = "BrewingMode"), status)
        assertNotNull(result)
        status = result!!.status
        assertEquals(true, result.connected)
        assertEquals("Success", result.commandResults["c-1"])
        assertTrue(status.isBrewing)
        assertEquals(MachineMode.BREW.rawValue, status.mode)
        assertEquals(94.0, status.targetTemperature ?: 0.0, 0.001)
        assertEquals(false, status.hasPressure)
        assertNull(status.pressure)
    }

    @Test
    fun testDashboardStandby() {
        var status = MachineStatus()
        status = LaMarzoccoProtocol.apply(dashboard(status = "Brewing", mode = "BrewingMode"), status)!!.status
        val result = LaMarzoccoProtocol.apply(dashboard(status = "StandBy", mode = "StandBy", boiler = "StandBy"), status)
        assertNotNull(result)
        status = result!!.status
        assertFalse(status.isBrewing)
        assertEquals(MachineMode.STANDBY.rawValue, status.mode)
        assertEquals("standby", status.systemState)
    }

    @Test
    fun testUnknownWidgetsIgnored() {
        var status = MachineStatus()
        val extra = """, { "code": "CMSomethingNew", "index": 1, "output": { "x": [1, 2] } }, { "code": "CMNoWater" }"""
        val result = LaMarzoccoProtocol.apply(dashboard(status = "PoweredOn", mode = "BrewingMode", extra = extra), status)
        assertNotNull(result)
        status = result!!.status
        assertEquals(true, result.connected)
        assertFalse(status.isBrewing)
        assertEquals(MachineMode.BREW.rawValue, status.mode)

        val before = status
        assertNull(LaMarzoccoProtocol.apply("not json".toByteArray(Charsets.UTF_8), status))
        assertNull(LaMarzoccoProtocol.apply("""{"widgets": [ {""".toByteArray(Charsets.UTF_8), status))
        assertEquals(before, status)
    }

    @Test
    fun testOfflineMachine() {
        var status = MachineStatus()
        val result = LaMarzoccoProtocol.apply(dashboard(status = "Brewing", mode = "BrewingMode", connected = false), status)
        assertNotNull(result)
        status = result!!.status
        assertEquals(false, result.connected)
        assertFalse(status.isBrewing)
    }

    @Test
    fun testMissingConnectedIsNoChange() {
        val status = MachineStatus()
        val result = LaMarzoccoProtocol.apply("""{"widgets": [], "commands": []}""".toByteArray(Charsets.UTF_8), status)
        assertNotNull(result)
        assertNull(result?.connected)
    }

    @Test
    fun testCommandID() {
        assertEquals("abc", LaMarzoccoProtocol.commandID("""[{"id":"abc","status":"Pending"}]""".toByteArray(Charsets.UTF_8)))
        assertNull(LaMarzoccoProtocol.commandID("[]".toByteArray(Charsets.UTF_8)))
        assertNull(LaMarzoccoProtocol.commandID("{}".toByteArray(Charsets.UTF_8)))
    }

    @Test
    fun testBoilerNoWater() {
        var status = MachineStatus()
        status = LaMarzoccoProtocol.apply(dashboard(status = "PoweredOn", mode = "BrewingMode", boiler = "NoWater"), status)!!.status
        assertEquals("error", status.systemState)
        assertEquals("No water in the tank", status.systemMessage)
    }

    @Test
    fun testDecodesStompFrames() {
        val connected = LaMarzoccoProtocol.parseStomp("CONNECTED\nversion:1.2\nheart-beat:0,0\n\n\u0000")
        assertNotNull(connected)
        assertEquals("CONNECTED", connected!!.command)
        assertEquals("1.2", connected.headers["version"])

        val message = LaMarzoccoProtocol.parseStomp("MESSAGE\ndestination:/ws/sn/X/dashboard\n\n{\"a\":1}\u0000")
        assertNotNull(message)
        assertEquals("MESSAGE", message!!.command)
        assertEquals("{\"a\":1}", message.body)

        val noNul = LaMarzoccoProtocol.parseStomp("ERROR\nmessage:Bad token\n\nboom")
        assertNotNull(noNul)
        assertEquals("ERROR", noNul!!.command)
        assertEquals("Bad token", noNul.headers["message"])
        assertEquals("boom", noNul.body)

        assertNull(LaMarzoccoProtocol.parseStomp(""))
        assertNull(LaMarzoccoProtocol.parseStomp("\n"))

        val frame = LaMarzoccoProtocol.stompFrame("SUBSCRIBE", listOf("destination" to "/ws/sn/X/dashboard", "ack" to "auto"))
        assertEquals("SUBSCRIBE\ndestination:/ws/sn/X/dashboard\nack:auto\n\n\u0000", frame)
    }

    @Test
    fun testMachinesListFiltersGrinders() {
        val json = """
        [ { "serialNumber": "MR1", "type": "CoffeeMachine", "name": "Micra", "modelName": "LINEA MICRA" },
          { "serialNumber": "G1", "type": "Grinder", "name": "Pico" },
          { "type": "CoffeeMachine", "name": "no serial" } ]
        """.trimIndent().toByteArray(Charsets.UTF_8)
        assertEquals(
            listOf(LaMarzoccoProtocol.Machine(id = "MR1", name = "Micra", model = "LINEA MICRA")),
            LaMarzoccoProtocol.machines(json),
        )
        assertEquals(emptyList<LaMarzoccoProtocol.Machine>(), LaMarzoccoProtocol.machines("{}".toByteArray(Charsets.UTF_8)))
    }

    @Test
    fun testTokens() {
        val tokens = LaMarzoccoProtocol.tokens("""{"accessToken":"a","refreshToken":"r","extra":1}""".toByteArray(Charsets.UTF_8))
        assertNotNull(tokens)
        assertEquals("a", tokens?.first)
        assertEquals("r", tokens?.second)
        assertNull(LaMarzoccoProtocol.tokens("""{"accessToken":"a"}""".toByteArray(Charsets.UTF_8)))
    }

    @Test
    fun testTokenNeedsRefresh() {
        val now = 1_000_000_000L
        assertFalse(LaMarzoccoProtocol.needsRefresh(expiresAtMs = now + 11 * 60 * 1000L, nowMs = now))
        assertTrue(LaMarzoccoProtocol.needsRefresh(expiresAtMs = now + 9 * 60 * 1000L, nowMs = now))
        assertTrue(LaMarzoccoProtocol.needsRefresh(expiresAtMs = now - 60 * 1000L, nowMs = now))
    }
}
