package com.brewlog.app.machine

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
import androidx.core.content.ContextCompat
import com.brewlog.app.domain.sanitized
import com.brewlog.app.scale.BookooProtocol
import com.brewlog.app.scale.DiscoveredScale
import com.brewlog.app.scale.ScaleConnectionState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.UUID

/**
 * Bluetooth connection to a Decent DE1: subscribes to its state and shot samples and writes requested states.
 * [MachineManager] owns it and turns its updates into the machine status the brew engine reads.
 */
@SuppressLint("MissingPermission")
class DecentConnection(
    private val context: Context?,
    private val prefs: SharedPreferences,
) {
    private val adapter: BluetoothAdapter? =
        context?.let { (it.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter }
    private val main = Handler(Looper.getMainLooper())

    private val _state = MutableStateFlow(ScaleConnectionState.IDLE)
    val state: StateFlow<ScaleConnectionState> = _state.asStateFlow()

    private val _discovered = MutableStateFlow<List<DiscoveredScale>>(emptyList())
    val discovered: StateFlow<List<DiscoveredScale>> = _discovered.asStateFlow()

    private val _connectedName = MutableStateFlow<String?>(null)
    val connectedName: StateFlow<String?> = _connectedName.asStateFlow()

    var onStatus: ((MachineStatus, Boolean) -> Unit)? = null
    var onDisconnect: (() -> Unit)? = null

    private var gatt: BluetoothGatt? = null
    private var requestCharacteristic: BluetoothGattCharacteristic? = null
    private var status = MachineStatus()
    private var userInitiatedDisconnect = false
    private var active = false
    private var machineState: Int? = null
    private var receiverRegistered = false

    val isInEspressoState: Boolean get() = machineState == DecentProtocol.State.ESPRESSO.value

    var savedAddress: String?
        get() = prefs.getString(KEY_DECENT_ADDRESS, null)
        private set(value) {
            prefs.edit().apply {
                if (value == null) remove(KEY_DECENT_ADDRESS) else putString(KEY_DECENT_ADDRESS, value)
            }.apply()
        }

    val hasSavedMachine: Boolean get() = savedAddress != null

    fun hasPermissions(): Boolean {
        val ctx = context ?: return false
        fun granted(p: String) = ContextCompat.checkSelfPermission(ctx, p) == PackageManager.PERMISSION_GRANTED
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            granted(Manifest.permission.BLUETOOTH_SCAN) && granted(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            granted(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    val isBluetoothOn: Boolean get() = adapter?.isEnabled == true

    fun reconnectRemembered() {
        active = true
        registerReceiver()
        val address = savedAddress
        if (address != null && adapter?.isEnabled == true && hasPermissions()) {
            connect(address)
        } else {
            startScan()
        }
    }

    fun startScan() {
        active = true
        registerReceiver()
        if (adapter == null || adapter.isEnabled.not() || !hasPermissions()) {
            refreshState()
            return
        }
        _discovered.value = emptyList()
        if (_state.value != ScaleConnectionState.CONNECTED && _state.value != ScaleConnectionState.CONNECTING) {
            _state.value = ScaleConnectionState.SCANNING
        }
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        runCatching {
            adapter?.bluetoothLeScanner?.startScan(null, settings, scanCallback)
        }
    }

    fun stopScan() {
        if (hasPermissions()) {
            runCatching { adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
        }
        if (_state.value == ScaleConnectionState.SCANNING) _state.value = ScaleConnectionState.IDLE
    }

    fun connect(address: String) {
        val ctx = context ?: return
        if (!hasPermissions() || !BluetoothAdapter.checkBluetoothAddress(address)) return
        val device = adapter?.getRemoteDevice(address) ?: return
        stopScan()
        if (gatt != null && gatt?.device?.address != address) {
            userInitiatedDisconnect = true
            gatt?.disconnect()
            gatt?.close()
            gatt = null
        }
        savedAddress = address
        _state.value = ScaleConnectionState.CONNECTING
        gatt = device.connectGatt(ctx, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
    }

    fun disconnect(forget: Boolean) {
        active = false
        stopScan()
        if (gatt != null) {
            userInitiatedDisconnect = true
            gatt?.disconnect()
            gatt?.close()
            gatt = null
        }
        requestCharacteristic = null
        status = MachineStatus()
        machineState = null
        _connectedName.value = null
        if (forget) savedAddress = null
        _state.value = ScaleConnectionState.IDLE
    }

    fun write(command: ByteArray): Boolean {
        val g = gatt ?: return false
        val c = requestCharacteristic ?: return false
        writeCharacteristic(g, c, command, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)
        return true
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val name = result.device.name ?: result.scanRecord?.deviceName
            val serviceUuids = result.scanRecord?.serviceUuids?.map { it.uuid } ?: emptyList()
            val matches = serviceUuids.contains(DecentProtocol.SERVICE_UUID) || (name?.startsWith("DE1") == true)
            if (!matches) return
            val safeName = (name ?: "DE1").sanitized(40).let { if (it.isEmpty()) "DE1" else it }
            val entry = DiscoveredScale(address = result.device.address, name = safeName, rssi = result.rssi)
            val current = _discovered.value.toMutableList()
            val idx = current.indexOfFirst { it.address == entry.address }
            if (idx >= 0) {
                current[idx] = entry
            } else if (current.size < 20) {
                current.add(entry)
            }
            _discovered.value = current

            if (result.device.address == savedAddress && _state.value != ScaleConnectionState.CONNECTED && _state.value != ScaleConnectionState.CONNECTING) {
                connect(result.device.address)
            }
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            main.post {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    _connectedName.value = (g.device.name ?: "DE1").sanitized(40)
                    g.discoverServices()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    handleDisconnect(g)
                }
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            main.post {
                if (status != BluetoothGatt.GATT_SUCCESS) return@post
                val service = g.getService(DecentProtocol.SERVICE_UUID) ?: return@post
                for (c in service.characteristics) {
                    when (c.uuid) {
                        DecentProtocol.REQUESTED_STATE_UUID -> requestCharacteristic = c
                        DecentProtocol.SHOT_SAMPLE_UUID -> enableNotifications(g, c)
                        DecentProtocol.STATE_INFO_UUID -> {
                            enableNotifications(g, c)
                            g.readCharacteristic(c)
                        }
                    }
                }
            }
        }

        @Deprecated("Deprecated in Java")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            handleCharacteristic(c.uuid, c.value)
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
            handleCharacteristic(c.uuid, value)
        }

        @Deprecated("Deprecated in Java")
        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) handleCharacteristic(c.uuid, c.value)
        }

        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) handleCharacteristic(c.uuid, value)
        }
    }

    private fun handleCharacteristic(uuid: UUID, data: ByteArray?) {
        if (data == null || data.size > 64) return
        main.post {
            when (uuid) {
                DecentProtocol.STATE_INFO_UUID -> {
                    val info = DecentProtocol.state(data) ?: return@post
                    machineState = info.state
                    status = DecentProtocol.apply(info.state, info.substate, status)
                    _state.value = ScaleConnectionState.CONNECTED
                    onStatus?.invoke(status, false)
                }
                DecentProtocol.SHOT_SAMPLE_UUID -> {
                    val sample = DecentProtocol.sample(data) ?: return@post
                    status = DecentProtocol.apply(sample, status)
                    onStatus?.invoke(status, true)
                }
            }
        }
    }

    private fun handleDisconnect(g: BluetoothGatt) {
        requestCharacteristic = null
        status = MachineStatus()
        machineState = null
        if (userInitiatedDisconnect || !active) {
            _state.value = ScaleConnectionState.IDLE
            userInitiatedDisconnect = false
            return
        }
        _state.value = ScaleConnectionState.CONNECTING
        onDisconnect?.invoke()
        main.postDelayed({
            if (active && _state.value != ScaleConnectionState.CONNECTED) {
                connect(g.device.address)
            }
        }, 5000)
    }

    private fun dropConnection() {
        if (gatt == null) return
        gatt?.close()
        gatt = null
        requestCharacteristic = null
        status = MachineStatus()
        machineState = null
        if (active) onDisconnect?.invoke()
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

    private fun registerReceiver() {
        val ctx = context ?: return
        if (receiverRegistered) return
        receiverRegistered = true
        ContextCompat.registerReceiver(
            ctx,
            object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    val wasOff = _state.value == ScaleConnectionState.BLUETOOTH_OFF
                    refreshState()
                    if (adapter?.isEnabled == false) {
                        dropConnection()
                    } else if (wasOff && _state.value == ScaleConnectionState.IDLE && active) {
                        reconnectRemembered()
                    }
                }
            },
            IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    @Suppress("DEPRECATION")
    private fun enableNotifications(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
        g.setCharacteristicNotification(c, true)
        val cccd = c.getDescriptor(BookooProtocol.CCCD_UUID) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
        } else {
            cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            g.writeDescriptor(cccd)
        }
    }

    @Suppress("DEPRECATION")
    private fun writeCharacteristic(g: BluetoothGatt, c: BluetoothGattCharacteristic, bytes: ByteArray, type: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeCharacteristic(c, bytes, type)
        } else {
            c.writeType = type
            c.value = bytes
            g.writeCharacteristic(c)
        }
    }

    companion object {
        private const val KEY_DECENT_ADDRESS = "machine.decent.id"
    }
}
