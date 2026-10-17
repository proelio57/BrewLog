package com.brewlog.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.brewlog.app.LocalContainer
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.fmt1
import com.brewlog.app.machine.MachineConnection
import com.brewlog.app.machine.MachineKind
import com.brewlog.app.machine.MachineMode
import com.brewlog.app.machine.gaggiMateUrl
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.PillChip
import com.brewlog.app.ui.components.SectionHeader
import com.brewlog.app.ui.components.StatView

// Port of MachineCard.swift and the machine part of SettingsView (iOS) / screens/Machine.tsx (web).

private fun connectionText(connection: MachineConnection, brewing: Boolean): String =
    if (connection == MachineConnection.CONNECTED && brewing) "Brewing" else connection.label

/** Espresso machine status and controls on the Brew tab. */
@Composable
fun MachineCard(recipe: Recipe, dose: Double, temperature: Double, onOpenSettings: () -> Unit) {
    val machine = LocalContainer.current.machine
    val state by machine.state.collectAsStateWithLifecycle()
    val status = state.status
    BrewCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Coffee, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
            Text(machine.displayName, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(connectionText(state.connection, status.isBrewing), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        when {
            state.kind == MachineKind.NONE -> {
                Text("Connect a GaggiMate to record pressure and temperature, start shots from here and send recipes as profiles. Without one, BrewLog times the shot with your scale.",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                TextButton(onClick = onOpenSettings) { Text("Set up machine") }
            }
            state.connection != MachineConnection.CONNECTED -> {
                Text(if (state.connection == MachineConnection.CONNECTING) "Connecting to ${state.host}…"
                    else "Can't reach ${state.host}. Is the machine on and in the same Wi-Fi?",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                TextButton(onClick = onOpenSettings) { Text("Machine settings") }
            }
            else -> {
                Spacer(Modifier.height(8.dp))
                Row {
                    StatView(status.temperature?.let { "${fmt1(it)}°" } ?: "–", "Boiler")
                    StatView(status.targetTemperature?.let { "${it.toInt()}°" } ?: "–", "Target")
                    StatView(status.profile ?: "–", "Profile")
                }
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    MachineMode.entries.forEach { mode ->
                        PillChip(mode.title, (status.mode ?: 0) == mode.value) { machine.setMode(mode) }
                    }
                }
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("Temperature", Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    IconButton(onClick = { machine.nudgeTemperature(false) }) { Icon(Icons.Filled.Remove, contentDescription = "1 °C cooler") }
                    IconButton(onClick = { machine.nudgeTemperature(true) }) { Icon(Icons.Filled.Add, contentDescription = "1 °C hotter") }
                }
                FilledTonalButton(onClick = { machine.sendProfile(recipe, dose, temperature) }) {
                    Icon(Icons.Filled.Send, null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Send recipe to machine")
                }
                state.notice?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                status.systemMessage?.takeIf { it.isNotEmpty() }?.let {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Warning, null, tint = Color(0xFFFF9500), modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(it, style = MaterialTheme.typography.bodySmall, color = Color(0xFFFF9500))
                    }
                }
            }
        }
    }
}

/** Settings: which espresso machine and where to find it. */
@Composable
fun EspressoMachineSettingsCard() {
    val machine = LocalContainer.current.machine
    val state by machine.state.collectAsStateWithLifecycle()
    var host by remember { mutableStateOf(state.host) }
    val valid = gaggiMateUrl(host) != null
    SectionHeader("Espresso machine")
    Spacer(Modifier.height(8.dp))
    BrewCard {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            MachineKind.entries.forEach { kind ->
                PillChip(kind.title, state.kind == kind) { machine.configure(kind, if (valid) host else state.host) }
            }
        }
        if (state.kind == MachineKind.GAGGIMATE) {
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = host, onValueChange = { host = it.take(253) }, label = { Text("Address") }, singleLine = true,
                isError = !valid, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                modifier = Modifier.fillMaxWidth(),
            )
            if (!valid) Text("Enter a host name like gaggimate.local or an IP address like 192.168.1.20.", style = MaterialTheme.typography.bodySmall, color = Color(0xFFFF9500))
            TextButton(onClick = { machine.configure(MachineKind.GAGGIMATE, host) }, enabled = valid && host != state.host) { Text("Connect") }
        }
        if (state.kind != MachineKind.NONE) {
            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                Text("Status", Modifier.weight(1f))
                Text(connectionText(state.connection, state.status.isBrewing) +
                    (state.status.temperature?.takeIf { state.connection == MachineConnection.CONNECTED }?.let { " · ${fmt1(it)} °C" } ?: ""),
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Text("GaggiMate: BrewLog connects over your Wi-Fi, records pressure, temperature and flow, follows the shot and can start it, switch modes and send recipes as profiles. Use the address from GaggiMate's web interface (the IP address works if your phone can't resolve gaggimate.local). Your scale can stay connected to GaggiMate; BrewLog then reads the weight from there.",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** GaggiMate refused to start because of a warning (e.g. low water): ask whether to start anyway. */
@Composable
fun MachineWarningDialog() {
    val machine = LocalContainer.current.machine
    val state by machine.state.collectAsStateWithLifecycle()
    if (state.startBlockedBy.isEmpty()) return
    AlertDialog(
        onDismissRequest = { machine.dismissStartWarning() },
        title = { Text("The machine reports a warning") },
        text = { Text("GaggiMate didn't start the shot (${state.startBlockedBy.joinToString()}). Check the machine first.") },
        confirmButton = { TextButton(onClick = { machine.startShot(ignoreWarnings = true) }) { Text("Start anyway", color = Color(0xFFFF3B30)) } },
        dismissButton = { TextButton(onClick = { machine.dismissStartWarning() }) { Text("Cancel") } },
    )
}
