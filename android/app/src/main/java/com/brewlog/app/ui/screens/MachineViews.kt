package com.brewlog.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bluetooth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
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
import com.brewlog.app.AppContainer
import com.brewlog.app.LocalContainer
import com.brewlog.app.data.DataImporter
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.fmt1
import com.brewlog.app.machine.MachineConnection
import com.brewlog.app.machine.MachineKind
import com.brewlog.app.machine.MachineMode
import com.brewlog.app.machine.MachineProfileSummary
import com.brewlog.app.machine.gaggiMateUrl
import com.brewlog.app.scale.ScaleConnectionState
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
                    Icon(Icons.AutoMirrored.Filled.Send, null, modifier = Modifier.size(16.dp))
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
    val container = LocalContainer.current
    val machine = container.machine
    val state by machine.state.collectAsStateWithLifecycle()
    var host by remember { mutableStateOf(state.host) }
    var importLoading by remember { mutableStateOf(false) }
    var importMessage by remember { mutableStateOf<String?>(null) }
    var showDecentSheet by remember { mutableStateOf(false) }
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
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { machine.configure(MachineKind.GAGGIMATE, host) }, enabled = valid && host != state.host) { Text("Connect") }
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(enabled = state.isConnected && !importLoading) {
                        importLoading = true
                        importMessage = null
                        machine.fetchProfiles { recipes ->
                            importLoading = false
                            if (recipes == null) {
                                importMessage = "The machine didn't send its profiles. Check the connection and try again."
                            } else if (recipes.isEmpty()) {
                                importMessage = "No brew profiles on the machine besides the ones BrewLog sent."
                            } else {
                                val summary = DataImporter.importRecipes(recipes, container.repository, container.presets)
                                importMessage = summary.message + " They're with the espresso recipes."
                            }
                        }
                    }
                    .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Download, contentDescription = null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(8.dp))
                Text("Import profiles as recipes", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                if (importLoading) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                }
            }
            importMessage?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (state.kind == MachineKind.DECENT) {
            val decent = machine.decent
            val connectedName by decent.connectedName.collectAsStateWithLifecycle()
            Spacer(Modifier.height(8.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { showDecentSheet = true }
                    .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Bluetooth, contentDescription = null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(8.dp))
                Text("DE1", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                Text(
                    if (decent.hasSavedMachine) (connectedName ?: "Paired") else "Find machine",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        if (state.kind != MachineKind.NONE) {
            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                Text("Status", Modifier.weight(1f))
                Text(connectionText(state.connection, state.status.isBrewing) +
                    (state.status.temperature?.takeIf { state.connection == MachineConnection.CONNECTED }?.let { " · ${fmt1(it)} °C" } ?: ""),
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        val explText = when (state.kind) {
            MachineKind.GAGGIMATE -> "GaggiMate: BrewLog connects over your Wi-Fi, records pressure, temperature and flow, follows the shot and can start it, switch modes and send recipes as profiles. Use the address from GaggiMate's web interface (the IP address works if your phone can't resolve gaggimate.local). Your scale can stay connected to GaggiMate; BrewLog then reads the weight from there."
            MachineKind.DECENT -> "Decent DE1: BrewLog connects over Bluetooth, records live pressure, flow and head temperature, follows the shot and can start and stop it. Close the Decent tablet app first: the DE1 talks to one app at a time."
            MachineKind.LA_MARZOCCO -> "La Marzocco: BrewLog connects through your La Marzocco account, turns the machine on and off and sets boiler temperatures."
            MachineKind.DEMO -> "Demo machine: simulated espresso machine with realistic pressure, temperature and flow curves."
            MachineKind.NONE -> "Without a machine, BrewLog times your espresso shots with your scale."
        }
        Text(explText, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    if (showDecentSheet) DecentConnectSheet { showDecentSheet = false }
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

private fun resolveProfileRecipe(profile: MachineProfileSummary, container: AppContainer): Recipe? {
    val saved = container.repository.data.value.customRecipes
    fun savedRecipe(id: String): Recipe? = saved.firstOrNull { it.id == id }
    if (profile.isBrewLogs) {
        val id = container.machine.recipeIdForProfile(profile.id)
        if (id != null) {
            container.presets.firstOrNull { it.id == id }?.let { return it }
            savedRecipe(id)?.let { return it }
        }
        return profile.recipe
    }
    val recipe = profile.recipe ?: return null
    if (container.machine.kind == MachineKind.DEMO) return recipe
    savedRecipe(recipe.id)?.let { return it }
    container.repository.upsertRecipe(recipe)
    return recipe
}

/** Modal sheet listing the profiles stored on the machine. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MachineProfilesSheet(onDismiss: () -> Unit) {
    val container = LocalContainer.current
    val machine = container.machine
    val state by machine.state.collectAsStateWithLifecycle()
    var selecting by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        machine.refreshProfiles()
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Machine profiles", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                TextButton(onClick = onDismiss) { Text("Done") }
            }

            if (!state.isConnected) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Warning, null, tint = Color(0xFFFF9500), modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("The machine isn't connected.", color = Color(0xFFFF9500), style = MaterialTheme.typography.bodyMedium)
                }
            } else if (state.profiles.isEmpty()) {
                if (state.profilesLoading) {
                    Box(Modifier.fillMaxWidth().padding(vertical = 16.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp))
                    }
                } else {
                    Text("No profiles on the machine.", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                }
            }

            LazyColumn(
                modifier = Modifier.weight(1f, fill = false),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                items(state.profiles, key = { it.id }) { profile ->
                    Surface(
                        onClick = {
                            selecting = profile.id
                            machine.selectProfile(profile.id) { accepted ->
                                selecting = null
                                if (accepted) {
                                    val r = resolveProfileRecipe(profile, container)
                                    if (r != null) container.espressoSetup.select(r)
                                    onDismiss()
                                }
                            }
                        },
                        enabled = selecting == null && state.isConnected,
                        shape = RoundedCornerShape(12.dp),
                        color = Color.Transparent,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(
                            Modifier.fillMaxWidth().padding(vertical = 10.dp, horizontal = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                profile.label,
                                style = MaterialTheme.typography.bodyLarge,
                                fontWeight = if (profile.isSelected) FontWeight.SemiBold else FontWeight.Normal,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                            if (profile.isFavorite) {
                                Spacer(Modifier.width(6.dp))
                                Icon(Icons.Filled.Star, contentDescription = "Favorite", tint = Color(0xFFFFCC00), modifier = Modifier.size(16.dp))
                            }
                            Spacer(Modifier.weight(1f))
                            if (selecting == profile.id) {
                                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                            } else if (profile.isSelected) {
                                Icon(Icons.Filled.Check, contentDescription = "Selected", tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                            }
                        }
                    }
                }
            }

            state.notice?.let { notice ->
                if (selecting == null) {
                    Text(notice, color = Color(0xFFFF9500), style = MaterialTheme.typography.bodySmall)
                }
            }
            Text(
                "Selecting a profile sets it on the machine and brews with it here: BrewLog takes the yield, time and pressure from it.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

/** Find a Decent DE1 nearby and pair it, or forget the paired one. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DecentConnectSheet(onDismiss: () -> Unit) {
    val container = LocalContainer.current
    val machine = container.machine
    val decent = machine.decent
    val state by decent.state.collectAsStateWithLifecycle()
    val discovered by decent.discovered.collectAsStateWithLifecycle()
    val connectedName by decent.connectedName.collectAsStateWithLifecycle()
    val askBluetooth = rememberBluetoothAccess { decent.startScan() }

    LaunchedEffect(Unit) {
        if (state != ScaleConnectionState.CONNECTED) askBluetooth()
    }
    DisposableEffect(Unit) {
        onDispose { decent.stopScan() }
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Decent DE1", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                TextButton(onClick = onDismiss) { Text("Done") }
            }

            Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Coffee, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(
                            connectedName ?: state.label,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.weight(1f),
                        )
                        if (state == ScaleConnectionState.SCANNING || state == ScaleConnectionState.CONNECTING) {
                            CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                        }
                    }
                    if (decent.hasSavedMachine) {
                        TextButton(
                            onClick = { machine.forgetDecent() },
                        ) {
                            Text("Disconnect & forget", color = Color(0xFFFF3B30))
                        }
                    }
                }
            }

            Text(
                "Switch the DE1 on and keep the phone nearby. Close the Decent tablet app first: the DE1 talks to one app at a time.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )

            if (state != ScaleConnectionState.CONNECTED) {
                Text("Nearby machines", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                if (discovered.isEmpty()) {
                    Text(
                        if (state == ScaleConnectionState.SCANNING) "Searching…" else "Tap Search to find your DE1",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                LazyColumn(
                    modifier = Modifier.weight(1f, fill = false),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    items(discovered, key = { it.address }) { device ->
                        Surface(
                            onClick = { machine.connectDecent(device.address) },
                            shape = RoundedCornerShape(8.dp),
                            color = Color.Transparent,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Row(
                                Modifier.fillMaxWidth().padding(vertical = 8.dp, horizontal = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(Icons.Filled.Coffee, null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                                Spacer(Modifier.width(8.dp))
                                Text(device.name, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                                Text("${device.rssi} dBm", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
                FilledTonalButton(
                    onClick = {
                        if (state == ScaleConnectionState.SCANNING) decent.stopScan() else askBluetooth()
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(if (state == ScaleConnectionState.SCANNING) "Stop searching" else "Search")
                }
            }
        }
    }
}
