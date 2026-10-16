package com.brewlog.app.scale

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.core.content.ContextCompat
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.sanitized
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update

enum class ScaleConnectionState(val label: String) {
    BLUETOOTH_OFF("Bluetooth is off"),
    NO_PERMISSION("Bluetooth permission needed"),
    UNSUPPORTED("Bluetooth not supported"),
    IDLE("Not connected"),
    SCANNING("Searching…"),
    CONNECTING("Connecting…"),
    CONNECTED("Connected"),
}

data class DiscoveredScale(val address: String, val name: String, val rssi: Int)

/** One validated reading: grams + monotonic timestamp (see [monotonicMillis]). */
data class ScaleReading(val grams: Double, val timeMillis: Long)

/** What the brew engine needs from a scale. */
interface ScaleCommands {
    val isReady: Boolean
    fun tare()
    fun prepareForBrew(recipe: Recipe)
    fun brewStarted()
    fun brewFinished()
}

/**
 * Connects to a BOOKOO Themis Mini over Bluetooth LE (or the built-in demo scale) and publishes live readings.
 * Android port of ScaleManager.swift. All Bluetooth calls are guarded by [hasPermissions].
 */
@SuppressLint("MissingPermission")
class ScaleManager(
    private val context: Context,
    private val prefs: SharedPreferences,
    scope: CoroutineScope,
) : ScaleCommands {
    private val adapter: BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    private val main = Handler(Looper.getMainLooper())

    private val _state = MutableStateFlow(ScaleConnectionState.IDLE)
    val state: StateFlow<ScaleConnectionState> = _state.asStateFlow()
    private val _discovered = MutableStateFlow<List<DiscoveredScale>>(emptyList())
    val discovered: StateFlow<List<DiscoveredScale>> = _discovered.asStateFlow()
    private val _weight = MutableStateFlow(0.0)
    val weight: StateFlow<Double> = _weight.asStateFlow()
    private val _battery = MutableStateFlow<Int?>(null)
    val battery: StateFlow<Int?> = _battery.asStateFlow()
    private val _connectedName = MutableStateFlow<String?>(null)
    val connectedName: StateFlow<String?> = _connectedName.asStateFlow()
    private val _rejected = MutableStateFlow(0)
    /** Packets dropped by validation (diagnostics). */
    val rejectedPackets: StateFlow<Int> = _rejected.asStateFlow()
    private val _isDemo = MutableStateFlow(prefs.getBoolean(KEY_DEMO, false))
    val isDemo: StateFlow<Boolean> = _isDemo.asStateFlow()
    private val _readings = MutableSharedFlow<ScaleReading>(extraBufferCapacity = 128)
    /** Every validated reading. Used by the brew engine and quick weigh. */
    val readings: SharedFlow<ScaleReading> = _readings.asSharedFlow()

    /** True when live weight is available. */
    val ready: StateFlow<Boolean> = combine(_isDemo, _state) { demo, state ->
        demo || state == ScaleConnectionState.CONNECTED
    }.stateIn(scope, SharingStarted.Eagerly, false)

    override val isReady: Boolean get() = _isDemo.value || _state.value == ScaleConnectionState.CONNECTED

    val displayName: String get() = if (_isDemo.value) "Demo scale" else (_connectedName.value ?: "Scale")

    private var gatt: BluetoothGatt? = null
    private var commandCharacteristic: BluetoothGattCharacteristic? = null
    private var userInitiatedDisconnect = false
    private var receiverRegistered = false
    private val validator = BookooPacketValidator()
    private val demo = DemoScale(scope) { grams -> handle(grams, 100) }

    // MARK: Public API

    fun hasPermissions(): Boolean {
        fun granted(permission: String) =
            ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            granted(Manifest.permission.BLUETOOTH_SCAN) && granted(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            granted(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    val isBluetoothOn: Boolean get() = adapter?.isEnabled == true

    /** Call at launch and after permissions were granted: starts Bluetooth and reconnects to the last scale. */
    fun start() {
        applyDemoMode()
        if (_isDemo.value) return
        registerBluetoothReceiver()
        refreshState()
        if (_state.value == ScaleConnectionState.IDLE) reconnectSaved()
    }

    fun setDemo(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_DEMO, enabled).apply()
        _isDemo.value = enabled
        applyDemoMode()
        if (!enabled) start()
    }

    fun startScan() {
        if (_isDemo.value) return
        refreshState()
        if (_state.value != ScaleConnectionState.IDLE) return
        val scanner = adapter?.bluetoothLeScanner ?: return
        _discovered.value = emptyList()
        _state.value = ScaleConnectionState.SCANNING
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        runCatching { scanner.startScan(null, settings, scanCallback) }
            .onFailure { _state.value = ScaleConnectionState.IDLE }
        main.postDelayed({ stopScan() }, SCAN_TIMEOUT_MS)
    }

    fun stopScan() {
        if (hasPermissions()) runCatching { adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
        if (_state.value == ScaleConnectionState.SCANNING) _state.value = ScaleConnectionState.IDLE
    }

    fun connect(address: String, autoConnect: Boolean = false) {
        if (!hasPermissions() || !BluetoothAdapter.checkBluetoothAddress(address)) return
        val device = adapter?.getRemoteDevice(address) ?: return
        stopScan()
        userInitiatedDisconnect = false
        validator.reset()
        gatt?.close()
        _state.value = ScaleConnectionState.CONNECTING
        prefs.edit().putString(KEY_ADDRESS, address).apply()
        // Deprecated in API 37, but it's the API available on Android 8–16 (minSdk 26).
        @Suppress("DEPRECATION")
        gatt = device.connectGatt(context, autoConnect, gattCallback, BluetoothDevice.TRANSPORT_LE)
    }

    fun disconnect(forget: Boolean) {
        userInitiatedDisconnect = true
        if (hasPermissions()) {
            gatt?.disconnect()
            gatt?.close()
        }
        gatt = null
        commandCharacteristic = null
        _connectedName.value = null
        if (forget) prefs.edit().remove(KEY_ADDRESS).apply()
        _state.value = ScaleConnectionState.IDLE
    }

    val hasSavedScale: Boolean get() = prefs.getString(KEY_ADDRESS, null) != null

    override fun tare() {
        if (_isDemo.value) demo.tare() else send(BookooProtocol.Command.TARE)
    }

    /** Tares and resets the scale timer. In demo mode it also schedules a simulated pour that follows the recipe. */
    override fun prepareForBrew(recipe: Recipe) {
        if (_isDemo.value) {
            demo.simulate(recipe)
        } else {
            send(BookooProtocol.Command.TARE)
            main.postDelayed({ send(BookooProtocol.Command.RESET_TIMER) }, 150)
        }
    }

    override fun brewStarted() = send(BookooProtocol.Command.START_TIMER)

    override fun brewFinished() {
        send(BookooProtocol.Command.STOP_TIMER)
        if (_isDemo.value) demo.stopSimulation()
    }

    /** Writes one of the allowlisted commands. No other bytes can be sent to the scale. */
    fun send(command: BookooProtocol.Command) {
        if (_isDemo.value || !hasPermissions()) return
        val g = gatt ?: return
        val characteristic = commandCharacteristic ?: return
        val type = if (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0) {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        }
        write(g, characteristic, command.packet(), type)
    }

    // MARK: Private

    private fun applyDemoMode() {
        if (_isDemo.value) {
            if (gatt != null) disconnect(forget = false)
            demo.start()
            _battery.value = 100
        } else {
            demo.stop()
        }
    }

    private fun refreshState() {
        val current = _state.value
        _state.value = when {
            adapter == null -> ScaleConnectionState.UNSUPPORTED
            !hasPermissions() -> ScaleConnectionState.NO_PERMISSION
            adapter.isEnabled.not() -> ScaleConnectionState.BLUETOOTH_OFF
            current == ScaleConnectionState.UNSUPPORTED ||
                current == ScaleConnectionState.NO_PERMISSION ||
                current == ScaleConnectionState.BLUETOOTH_OFF -> ScaleConnectionState.IDLE
            else -> current
        }
    }

    private fun reconnectSaved() {
        val address = prefs.getString(KEY_ADDRESS, null) ?: return
        // autoConnect = true: Android connects as soon as the scale is switched on.
        connect(address, autoConnect = true)
    }

    private fun registerBluetoothReceiver() {
        if (receiverRegistered) return
        receiverRegistered = true
        ContextCompat.registerReceiver(
            context,
            object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    val wasOff = _state.value == ScaleConnectionState.BLUETOOTH_OFF
                    refreshState()
                    if (wasOff && _state.value == ScaleConnectionState.IDLE && !_isDemo.value) reconnectSaved()
                }
            },
            IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    private fun handle(grams: Double, battery: Int?) {
        if (!grams.isFinite()) return
        _weight.value = grams
        if (battery != null) _battery.value = battery.coerceIn(0, 100)
        _readings.tryEmit(ScaleReading(grams, monotonicMillis()))
    }

    private fun isScale(name: String?, result: ScanResult): Boolean {
        // The BOOKOO Espresso Monitor is a pressure sensor, not a scale.
        if (BookooPressureProtocol.isMonitorName(name)) return false
        if (name?.contains(BookooProtocol.NAME_PREFIX, ignoreCase = true) == true) return true
        return result.scanRecord?.serviceUuids?.contains(ParcelUuid(BookooProtocol.SERVICE_UUID)) == true
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val name = result.scanRecord?.deviceName ?: runCatching { result.device.name }.getOrNull()
            if (!isScale(name, result)) return
            // Advertised names are untrusted input: sanitize and bound them.
            val safeName = (name ?: "BOOKOO scale").sanitized(40).ifEmpty { "BOOKOO scale" }
            val entry = DiscoveredScale(result.device.address, safeName, result.rssi)
            _discovered.update { list ->
                when {
                    list.any { it.address == entry.address } -> list.map { if (it.address == entry.address) entry else it }
                    list.size < MAX_DISCOVERED -> list + entry
                    else -> list
                }
            }
        }

        override fun onScanFailed(errorCode: Int) {
            _state.value = ScaleConnectionState.IDLE
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    _connectedName.value = (runCatching { g.device.name }.getOrNull() ?: "BOOKOO").sanitized(40)
                    g.discoverServices()
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    commandCharacteristic = null
                    if (userInitiatedDisconnect || _isDemo.value) {
                        _state.value = ScaleConnectionState.IDLE
                    } else {
                        // Unexpected disconnect (scale off or out of range): keep trying in the background.
                        _state.value = ScaleConnectionState.CONNECTING
                        val address = g.device.address
                        main.postDelayed({
                            if (!userInitiatedDisconnect && !_isDemo.value) connect(address, autoConnect = true)
                        }, 1_000)
                    }
                }
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            val service = g.getService(BookooProtocol.SERVICE_UUID) ?: return
            commandCharacteristic = service.getCharacteristic(BookooProtocol.COMMAND_CHAR_UUID)
            val weight = service.getCharacteristic(BookooProtocol.WEIGHT_CHAR_UUID) ?: return
            enableNotifications(g, weight)
        }

        override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS && !_isDemo.value) _state.value = ScaleConnectionState.CONNECTED
        }

        // Android 13+
        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            onData(characteristic, value)
        }

        // Android 12 and lower
        @Deprecated("Used on Android 12 and lower")
        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) onData(characteristic, characteristic.value ?: return)
        }
    }

    private fun onData(characteristic: BluetoothGattCharacteristic, value: ByteArray) {
        if (characteristic.uuid != BookooProtocol.WEIGHT_CHAR_UUID) return
        val reading = validator.accept(value)
        if (reading == null) {
            _rejected.value = validator.rejected
            return
        }
        if (_state.value != ScaleConnectionState.CONNECTED && !_isDemo.value) _state.value = ScaleConnectionState.CONNECTED
        handle(reading.grams, reading.batteryPercent)
    }

    @Suppress("DEPRECATION")
    private fun enableNotifications(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
        g.setCharacteristicNotification(characteristic, true)
        val cccd = characteristic.getDescriptor(BookooProtocol.CCCD_UUID) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
        } else {
            cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            g.writeDescriptor(cccd)
        }
    }

    @Suppress("DEPRECATION")
    private fun write(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, bytes: ByteArray, type: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeCharacteristic(characteristic, bytes, type)
        } else {
            characteristic.writeType = type
            characteristic.value = bytes
            g.writeCharacteristic(characteristic)
        }
    }

    companion object {
        private const val KEY_DEMO = "demoScale"
        private const val KEY_ADDRESS = "scale.lastAddress"
        private const val SCAN_TIMEOUT_MS = 15_000L
        /** Upper bound on remembered nearby devices (scan results are attacker-controllable). */
        private const val MAX_DISCOVERED = 20
    }
}
