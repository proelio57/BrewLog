package com.brewlog.app.scale

import java.util.UUID

/**
 * Timemore Black Mirror Dot (TES017) over Bluetooth LE. Port of TimemoreDotProtocol.swift; community-documented
 * protocol (decentespresso/decaid #739, Sofronio/dot-scale-mate), not an official Timemore spec.
 *
 * Frames: `A5 5A | opcode | cmd | length (2, big-endian) | payload | 2-byte tail`. Commands carry a CRC-16/MODBUS
 * tail (init 0xFFFF, reflected poly 0xA001, big-endian). Notifications leave the tail at `00 00`, so incoming frames
 * are checked for shape and plausibility, not CRC.
 */
object TimemoreDotProtocol {
    val SERVICE_UUID: UUID = UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb")
    val NOTIFY_CHAR_UUID: UUID = UUID.fromString("0000fff1-0000-1000-8000-00805f9b34fb")
    val COMMAND_CHAR_UUID: UUID = UUID.fromString("0000fff2-0000-1000-8000-00805f9b34fb")

    const val HEADER_SIZE = 6
    const val TAIL_SIZE = 2
    const val MAX_PAYLOAD = 64
    private val PLAUSIBLE_WEIGHT = -3_000.0..5_000.0

    /** The Dot advertises "...Dot..." or its model number; outside pairing mode it can advertise FFF0 without a name. */
    fun isDot(name: String?): Boolean {
        val lower = name?.lowercase() ?: return false
        return lower.contains("dot") || lower.contains("tes017")
    }

    fun crc16(bytes: ByteArray): Int {
        var crc = 0xFFFF
        for (b in bytes) {
            crc = crc xor (b.toInt() and 0xFF)
            repeat(8) { crc = if (crc and 1 != 0) (crc ushr 1) xor 0xA001 else crc ushr 1 }
        }
        return crc and 0xFFFF
    }

    fun frame(opcode: Int, cmd: Int, payload: ByteArray = ByteArray(0)): ByteArray {
        require(payload.size <= MAX_PAYLOAD)
        val body = byteArrayOf(0xA5.toByte(), 0x5A, opcode.toByte(), cmd.toByte(), (payload.size shr 8).toByte(), (payload.size and 0xFF).toByte()) + payload
        val crc = crc16(body)
        return body + byteArrayOf((crc shr 8).toByte(), (crc and 0xFF).toByte())
    }

    enum class Command(private val opcode: Int, private val cmd: Int, private vararg val payload: Int) {
        TARE(0x03, 0x0D),
        START_TIMER(0x03, 0x02, 0x01),
        STOP_TIMER(0x03, 0x02, 0x02),
        RESET_TIMER(0x03, 0x02, 0x03),
        SET_UNIT_GRAMS(0x03, 0x06, 0x00),
        SET_STANDARD_MODE(0x03, 0x08, 0x01, 0x00),
        REQUEST_BATTERY(0x02, 0x05);

        fun packet(): ByteArray = frame(opcode, cmd, ByteArray(payload.size) { payload[it].toByte() })
    }

    /** The Dot only sends weight after unit and mode are set: (command, delay before it in ms). */
    val INIT_SEQUENCE = listOf(Command.SET_UNIT_GRAMS to 500L, Command.SET_STANDARD_MODE to 200L, Command.REQUEST_BATTERY to 100L)

    sealed interface Event {
        data class Weight(val grams: Double, val timerSeconds: Int) : Event
        data class Battery(val percent: Int) : Event
    }

    /** Reassembles frames that are split across or packed into notifications, and resyncs on garbage. */
    class Parser {
        private val buffer = ArrayList<Int>()

        fun feed(data: ByteArray): List<Event> {
            data.forEach { buffer += it.toInt() and 0xFF }
            if (buffer.size > MAX_BUFFER) buffer.subList(0, buffer.size - MAX_BUFFER).clear()
            val events = mutableListOf<Event>()
            while (buffer.size >= HEADER_SIZE) {
                if (buffer[0] != 0xA5 || buffer[1] != 0x5A) { buffer.removeAt(0); continue }
                val length = buffer[4] shl 8 or buffer[5]
                if (length > MAX_PAYLOAD) { buffer.removeAt(0); continue }
                val total = HEADER_SIZE + length + TAIL_SIZE
                if (buffer.size < total) break
                val opcode = buffer[2]
                val cmd = buffer[3]
                val payload = buffer.subList(HEADER_SIZE, HEADER_SIZE + length).toList()
                buffer.subList(0, total).clear()
                event(opcode, cmd, payload)?.let { events += it }
            }
            return events
        }

        fun reset() = buffer.clear()

        private companion object {
            const val MAX_BUFFER = 256
        }
    }

    fun event(opcode: Int, cmd: Int, payload: List<Int>): Event? {
        if (opcode == 0x03) return null // command ack
        return when (cmd) {
            0x01 -> {
                if (payload.size < 8) return null
                val raw = (payload[0] shl 24) or (payload[1] shl 16) or (payload[2] shl 8) or payload[3] // signed Int
                val grams = raw / 10.0
                if (grams !in PLAUSIBLE_WEIGHT) null else Event.Weight(grams, payload[6] shl 8 or payload[7])
            }
            0x05 -> {
                val raw = (if (payload.size >= 2) payload[1] else payload.firstOrNull()) ?: return null
                if (raw <= 100) Event.Battery(raw) else null
            }
            else -> null
        }
    }
}

/** The scales BrewLog can connect to. */
enum class ScaleModel(val defaultName: String, val serviceUuid: UUID, val notifyUuid: UUID, val commandUuid: UUID) {
    BOOKOO("BOOKOO scale", BookooProtocol.SERVICE_UUID, BookooProtocol.WEIGHT_CHAR_UUID, BookooProtocol.COMMAND_CHAR_UUID),
    TIMEMORE_DOT("Timemore Dot", TimemoreDotProtocol.SERVICE_UUID, TimemoreDotProtocol.NOTIFY_CHAR_UUID, TimemoreDotProtocol.COMMAND_CHAR_UUID);

    companion object {
        /** Which scale an advertisement belongs to, null for anything else (the BOOKOO Espresso Monitor is not a scale). */
        fun detect(name: String?, services: List<UUID>): ScaleModel? {
            if (BookooPressureProtocol.isMonitorName(name)) return null
            if (name?.contains(BookooProtocol.NAME_PREFIX, ignoreCase = true) == true) return BOOKOO
            if (TimemoreDotProtocol.isDot(name)) return TIMEMORE_DOT
            if (BookooProtocol.SERVICE_UUID in services) return BOOKOO
            // A nameless FFF0 advertisement: a Dot outside pairing mode. The FFF0 service check on connect rejects others.
            if (name.isNullOrEmpty() && TimemoreDotProtocol.SERVICE_UUID in services) return TIMEMORE_DOT
            return null
        }
    }
}

/** What BrewLog asks a scale to do. Each model translates it into its own packet. */
enum class ScaleCommand {
    TARE, START_TIMER, STOP_TIMER, RESET_TIMER;

    fun packet(model: ScaleModel): ByteArray = when (model) {
        ScaleModel.BOOKOO -> when (this) {
            TARE -> BookooProtocol.Command.TARE
            START_TIMER -> BookooProtocol.Command.START_TIMER
            STOP_TIMER -> BookooProtocol.Command.STOP_TIMER
            RESET_TIMER -> BookooProtocol.Command.RESET_TIMER
        }.packet()
        ScaleModel.TIMEMORE_DOT -> when (this) {
            TARE -> TimemoreDotProtocol.Command.TARE
            START_TIMER -> TimemoreDotProtocol.Command.START_TIMER
            STOP_TIMER -> TimemoreDotProtocol.Command.STOP_TIMER
            RESET_TIMER -> TimemoreDotProtocol.Command.RESET_TIMER
        }.packet()
    }
}
