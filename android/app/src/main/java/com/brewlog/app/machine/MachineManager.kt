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

// Port of MachineManager.swift / machineManager.ts. Espresso machine connections (GaggiMate, Decent DE1, La Marzocco, demo).

enum class MachineCapability {
    PROFILES, TEMPERATURE_NUDGE, MACHINE_SCALE, START_STOP, POWER
}

enum class MachineKind(val raw: String, val title: String) {
    NONE("none", "None"),
    GAGGIMATE("gaggimate", "GaggiMate"),
    DECENT("decent", "Decent DE1"),
    LA_MARZOCCO("laMarzocco", "La Marzocco"),
    DEMO("demo", "Demo machine");

    val capabilities: Set<MachineCapability>
        get() = when (this) {
            NONE -> emptySet()
            GAGGIMATE, DEMO -> setOf(
                MachineCapability.PROFILES,
                MachineCapability.TEMPERATURE_NUDGE,
                MachineCapability.MACHINE_SCALE,
                MachineCapability.START_STOP,
            )
            DECENT -> setOf(MachineCapability.START_STOP)
            LA_MARZOCCO -> setOf(MachineCapability.POWER, MachineCapability.TEMPERATURE_NUDGE)
        }

    val connectionNote: String
        get() = when (this) {
            NONE -> "Shots are timed with your scale"
            GAGGIMATE -> "Over your Wi-Fi"
            DECENT -> "Over Bluetooth"
            LA_MARZOCCO -> "Through your La Marzocco account"
            DEMO -> "Simulated, to try it out"
        }

    companion object {
        val connectable: List<MachineKind> = listOf(GAGGIMATE, DECENT, LA_MARZOCCO)

        fun from(raw: String?): MachineKind = entries.firstOrNull { it.raw == raw } ?: NONE

        fun suggested(brewerName: String): MachineKind? {
            val lower = brewerName.lowercase()
            return when {
                lower.contains("gaggimate") -> GAGGIMATE
                lower.contains("decent") -> DECENT
                lower.contains("marzocco") -> LA_MARZOCCO
                else -> null
            }
        }
    }
}

enum class MachineConnection(val label: String) {
    OFF("Off"), CONNECTING("Connecting…"), CONNECTED("Connected"), UNREACHABLE("Offline"),
}

data class MachineState(
    val kind: MachineKind = MachineKind.NONE,
    val host: String = "gaggimate.local",
    val connection: MachineConnection = MachineConnection.OFF,
    val status: MachineStatus = MachineStatus(),
    /** Feedback for the last command, e.g. "Profile sent". */
    val notice: String? = null,
    /** The machine refused to start because of a warning (e.g. low water). */
    val startBlockedBy: List<String> = emptyList(),
    val profiles: List<MachineProfileSummary> = emptyList(),
    val profilesLoading: Boolean = false,
) {
    val isConnected: Boolean get() = connection == MachineConnection.CONNECTED
    val canControl: Boolean get() = MachineCapability.START_STOP in kind.capabilities && isConnected
    val readsPressure: Boolean get() = kind != MachineKind.NONE && kind != MachineKind.LA_MARZOCCO && status.hasPressure != false
}

class MachineManager(
    private val prefs: SharedPreferences,
    private val context: android.content.Context? = null,
    private val presets: () -> List<Recipe> = { emptyList() },
) {
    private val main = Handler(Looper.getMainLooper())
    private val _state = MutableStateFlow(
        MachineState(kind = MachineKind.from(prefs.getString(KEY_KIND, null)), host = prefs.getString(KEY_HOST, null) ?: "gaggimate.local"),
    )
    val state: StateFlow<MachineState> = _state.asStateFlow()

    val decent = DecentConnection(context, prefs).also { conn ->
        conn.onStatus = { st, telemetry ->
            if (_state.value.kind == MachineKind.DECENT) apply(st, telemetry)
        }
        conn.onDisconnect = {
            if (_state.value.kind == MachineKind.DECENT) machineLost()
        }
    }

    private val client by lazy { OkHttpClient.Builder().connectTimeout(8, TimeUnit.SECONDS).readTimeout(0, TimeUnit.SECONDS).build() }
    private var socket: WebSocket? = null
    private var lastMessage = 0L
    private val shotListeners = mutableSetOf<(Boolean, Long) -> Unit>()
    private val readingListeners = mutableSetOf<(GaggiMateStatus, Long) -> Unit>()
    private val pending = mutableMapOf<String, (JsonObject?) -> Unit>()
    private var nextRequest = 0
    private var refreshAgain = false
    private val demo = DemoMachine(presets) { status, telemetry -> apply(status, telemetry) }

    val kind: MachineKind get() = _state.value.kind
    val isConnected: Boolean get() = _state.value.isConnected
    val canControl: Boolean get() = _state.value.canControl
    val canChooseProfile: Boolean get() = isConnected && MachineCapability.PROFILES in kind.capabilities
    val readsPressure: Boolean get() = _state.value.readsPressure
    val status: MachineStatus get() = _state.value.status
    val profiles: List<MachineProfileSummary> get() = _state.value.profiles
    val profilesLoading: Boolean get() = _state.value.profilesLoading
    val notice: String? get() = _state.value.notice
    val displayName: String
        get() = when (_state.value.kind) {
            MachineKind.GAGGIMATE -> "GaggiMate"
            MachineKind.DECENT -> "Decent DE1"
            MachineKind.LA_MARZOCCO -> "La Marzocco"
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
        if (_state.value.kind == MachineKind.DECENT) return run { writeToDecent(DecentProtocol.command(mode)) }
        send(buildJsonObject { put("tp", "req:change-mode"); put("mode", mode.value) })
    }

    fun startShot(ignoreWarnings: Boolean = false) {
        _state.update { it.copy(startBlockedBy = emptyList()) }
        if (_state.value.kind == MachineKind.DEMO) return demo.startShotNow()
        if (_state.value.kind == MachineKind.DECENT) {
            if (!writeToDecent(DecentProtocol.startShot)) return
            main.postDelayed({
                if (_state.value.kind == MachineKind.DECENT && isConnected && !decent.isInEspressoState) {
                    _state.update { it.copy(notice = "Start the shot on the machine.") }
                }
            }, 2_000)
            return
        }
        if (status.mode != MachineMode.BREW.value) send(buildJsonObject { put("tp", "req:change-mode"); put("mode", MachineMode.BREW.value) })
        send(buildJsonObject { put("tp", "req:process:activate"); put("ignoreWarnings", ignoreWarnings) })
    }

    fun stopShot() {
        if (_state.value.kind == MachineKind.DEMO) return demo.stopShot()
        if (_state.value.kind == MachineKind.DECENT) return run { writeToDecent(DecentProtocol.stopShot) }
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

    /**
     * Reads the profiles saved on the machine as espresso recipes. Profiles BrewLog sent itself are left out.
     * `completion` gets null if the machine didn't answer.
     */
    fun fetchProfiles(completion: (List<Recipe>?) -> Unit) {
        if (_state.value.kind != MachineKind.GAGGIMATE) {
            completion(null)
            return
        }
        requestProfiles { summaries ->
            completion(summaries?.filter { !it.isBrewLogs }?.mapNotNull { it.recipe })
        }
    }

    /** Loads the machine's profile list into `profiles` (selected first, then favorites). */
    fun refreshProfiles() {
        if (_state.value.kind == MachineKind.DEMO) {
            _state.update { it.copy(profiles = demo.profiles) }
            return
        }
        if (_state.value.kind != MachineKind.GAGGIMATE || !isConnected) return
        if (_state.value.profilesLoading) {
            refreshAgain = true
            return
        }
        _state.update { it.copy(profilesLoading = true) }
        refreshAgain = false
        requestProfiles { summaries ->
            if (_state.value.kind != MachineKind.GAGGIMATE) return@requestProfiles
            _state.update { s ->
                s.copy(
                    profilesLoading = false,
                    profiles = summaries ?: s.profiles,
                    notice = if (summaries == null) "Couldn't read the profiles from the machine." else s.notice,
                )
            }
            if (refreshAgain) {
                refreshAgain = false
                refreshProfiles()
            }
        }
    }

    /** Selects a profile on the machine; `completion` gets whether the machine accepted it. */
    fun selectProfile(id: String, completion: (Boolean) -> Unit) {
        if (_state.value.kind == MachineKind.DEMO) {
            demo.selectProfile(id)
            _state.update { it.copy(profiles = demo.profiles) }
            completion(true)
            return
        }
        send(buildJsonObject { put("tp", "req:profiles:select"); put("id", id) }) { response ->
            val accepted = response != null && response["error"] == null
            if (accepted) {
                _state.update { it.copy(notice = null) }
                refreshProfiles()
            } else {
                val error = (response?.get("error") as? JsonPrimitive)?.content
                _state.update { it.copy(notice = "The machine didn't select the profile" + (error?.let { e -> ": $e" } ?: ".")) }
            }
            completion(accepted)
        }
    }

    /** The BrewLog recipe a profile was sent from (`sendProfile` remembers the profile id per recipe). */
    fun recipeIdForProfile(id: String): String? {
        val prefix = "machine.profile."
        return prefs.all.entries.firstOrNull { it.key.startsWith(prefix) && it.value == id }?.key?.removePrefix(prefix)
    }

    private fun requestProfiles(completion: (List<MachineProfileSummary>?) -> Unit) {
        send(buildJsonObject { put("tp", "req:profiles:list") }) { response ->
            if (response == null || response["error"] != null || response["profiles"] !is JsonArray) {
                completion(null)
                return@send
            }
            completion(GaggiMateProfileImport.summaries(response))
        }
    }

    // MARK: Connection

    fun connectDecent(address: String) {
        decent.connect(address)
    }

    fun forgetDecent() {
        decent.disconnect(forget = true)
        _state.update { it.copy(connection = MachineConnection.UNREACHABLE, status = MachineStatus()) }
    }

    private fun writeToDecent(command: ByteArray): Boolean {
        if (!decent.write(command)) {
            _state.update { it.copy(notice = "The machine isn't connected.") }
            return false
        }
        _state.update { it.copy(notice = null) }
        return true
    }

    private fun machineLost() {
        val wasBrewing = status.isBrewing
        _state.update { it.copy(connection = MachineConnection.UNREACHABLE, status = MachineStatus()) }
        if (wasBrewing) shotListeners.toList().forEach { it(false, monotonicMillis()) }
    }

    private fun restart() {
        disconnect()
        refreshAgain = false
        demo.stop()
        val kind = _state.value.kind
        if (kind != MachineKind.DECENT) decent.disconnect(forget = false)
        _state.update {
            it.copy(
                status = MachineStatus(),
                profiles = emptyList(),
                profilesLoading = false,
                notice = null,
                connection = when (kind) {
                    MachineKind.NONE -> MachineConnection.OFF
                    MachineKind.DEMO -> MachineConnection.CONNECTED
                    MachineKind.GAGGIMATE -> MachineConnection.CONNECTING
                    MachineKind.DECENT -> if (decent.hasSavedMachine) MachineConnection.CONNECTING else MachineConnection.UNREACHABLE
                    MachineKind.LA_MARZOCCO -> MachineConnection.OFF
                },
            )
        }
        when (kind) {
            MachineKind.DEMO -> demo.start()
            MachineKind.GAGGIMATE -> connect()
            MachineKind.DECENT -> decent.reconnectRemembered()
            MachineKind.LA_MARZOCCO, MachineKind.NONE -> Unit
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
        _state.update { it.copy(connection = MachineConnection.UNREACHABLE, status = GaggiMateStatus(), profilesLoading = false) }
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
private class DemoMachine(
    private val presets: () -> List<Recipe>,
    private val emit: (GaggiMateStatus, Boolean) -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private var running = false
    private var status = GaggiMateStatus()
    private var shotStart: Long? = null
    private var preinfusion = 7.0
    private var peak = 9.0
    private var duration = 28.0
    private var selectedProfile: String? = null

    val profiles: List<MachineProfileSummary>
        get() {
            val recipes = presets().filter { it.method.isEspresso }.take(2)
            val selected = selectedProfile ?: recipes.firstOrNull()?.id
            return recipes.map {
                MachineProfileSummary(
                    id = it.id,
                    label = it.name,
                    isSelected = it.id == selected,
                    isFavorite = false,
                    isBrewLogs = false,
                    recipe = it,
                )
            }.sortedBy { !it.isSelected }
        }

    fun selectProfile(id: String) {
        selectedProfile = id
        status = status.copy(profile = profiles.firstOrNull { it.id == id }?.label)
        emit(status, false)
    }

    private val tick: Runnable = object : Runnable {
        override fun run() {
            if (!running) return
            step()
            main.postDelayed(this, 500)
        }
    }

    fun start() {
        status = GaggiMateStatus(
            mode = 1,
            profile = profiles.firstOrNull()?.label ?: "Demo",
            hasPressure = true,
            targetTemperature = 93.0,
            temperature = 93.0,
            pressure = 0.0,
            flow = 0.0,
        )
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
