package com.brewlog.app.machine

import android.content.SharedPreferences
import com.brewlog.app.sync.SecretStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.io.IOException
import java.util.Base64
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt

/**
 * Talks to La Marzocco's cloud with the user's own La Marzocco account (opt-in, see docs/la-marzocco-protocol.md):
 * signs in, lists the machines, follows the chosen one's dashboard over a STOMP WebSocket and sends power and
 * temperature commands. Login and key material live only in SecretStore.
 *
 * Every connection attempt belongs to a generation; disconnect() and signOut() start a new one, so answers that
 * arrive afterwards (a slow dashboard request, a token, a socket message) are dropped instead of reviving old state.
 */
class LaMarzoccoCloud(
    private val secretStore: SecretStore,
    private val prefs: SharedPreferences,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
) {
    sealed class CloudError(message: String, val isTemporary: Boolean) : Exception(message) {
        object NotSignedIn : CloudError("Sign in to your La Marzocco account first.", false)
        object WrongLogin : CloudError("Wrong La Marzocco login.", false)
        object Policy : CloudError("Accept La Marzocco's privacy policy in their app, then try again.", false)
        object Offline : CloudError("No internet connection.", true)
        object Unexpected : CloudError("La Marzocco's service didn't answer as expected. They may have changed it.", true)
    }

    private val _signedInAs = MutableStateFlow<String?>(null)
    val signedInAs: StateFlow<String?> = _signedInAs.asStateFlow()

    private val _machine = MutableStateFlow<LaMarzoccoProtocol.Machine?>(null)
    val machine: StateFlow<LaMarzoccoProtocol.Machine?> = _machine.asStateFlow()

    private val _machines = MutableStateFlow<List<LaMarzoccoProtocol.Machine>>(emptyList())
    val machines: StateFlow<List<LaMarzoccoProtocol.Machine>> = _machines.asStateFlow()

    val isReady: Boolean get() = signedInAs.value != null && machine.value != null

    var onStatus: ((MachineStatus) -> Unit)? = null
    var onOnline: ((Boolean) -> Unit)? = null
    var onNotice: ((String) -> Unit)? = null

    private var accessToken: String? = null
    private var refreshToken: String? = null
    private var tokenExpiryMs: Long = 0L
    private var socket: WebSocket? = null
    private var retryJob: Job? = null
    private var generation: Int = 0
    private var opening: Boolean = false
    private var failures: Int = 0
    private var online: Boolean = false
    private var haveDashboard: Boolean = false
    private var haveReportedOffline: Boolean = false
    private val pendingCommands = mutableMapOf<String, String>()
    private var wanted: Boolean = false
    private var status = MachineStatus()

    private val restClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .callTimeout(20, TimeUnit.SECONDS)
        .build()

    private val wsClient: OkHttpClient = OkHttpClient.Builder()
        .pingInterval(15, TimeUnit.SECONDS)
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()

    init {
        _signedInAs.value = secretStore.get(USERNAME_ACCOUNT)
        prefs.getString(MACHINE_KEY, null)?.let { json ->
            runCatching {
                val obj = Json.parseToJsonElement(json).jsonObject
                LaMarzoccoProtocol.Machine(
                    id = obj["id"]?.jsonPrimitive?.content ?: "",
                    name = obj["name"]?.jsonPrimitive?.content ?: "",
                    model = obj["model"]?.jsonPrimitive?.content ?: "",
                )
            }.getOrNull()?.let { _machine.value = it }
        }
    }

    // MARK: Account

    suspend fun signIn(username: String, password: String): List<LaMarzoccoProtocol.Machine> {
        val user = username.trim()
        if (user.isEmpty() || password.isEmpty()) throw CloudError.WrongLogin
        val key = getInstallationKey(create = true)
        fetchTokens(
            path = "/auth/signin",
            body = mapOf("username" to user, "password" to password),
            key = key,
            gen = generation,
        )
        secretStore.set(USERNAME_ACCOUNT, user)
        secretStore.set(PASSWORD_ACCOUNT, password)
        _signedInAs.value = user
        val list = LaMarzoccoProtocol.machines(request("/things", key = key))
        _machines.value = list
        return list
    }

    suspend fun reloadMachines(): List<LaMarzoccoProtocol.Machine> {
        if (signedInAs.value == null) throw CloudError.NotSignedIn
        val list = LaMarzoccoProtocol.machines(request("/things"))
        _machines.value = list
        return list
    }

    fun choose(chosen: LaMarzoccoProtocol.Machine) {
        _machine.value = chosen
        val json = buildJsonObject {
            put("id", chosen.id)
            put("name", chosen.name)
            put("model", chosen.model)
        }.toString()
        prefs.edit().putString(MACHINE_KEY, json).apply()
    }

    fun signOut() {
        disconnect()
        for (account in listOf(USERNAME_ACCOUNT, PASSWORD_ACCOUNT, KEY_ACCOUNT)) {
            secretStore.set(account, null)
        }
        prefs.edit().remove(MACHINE_KEY).apply()
        accessToken = null
        refreshToken = null
        tokenExpiryMs = 0L
        _signedInAs.value = null
        _machine.value = null
        _machines.value = emptyList()
    }

    // MARK: Following the machine

    fun connect() {
        if (!isReady) {
            onOnline?.invoke(false)
            return
        }
        wanted = true
        failures = 0
        if (socket != null || opening) return
        retryJob?.cancel()
        openNow()
    }

    fun disconnect() {
        wanted = false
        generation++
        opening = false
        retryJob?.cancel()
        retryJob = null
        closeSocket()
        status = MachineStatus()
        online = false
        haveDashboard = false
        pendingCommands.clear()
    }

    // MARK: Commands

    suspend fun setPower(on: Boolean): Boolean {
        return command(
            name = "CoffeeMachineChangeMode",
            body = mapOf("mode" to if (on) "BrewingMode" else "StandBy"),
            what = if (on) "switch on" else "go to standby",
        )
    }

    suspend fun setTargetTemperature(value: Double): Boolean {
        val rounded = (minOf(maxOf(value, 80.0), 100.0) * 10).roundToInt() / 10.0
        return command(
            name = "CoffeeMachineSettingCoffeeBoilerTargetTemperature",
            body = mapOf("boilerIndex" to 1, "targetTemperature" to rounded),
            what = "change the temperature",
        )
    }

    private suspend fun command(name: String, body: Map<String, Any>, what: String): Boolean {
        val curMachine = machine.value ?: return false
        if (!wanted) return false
        return try {
            val answer = request("/things/${pathSafe(curMachine.id)}/command/$name", method = "POST", body = body)
            val id = LaMarzoccoProtocol.commandID(answer)
            if (id != null) {
                pendingCommands[id] = what
            }
            true
        } catch (e: Exception) {
            val message = e.message ?: "Command failed"
            onNotice?.invoke(message)
            false
        }
    }

    // MARK: WebSocket

    private fun openNow() {
        if (!wanted || socket != null || opening) return
        opening = true
        val gen = generation
        scope.launch { open(gen) }
    }

    private suspend fun open(gen: Int) {
        val curMachine = machine.value ?: return
        try {
            if (signedInAs.value == null) throw CloudError.NotSignedIn
            val key = getInstallationKey(create = false)
            val token = validAccessToken(key, gen)
            // Current state first
            val dashboard = runCatching { request("/things/${pathSafe(curMachine.id)}/dashboard", key = key) }.getOrNull()
            if (dashboard != null && gen == generation) {
                handle(dashboard)
            }
            if (gen == generation) {
                opening = false
                openSocket(key, token, curMachine.id)
            }
        } catch (e: Exception) {
            val cloudError = (e as? CloudError) ?: CloudError.Unexpected
            if (gen == generation) {
                opening = false
                onNotice?.invoke(cloudError.message ?: "")
                connectionLost(retry = cloudError.isTemporary)
            }
        }
    }

    private fun openSocket(key: LaMarzoccoAuth.InstallationKey, token: String, serial: String) {
        if (!wanted || socket != null) return
        val reqBuilder = Request.Builder().url(LaMarzoccoProtocol.SOCKET_URL)
        for ((name, value) in LaMarzoccoAuth.signedHeaders(key)) {
            reqBuilder.addHeader(name, value)
        }
        val task = wsClient.newWebSocket(
            reqBuilder.build(),
            object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    failures = 0
                    val connectFrame = LaMarzoccoProtocol.stompFrame(
                        "CONNECT",
                        listOf(
                            "host" to LaMarzoccoProtocol.HOST,
                            "accept-version" to "1.2,1.1,1.0",
                            "heart-beat" to "0,0",
                            "Authorization" to "Bearer $token",
                        ),
                    )
                    webSocket.send(connectFrame)
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    val frame = LaMarzoccoProtocol.parseStomp(text) ?: return
                    scope.launch {
                        handleFrame(frame, serial, webSocket)
                    }
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    scope.launch {
                        connectionLost(retry = true)
                    }
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    scope.launch {
                        connectionLost(retry = true)
                    }
                }
            },
        )
        socket = task
    }

    private fun handleFrame(
        frame: LaMarzoccoProtocol.StompFrame,
        serial: String,
        webSocket: WebSocket,
    ) {
        when (frame.command) {
            "CONNECTED" -> {
                failures = 0
                val subscribeFrame = LaMarzoccoProtocol.stompFrame(
                    "SUBSCRIBE",
                    listOf(
                        "destination" to "/ws/sn/${pathSafe(serial)}/dashboard",
                        "ack" to "auto",
                        "id" to java.util.UUID.randomUUID().toString().lowercase(),
                        "content-length" to "0",
                    ),
                )
                webSocket.send(subscribeFrame)
                if (!haveDashboard) refreshDashboard(serial)
            }
            "MESSAGE" -> {
                handle(frame.body.toByteArray(Charsets.UTF_8))
            }
            "ERROR" -> {
                accessToken = null
                onNotice?.invoke(CloudError.Unexpected.message ?: "")
                connectionLost(retry = true)
            }
        }
    }

    private fun refreshDashboard(serial: String) {
        val gen = generation
        scope.launch {
            val data = runCatching { request("/things/${pathSafe(serial)}/dashboard") }.getOrNull() ?: return@launch
            if (gen == generation) {
                handle(data)
            }
        }
    }

    private fun handle(dashboard: ByteArray) {
        if (!wanted) return
        val result = LaMarzoccoProtocol.apply(dashboard, status) ?: return
        status = result.status
        haveDashboard = true
        for ((id, outcome) in result.commandResults) {
            val what = pendingCommands.remove(id) ?: continue
            if (outcome != "Success") {
                onNotice?.invoke("The machine didn't $what (${outcome.lowercase()}).")
            }
        }
        when (result.connected) {
            false -> {
                if (online || !haveReportedOffline) {
                    onNotice?.invoke("The machine is offline in La Marzocco's app.")
                }
                haveReportedOffline = true
                online = false
                onOnline?.invoke(false)
            }
            true -> {
                haveReportedOffline = false
                online = true
                onOnline?.invoke(true)
                onStatus?.invoke(status)
            }
            null -> {
                if (online) onStatus?.invoke(status)
            }
        }
    }

    private fun closeSocket() {
        socket?.close(1000, "Going away")
        socket = null
    }

    private fun connectionLost(retry: Boolean) {
        closeSocket()
        status = MachineStatus()
        online = false
        haveDashboard = false
        onOnline?.invoke(false)
        if (!wanted || !retry) return
        failures++
        if (failures >= MAX_ATTEMPTS) {
            onNotice?.invoke("Couldn't reach your machine through La Marzocco. Open the machine settings to try again.")
            return
        }
        val delayMs = minOf(5000L * (1L shl minOf(failures - 1, 6)), 300_000L)
        retryJob?.cancel()
        retryJob = scope.launch {
            delay(delayMs)
            openNow()
        }
    }

    // MARK: HTTP

    private suspend fun getInstallationKey(create: Boolean): LaMarzoccoAuth.InstallationKey = withContext(Dispatchers.IO) {
        secretStore.get(KEY_ACCOUNT)?.let { json ->
            LaMarzoccoAuth.InstallationKey.fromJson(json)?.let { return@withContext it }
        }
        if (!create) throw CloudError.Offline
        val key = LaMarzoccoAuth.makeKey()
        send(
            path = "/auth/init",
            method = "POST",
            body = buildJsonObject { put("pk", Base64.getEncoder().encodeToString(key.publicKeyDer)) }.toString(),
            headers = LaMarzoccoAuth.registrationHeaders(key),
        )
        secretStore.set(KEY_ACCOUNT, key.toJson())
        key
    }

    private suspend fun validAccessToken(key: LaMarzoccoAuth.InstallationKey, gen: Int = generation): String {
        if (accessToken != null && !LaMarzoccoProtocol.needsRefresh(tokenExpiryMs)) {
            return accessToken!!
        }
        val user = secretStore.get(USERNAME_ACCOUNT)
        val pass = secretStore.get(PASSWORD_ACCOUNT)
        if (user == null || pass == null) {
            throw if (signedInAs.value == null) CloudError.NotSignedIn else CloudError.Offline
        }
        if (refreshToken != null && accessToken != null && tokenExpiryMs > System.currentTimeMillis()) {
            try {
                fetchTokens(
                    path = "/auth/refreshtoken",
                    body = mapOf("username" to user, "refreshToken" to refreshToken!!),
                    key = key,
                    gen = gen,
                )
                accessToken?.let { return it }
            } catch (_: Exception) {
            }
        }
        fetchTokens(
            path = "/auth/signin",
            body = mapOf("username" to user, "password" to pass),
            key = key,
            gen = gen,
        )
        return accessToken ?: throw CloudError.Unexpected
    }

    private suspend fun fetchTokens(path: String, body: Map<String, Any>, key: LaMarzoccoAuth.InstallationKey, gen: Int) {
        val jsonBody = buildJsonObject {
            for ((k, v) in body) {
                put(k, v.toString())
            }
        }.toString()
        val data = send(path = path, method = "POST", body = jsonBody, headers = LaMarzoccoAuth.signedHeaders(key))
        val tokens = LaMarzoccoProtocol.tokens(data) ?: throw CloudError.Unexpected
        if (gen == generation) {
            accessToken = tokens.first
            refreshToken = tokens.second
            tokenExpiryMs = System.currentTimeMillis() + LaMarzoccoProtocol.TOKEN_LIFETIME_MS
        }
    }

    private suspend fun request(
        path: String,
        method: String = "GET",
        body: Any? = null,
        key: LaMarzoccoAuth.InstallationKey? = null,
    ): ByteArray {
        val resolvedKey = key ?: getInstallationKey(create = false)
        val token = validAccessToken(resolvedKey)
        val headers = LaMarzoccoAuth.signedHeaders(resolvedKey).toMutableMap()
        headers["Authorization"] = "Bearer $token"
        val bodyStr = when (body) {
            is Map<*, *> -> buildJsonObject {
                for ((k, v) in body) {
                    when (v) {
                        is Number -> put(k.toString(), v.toDouble())
                        is Boolean -> put(k.toString(), v)
                        else -> put(k.toString(), v?.toString() ?: "")
                    }
                }
            }.toString()
            is String -> body
            null -> null
            else -> body.toString()
        }
        return try {
            send(path = path, method = method, body = bodyStr, headers = headers)
        } catch (e: CloudError.WrongLogin) {
            accessToken = null
            throw e
        }
    }

    private suspend fun send(
        path: String,
        method: String,
        body: String?,
        headers: Map<String, String>,
    ): ByteArray = withContext(Dispatchers.IO) {
        val url = LaMarzoccoProtocol.API_BASE + path
        val reqBuilder = Request.Builder().url(url)
        for ((name, value) in headers) {
            reqBuilder.addHeader(name, value)
        }
        if (body != null) {
            reqBuilder.addHeader("Content-Type", "application/json")
            reqBuilder.method(method, body.toRequestBody("application/json; charset=utf-8".toMediaType()))
        } else {
            reqBuilder.method(method, null)
        }
        val response = try {
            restClient.newCall(reqBuilder.build()).execute()
        } catch (e: IOException) {
            throw CloudError.Offline
        } catch (e: Exception) {
            throw CloudError.Unexpected
        }
        val bytes = response.body?.bytes() ?: ByteArray(0)
        if (bytes.size > 1_000_000) throw CloudError.Unexpected
        when (response.code) {
            in 200..299 -> bytes
            401 -> throw CloudError.WrongLogin
            403 -> {
                val text = bytes.toString(Charsets.UTF_8)
                val code = runCatching { Json.parseToJsonElement(text).jsonObject["code"]?.jsonPrimitive?.content }.getOrNull()
                if (code == "USER_MUST_ACCEPT_POLICY") throw CloudError.Policy else throw CloudError.WrongLogin
            }
            else -> throw CloudError.Unexpected
        }
    }

    private fun pathSafe(value: String): String {
        return value.filter { it.isLetterOrDigit() || it == '-' || it == '_' }
    }

    companion object {
        private const val USERNAME_ACCOUNT = "lm.username"
        private const val PASSWORD_ACCOUNT = "lm.password"
        private const val KEY_ACCOUNT = "lm.installation"
        private const val MACHINE_KEY = "machine.lmMachine"
        private const val MAX_ATTEMPTS = 6
    }
}
