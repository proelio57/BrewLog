package com.brewlog.app

import com.brewlog.app.machine.DecentProtocol
import com.brewlog.app.machine.MachineMode
import com.brewlog.app.machine.MachineStatus
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DecentProtocolTest {

    private fun bytes(vararg values: Int): ByteArray = values.map { it.toByte() }.toByteArray()

    @Test
    fun testDecodesShotSample() {
        val data = bytes(
            0x00, 0x64,          // SampleTime
            0x90, 0x00,          // GroupPressure 9.0
            0x20, 0x00,          // GroupFlow 2.0
            0x5D, 0x00,          // MixTemp 93.0
            0x5D, 0x80, 0x00,    // HeadTemp 93.5
            0x5D, 0x00,          // SetMixTemp 93.0
            0x5D, 0x80,          // SetHeadTemp 93.5
            0x90,                // SetGroupPressure 9.0
            0x00,                // SetGroupFlow 0
            0x03,                // FrameNumber
            0x82                 // SteamTemp
        )
        val sample = DecentProtocol.sample(data)
        assertNotNull(sample)
        assertEquals(9.0, sample!!.pressure, 0.001)
        assertEquals(2.0, sample.flow, 0.001)
        assertEquals(93.0, sample.mixTemp, 0.001)
        assertEquals(93.5, sample.headTemp, 0.001)
        assertEquals(93.0, sample.targetMixTemp, 0.001)
        assertEquals(93.5, sample.targetHeadTemp, 0.001)
        assertEquals(9.0, sample.targetPressure, 0.001)
        assertEquals(0.0, sample.targetFlow, 0.001)
        assertEquals(3, sample.frame)

        var status = MachineStatus()
        status = DecentProtocol.apply(sample, status)
        assertEquals(9.0, status.pressure ?: 0.0, 0.001)
        assertEquals(93.5, status.temperature ?: 0.0, 0.001)
        assertEquals(93.5, status.targetTemperature ?: 0.0, 0.001)
        assertEquals(9.0, status.targetPressure ?: 0.0, 0.001)
        assertEquals(true, status.hasPressure)
    }

    @Test
    fun testStatesMapToShot() {
        var status = MachineStatus()
        status = DecentProtocol.apply(rawState = 4, substate = 4, status = status)
        assertTrue(status.isBrewing)
        assertEquals("infusion", status.processKind)

        status = DecentProtocol.apply(rawState = 4, substate = 5, status = status)
        assertTrue(status.isBrewing)
        assertEquals("brew", status.processKind)

        status = DecentProtocol.apply(rawState = 2, substate = 0, status = status)
        assertFalse(status.isBrewing)
        assertEquals(MachineMode.BREW.value, status.mode)

        status = DecentProtocol.apply(rawState = 0, substate = 0, status = status)
        assertEquals(MachineMode.STANDBY.value, status.mode)
    }

    @Test
    fun testFlushIsNotAShot() {
        var status = MachineStatus()
        status = DecentProtocol.apply(rawState = 15, substate = 6, status = status)
        assertFalse(status.isBrewing)

        status = DecentProtocol.apply(rawState = 6, substate = 0, status = status)
        assertFalse(status.isBrewing)
        assertEquals(MachineMode.WATER.value, status.mode)

        status = DecentProtocol.apply(rawState = 5, substate = 7, status = status)
        assertFalse(status.isBrewing)
        assertEquals(MachineMode.STEAM.value, status.mode)
    }

    @Test
    fun testErrorStateEndsShot() {
        var status = MachineStatus()
        status = DecentProtocol.apply(rawState = 4, substate = 5, status = status)
        status = DecentProtocol.apply(rawState = 11, substate = 0, status = status)
        assertFalse(status.isBrewing)
        assertEquals("error", status.systemState)

        status = DecentProtocol.apply(rawState = 4, substate = 205, status = status)
        assertFalse(status.isBrewing)
        assertTrue(status.systemMessage?.lowercase()?.contains("pressure sensor") == true)

        status = DecentProtocol.apply(rawState = 2, substate = 0, status = status)
        assertNull("the error clears once the machine is fine again", status.systemMessage)
    }

    @Test
    fun testShortPacketsAreIgnored() {
        assertNull(DecentProtocol.sample(ByteArray(18)))
        assertNull(DecentProtocol.state(byteArrayOf(4)))
        val st = DecentProtocol.state(byteArrayOf(4, 5))
        assertNotNull(st)
        assertEquals(4, st!!.state)
        assertEquals(5, st.substate)
    }

    @Test
    fun testCommands() {
        assertArrayEquals(byteArrayOf(0), DecentProtocol.command(MachineMode.STANDBY))
        assertArrayEquals(byteArrayOf(2), DecentProtocol.command(MachineMode.BREW))
        assertArrayEquals(byteArrayOf(5), DecentProtocol.command(MachineMode.STEAM))
        assertArrayEquals(byteArrayOf(6), DecentProtocol.command(MachineMode.WATER))
        assertArrayEquals(byteArrayOf(4), DecentProtocol.startShot)
        assertArrayEquals(byteArrayOf(2), DecentProtocol.stopShot)
    }
}
