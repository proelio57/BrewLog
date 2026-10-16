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
        /** Builds a 20-byte pressure monitor packet conforming to BOOKOO specification. */
        fun packet(
            bar: Double,
            negative: Boolean = false,
            battery: Int = 92,
            validChecksum: Boolean = true,
            header: Int = 0x0B,
        ): ByteArray {
            val raw = (abs(bar) * 100).roundToInt()
            val b = intArrayOf(
                0x03, header, 0x00, 0x05, 0x10, 0x01, if (negative) 0x2D else 0x2B,
                (raw shr 16) and 0xFF, (raw shr 8) and 0xFF, raw and 0xFF,
                0x2B, 0x00, 0x00,
                battery, 0x00, 0x20, 0x01, 0x00, 0x00,
            )
            val sum = b.fold(0) { acc, v -> acc xor v }
            return (b + (if (validChecksum) sum else sum xor 0xFF)).map { it.toByte() }.toByteArray()
        }
    }

    @Test
    fun parsesPressureBatteryAndMilliseconds() {
        val reading = BookooPressureProtocol.parse(packet(9.25, battery = 88))
        assertNotNull(reading)
        assertEquals(9.25, reading!!.bar, 0.001)
        assertEquals(88, reading.batteryPercent)
        assertEquals(0x000510, reading.milliseconds)
        assertTrue(reading.checksumValid)
    }

    @Test
    fun parsesNegativePressureZeroDrift() {
        val reading = BookooPressureProtocol.parse(packet(0.35, negative = true))
        assertNotNull(reading)
        assertEquals(-0.35, reading!!.bar, 0.001)
    }

    @Test
    fun parsesExtractionHeader() {
        val reading = BookooPressureProtocol.parse(packet(8.5, header = 0x0C))
        assertNotNull(reading)
        assertEquals(8.5, reading!!.bar, 0.001)
    }

    @Test
    fun rejectsMalformedAndOutOfBoundsPackets() {
        assertNull(BookooPressureProtocol.parse(ByteArray(0)))
        assertNull(BookooPressureProtocol.parse(ByteArray(19)))
        assertNull(BookooPressureProtocol.parse(ByteArray(65)))
        // Wrong starting magic byte
        assertNull(BookooPressureProtocol.parse(ByteArray(20) { 0x01 }))
        // Wrong header byte
        assertNull(BookooPressureProtocol.parse(packet(5.0, header = 0x0A)))
        // Pressure beyond plausible espresso transducer limit (> 20 bar)
        assertNull(BookooPressureProtocol.parse(packet(25.0)))
        // Pressure negative beyond calibration drift (< -1.0 bar)
        assertNull(BookooPressureProtocol.parse(packet(2.0, negative = true)))
    }

    @Test
    fun clampsBatteryAndFlagsInvalidChecksum() {
        val reading = BookooPressureProtocol.parse(packet(9.0, battery = 150, validChecksum = false))
        assertNotNull(reading)
        assertEquals(100, reading!!.batteryPercent)
        assertFalse(reading.checksumValid)
    }

    @Test
    fun commandsAreStrictlyAllowlistedAndDefensiveCopies() {
        fun bytes(vararg v: Int) = v.map { it.toByte() }.toByteArray()
        assertArrayEquals(bytes(0x03, 0x0A, 0x01, 0x00, 0x00, 0x08), BookooPressureProtocol.Command.TARE_PRESSURE.packet())
        assertArrayEquals(bytes(0x03, 0x0A, 0x04, 0x00, 0x00, 0x0A), BookooPressureProtocol.Command.START_MONITOR.packet())
        assertArrayEquals(bytes(0x03, 0x0A, 0x05, 0x00, 0x00, 0x0D), BookooPressureProtocol.Command.STOP_MONITOR.packet())
        assertArrayEquals(bytes(0x03, 0x0A, 0x07, 0x00, 0x00, 0x0E), BookooPressureProtocol.Command.ZERO_CALIBRATE.packet())

        // Ensure returned packets are defensive copies
        val copy = BookooPressureProtocol.Command.TARE_PRESSURE.packet()
        copy[0] = 0xFF.toByte()
        assertEquals(0x03.toByte(), BookooPressureProtocol.Command.TARE_PRESSURE.packet()[0])
    }

    @Test
    fun validatorLearnsAndEnforcesValidChecksums() {
        val validator = BookooPressurePacketValidator(learningPackets = 10)
        repeat(10) {
            assertNotNull(validator.accept(packet(9.0, validChecksum = true)))
        }
        assertEquals(BookooPressurePacketValidator.Policy.ENFORCED, validator.policy)
        assertEquals(0, validator.rejected)

        // Once enforced, corrupt checksum is rejected
        assertNull(validator.accept(packet(9.0, validChecksum = false)))
        assertEquals(1, validator.rejected)
    }

    @Test
    fun validatorFallsBackGracefullyIfChecksumsAreOmitted() {
        val validator = BookooPressurePacketValidator(learningPackets = 10)
        repeat(10) {
            assertNotNull(validator.accept(packet(9.0, validChecksum = false)))
        }
        assertEquals(BookooPressurePacketValidator.Policy.IGNORED, validator.policy)
        // Accepts subsequent packets even with invalid checksum
        assertNotNull(validator.accept(packet(8.5, validChecksum = false)))
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
