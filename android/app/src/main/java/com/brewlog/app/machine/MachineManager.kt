package com.brewlog.app.machine

import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.StepKind
import com.brewlog.app.scale.monotonicMillis
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

// Port of MachineManager.swift / machineManager.ts. GaggiMate over its local WebSocket, or a demo machine.

enum class MachineKind(val raw: String, val title: String) {
    NONE("none", "None"), GAGGIMATE("gaggimate", "GaggiMate"), DEMO("demo", "Demo machine");

    companion object {
        fun from(raw: String?): MachineKind = entries.firstOrNull { it.raw == raw } ?: NONE
    }
}

enum class MachineConnection(val label: String) {
    OFF("Off"), CONNECTING("Connecting…"), CONNECTED("Connected"), UNREACHABLE("Offline"),
}

data class MachineState(
    val kind: MachineKind = MachineKind.NONE,
    val host: String = "gaggimate.local",
    val connection: MachineConnection = MachineConnection.OFF,
    val status: GaggiMateStatus = GaggiMateStatus(),
    /** Feedback for the last command, e.g. "Profile sent". */
    val notice: String? = null,
    /** The machine refused to start because of a warning (e.g. low water). */
    val startBlockedBy: List<String> = emptyList(),
)

class MachineManager(private val prefs: SharedPreferences) {
    private val main = Handler(Looper.getMainLooper())
    private val _state = MutableStateFlow(
        MachineState(kind = MachineKind.from(prefs.getString(KEY_KIND, null)), host = prefs.getString(KEY_HOST, null) ?: "gaggimate.local"),
    )
    val state: StateFlow<MachineState> = _state.asStateFlow()

    private val client by lazy { OkHttpClient.Builder().connectTimeout(8, TimeUnit.SECONDS).readTimeout(0, TimeUnit.SECONDS).build() }
    private var socket: WebSocket? = null
    private var lastMessage = 0L
    private val shotListeners = mutableSetOf<(Boolean, Long) -> Unit>()
    private val readingListeners = mutableSetOf<(GaggiMateStatus, Long) -> Unit>()
    private val pending = mutableMapOf<String, (JsonObject?) -> Unit>()
    private var nextRequest = 0
    private val demo = DemoMachine { status, telemetry -> apply(status, telemetry) }

    val isConnected: Boolean get() = _state.value.connection == MachineConnection.CONNECTED
    val status: GaggiMateStatus get() = _state.value.status
    val displayName: String
        get() = when (_state.value.kind) {
            MachineKind.GAGGIMATE -> "GaggiMate"
            MachineKind.DEMO -> "Demo machine"
            MachineKind.NONE -> "No machine"
        }

    fun onShot(listener: (Boolean, Long) -> Unit): () -> Unit {
        shotListeners += listener
        return { shotListeners -= listener }
    }

    fun onReading(listener: (GaggiMateStatus, Long) -> Unit): () -> Unit {
        readingListeners += listener
        return { readingListeners -= listener }
    }

    fun start() = restart()

    fun configure(kind: MachineKind, host: String) {
        _state.update { it.copy(kind = kind, host = host) }
        prefs.edit().putString(KEY_KIND, kind.raw).putString(KEY_HOST, host).apply()
        restart()
    }

    /** Demo machine: simulate a shot for this recipe (a real machine is started by hand or with [startShot]). */
    fun prepareForShot(recipe: Recipe) {
        if (_state.value.kind == MachineKind.DEMO) demo.simulateShot(recipe)
    }

    fun cancelShot() {
        if (_state.value.kind == MachineKind.DEMO) demo.stopShot()
    }

    // MARK: Control

    fun setMode(mode: MachineMode) {
        if (_state.value.kind == MachineKind.DEMO) return demo.setMode(mode.value)
        send(buildJsonObject { put("tp", "req:change-mode"); put("mode", mode.value) })
    }

    fun startShot(ignoreWarnings: Boolean = false) {
        _state.update { it.copy(startBlockedBy = emptyList()) }
        if (_state.value.kind == MachineKind.DEMO) return demo.startShotNow()
        if (status.mode != MachineMode.BREW.value) send(buildJsonObject { put("tp", "req:change-mode"); put("mode", MachineMode.BREW.value) })
        send(buildJsonObject { put("tp", "req:process:activate"); put("ignoreWarnings", ignoreWarnings) })
    }

    fun stopShot() {
        if (_state.value.kind == MachineKind.DEMO) return demo.stopShot()
        send(buildJsonObject { put("tp", "req:process:deactivate") })
    }

    fun tareScale() {
        if (_state.value.kind != MachineKind.DEMO) send(buildJsonObject { put("tp", "req:scale:tare") })
    }

    fun dismissStartWarning() {
        _state.update { it.copy(startBlockedBy = emptyList()) }
        send(buildJsonObject { put("tp", "req:brew:confirm:cancel") })
    }

    fun nudgeTemperature(up: Boolean) {
        if (_state.value.kind == MachineKind.DEMO) return demo.nudgeTemperature(up)
        send(buildJsonObject { put("tp", if (up) "req:raise-temp" else "req:lower-temp") })
    }

    /** Saves the recipe as a GaggiMate profile (updating the one sent before) and selects it. */
    fun sendProfile(recipe: Recipe, dose: Double, temperature: Double) {
        if (_state.value.kind == MachineKind.DEMO) {
            demo.setTargetTemperature(temperature)
            _state.update { it.copy(notice = "Demo machine: ${recipe.name} selected") }
            return
        }
        val key = "machine.profile.${recipe.id}"
        val savedId = prefs.getString(key, null)
        var profile = GaggiMateProfile.make(recipe, dose, temperature, status.hasPressure ?: true, status.scaleConnected)
        if (savedId != null) profile = JsonObject(profile + ("id" to JsonPrimitive(savedId)))
        _state.update { it.copy(notice = "Sending ${recipe.name}…") }
        send(buildJsonObject { put("tp", "req:profiles:save"); put("profile", profile) }) { response ->
            val saved = ((response?.get("profile") as? JsonObject)?.get("id") as? JsonPrimitive)?.takeIf { it.isString }?.content
            if (response == null || response["error"] != null || saved == null) {
                if (savedId != null) {
                    prefs.edit().remove(key).apply()
                    sendProfile(recipe, dose, temperature)
                } else {
                    val error = (response?.get("error") as? JsonPrimitive)?.content
                    _state.update { it.copy(notice = "The machine didn't accept the profile" + (error?.let { e -> ": $e" } ?: ".")) }
                }
                return@send
            }
            prefs.edit().putString(key, saved).apply()
            send(buildJsonObject { put("tp", "req:profiles:select"); put("id", saved) }) {
                _state.update { s -> s.copy(notice = "${recipe.name} is selected on the machine") }
            }
        }
    }

    // MARK: Connection

    private fun restart() {
        disconnect()
        demo.stop()
        val kind = _state.value.kind
        _state.update {
            it.copy(status = GaggiMateStatus(), connection = when (kind) {
                MachineKind.NONE -> MachineConnection.OFF
                MachineKind.DEMO -> MachineConnection.CONNECTED
                MachineKind.GAGGIMATE -> MachineConnection.CONNECTING
            })
        }
        when (kind) {
            MachineKind.DEMO -> demo.start()
            MachineKind.GAGGIMATE -> connect()
            MachineKind.NONE -> Unit
        }
    }

    private fun connect() {
        main.removeCallbacks(retry)
        val url = gaggiMateUrl(_state.value.host)
        if (url == null) {
            _state.update { it.copy(connection = MachineConnection.UNREACHABLE) }
            return
        }
        _state.update { it.copy(connection = MachineConnection.CONNECTING) }
        lastMessage = System.currentTimeMillis()
        socket = client.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                main.post {
                    if (socket !== webSocket) return@post
                    lastMessage = System.currentTimeMillis()
                    val frame = GaggiMateStatus.statusFrame(text)
                    if (frame != null) apply(status.merge(frame), GaggiMateStatus.isTelemetry(frame))
                    else GaggiMateStatus.parseMessage(text)?.let { handleOther(it) }
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                main.post { if (socket === webSocket) connectionLost() }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                main.post { if (socket === webSocket) connectionLost() }
            }
        })
        main.postDelayed(watchdog, 2_000)
    }

    /** GaggiMate sends telemetry every 500 ms, so a few silent seconds mean the connection is gone. */
    private val watchdog: Runnable = object : Runnable {
        override fun run() {
            if (socket == null) return
            if (System.currentTimeMillis() - lastMessage > 6_000) connectionLost() else main.postDelayed(this, 2_000)
        }
    }

    private val retry = Runnable { if (_state.value.kind == MachineKind.GAGGIMATE) connect() }

    private fun disconnect() {
        pending.values.toList().forEach { it(null) }
        pending.clear()
        main.removeCallbacks(watchdog)
        main.removeCallbacks(retry)
        val old = socket
        socket = null
        old?.close(1000, null)
    }

    private fun connectionLost() {
        val wasBrewing = status.isBrewing
        disconnect()
        _state.update { it.copy(connection = MachineConnection.UNREACHABLE, status = GaggiMateStatus()) }
        if (wasBrewing) shotListeners.toList().forEach { it(false, monotonicMillis()) }
        main.postDelayed(retry, 5_000)
    }

    private fun apply(newStatus: GaggiMateStatus, telemetry: Boolean) {
        val wasBrewing = status.isBrewing
        _state.update { it.copy(status = newStatus, connection = MachineConnection.CONNECTED) }
        val now = monotonicMillis()
        if (telemetry) readingListeners.toList().forEach { it(newStatus, now) }
        if (newStatus.isBrewing != wasBrewing) shotListeners.toList().forEach { it(newStatus.isBrewing, now) }
    }

    private fun handleOther(message: JsonObject) {
        val type = (message["tp"] as? JsonPrimitive)?.content ?: return
        when {
            type == "evt:brew:confirm" -> _state.update { s ->
                val warnings = (message["warn"] as? JsonArray)?.mapNotNull { ((it as? JsonObject)?.get("k") as? JsonPrimitive)?.content } ?: emptyList()
                s.copy(startBlockedBy = warnings)
            }
            type == "evt:brew:confirm:cancel" -> _state.update { it.copy(startBlockedBy = emptyList()) }
            type.startsWith("res:") -> {
                val rid = (message["rid"] as? JsonPrimitive)?.content ?: return
                pending.remove(rid)?.invoke(message)
            }
        }
    }

    private fun send(payload: JsonObject, complete: ((JsonObject?) -> Unit)? = null) {
        val socket = socket
        if (socket == null || !isConnected) {
            _state.update { it.copy(notice = "The machine isn't connected.") }
            complete?.invoke(null)
            return
        }
        var message: Map<String, JsonElement> = payload
        if (complete != null) {
            val rid = "bl${++nextRequest}"
            message = payload + ("rid" to JsonPrimitive(rid))
            pending[rid] = complete
            main.postDelayed({ pending.remove(rid)?.invoke(null) }, 8_000)
        }
        socket.send(JsonObject(message).toString())
    }

    companion object {
        private const val KEY_KIND = "machine.kind"
        private const val KEY_HOST = "machine.host"
    }
}

/** Simulated machine: idles at brew temperature and runs a realistic pressure profile during a simulated shot. */
private class DemoMachine(private val emit: (GaggiMateStatus, Boolean) -> Unit) {
    private val main = Handler(Looper.getMainLooper())
    private var running = false
    private var status = GaggiMateStatus()
    private var shotStart: Long? = null
    private var preinfusion = 7.0
    private var peak = 9.0
    private var duration = 28.0

    private val tick: Runnable = object : Runnable {
        override fun run() {
            if (!running) return
            step()
            main.postDelayed(this, 500)
        }
    }

    fun start() {
        status = GaggiMateStatus(mode = 1, profile = "Demo", hasPressure = true, targetTemperature = 93.0, temperature = 93.0, pressure = 0.0, flow = 0.0)
        if (!running) {
            running = true
            main.post(tick)
        }
        emit(status, false)
    }

    fun stop() {
        running = false
        main.removeCallbacks(tick)
        shotStart = null
    }

    fun simulateShot(recipe: Recipe) {
        val start = shotStart
        if (start != null && System.currentTimeMillis() >= start) return
        val extract = recipe.steps.firstOrNull { it.kind == StepKind.EXTRACT }?.time ?: 6.0
        preinfusion = max(extract - 1, 2.0)
        peak = recipe.pressure ?: 9.0
        duration = recipe.targetTime + Random.nextDouble(-1.5, 2.0)
        shotStart = System.currentTimeMillis() + 2_500
    }

    fun startShotNow() {
        if (shotStart == null) shotStart = System.currentTimeMillis()
    }

    fun stopShot() {
        shotStart = null
        status = status.copy(processActive = false, pressure = 0.0, flow = 0.0)
    }

    fun setMode(mode: Int) {
        status = status.copy(mode = mode)
        emit(status, false)
    }

    fun nudgeTemperature(up: Boolean) = setTargetTemperature((status.targetTemperature ?: 93.0) + if (up) 1 else -1)

    fun setTargetTemperature(value: Double) {
        status = status.copy(targetTemperature = value)
        emit(status, false)
    }

    private fun step() {
        val target = status.targetTemperature ?: 93.0
        fun noise(n: Double) = Random.nextDouble(-n, n)
        val start = shotStart
        if (start != null && System.currentTimeMillis() >= start) {
            val t = (System.currentTimeMillis() - start) / 1000.0
            if (t >= duration) {
                stopShot()
                status = status.copy(processLabel = "Finished")
            } else {
                val pressure = when {
                    t < preinfusion -> min(t / 1.5, 1.0) * 3
                    t < preinfusion + 2.5 -> 3 + (peak - 3) * (t - preinfusion) / 2.5
                    else -> peak * (1 - 0.18 * ((t - preinfusion - 2.5) / max(duration - preinfusion - 2.5, 1.0)))
                }
                status = status.copy(
                    processActive = true,
                    processKind = if (t < preinfusion) "infusion" else "brew",
                    processLabel = if (t < preinfusion) "Pre-infusion" else "Extraction",
                    pressure = max(pressure + noise(0.15), 0.0),
                    flow = if (t < preinfusion) 3.5 - t / preinfusion * 1.5 else 1.8 + noise(0.2),
                    temperature = target - 0.8 * sin(min(t / duration, 1.0) * PI) + noise(0.1),
                )
            }
        } else {
            status = status.copy(temperature = target + noise(0.1))
        }
        emit(status, true)
    }
}
