package com.brewlog.app.scale

import java.util.UUID

/**
 * BOOKOO Espresso Monitor (pressure sensor) BLE protocol, from BOOKOO's published spec
 * (github.com/BooKooCode/OpenSource, `espresso_monitor/protocols.md`), as also used by Beanconqueror.
 * Same parsing as iOS (`BookooMonitorProtocol.swift`) and web (`scale/pressure.ts`).
 *
 * - Service 0x0FFF, commands on 0xFF01, extraction data notifications on 0xFF02.
 * - Data packet (10 bytes): `02 1B 00 00 <pressure×100 hi> <lo> <battery %> 00 00 00`.
 * - Commands (7 bytes, last byte = XOR of the others): start `02 0C 01 00 00 00 0F`, stop `02 0C 00 00 00 00 0E`.
 *   There is no tare/zero command in the public protocol.
 *
 * No Android dependencies; unit-testable on the JVM.
 */
object BookooPressureProtocol {
    val SERVICE_UUID: UUID = UUID.fromString("00000fff-0000-1000-8000-00805f9b34fb")
    /** Extraction data notifications (0xFF02). */
    val PRESSURE_CHAR_UUID: UUID = UUID.fromString("0000ff02-0000-1000-8000-00805f9b34fb")
    /** Commands (0xFF01). */
    val COMMAND_CHAR_UUID: UUID = UUID.fromString("0000ff01-0000-1000-8000-00805f9b34fb")
    /** Client Characteristic Configuration Descriptor to enable notifications. */
    val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    /** Advertised as "BOOKOO_EM …". The scale advertises "BOOKOO_SC …", so match the full prefix. */
    val NAME_PREFIXES = listOf("bookoo_em", "espresso monitor")
    const val MIN_PACKET_LENGTH = 7
    const val MAX_PACKET_LENGTH = 20

    val PLAUSIBLE_PRESSURE_BAR = 0.0..20.0

    /** The only commands BrewLog ever writes to the sensor. */
    enum class Command(private val bytes: ByteArray) {
        START_MONITOR(byteArrayOf(0x02, 0x0C, 0x01, 0x00, 0x00, 0x00, 0x0F)),
        STOP_MONITOR(byteArrayOf(0x02, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x0E));

        fun packet(): ByteArray = bytes.copyOf()
    }

    data class Reading(
        /** Pressure in bar (0.01 resolution). */
        val bar: Double,
        /** Battery percentage (0..100). */
        val batteryPercent: Int,
    )

    /** XOR of all bytes but the last, which is how BOOKOO checksums its commands. */
    fun checksum(bytes: ByteArray): Int = bytes.dropLast(1).fold(0) { acc, b -> acc xor (b.toInt() and 0xFF) }

    fun isMonitorName(name: String?): Boolean =
        name != null && NAME_PREFIXES.any { name.lowercase().contains(it) }

    /** Parses an extraction data notification. Returns null for anything that isn't a plausible pressure packet. */
    fun parse(data: ByteArray): Reading? {
        if (data.size < MIN_PACKET_LENGTH || data.size > MAX_PACKET_LENGTH) return null
        val b = IntArray(MIN_PACKET_LENGTH) { data[it].toInt() and 0xFF }
        if (b[0] != 0x02 || b[1] != 0x1B) return null
        val bar = ((b[4] shl 8) or b[5]) / 100.0
        if (bar !in PLAUSIBLE_PRESSURE_BAR) return null
        return Reading(bar, minOf(b[6], 100))
    }
}

/** Drops packets that aren't plausible pressure readings and counts them for diagnostics. */
class BookooPressurePacketValidator {
    var rejected: Int = 0
        private set

    fun accept(data: ByteArray): BookooPressureProtocol.Reading? =
        BookooPressureProtocol.parse(data) ?: run {
            rejected++
            null
        }

    fun reset() {
        rejected = 0
    }
}
