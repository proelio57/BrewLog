package com.brewlog.app.scale

import java.util.UUID

/**
 * BOOKOO Espresso Monitor BLE protocol.
 * Source: https://github.com/BooKooCode/OpenSource/blob/main/espresso_monitor/protocols.md
 * and Beanconqueror field-tested implementations.
 * No Android dependencies; 100% unit-testable on JVM.
 */
object BookooPressureProtocol {
    /** 16-bit alias 0x0FFF */
    val SERVICE_UUID: UUID = UUID.fromString("00000fff-0000-1000-8000-00805f9b34fb")
    /** Real-time pressure notifications (16-bit alias 0xFF02). */
    val PRESSURE_CHAR_UUID: UUID = UUID.fromString("0000ff02-0000-1000-8000-00805f9b34fb")
    /** Commands characteristic (16-bit alias 0xFF01). */
    val COMMAND_CHAR_UUID: UUID = UUID.fromString("0000ff01-0000-1000-8000-00805f9b34fb")
    /** Client Characteristic Configuration Descriptor to enable notifications. */
    val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    /** Advertised name prefixes. */
    val NAME_PREFIXES = listOf("bookoo", "bk_em", "bk-em", "espresso monitor")
    const val PRESSURE_PACKET_LENGTH = 20
    const val MAX_PACKET_LENGTH = 64

    /** Plausible espresso pressure range in bar (-1.0 for zero calibration drift, up to 20.0 bar max). */
    val PLAUSIBLE_PRESSURE_BAR = -1.0..20.0

    /**
     * Safe, allowlisted command packets for the monitor.
     */
    enum class Command(private val bytes: ByteArray) {
        TARE_PRESSURE(byteArrayOf(0x03, 0x0A, 0x01, 0x00, 0x00, 0x08)),
        START_MONITOR(byteArrayOf(0x03, 0x0A, 0x04, 0x00, 0x00, 0x0A)),
        STOP_MONITOR(byteArrayOf(0x03, 0x0A, 0x05, 0x00, 0x00, 0x0D)),
        ZERO_CALIBRATE(byteArrayOf(0x03, 0x0A, 0x07, 0x00, 0x00, 0x0E));

        fun packet(): ByteArray = bytes.copyOf()
    }

    data class Reading(
        /** Internal timer from monitor in milliseconds. */
        val milliseconds: Int,
        /** Current extraction pressure in bar (0.01 resolution). */
        val bar: Double,
        /** Battery percentage (0..100). */
        val batteryPercent: Int,
        /** True if byte 20 matched XOR checksum. */
        val checksumValid: Boolean,
    )

    fun checksum(bytes: IntArray, count: Int = bytes.size): Int {
        var x = 0
        for (i in 0 until count) x = x xor bytes[i]
        return x
    }

    /**
     * Parses a 20-byte BLE notification packet from the BOOKOO Espresso Monitor.
     * Returns null if malformed, corrupted, or values are outside physical plausibility.
     */
    fun parse(data: ByteArray): Reading? {
        if (data.size < PRESSURE_PACKET_LENGTH || data.size > MAX_PACKET_LENGTH) return null
        val b = IntArray(PRESSURE_PACKET_LENGTH) { data[it].toInt() and 0xFF }

        // BooKoo packets start with 0x03. Header byte 1 is 0x0B (telemetry) or 0x0C (extraction data).
        if (b[0] != 0x03 || (b[1] != 0x0B && b[1] != 0x0C)) return null

        val ms = (b[2] shl 16) or (b[3] shl 8) or b[4]

        // Pressure is encoded at bytes 7, 8, 9 (or 7, 8 for 16-bit with byte 6 as sign).
        // 0.01 bar resolution: 900 -> 9.00 bar.
        var rawPressure = ((b[7] shl 16) or (b[8] shl 8) or b[9]) / 100.0
        if (b[6] == 0x2D) rawPressure = -rawPressure // '-' sign

        if (rawPressure !in PLAUSIBLE_PRESSURE_BAR) return null

        val battery = minOf(b[13], 100)
        val valid = checksum(b, 19) == b[19]

        return Reading(ms, rawPressure, battery, valid)
    }
}

/**
 * Validates incoming packets from BOOKOO Espresso Monitor and enforces checksum integrity after learning.
 */
class BookooPressurePacketValidator(private val learningPackets: Int = 10) {
    enum class Policy { LEARNING, ENFORCED, IGNORED }

    var policy: Policy = Policy.LEARNING
        private set
    var rejected: Int = 0
        private set
    private var seen = 0
    private var valid = 0

    fun accept(data: ByteArray): BookooPressureProtocol.Reading? {
        val reading = BookooPressureProtocol.parse(data)
        if (reading == null) {
            rejected++
            return null
        }
        return when (policy) {
            Policy.LEARNING -> {
                seen++
                if (reading.checksumValid) valid++
                if (seen >= learningPackets) {
                    policy = if (valid * 10 >= seen * 9) Policy.ENFORCED else Policy.IGNORED
                }
                reading
            }
            Policy.ENFORCED -> if (reading.checksumValid) reading else {
                rejected++
                null
            }
            Policy.IGNORED -> reading
        }
    }

    fun reset() {
        policy = Policy.LEARNING
        rejected = 0
        seen = 0
        valid = 0
    }
}
