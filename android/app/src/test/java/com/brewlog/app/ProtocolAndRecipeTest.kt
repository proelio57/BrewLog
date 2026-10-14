package com.brewlog.app

import com.brewlog.app.domain.GrindUnit
import com.brewlog.app.domain.GrinderSpec
import com.brewlog.app.domain.InputLimits
import com.brewlog.app.domain.RecipeLibrary
import com.brewlog.app.domain.RecipeStep
import com.brewlog.app.domain.StepKind
import com.brewlog.app.domain.TasteProfile
import com.brewlog.app.domain.clamped
import com.brewlog.app.domain.mmss
import com.brewlog.app.domain.sanitized
import com.brewlog.app.domain.validated
import com.brewlog.app.scale.BookooPacketValidator
import com.brewlog.app.scale.BookooProtocol
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.abs
import kotlin.math.roundToInt

class BookooProtocolTest {
    companion object {
        /** Builds a weight packet as documented by BOOKOO. */
        fun packet(grams: Double, negative: Boolean = false, flow: Double = 0.0, battery: Int = 87,
                   validChecksum: Boolean = true, header: Int = 0x0B): ByteArray {
            val raw = (abs(grams) * 100).roundToInt()
            val flowRaw = (abs(flow) * 100).roundToInt()
            val b = intArrayOf(
                0x03, header, 0x00, 0x10, 0x20, 0x01, if (negative) 0x2D else 0x2B,
                (raw shr 16) and 0xFF, (raw shr 8) and 0xFF, raw and 0xFF,
                if (flow < 0) 0x2D else 0x2B, (flowRaw shr 8) and 0xFF, flowRaw and 0xFF,
                battery, 0x00, 0x32, 0x03, 0x01, 0x00,
            )
            val sum = b.fold(0) { acc, v -> acc xor v }
            return (b + (if (validChecksum) sum else sum xor 0xFF)).map { it.toByte() }.toByteArray()
        }
    }

    @Test fun parsesWeightFlowAndBattery() {
        val r = BookooProtocol.parse(packet(123.45, flow = 4.5))!!
        assertEquals(123.45, r.grams, 0.001)
        assertEquals(4.5, r.flowRate, 0.001)
        assertEquals(87, r.batteryPercent)
        assertEquals(0x001020, r.milliseconds)
        assertTrue(r.checksumValid)
    }

    @Test fun parsesNegativeWeight() {
        assertEquals(-2.3, BookooProtocol.parse(packet(2.3, negative = true))!!.grams, 0.001)
    }

    @Test fun rejectsMalformedPackets() {
        assertNull(BookooProtocol.parse(ByteArray(0)))
        assertNull(BookooProtocol.parse(ByteArray(19) { 3 }))
        assertNull(BookooProtocol.parse(ByteArray(200) { 3 }))
        assertNull(BookooProtocol.parse(packet(10.0, header = 0x0A)))
        assertNull(BookooProtocol.parse(packet(90_000.0)))
    }

    @Test fun clampsBatteryAndDetectsBadChecksum() {
        assertEquals(100, BookooProtocol.parse(packet(1.0, battery = 250))!!.batteryPercent)
        assertFalse(BookooProtocol.parse(packet(5.0, validChecksum = false))!!.checksumValid)
    }

    @Test fun commandAllowlistMatchesKnownGoodPackets() {
        fun bytes(vararg v: Int) = v.map { it.toByte() }.toByteArray()
        assertArrayEquals(bytes(0x03, 0x0A, 0x01, 0x00, 0x00, 0x08), BookooProtocol.Command.TARE.packet())
        assertArrayEquals(bytes(0x03, 0x0A, 0x04, 0x00, 0x00, 0x0A), BookooProtocol.Command.START_TIMER.packet())
        assertArrayEquals(bytes(0x03, 0x0A, 0x05, 0x00, 0x00, 0x0D), BookooProtocol.Command.STOP_TIMER.packet())
        assertArrayEquals(bytes(0x03, 0x0A, 0x06, 0x00, 0x00, 0x0C), BookooProtocol.Command.RESET_TIMER.packet())
        assertEquals(0x08, BookooProtocol.checksum(intArrayOf(0x03, 0x0A, 0x01, 0x00, 0x00)))
        // Packets are copies: modifying one can't change the allowlist.
        BookooProtocol.Command.TARE.packet()[5] = 0
        assertEquals(0x08.toByte(), BookooProtocol.Command.TARE.packet()[5])
    }

    @Test fun validatorEnforcesChecksumWhenFirmwareFollowsSpec() {
        val v = BookooPacketValidator()
        repeat(10) { assertNotNull(v.accept(packet(1.0))) }
        assertEquals(BookooPacketValidator.Policy.ENFORCED, v.policy)
        assertNull(v.accept(packet(1.0, validChecksum = false)))
        assertEquals(1, v.rejected)
    }

    @Test fun validatorFallsBackWhenChecksumsNeverMatch() {
        val v = BookooPacketValidator()
        repeat(10) { v.accept(packet(1.0, validChecksum = false)) }
        assertEquals(BookooPacketValidator.Policy.IGNORED, v.policy)
        assertNotNull(v.accept(packet(3.0, validChecksum = false)))
        assertNull(v.accept(ByteArray(20)))
    }
}

class RecipeTest {
    private val presets by lazy { RecipeLibrary.parse(File("src/main/assets/recipes.json").readText()) }

    @Test fun presetsLoadAndAreConsistent() {
        assertTrue(presets.size >= 9)
        assertEquals(presets.size, presets.map { it.id }.toSet().size)
        for (recipe in presets) {
            assertTrue(recipe.id, recipe.tasteNotes.isNotEmpty())
            assertEquals(recipe.id, 0.0, recipe.steps.first().time, 0.0)
            assertEquals(recipe.id, recipe.steps.map { it.time }.sorted(), recipe.steps.map { it.time })
            val targets = recipe.pourSteps.mapNotNull { it.target }
            assertEquals(recipe.id, targets.sorted(), targets)
            assertEquals(recipe.id, recipe.water, targets.last(), 0.5)
            assertTrue(recipe.targetTime >= recipe.steps.last().time)
            assertTrue(recipe.ratio in 12.0..18.0)
        }
    }

    @Test fun bundledJsonIsAlreadyValid() {
        val raw = RecipeLibrary.json.decodeFromString(
            kotlinx.serialization.builtins.ListSerializer(com.brewlog.app.domain.Recipe.serializer()),
            File("src/main/assets/recipes.json").readText(),
        )
        raw.forEach { assertEquals(it.id, it, it.validated()) }
    }

    @Test fun scalingKeepsTimesAndScalesWeights() {
        val recipe = presets.first { it.id == "kasuya-46" }
        val scaled = recipe.scaled(30.0)
        assertEquals(450.0, scaled.water, 0.0)
        assertEquals(recipe.steps.map { it.time }, scaled.steps.map { it.time })
        assertEquals(listOf(90.0, 180.0, 270.0, 360.0, 450.0), scaled.pourSteps.mapNotNull { it.target })
    }

    @Test fun targetCurveEndsAtTotalWater() {
        val recipe = presets.first { it.id == "hoffmann-ultimate-v60" }
        val curve = recipe.targetCurve()
        assertEquals(0.0, curve.first().second, 0.0)
        assertEquals(recipe.water, curve.last().second, 0.0)
        assertEquals(recipe.targetTime, curve.last().first, 0.0)
    }

    @Test fun validationClampsHostileValues() {
        val hostile = RecipeLibrary.blankRecipe().copy(
            name = "  \u0000Evil\u0007 name " + "x".repeat(500),
            dose = Double.NaN, water = -50.0, temperature = 1_000.0, targetTime = Double.POSITIVE_INFINITY,
            flowMin = 10.0, flowMax = 2.0, taste = TasteProfile(99, -3, 3, 0),
            steps = listOf(
                RecipeStep(StepKind.POUR, 60.0, 50.0),
                RecipeStep(StepKind.BLOOM, -5.0, 1_000_000.0),
                RecipeStep(StepKind.SWIRL, 9_999.0, 42.0, note = "n".repeat(999)),
            ) + List(100) { RecipeStep(StepKind.POUR, 10.0, 1.0) },
        )
        val clean = hostile.validated()
        assertTrue(clean.name.startsWith("Evil name"))
        assertTrue(clean.name.length <= InputLimits.MAX_NAME_LENGTH)
        assertEquals(1.0, clean.dose, 0.0)
        assertEquals(10.0, clean.water, 0.0)
        assertEquals(100.0, clean.temperature, 0.0)
        assertTrue(clean.targetTime.isFinite())
        assertTrue(clean.flowMax > clean.flowMin)
        assertEquals(TasteProfile(5, 1, 3, 1), clean.taste)
        assertTrue(clean.steps.size <= InputLimits.MAX_STEPS)
        assertEquals(clean.steps.map { it.time }.sorted(), clean.steps.map { it.time })
        val targets = clean.pourSteps.mapNotNull { it.target }
        assertEquals(targets.sorted(), targets)
        assertTrue(targets.all { it <= clean.water * 1.5 })
        assertNull(clean.steps.first { it.kind == StepKind.SWIRL }.target)
    }

    @Test fun helpers() {
        assertEquals("helloworld", "  hello\u0000\u001Bworld  ".sanitized(50))
        assertEquals("abc", "abcdef".sanitized(3))
        assertEquals("line1\nline2", "line1\nline2".sanitized(50))
        assertEquals(1.0, Double.NaN.clamped(1.0, 5.0), 0.0)
        assertEquals(5.0, 7.0.clamped(1.0, 5.0), 0.0)
        assertEquals("0:00", 0.0.mmss())
        assertEquals("1:05", 65.9.mmss())
        assertEquals("3:30", 210.0.mmss())
    }
}

class GrinderSpecTest {
    private val comandante = GrinderSpec(GrindUnit.CLICKS, 1.0, 2.0, true)

    @Test fun adjustFinerAndCoarser() {
        assertEquals(22.0, comandante.adjusted(24.0, coarser = false), 0.0)
        assertEquals(26.0, comandante.adjusted(24.0, coarser = true), 0.0)
        assertEquals(20.0, comandante.adjusted(24.0, coarser = false, multiplier = 2.0), 0.0)
        assertEquals(0.0, comandante.adjusted(1.0, coarser = false), 0.0)
    }

    @Test fun reversedScaleAndSnapping() {
        val reversed = GrinderSpec(GrindUnit.NUMBERS, 1.0, 1.0, finerIsLower = false)
        assertEquals(11.0, reversed.adjusted(10.0, coarser = false), 0.0)
        assertEquals(9.0, reversed.adjusted(10.0, coarser = true), 0.0)
        val dial = GrinderSpec(GrindUnit.DIAL, 0.1, 0.2)
        assertEquals(7.3, dial.adjusted(7.5, coarser = false), 0.0001)
    }

    @Test fun formatting() {
        assertEquals("24 clicks", comandante.format(24.0))
        assertEquals("1 click", comandante.formatDelta(1.0))
        assertEquals("2 clicks", comandante.formatDelta(-2.0))
        assertEquals("7.5", GrinderSpec(GrindUnit.DIAL, 0.1, 0.2).format(7.5))
    }
}
