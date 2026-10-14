package com.brewlog.app.scale

import java.util.UUID

/**
 * BOOKOO Themis Mini BLE protocol. 1:1 port of BookooProtocol.swift (no Android imports, unit-testable).
 * Source: https://github.com/BooKooCode/OpenSource/blob/main/bookoo_mini_scale/protocols.md
 * and Beanconqueror's field-tested implementation.
 */
object BookooProtocol {
    val SERVICE_UUID: UUID = UUID.fromString("00000ffe-0000-1000-8000-00805f9b34fb")
    /** Weight notifications (20-byte packets). */
    val WEIGHT_CHAR_UUID: UUID = UUID.fromString("0000ff11-0000-1000-8000-00805f9b34fb")
    /** Commands (6-byte packets). */
    val COMMAND_CHAR_UUID: UUID = UUID.fromString("0000ff12-0000-1000-8000-00805f9b34fb")
    /** Client Characteristic Configuration descriptor: must be written on Android to enable notifications. */
    val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    /** Advertised name prefix, e.g. "BOOKOO_SC xxxx". */
    const val NAME_PREFIX = "bookoo"
    const val WEIGHT_PACKET_LENGTH = 20
    /** Anything longer than this is rejected outright. */
    const val MAX_PACKET_LENGTH = 64
    /** Themis Mini capacity is 2 kg; anything far outside is garbage. */
    private val PLAUSIBLE_WEIGHT = -3_000.0..5_000.0
    private val PLAUSIBLE_FLOW = -200.0..200.0

    /**
     * The only commands BrewLog ever sends (write allowlist). Fixed, field-tested byte sequences.
     * Note: the timer checksums don't match a plain XOR, so they're kept verbatim instead of computed.
     */
    enum class Command(private val bytes: ByteArray) {
        TARE(byteArrayOf(0x03, 0x0A, 0x01, 0x00, 0x00, 0x08)),
        START_TIMER(byteArrayOf(0x03, 0x0A, 0x04, 0x00, 0x00, 0x0A)),
        STOP_TIMER(byteArrayOf(0x03, 0x0A, 0x05, 0x00, 0x00, 0x0D)),
        RESET_TIMER(byteArrayOf(0x03, 0x0A, 0x06, 0x00, 0x00, 0x0C));

        /** A copy, so callers can't modify the allowlisted bytes. */
        fun packet(): ByteArray = bytes.copyOf()
    }

    data class Reading(
        /** Scale's internal timer in milliseconds. */
        val milliseconds: Int,
        val grams: Double,
        val flowRate: Double,
        val batteryPercent: Int,
        /** Whether byte 20 matched the documented XOR checksum. */
        val checksumValid: Boolean,
    )

    fun checksum(bytes: IntArray, count: Int = bytes.size): Int {
        var x = 0
        for (i in 0 until count) x = x xor bytes[i]
        return x
    }

    /** Parses a weight notification. Returns null for anything malformed or implausible. */
    fun parse(data: ByteArray): Reading? {
        if (data.size < WEIGHT_PACKET_LENGTH || data.size > MAX_PACKET_LENGTH) return null
        val b = IntArray(WEIGHT_PACKET_LENGTH) { data[it].toInt() and 0xFF }
        if (b[0] != 0x03 || b[1] != 0x0B) return null

        val ms = (b[2] shl 16) or (b[3] shl 8) or b[4]
        var grams = ((b[7] shl 16) or (b[8] shl 8) or b[9]) / 100.0
        if (b[6] == 0x2D) grams = -grams // '-'
        var flow = ((b[11] shl 8) or b[12]) / 100.0
        if (b[10] == 0x2D) flow = -flow

        if (grams !in PLAUSIBLE_WEIGHT || flow !in PLAUSIBLE_FLOW) return null
        val battery = minOf(b[13], 100)
        val valid = checksum(b, 19) == b[19]
        return Reading(ms, grams, flow, battery, valid)
    }
}

/**
 * Decides whether to enforce checksums. If the scale's firmware follows the documented XOR checksum,
 * it is enforced after a short learning phase; if not, only the plausibility checks apply.
 */
class BookooPacketValidator(private val learningPackets: Int = 10) {
    enum class Policy { LEARNING, ENFORCED, IGNORED }

    var policy: Policy = Policy.LEARNING
        private set
    var rejected: Int = 0
        private set
    private var seen = 0
    private var valid = 0

    fun accept(data: ByteArray): BookooProtocol.Reading? {
        val reading = BookooProtocol.parse(data)
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
