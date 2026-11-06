package com.brewlog.app.machine

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * La Marzocco's cloud messages (see docs/la-marzocco-protocol.md): the machine list, the dashboard
 * (widgets -> MachineStatus), tokens and the STOMP frames the dashboard WebSocket speaks. Pure logic.
 */
object LaMarzoccoProtocol {
    const val HOST = "lion.lamarzocco.io"
    const val API_BASE = "https://lion.lamarzocco.io/api/customer-app"
    const val SOCKET_URL = "wss://lion.lamarzocco.io/ws/connect"

    /** Refresh the access token this long before it expires (it lasts about an hour). */
    const val REFRESH_MARGIN_MS: Long = 10 * 60 * 1000L
    const val TOKEN_LIFETIME_MS: Long = 60 * 60 * 1000L

    data class Machine(
        /** Serial number. */
        val id: String,
        val name: String,
        val model: String,
    )

    data class DashboardResult(
        val connected: Boolean?,
        val commandResults: Map<String, String>,
        val status: MachineStatus,
    )

    data class StompFrame(
        val command: String,
        val headers: Map<String, String>,
        val body: String,
    )

    // MARK: REST

    /** Coffee machines from `GET /things` (grinders and entries without a serial are left out). */
    fun machines(json: ByteArray): List<Machine> {
        if (json.size > 1_000_000) return emptyList()
        val text = json.toString(Charsets.UTF_8)
        val array = runCatching { Json.parseToJsonElement(text).jsonArray }.getOrNull() ?: return emptyList()
        val list = mutableListOf<Machine>()
        for (element in array.take(20)) {
            val thing = element as? JsonObject ?: continue
            val type = thing["type"]?.jsonPrimitive?.content ?: "CoffeeMachine"
            if (type != "CoffeeMachine") continue
            val rawSerial = thing["serialNumber"]?.jsonPrimitive?.content?.take(40) ?: ""
            if (rawSerial.isEmpty()) continue
            val rawName = thing["name"]?.jsonPrimitive?.content?.take(60) ?: ""
            val rawModel = thing["modelName"]?.jsonPrimitive?.content?.take(60) ?: ""
            val name = if (rawName.isEmpty()) (if (rawModel.isEmpty()) rawSerial else rawModel) else rawName
            list.add(Machine(id = rawSerial, name = name, model = rawModel))
        }
        return list
    }

    /** Access and refresh token from `/auth/signin` or `/auth/refreshtoken`. */
    fun tokens(json: ByteArray): Pair<String, String>? {
        if (json.size > 100_000) return null
        val text = json.toString(Charsets.UTF_8)
        val obj = runCatching { Json.parseToJsonElement(text).jsonObject }.getOrNull() ?: return null
        val access = obj["accessToken"]?.jsonPrimitive?.content ?: ""
        val refresh = obj["refreshToken"]?.jsonPrimitive?.content ?: ""
        if (access.isEmpty() || refresh.isEmpty()) return null
        return Pair(access, refresh)
    }

    /** The id of a command just sent (`POST .../command/...` answers `[{"id", "status"}]`). */
    fun commandID(json: ByteArray): String? {
        if (json.size > 100_000) return null
        val text = json.toString(Charsets.UTF_8)
        val array = runCatching { Json.parseToJsonElement(text).jsonArray }.getOrNull() ?: return null
        if (array.isEmpty()) return null
        val first = array[0] as? JsonObject ?: return null
        val id = first["id"]?.jsonPrimitive?.content ?: ""
        return id.ifEmpty { null }
    }

    fun needsRefresh(expiresAtMs: Long, nowMs: Long = System.currentTimeMillis()): Boolean {
        return (expiresAtMs - nowMs) < REFRESH_MARGIN_MS
    }

    // MARK: Dashboard

    /**
     * Applies a dashboard (REST or WebSocket message) to the status.
     * Returns whether the machine is online (null when the message doesn't say) and the results of commands
     * it mentions (command id -> "Success", "Error", "Failed" or "Timeout").
     * Returns null, changing nothing, for a message that isn't a dashboard (garbled or split frame).
     */
    fun apply(dashboard: ByteArray, currentStatus: MachineStatus): DashboardResult? {
        if (dashboard.size > 1_000_000) return null
        val text = dashboard.toString(Charsets.UTF_8)
        val obj = runCatching { Json.parseToJsonElement(text).jsonObject }.getOrNull() ?: return null

        val connected = obj["connected"]?.jsonPrimitive?.booleanOrNull
        val commandResults = mutableMapOf<String, String>()
        val commandsArray = obj["commands"] as? JsonArray
        if (commandsArray != null) {
            for (element in commandsArray.take(50)) {
                val cmd = element as? JsonObject ?: continue
                val id = cmd["id"]?.jsonPrimitive?.content ?: ""
                val status = cmd["status"]?.jsonPrimitive?.content ?: ""
                if (id.isNotEmpty() && status.isNotEmpty()) {
                    commandResults[id] = status
                }
            }
        }

        // The machine has no pressure sensor or live temperature in the cloud data.
        var next = currentStatus.copy(
            hasPressure = false,
            pressure = null,
            flow = null,
        )

        val widgetsArray = obj["widgets"] as? JsonArray
        if (widgetsArray != null) {
            for (element in widgetsArray.take(100)) {
                val widget = element as? JsonObject ?: continue
                val code = widget["code"]?.jsonPrimitive?.content ?: ""
                val output = widget["output"] as? JsonObject ?: continue
                when (code) {
                    "CMMachineStatus" -> next = applyMachineStatus(output, connected != false, next)
                    "CMCoffeeBoiler" -> next = applyBoiler(output, next)
                }
            }
        }

        if (connected == false) {
            next = setBrewing(false, next)
        }

        return DashboardResult(connected, commandResults, next)
    }

    private fun applyMachineStatus(output: JsonObject, connected: Boolean, status: MachineStatus): MachineStatus {
        val state = output["status"]?.jsonPrimitive?.content
        val modeStr = output["mode"]?.jsonPrimitive?.content ?: ""
        var next = when (modeStr) {
            "StandBy" -> status.copy(mode = MachineMode.STANDBY.value)
            "BrewingMode", "EcoMode" -> status.copy(mode = MachineMode.BREW.value)
            else -> status
        }
        if (state == "StandBy" || state == "Off") {
            next = next.copy(
                mode = MachineMode.STANDBY.value,
                systemState = "standby",
                systemMessage = null,
            )
        } else if (next.systemState == "standby") {
            next = next.copy(systemState = "ready")
        }
        val isBrewing = connected && state == "Brewing"
        return setBrewing(isBrewing, next)
    }

    private fun applyBoiler(output: JsonObject, status: MachineStatus): MachineStatus {
        var next = status
        val target = output["targetTemperature"]?.jsonPrimitive?.doubleOrNull
        if (target != null && target.isFinite() && target in 50.0..130.0) {
            next = next.copy(targetTemperature = target)
        }
        val boilerStatus = output["status"]?.jsonPrimitive?.content ?: ""
        next = when (boilerStatus) {
            "NoWater" -> next.copy(systemState = "error", systemMessage = "No water in the tank")
            "HeatingUp" -> next.copy(systemState = "heating", systemMessage = null)
            "Ready" -> next.copy(systemState = "ready", systemMessage = null)
            else -> next
        }
        return next
    }

    private fun setBrewing(brewing: Boolean, status: MachineStatus): MachineStatus {
        return status.copy(
            processActive = brewing,
            processKind = if (brewing) "brew" else null,
            processLabel = if (brewing) "Brewing" else null,
            processIsUtility = false,
        )
    }

    // MARK: STOMP

    /** One STOMP frame: command, `key:value` headers, blank line, body, NUL. */
    fun stompFrame(command: String, headers: List<Pair<String, String>>, body: String = ""): String {
        val sb = StringBuilder()
        sb.append(command).append("\n")
        for ((k, v) in headers) {
            sb.append(k).append(":").append(v).append("\n")
        }
        sb.append("\n").append(body).append("\u0000")
        return sb.toString()
    }

    /** Splits a STOMP frame. Null for empty text or a bare heart-beat newline. */
    fun parseStomp(text: String): StompFrame? {
        var frame = text
        if (frame.endsWith("\u0000")) {
            frame = frame.substring(0, frame.length - 1)
        }
        var startIdx = 0
        while (startIdx < frame.length && (frame[startIdx] == '\n' || frame[startIdx] == '\r')) {
            startIdx++
        }
        val trimmedStart = frame.substring(startIdx)
        if (trimmedStart.isEmpty()) return null

        val parts = trimmedStart.split("\n\n", limit = 2)
        val headLines = parts[0].split("\n")
        val command = headLines[0].trim()
        if (command.isEmpty()) return null

        val headers = mutableMapOf<String, String>()
        for (i in 1 until headLines.size) {
            val line = headLines[i]
            val colon = line.indexOf(':')
            if (colon != -1) {
                val key = line.substring(0, colon)
                val value = line.substring(colon + 1)
                headers[key] = value
            }
        }
        val body = if (parts.size > 1) parts[1] else ""
        return StompFrame(command, headers, body)
    }
}
