package com.brewlog.app.machine

import java.util.UUID

/**
 * The Decent DE1's Bluetooth protocol (from decentespresso/de1app, `de1plus/binary.tcl`): decodes the state and
 * shot sample notifications into [MachineStatus] and encodes the requested-state commands. All values big-endian.
 */
object DecentProtocol {
    val SERVICE_UUID: UUID = UUID.fromString("0000a000-0000-1000-8000-00805f9b34fb")
    val REQUESTED_STATE_UUID: UUID = UUID.fromString("0000a002-0000-1000-8000-00805f9b34fb")
    val SHOT_SAMPLE_UUID: UUID = UUID.fromString("0000a00d-0000-1000-8000-00805f9b34fb")
    val STATE_INFO_UUID: UUID = UUID.fromString("0000a00e-0000-1000-8000-00805f9b34fb")

    const val SERVICE = "0000A000-0000-1000-8000-00805F9B34FB"
    const val REQUESTED_STATE = "0000A002-0000-1000-8000-00805F9B34FB"
    const val SHOT_SAMPLE = "0000A00D-0000-1000-8000-00805F9B34FB"
    const val STATE_INFO = "0000A00E-0000-1000-8000-00805F9B34FB"

    enum class State(val value: Int) {
        SLEEP(0), GOING_TO_SLEEP(1), IDLE(2), BUSY(3), ESPRESSO(4), STEAM(5), HOT_WATER(6),
        SHORT_CAL(7), SELF_TEST(8), LONG_CAL(9), DESCALE(10), FATAL_ERROR(11), INITIALIZING(12),
        NO_REQUEST(13), SKIP_TO_NEXT(14), HOT_WATER_RINSE(15), STEAM_RINSE(16), REFILL(17),
        CLEAN(18), IN_BOOT_LOADER(19), AIR_PURGE(20), SCHED_IDLE(21);

        companion object {
            fun from(value: Int): State? = entries.firstOrNull { it.value == value }
        }
    }

    enum class Substate(val value: Int) {
        NONE(0), HEAT_WATER_TANK(1), HEAT_WATER_HEATER(2), STABILIZE_MIX_TEMP(3),
        PRE_INFUSE(4), POUR(5), FLUSH(6), STEAMING(7);

        companion object {
            fun from(value: Int): Substate? = entries.firstOrNull { it.value == value }
        }
    }

    data class Sample(
        val pressure: Double,
        val flow: Double,
        val mixTemp: Double,
        val headTemp: Double,
        val targetMixTemp: Double,
        val targetHeadTemp: Double,
        val targetPressure: Double,
        val targetFlow: Double,
        val frame: Int,
    )

    data class StateResult(val state: Int, val substate: Int)

    fun sample(data: ByteArray): Sample? {
        if (data.size < 19) return null
        fun u16(i: Int): Double = (((data[i].toInt() and 0xFF) shl 8) or (data[i + 1].toInt() and 0xFF)).toDouble()
        fun u24(i: Int): Double = (((data[i].toInt() and 0xFF) shl 16) or ((data[i + 1].toInt() and 0xFF) shl 8) or (data[i + 2].toInt() and 0xFF)).toDouble()
        return Sample(
            pressure = u16(2) / 4096.0,
            flow = u16(4) / 4096.0,
            mixTemp = u16(6) / 256.0,
            headTemp = u24(8) / 65536.0,
            targetMixTemp = u16(11) / 256.0,
            targetHeadTemp = u16(13) / 256.0,
            targetPressure = (data[15].toInt() and 0xFF) / 16.0,
            targetFlow = (data[16].toInt() and 0xFF) / 16.0,
            frame = data[17].toInt() and 0xFF,
        )
    }

    fun state(data: ByteArray): StateResult? {
        if (data.size < 2) return null
        return StateResult(data[0].toInt() and 0xFF, data[1].toInt() and 0xFF)
    }

    fun apply(rawState: Int, substate: Int, status: MachineStatus): MachineStatus {
        val state = State.from(rawState) ?: State.NO_REQUEST
        var next = status
        when (state) {
            State.SLEEP, State.GOING_TO_SLEEP, State.SCHED_IDLE -> next = next.copy(mode = MachineMode.STANDBY.value)
            State.STEAM, State.STEAM_RINSE -> next = next.copy(mode = MachineMode.STEAM.value)
            State.HOT_WATER, State.HOT_WATER_RINSE -> next = next.copy(mode = MachineMode.WATER.value)
            State.IDLE, State.ESPRESSO, State.BUSY -> next = next.copy(mode = MachineMode.BREW.value)
            else -> {}
        }

        if (substate >= 200 || state == State.FATAL_ERROR) {
            return next.copy(
                systemState = "error",
                systemMessage = errorMessage(substate, rawState),
                processActive = false,
                processKind = null,
                processLabel = null,
                processIsUtility = false,
            )
        }
        next = next.copy(
            systemState = if (state == State.SLEEP) "sleep" else "ready",
            systemMessage = null,
        )

        val sub = Substate.from(substate)
        return when {
            state == State.ESPRESSO && sub == Substate.PRE_INFUSE ->
                next.copy(processActive = true, processKind = "infusion", processLabel = "Pre-infusion", processIsUtility = false)
            state == State.ESPRESSO && sub == Substate.POUR ->
                next.copy(processActive = true, processKind = "brew", processLabel = "Extraction", processIsUtility = false)
            state in listOf(State.HOT_WATER_RINSE, State.HOT_WATER, State.STEAM, State.STEAM_RINSE, State.CLEAN, State.DESCALE) -> {
                val running = sub in listOf(Substate.POUR, Substate.FLUSH, Substate.STEAMING, Substate.PRE_INFUSE)
                next.copy(processActive = running, processKind = if (running) "brew" else null, processLabel = if (running) "Flush" else null, processIsUtility = true)
            }
            else ->
                next.copy(processActive = false, processKind = null, processLabel = null, processIsUtility = false)
        }
    }

    fun apply(sample: Sample, status: MachineStatus): MachineStatus {
        return status.copy(
            pressure = sample.pressure.coerceIn(0.0, 20.0),
            flow = sample.flow.coerceIn(0.0, 30.0),
            temperature = sample.headTemp.coerceIn(0.0, 200.0),
            targetTemperature = if (sample.targetHeadTemp > 0) minOf(sample.targetHeadTemp, 200.0) else null,
            targetPressure = if (sample.targetPressure > 0) sample.targetPressure else null,
            hasPressure = true,
        )
    }

    fun command(mode: MachineMode): ByteArray = byteArrayOf(
        when (mode) {
            MachineMode.STANDBY -> State.SLEEP.value.toByte()
            MachineMode.BREW -> State.IDLE.value.toByte()
            MachineMode.STEAM -> State.STEAM.value.toByte()
            MachineMode.WATER -> State.HOT_WATER.value.toByte()
        }
    )

    val startShot: ByteArray = byteArrayOf(State.ESPRESSO.value.toByte())
    val stopShot: ByteArray = byteArrayOf(State.IDLE.value.toByte())

    private fun errorMessage(substate: Int, state: Int): String = when (substate) {
        204 -> "Temperature sensor error"
        205 -> "Pressure sensor error"
        206 -> "Water level error"
        else -> if (substate >= 200) "Machine error $substate" else "Machine error (state $state)"
    }
}
