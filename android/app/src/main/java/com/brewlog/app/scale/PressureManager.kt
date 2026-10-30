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

enum class PressureConnectionState(val label: String) {
    BLUETOOTH_OFF("Bluetooth is off"),
    NO_PERMISSION("Bluetooth permission needed"),
    UNSUPPORTED("Bluetooth not supported"),
    IDLE("Not connected"),
    SCANNING("Searching…"),
    CONNECTING("Connecting…"),
    CONNECTED("Connected"),
}

data class DiscoveredPressureDevice(val address: String, val name: String, val rssi: Int)

/** One validated reading: bar + monotonic timestamp. */
data class PressureReading(val bar: Double, val timeMillis: Long)

interface PressureCommands {
    val isReady: Boolean
    fun tare()
    fun prepareForBrew(recipe: com.brewlog.app.domain.Recipe)
    fun startMonitoring()
    fun stopMonitoring()
    fun brewFinished()
}

/**
 * Connects to a BOOKOO Espresso Monitor over BLE (or the demo monitor) and publishes real-time pressure.
 * Operates concurrently alongside ScaleManager for dual-device BLE workflows.
 */
@SuppressLint("MissingPermission")
class PressureManager(
    private val context: Context,
    private val prefs: SharedPreferences,
    scope: CoroutineScope,
) : PressureCommands {
    private val adapter: BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    private val main = Handler(Looper.getMainLooper())

    private val _state = MutableStateFlow(PressureConnectionState.IDLE)
    val state: StateFlow<PressureConnectionState> = _state.asStateFlow()

    private val _discovered = MutableStateFlow<List<DiscoveredPressureDevice>>(emptyList())
    val discovered: StateFlow<List<DiscoveredPressureDevice>> = _discovered.asStateFlow()

    private val _pressure = MutableStateFlow(0.0)
    val pressure: StateFlow<Double> = _pressure.asStateFlow()

    private val _battery = MutableStateFlow<Int?>(null)
    val battery: StateFlow<Int?> = _battery.asStateFlow()

    private val _connectedName = MutableStateFlow<String?>(null)
    val connectedName: StateFlow<String?> = _connectedName.asStateFlow()

    private val _isDemo = MutableStateFlow(prefs.getBoolean(KEY_DEMO, false))
    val isDemo: StateFlow<Boolean> = _isDemo.asStateFlow()

    private val _isEnabled = MutableStateFlow(prefs.getBoolean(KEY_ENABLED, false))
    /** Zero-Clutter Invariant: UI elements only appear when enabled and connected. */
    val isEnabled: StateFlow<Boolean> = _isEnabled.asStateFlow()

    private val _readings = MutableSharedFlow<PressureReading>(extraBufferCapacity = 128)
    val readings: SharedFlow<PressureReading> = _readings.asSharedFlow()

    val ready: StateFlow<Boolean> = combine(_isDemo, _state, _isEnabled) { demo, state, enabled ->
        enabled && (demo || state == PressureConnectionState.CONNECTED)
    }.stateIn(scope, SharingStarted.Eagerly, false)

    override val isReady: Boolean get() = _isEnabled.value && (_isDemo.value || _state.value == PressureConnectionState.CONNECTED)

    val displayName: String get() = if (_isDemo.value) "Demo pressure" else (_connectedName.value ?: "Espresso Monitor")

    private var gatt: BluetoothGatt? = null
    private var commandCharacteristic: BluetoothGattCharacteristic? = null
    private var userInitiatedDisconnect = false
    private var receiverRegistered = false
    private val validator = BookooPressurePacketValidator()
    private val demo = DemoPressureMonitor(scope) { bar -> handle(bar, 100) }

    init {
        registerBluetoothReceiver()
        if (_isEnabled.value) {
            if (_isDemo.value) {
                demo.start()
            } else {
                reconnectSaved()
            }
        }
    }

    fun hasPermissions(): Boolean {
        fun granted(permission: String) =
            ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            granted(Manifest.permission.BLUETOOTH_SCAN) && granted(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            granted(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    fun setEnabled(enabled: Boolean) {
        _isEnabled.value = enabled
        prefs.edit().putBoolean(KEY_ENABLED, enabled).apply()
        if (!enabled) {
            disconnect()
            demo.stop()
        } else {
            if (_isDemo.value) {
                demo.start()
            } else {
                reconnectSaved()
            }
        }
    }

    fun setDemo(enabled: Boolean) {
        _isDemo.value = enabled
        prefs.edit().putBoolean(KEY_DEMO, enabled).apply()
        if (enabled) {
            disconnect()
            demo.start()
        } else {
            demo.stop()
            _pressure.value = 0.0
            reconnectSaved()
        }
    }

    fun toggleDemo(enable: Boolean) = setDemo(enable)

    fun startScan() {
        if (_isDemo.value) return
        if (!hasPermissions()) {
            _state.value = PressureConnectionState.NO_PERMISSION
            return
        }
        val scanner = adapter?.bluetoothLeScanner ?: run {
            _state.value = PressureConnectionState.UNSUPPORTED
            return
        }
        if (!adapter.isEnabled) {
            _state.value = PressureConnectionState.BLUETOOTH_OFF
            return
        }
        _discovered.value = emptyList()
        _state.value = PressureConnectionState.SCANNING
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        scanner.startScan(null, settings, scanCallback)
        main.postDelayed({ stopScan() }, SCAN_TIMEOUT_MS)
    }

    fun stopScan() {
        if (_state.value != PressureConnectionState.SCANNING) return
        if (hasPermissions()) runCatching { adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
        _state.value = if (gatt != null) PressureConnectionState.CONNECTED else PressureConnectionState.IDLE
    }

    fun connect(address: String, autoConnect: Boolean = false) {
        if (_isDemo.value) return
        if (!hasPermissions()) {
            _state.value = PressureConnectionState.NO_PERMISSION
            return
        }
        val device = runCatching { adapter?.getRemoteDevice(address) }.getOrNull() ?: return
        userInitiatedDisconnect = false
        stopScan()
        _state.value = PressureConnectionState.CONNECTING
        prefs.edit().putString(KEY_ADDRESS, address).apply()
        gatt?.close()
        gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            device.connectGatt(context, autoConnect, gattCallback, BluetoothDevice.TRANSPORT_LE)
        } else {
            device.connectGatt(context, autoConnect, gattCallback)
        }
    }

    fun disconnect() {
        userInitiatedDisconnect = true
        prefs.edit().remove(KEY_ADDRESS).apply()
        gatt?.let {
            it.disconnect()
            it.close()
        }
        gatt = null
        commandCharacteristic = null
        _connectedName.value = null
        _battery.value = null
        _pressure.value = 0.0
        validator.reset()
        _state.value = PressureConnectionState.IDLE
    }

    override fun tare() {
        if (_isDemo.value) {
            demo.tare()
            return
        }
        // The sensor has no tare command in BOOKOO's public protocol; it reads 0 bar when the pump is off.
    }

    override fun prepareForBrew(recipe: com.brewlog.app.domain.Recipe) {
        if (_isDemo.value) {
            demo.simulate(recipe, delaySeconds = 2.5)
        } else {
            tare()
            startMonitoring()
        }
    }

    override fun startMonitoring() {
        if (_isDemo.value) {
            demo.simulateShot()
            return
        }
        send(BookooPressureProtocol.Command.START_MONITOR)
    }

    override fun stopMonitoring() {
        if (_isDemo.value) {
            demo.stopSimulation()
            return
        }
        send(BookooPressureProtocol.Command.STOP_MONITOR)
    }

    override fun brewFinished() {
        stopMonitoring()
    }

    private fun send(command: BookooPressureProtocol.Command) {
        val g = gatt ?: return
        val char = commandCharacteristic ?: return
        write(g, char, command.packet(), BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)
    }

    private fun reconnectSaved() {
        val address = prefs.getString(KEY_ADDRESS, null) ?: return
        connect(address, autoConnect = true)
    }

    private fun registerBluetoothReceiver() {
        if (receiverRegistered) return
        receiverRegistered = true
        ContextCompat.registerReceiver(
            context,
            object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    val wasOff = _state.value == PressureConnectionState.BLUETOOTH_OFF
                    refreshState()
                    if (wasOff && _state.value == PressureConnectionState.IDLE && !_isDemo.value && _isEnabled.value) {
                        reconnectSaved()
                    }
                }
            },
            IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    private fun refreshState() {
        if (_isDemo.value) return
        val a = adapter
        _state.value = when {
            a == null -> PressureConnectionState.UNSUPPORTED
            !hasPermissions() -> PressureConnectionState.NO_PERMISSION
            !a.isEnabled -> PressureConnectionState.BLUETOOTH_OFF
            gatt != null -> PressureConnectionState.CONNECTED
            else -> PressureConnectionState.IDLE
        }
    }

    private fun handle(bar: Double, battery: Int?) {
        if (!bar.isFinite()) return
        _pressure.value = bar
        if (battery != null) _battery.value = battery.coerceIn(0, 100)
        _readings.tryEmit(PressureReading(bar, monotonicMillis()))
    }

    private fun isPressureDevice(name: String?, result: ScanResult): Boolean {
        if (BookooPressureProtocol.isMonitorName(name)) return true
        return result.scanRecord?.serviceUuids?.contains(ParcelUuid(BookooPressureProtocol.SERVICE_UUID)) == true
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val name = result.scanRecord?.deviceName ?: runCatching { result.device.name }.getOrNull()
            if (!isPressureDevice(name, result)) return
            val safeName = (name ?: "BOOKOO monitor").sanitized(40).ifEmpty { "BOOKOO monitor" }
            val entry = DiscoveredPressureDevice(result.device.address, safeName, result.rssi)
            _discovered.update { list ->
                when {
                    list.any { it.address == entry.address } -> list.map { if (it.address == entry.address) entry else it }
                    list.size < MAX_DISCOVERED -> list + entry
                    else -> list
                }
            }
        }

        override fun onScanFailed(errorCode: Int) {
            _state.value = PressureConnectionState.IDLE
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    _connectedName.value = (runCatching { g.device.name }.getOrNull() ?: "Espresso Monitor").sanitized(40)
                    g.discoverServices()
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    commandCharacteristic = null
                    if (userInitiatedDisconnect || _isDemo.value) {
                        _state.value = PressureConnectionState.IDLE
                    } else {
                        _state.value = PressureConnectionState.CONNECTING
                        val address = g.device.address
                        main.postDelayed({
                            if (!userInitiatedDisconnect && !_isDemo.value && _isEnabled.value) {
                                connect(address, autoConnect = true)
                            }
                        }, 1_000)
                    }
                }
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            val service = g.getService(BookooPressureProtocol.SERVICE_UUID) ?: return
            commandCharacteristic = service.getCharacteristic(BookooPressureProtocol.COMMAND_CHAR_UUID)
            val pressureChar = service.getCharacteristic(BookooPressureProtocol.PRESSURE_CHAR_UUID) ?: return
            enableNotifications(g, pressureChar)
        }

        override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS && !_isDemo.value) {
                _state.value = PressureConnectionState.CONNECTED
                // The sensor only streams after the start command.
                main.post { send(BookooPressureProtocol.Command.START_MONITOR) }
            }
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            onData(characteristic, value)
        }

        @Deprecated("Used on Android 12 and lower")
        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                onData(characteristic, characteristic.value ?: return)
            }
        }
    }

    private fun onData(characteristic: BluetoothGattCharacteristic, value: ByteArray) {
        if (characteristic.uuid != BookooPressureProtocol.PRESSURE_CHAR_UUID) return
        val reading = validator.accept(value) ?: return
        if (_state.value != PressureConnectionState.CONNECTED && !_isDemo.value) {
            _state.value = PressureConnectionState.CONNECTED
        }
        handle(reading.bar, reading.batteryPercent)
    }

    @Suppress("DEPRECATION")
    private fun enableNotifications(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
        g.setCharacteristicNotification(characteristic, true)
        val cccd = characteristic.getDescriptor(BookooPressureProtocol.CCCD_UUID) ?: return
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
        private const val KEY_ENABLED = "espressoPressureEnabled"
        private const val KEY_DEMO = "pressure.demo"
        private const val KEY_ADDRESS = "pressure.lastAddress"
        private const val SCAN_TIMEOUT_MS = 15_000L
        private const val MAX_DISCOVERED = 20
    }
}
