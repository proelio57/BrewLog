package com.brewlog.app

import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.PressureSample
import com.brewlog.app.domain.Recipe
import com.brewlog.app.scale.BookooPressurePacketValidator
import com.brewlog.app.scale.BookooPressureProtocol
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.roundToInt

class PressureMonitorUnitTest {

    companion object {
        /** Builds a 10-byte extraction data packet as the BOOKOO Espresso Monitor sends it. */
        fun packet(bar: Double, battery: Int = 92, header: Int = 0x1B): ByteArray {
            val raw = (bar * 100).roundToInt()
            return intArrayOf(0x02, header, 0x00, 0x00, (raw shr 8) and 0xFF, raw and 0xFF, battery, 0x00, 0x00, 0x00)
                .map { it.toByte() }.toByteArray()
        }
    }

    @Test
    fun parsesPressureAndBattery() {
        val reading = BookooPressureProtocol.parse(packet(9.25, battery = 88))
        assertNotNull(reading)
        assertEquals(9.25, reading!!.bar, 0.001)
        assertEquals(88, reading.batteryPercent)
        // Same bytes as the iOS test: 02 1B 00 00 03 84 50 … → 9.00 bar, 80 %
        val ios = intArrayOf(0x02, 0x1B, 0x00, 0x00, 0x03, 0x84, 0x50, 0x00, 0x00, 0x00).map { it.toByte() }.toByteArray()
        assertEquals(BookooPressureProtocol.Reading(9.0, 80), BookooPressureProtocol.parse(ios))
    }

    @Test
    fun rejectsMalformedAndOutOfBoundsPackets() {
        assertNull(BookooPressureProtocol.parse(ByteArray(0)))
        assertNull(BookooPressureProtocol.parse(ByteArray(6)))
        assertNull(BookooPressureProtocol.parse(ByteArray(21)))
        assertNull(BookooPressureProtocol.parse(packet(5.0, header = 0x0B)))
        assertNull(BookooPressureProtocol.parse(packet(25.0)))
        // A scale packet (03 0B …) is not a pressure packet.
        assertNull(BookooPressureProtocol.parse(byteArrayOf(0x03, 0x0B, 0, 0, 3, 0x84.toByte(), 50, 0, 0, 0)))
    }

    @Test
    fun clampsBattery() {
        assertEquals(100, BookooPressureProtocol.parse(packet(9.0, battery = 150))!!.batteryPercent)
    }

    @Test
    fun commandsMatchTheSpecAndAreDefensiveCopies() {
        fun bytes(vararg v: Int) = v.map { it.toByte() }.toByteArray()
        assertArrayEquals(bytes(0x02, 0x0C, 0x01, 0x00, 0x00, 0x00, 0x0F), BookooPressureProtocol.Command.START_MONITOR.packet())
        assertArrayEquals(bytes(0x02, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x0E), BookooPressureProtocol.Command.STOP_MONITOR.packet())
        for (command in BookooPressureProtocol.Command.entries) {
            val packet = command.packet()
            assertEquals(packet.last().toInt() and 0xFF, BookooPressureProtocol.checksum(packet))
        }
        val copy = BookooPressureProtocol.Command.START_MONITOR.packet()
        copy[0] = 0x7F
        assertEquals(0x02.toByte(), BookooPressureProtocol.Command.START_MONITOR.packet()[0])
    }

    @Test
    fun monitorNamesDontMatchTheScale() {
        assertTrue(BookooPressureProtocol.isMonitorName("BOOKOO_EM 0A12"))
        assertFalse(BookooPressureProtocol.isMonitorName("BOOKOO_SC 77F1"))
        assertFalse(BookooPressureProtocol.isMonitorName(null))
    }

    @Test
    fun validatorCountsRejectedPackets() {
        val validator = BookooPressurePacketValidator()
        assertNotNull(validator.accept(packet(9.0)))
        assertNull(validator.accept(ByteArray(3)))
        assertEquals(1, validator.rejected)
        validator.reset()
        assertEquals(0, validator.rejected)
    }

    @Test
    fun pressureSampleModelSerializationAndBrewIntegration() {
        val samples = listOf(
            PressureSample(t = 0.0, bar = 0.0),
            PressureSample(t = 3.0, bar = 2.8),
            PressureSample(t = 7.0, bar = 9.0),
            PressureSample(t = 25.0, bar = 7.2),
        )

        val brew = Brew(
            recipeId = "espresso",
            recipeName = "Classic Espresso",
            dose = 18.0,
            targetWater = 36.0,
            finalWeight = 36.2,
            totalTime = 28.5,
            waterTemp = 93.0,
            grindSetting = "10 clicks",
            grindValue = 10.0,
            pressureSamples = samples,
        )

        assertEquals(4, brew.pressureSamples.size)
        assertEquals(9.0, brew.pressureSamples[2].bar, 0.001)
        assertEquals(7.0, brew.pressureSamples[2].t, 0.001)
    }

    @Test
    fun demoPressureMonitorEmitsRealisticEspressoCurve() = runBlocking {
        val emitted = mutableListOf<Double>()
        val monitor = com.brewlog.app.scale.DemoPressureMonitor(
            scope = this,
            onPressure = { emitted.add(it) },
        )

        monitor.start()
        monitor.simulateShot(durationSeconds = 25.0)

        delay(250)
        assertTrue(emitted.isNotEmpty())

        monitor.stop()
    }

    @Test
    fun demoPressureMonitorFollowsRecipeTargetTime() = runBlocking {
        val emitted = mutableListOf<Double>()
        val monitor = com.brewlog.app.scale.DemoPressureMonitor(
            scope = this,
            onPressure = { emitted.add(it) },
        )

        monitor.start()
        val recipe = Recipe(
            id = "espresso-test",
            name = "Test Espresso",
            targetTime = 28.0,
            water = 36.0,
        )
        monitor.simulate(recipe)

        delay(200)
        assertTrue(emitted.isNotEmpty())
        monitor.tare()
        monitor.stopSimulation()
        monitor.stop()
    }
}
