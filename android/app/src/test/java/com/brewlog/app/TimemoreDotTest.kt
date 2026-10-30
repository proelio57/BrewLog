package com.brewlog.app

import com.brewlog.app.scale.BookooProtocol
import com.brewlog.app.scale.ScaleCommand
import com.brewlog.app.scale.ScaleModel
import com.brewlog.app.scale.TimemoreDotProtocol
import com.brewlog.app.scale.TimemoreDotProtocol.Command
import com.brewlog.app.scale.TimemoreDotProtocol.Event
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Same scenarios as TimemoreDotTests.swift; command bytes verified on a physical Dot (decentespresso/decaid #739). */
class TimemoreDotTest {
    private fun bytes(vararg v: Int) = ByteArray(v.size) { v[it].toByte() }

    @Test fun commandFramesMatchTheVerifiedBytes() {
        assertArrayEquals(bytes(0xA5, 0x5A, 0x03, 0x0D, 0x00, 0x00, 0x64, 0xD1), Command.TARE.packet())
        assertArrayEquals(bytes(0xA5, 0x5A, 0x03, 0x02, 0x00, 0x01, 0x01, 0x18, 0x67), Command.START_TIMER.packet())
        assertArrayEquals(bytes(0xA5, 0x5A, 0x03, 0x02, 0x00, 0x01, 0x02, 0x19, 0x27), Command.STOP_TIMER.packet())
        assertArrayEquals(bytes(0xA5, 0x5A, 0x03, 0x02, 0x00, 0x01, 0x03, 0xD9, 0xE6), Command.RESET_TIMER.packet())
        assertArrayEquals(bytes(0xA5, 0x5A, 0x03, 0x06, 0x00, 0x01, 0x00, 0xE8, 0xA7), Command.SET_UNIT_GRAMS.packet())
        assertArrayEquals(bytes(0xA5, 0x5A, 0x03, 0x08, 0x00, 0x02, 0x01, 0x00, 0xEB, 0x31), Command.SET_STANDARD_MODE.packet())
        assertArrayEquals(bytes(0xA5, 0x5A, 0x02, 0x05, 0x00, 0x00, 0x5A, 0x51), Command.REQUEST_BATTERY.packet())
        assertEquals(0x64D1, TimemoreDotProtocol.crc16(bytes(0xA5, 0x5A, 0x03, 0x0D, 0x00, 0x00)))
        // Generic commands map to each model's own packet.
        assertArrayEquals(Command.TARE.packet(), ScaleCommand.TARE.packet(ScaleModel.TIMEMORE_DOT))
        assertArrayEquals(BookooProtocol.Command.TARE.packet(), ScaleCommand.TARE.packet(ScaleModel.BOOKOO))
    }

    /** A weight notification as the Dot sends it: zero tail instead of a CRC. */
    private fun weightFrame(grams: Double, timer: Int = 0, opcode: Int = 0x01): ByteArray {
        val raw = Math.round(grams * 10).toInt()
        val payload = intArrayOf(raw ushr 24 and 0xFF, raw ushr 16 and 0xFF, raw ushr 8 and 0xFF, raw and 0xFF, 0, 0, timer shr 8, timer and 0xFF, 0)
        return bytes(0xA5, 0x5A, opcode, 0x01, 0x00, payload.size, *payload, 0x00, 0x00)
    }

    @Test fun decodesWeightTimerAndBattery() {
        val parser = TimemoreDotProtocol.Parser()
        assertEquals(listOf(Event.Weight(1234.5, 42)), parser.feed(weightFrame(1234.5, timer = 42)))
        assertEquals(listOf(Event.Weight(-12.3, 0)), parser.feed(weightFrame(-12.3)))
        assertEquals(listOf(Event.Weight(1.1, 0)), parser.feed(weightFrame(1.1, opcode = 0x02)))
        assertEquals(listOf(Event.Battery(72)), parser.feed(bytes(0xA5, 0x5A, 0x01, 0x05, 0x00, 0x02, 0x00, 0x48, 0, 0)))
        assertEquals(listOf(Event.Battery(80)), parser.feed(bytes(0xA5, 0x5A, 0x01, 0x05, 0x00, 0x01, 80, 0, 0)))
        assertTrue("implausible battery", parser.feed(bytes(0xA5, 0x5A, 0x01, 0x05, 0x00, 0x02, 0x00, 0x65, 0, 0)).isEmpty())
        assertTrue("command ack", parser.feed(Command.TARE.packet()).isEmpty())
    }

    @Test fun reassemblesSplitPackedAndGarbledNotifications() {
        val parser = TimemoreDotProtocol.Parser()
        val frame = weightFrame(250.0)
        assertTrue(parser.feed(frame.copyOfRange(0, 5)).isEmpty())
        assertEquals(listOf(Event.Weight(250.0, 0)), parser.feed(frame.copyOfRange(5, frame.size)))
        assertEquals(listOf(Event.Weight(1.0, 0), Event.Weight(2.0, 0)), parser.feed(weightFrame(1.0) + weightFrame(2.0)))
        assertEquals(listOf(Event.Weight(3.0, 0)), parser.feed(bytes(0x00, 0xFF, 0x12) + weightFrame(3.0)))
        assertEquals(listOf(Event.Weight(4.0, 0)), parser.feed(bytes(0xA5, 0x5A, 0x01, 0x01, 0xFF, 0xFF) + weightFrame(4.0)))
        assertTrue(parser.feed(weightFrame(99_999.0)).isEmpty())
    }

    @Test fun detectsTheModelFromTheAdvertisement() {
        assertEquals(ScaleModel.TIMEMORE_DOT, ScaleModel.detect("TIMEMORE Dot", emptyList()))
        assertEquals(ScaleModel.TIMEMORE_DOT, ScaleModel.detect("TES017-1A2B", emptyList()))
        assertEquals(ScaleModel.TIMEMORE_DOT, ScaleModel.detect(null, listOf(TimemoreDotProtocol.SERVICE_UUID)))
        assertEquals(ScaleModel.BOOKOO, ScaleModel.detect("BOOKOO_SC", emptyList()))
        assertEquals(ScaleModel.BOOKOO, ScaleModel.detect(null, listOf(BookooProtocol.SERVICE_UUID)))
        // A named non-Dot device advertising FFF0 is not taken for a scale.
        assertNull(ScaleModel.detect("Heart Rate", listOf(TimemoreDotProtocol.SERVICE_UUID)))
        assertFalse(TimemoreDotProtocol.isDot(null))
    }
}
