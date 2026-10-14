@file:OptIn(ExperimentalMaterial3Api::class)

package com.brewlog.app.ui.screens

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bluetooth
import androidx.compose.material.icons.filled.Scale
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.brewlog.app.LocalContainer
import com.brewlog.app.domain.grams1
import com.brewlog.app.scale.ScaleConnectionState
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.IconCircle
import com.brewlog.app.ui.theme.GoodGreen
import com.brewlog.app.ui.theme.WarnOrange

/** Returns a function that asks for Bluetooth permissions / switching Bluetooth on, then runs [onReady]. */
@Composable
fun rememberBluetoothAccess(onReady: () -> Unit): () -> Unit {
    val scale = LocalContainer.current.scale
    val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
    } else {
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }
    val enable = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        scale.start()
        if (scale.isBluetoothOn) onReady()
    }
    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        scale.start()
        if (result.values.all { it }) {
            if (scale.isBluetoothOn) onReady() else enable.launch(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
        }
    }
    return {
        when {
            !scale.hasPermissions() -> request.launch(permissions)
            !scale.isBluetoothOn -> enable.launch(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
            else -> onReady()
        }
    }
}

@Composable
fun ScaleStatusCard(onClick: () -> Unit) {
    val scale = LocalContainer.current.scale
    val state by scale.state.collectAsStateWithLifecycle()
    val isDemo by scale.isDemo.collectAsStateWithLifecycle()
    val ready by scale.ready.collectAsStateWithLifecycle()
    val weight by scale.weight.collectAsStateWithLifecycle()
    val battery by scale.battery.collectAsStateWithLifecycle()
    val name by scale.connectedName.collectAsStateWithLifecycle()

    val color = when {
        isDemo || state == ScaleConnectionState.CONNECTED -> GoodGreen
        state == ScaleConnectionState.CONNECTING || state == ScaleConnectionState.SCANNING -> WarnOrange
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    val subtitle = when {
        isDemo -> "Simulated pours. Turn off in Settings."
        state == ScaleConnectionState.CONNECTED -> "Connected" + (battery?.let { " · $it% battery" } ?: "")
        state == ScaleConnectionState.IDLE -> "Tap to connect your BOOKOO, or brew with the timer only"
        else -> state.label
    }
    BrewCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconCircle(Icons.Filled.Scale, color, size = 42)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(if (ready) (if (isDemo) "Demo scale" else name ?: "BOOKOO") else "No scale connected",
                    style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (ready) {
                Text(weight.grams1(), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            } else {
                Text("Connect", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
fun ScaleSheet(onDismiss: () -> Unit) {
    val scale = LocalContainer.current.scale
    val state by scale.state.collectAsStateWithLifecycle()
    val isDemo by scale.isDemo.collectAsStateWithLifecycle()
    val discovered by scale.discovered.collectAsStateWithLifecycle()
    val weight by scale.weight.collectAsStateWithLifecycle()
    val battery by scale.battery.collectAsStateWithLifecycle()
    val rejected by scale.rejectedPackets.collectAsStateWithLifecycle()
    val name by scale.connectedName.collectAsStateWithLifecycle()
    val search = rememberBluetoothAccess { scale.startScan() }

    LaunchedEffect(Unit) {
        if (!isDemo && state != ScaleConnectionState.CONNECTED) search()
    }
    DisposableEffect(Unit) { onDispose { scale.stopScan() } }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 24.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Scale", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Bluetooth, null, tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(8.dp))
                Text(if (isDemo) "Demo scale active" else state.label, Modifier.weight(1f))
                if (state == ScaleConnectionState.SCANNING || state == ScaleConnectionState.CONNECTING) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                }
            }
            if (state == ScaleConnectionState.CONNECTED && !isDemo) {
                InfoRow("Scale", name ?: "BOOKOO")
                battery?.let { InfoRow("Battery", "$it%") }
                InfoRow("Weight", weight.grams1())
                if (rejected > 0) InfoRow("Ignored invalid packets", rejected.toString())
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedButton(onClick = { scale.tare() }) { Text("Tare") }
                    TextButton(onClick = { scale.disconnect(forget = true) }) { Text("Disconnect & forget", color = Color(0xFFFF3B30)) }
                }
            }
            if (!isDemo && state != ScaleConnectionState.CONNECTED) {
                HorizontalDivider()
                Text("Nearby scales", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (discovered.isEmpty()) {
                    Text(
                        when (state) {
                            ScaleConnectionState.SCANNING -> "Searching…"
                            ScaleConnectionState.NO_PERMISSION -> "Allow Bluetooth access to find your scale."
                            ScaleConnectionState.BLUETOOTH_OFF -> "Switch Bluetooth on to find your scale."
                            else -> "Tap Search to find your scale."
                        },
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                discovered.forEach { device ->
                    Row(
                        Modifier.fillMaxWidth().clickable { scale.connect(device.address) }.padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.Scale, null)
                        Spacer(Modifier.width(10.dp))
                        Text(device.name, Modifier.weight(1f))
                        Text("${device.rssi} dBm", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                OutlinedButton(onClick = { if (state == ScaleConnectionState.SCANNING) scale.stopScan() else search() }) {
                    Text(if (state == ScaleConnectionState.SCANNING) "Stop searching" else "Search")
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                    Text("On Android 11 and lower, Location must be switched on for Bluetooth scanning.",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            HorizontalDivider()
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Demo scale", fontWeight = FontWeight.Medium)
                    Text("Simulates pours that follow the recipe. Use it to try BrewLog without a scale or in the emulator.",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Switch(checked = isDemo, onCheckedChange = { scale.setDemo(it) })
            }
            Spacer(Modifier.height(4.dp))
            Text("Turn on your BOOKOO Themis Mini. BrewLog reconnects to it automatically next time.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
fun InfoRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value)
    }
}
